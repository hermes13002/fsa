// pubspec_editor.dart
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:path/path.dart' as p;

/// handles merging assets & fonts into pubspec.yaml safely
/// - merges assets without duplicates (keeps existing order, adds new ones at end)
/// - merges fonts by family name (case-sensitive), adds only new assets,
///   removes font files that don't exist anymore, cleans up empty families
/// - writes clean multiline blocks (removes comments in those blocks)
class PubspecEditor {
  final String pubspecPath;
  YamlEditor? _editor;
  Map? _doc;
  final String assetsRootName;

  PubspecEditor(this.pubspecPath, {this.assetsRootName = 'assets'});

  Future<void> ensureFlutterSection() async {
    final file = File(pubspecPath);
    if (!file.existsSync()) {
      throw Exception('pubspec.yaml not found at $pubspecPath');
    }
    final content = await file.readAsString();
    _editor = YamlEditor(content);
    _doc = loadYaml(content) as Map?;
    _doc ??= {};
    if (!(_doc!.containsKey('flutter'))) {
      _editor!.update(['flutter'], {});
      await _write(_editor!.toString());
      final newContent = await file.readAsString();
      _editor = YamlEditor(newContent);
      _doc = loadYaml(newContent) as Map?;
      print('Created flutter: section in pubspec.yaml');
    }
  }

  /// merge assets and fonts with cleanup
  /// returns diagnostics like:
  /// { 'assetsAdded': int, 'assetsRemoved': int, 'fontsAdded': int, 'fontsRemoved': int }
  Future<Map<String, int>> updateAssetsAndFontsExplicit() async {
    if (_editor == null) {
      throw Exception('Call ensureFlutterSection() first.');
    }

    final projectRoot = Directory(pubspecPath).parent.path;

    // ---------- ASSETS ----------
    // read what's already in pubspec
    final existingAssets = <String>[];
    try {
      final flutter = _doc!['flutter'] as Map?;
      if (flutter != null && flutter.containsKey('assets')) {
        final list = flutter['assets'] as YamlList;
        for (var item in list) {
          existingAssets.add(item.toString().replaceAll('\\', '/'));
        }
      }
    } catch (_) {}

    // build paths from what's actually on disk
    final diskPaths = _collectExplicitAssetDirs(projectRoot);

    // merge: keep existing order, then add missing ones from disk
    final mergedAssets = <String>[];
    final seen = <String>{};
    for (final a in existingAssets) {
      final n = a.replaceAll('\\', '/');
      if (!seen.contains(n)) {
        mergedAssets.add(n);
        seen.add(n);
      }
    }
    for (final d in diskPaths) {
      final n = d.replaceAll('\\', '/');
      if (!seen.contains(n)) {
        mergedAssets.add(n);
        seen.add(n);
      }
    }

    // figure out what changed
    final assetsAdded = mergedAssets.where((p) => !existingAssets.contains(p)).length;
    final assetsRemoved = existingAssets.where((p) => !mergedAssets.contains(p)).length;

    // write assets to yaml under flutter.assets as multiline list
    // use yaml_edit to update the node
    _editor!.update(['flutter', 'assets'], mergedAssets);

    // ---------- FONTS ----------
    // existing fonts map: family -> list of asset paths
    final existingFonts = <String, List<String>>{};
    try {
      final flutter = _doc!['flutter'] as Map?;
      if (flutter != null && flutter.containsKey('fonts')) {
        final fList = flutter['fonts'] as YamlList;
        for (final famEntry in fList) {
          if (famEntry is YamlMap && famEntry.containsKey('family')) {
            final famName = famEntry['family'].toString();
            final assetsList = <String>[];
            if (famEntry.containsKey('fonts')) {
              final fontsYamlList = famEntry['fonts'] as YamlList;
              for (final a in fontsYamlList) {
                if (a is YamlMap && a.containsKey('asset')) {
                  assetsList.add(a['asset'].toString().replaceAll('\\', '/'));
                }
              }
            }
            existingFonts[famName] = assetsList;
          }
        }
      }
    } catch (_) {}

    // scan fonts folder recursively and group by family name
    final diskFontsMap = <String, List<String>>{};
    final fontsRoot = p.join(projectRoot, assetsRootName, 'fonts');
    if (Directory(fontsRoot).existsSync()) {
      for (final ent in Directory(fontsRoot).listSync(recursive: true, followLinks: false)) {
        if (ent is File) {
          final rel = p.relative(ent.path, from: projectRoot).replaceAll('\\', '/');
          final filename = p.basenameWithoutExtension(rel);
          final fam = _extractFamilyFromFilename(filename); // FILENAME strategy
          diskFontsMap.putIfAbsent(fam, () => []).add(rel);
        }
      }
    }

    // merge fonts:
    // - for each existing family, keep only assets that still exist
    // - add new assets alphabetically if they're on disk but not in the list
    // - for new families from disk, create new blocks with sorted assets
    final mergedFonts = <Map<String, dynamic>>[]; // list of family maps to write
    int fontsAdded = 0;
    int fontsRemoved = 0;

    // process existing families first, keep their order
    for (final fam in existingFonts.keys) {
      final existingList = existingFonts[fam]!;
      final diskList = diskFontsMap[fam] ?? [];

      // keep assets that still exist on disk
      final kept = <String>[];
      for (final a in existingList) {
        if (diskList.contains(a)) {
          kept.add(a);
        } else {
          fontsRemoved++;
        }
      }

      // find new ones to add (on disk but not in existing list)
      final toAdd = diskList.where((d) => !existingList.contains(d)).toList()..sort((a, b) => a.compareTo(b));

      // append new ones alphabetically
      final mergedList = <String>[]..addAll(kept)..addAll(toAdd);
      fontsAdded += toAdd.length;

      // only add family block if it's not empty
      if (mergedList.isNotEmpty) {
        mergedFonts.add({
          'family': fam,
          'fonts': mergedList.map((a) => {'asset': a}).toList(),
        });
      }

      // remove processed family so we know which ones are new
      diskFontsMap.remove(fam);
    }

    // process any remaining disk families (these are new)
    final newFamilies = diskFontsMap.keys.toList()..sort(); // alphabetical for consistency
    for (final fam in newFamilies) {
      final assetsForFam = diskFontsMap[fam]!..sort((a, b) => a.compareTo(b));
      if (assetsForFam.isNotEmpty) {
        mergedFonts.add({
          'family': fam,
          'fonts': assetsForFam.map((a) => {'asset': a}).toList(),
        });
        fontsAdded += assetsForFam.length;
      }
    }

    // write fonts block (replace entire 'flutter.fonts' with merged data)
    if (mergedFonts.isEmpty) {
      // remove fonts key if it exists and we have nothing
      try {
        final flutterMap = _doc!['flutter'] as Map?;
        if (flutterMap != null && flutterMap.containsKey('fonts')) {
          _editor!.remove(['flutter', 'fonts']);
        }
      } catch (_) {}
    } else {
      _editor!.update(['flutter', 'fonts'], mergedFonts);
    }

    // save changes
    await _write(_editor!.toString());

    return {
      'assetsAdded': assetsAdded,
      'assetsRemoved': assetsRemoved,
      'fontsAdded': fontsAdded,
      'fontsRemoved': fontsRemoved,
    };
  }

  /// collect explicit nested asset directories under the assets root
  /// returns list of relative paths (with trailing slash) in discovery order
  List<String> _collectExplicitAssetDirs(String projectRoot) {
    final assetsRoot = p.join(projectRoot, assetsRootName);
    final explicitPaths = <String>[];

    if (!Directory(assetsRoot).existsSync()) {
      return explicitPaths;
    }

    // get top-level stuff under assets/ in filesystem order
    final topEntries = Directory(assetsRoot).listSync(followLinks: false);
    for (final e in topEntries) {
      if (e is Directory) {
        final topDirPath = '${p.join(assetsRootName, p.basename(e.path))}/'.replaceAll('\\', '/');
        final nestedDirs = <String>[];
        nestedDirs.add(topDirPath);
        for (final sub in Directory(e.path).listSync(recursive: true, followLinks: false)) {
          if (sub is Directory) {
            final rel = p.relative(sub.path, from: projectRoot).replaceAll('\\', '/');
            final entry = rel.endsWith('/') ? rel : '$rel/';
            nestedDirs.add(entry);
          }
        }
        explicitPaths.addAll(nestedDirs);
      } else if (e is File) {
        final assetsRootEntry = '$assetsRootName/'.replaceAll('\\', '/');
        if (!explicitPaths.contains(assetsRootEntry)) explicitPaths.add(assetsRootEntry);
      }
    }

    // normalize and remove duplicates while keeping order
    final seen = <String>{};
    final normalized = <String>[];
    for (final pth in explicitPaths) {
      final np = pth.replaceAll('\\', '/');
      if (!seen.contains(np)) {
        normalized.add(np);
        seen.add(np);
      }
    }
    return normalized;
  }

  String _extractFamilyFromFilename(String filename) {
    final separators = ['-', '_', ' '];
    for (final s in separators) {
      if (filename.contains(s)) return filename.split(s).first;
    }
    return filename;
  }

  Future<void> _write(String content) async {
    final f = File(pubspecPath);
    await f.writeAsString(content);
  }

  /// read package name from pubspec.yaml 'name' field
  /// returns null if not found
  String? getPackageName() {
    try {
      final Map? doc = _doc;
      if (doc != null && doc.containsKey('name')) {
        return doc['name'].toString();
      }
    } catch (_) {}
    return null;
  }
}
