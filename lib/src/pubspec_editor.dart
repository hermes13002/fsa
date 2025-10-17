// pubspec_editor.dart
import 'dart:io';
import 'dart:developer';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:path/path.dart' as p;

/// Writes multiline `assets:` and `fonts:` blocks into pubspec.yaml.
/// Rules:
/// - Converts inline arrays into multiline lists
/// - Explicitly lists all nested subfolders under assets/ (including empty ones)
/// - Adds comment for empty folders: "# (empty folder — kept for future assets)"
/// - Rewrites fonts: into multiline family + fonts structure
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
      log('Created flutter: section in pubspec.yaml');
    }
  }

  /// Main entry: builds explicit nested folders for assets and a multiline fonts block.
  /// Returns a tuple-like map with counts added (assetsAdded, fontsAdded) for diagnostics.
  Future<Map<String, int>> updateAssetsAndFontsExplicit() async {
    if (_editor == null) {
      throw Exception('Call ensureFlutterSection() first.');
    }

    // final file = File(pubspecPath);

    // Step 1: Ensure assets and fonts nodes exist (create minimal placeholder)
    if (!(_doc!['flutter'] as Map).containsKey('assets')) {
      _editor!.update(['flutter', 'assets'], []);
    }
    if (!(_doc!['flutter'] as Map).containsKey('fonts')) {
      _editor!.update(['flutter', 'fonts'], []);
    }

    // Write the intermediate YAML (we'll replace placeholders with formatted blocks)
    final intermediate = _editor!.toString();

    // Step 2: Build explicit asset folder list (all nested subfolders under assets/)
    final projectRoot = Directory(pubspecPath).parent.path;
    final assetsRoot = p.join(projectRoot, assetsRootName);
    final List<String> explicitPaths = [];

    if (Directory(assetsRoot).existsSync()) {
      // Include top-level files under assets/ as 'assets/' explicit path
      final assetsRootDir = Directory(assetsRoot);

      // Gather top-level entries under assets/ in filesystem order
      final topEntries = assetsRootDir.listSync(followLinks: false);
      for (final e in topEntries) {
        if (e is Directory) {
          final topDirPath = '${p.join(assetsRootName, p.basename(e.path))}/';
          // collect all nested dirs including the top dir itself
          final nestedDirs = <String>{};
          nestedDirs.add(topDirPath); // top-level folder itself
          // recursively collect all subdirectories under this top dir
          for (final sub in Directory(e.path).listSync(recursive: true, followLinks: false)) {
            if (sub is Directory) {
              final rel = p.relative(sub.path, from: projectRoot).replaceAll('\\', '/');
              final entry = rel.endsWith('/') ? rel : '$rel/';
              nestedDirs.add(entry);
            }
          }
          // add in discovery order: topDir followed by any nested directories
          explicitPaths.addAll(nestedDirs.toList());
        } else if (e is File) {
          // if there are files directly under assets/, include 'assets/' path
          final assetsRootEntry = '$assetsRootName/';
          if (!explicitPaths.contains(assetsRootEntry)) explicitPaths.add(assetsRootEntry);
        }
      }
    } else {
      // No assets/ directory exists — nothing to add
    }

    // Normalize and deduplicate while preserving discovery order
    final seen = <String>{};
    final normalized = <String>[];
    for (final pth in explicitPaths) {
      final np = pth.replaceAll('\\', '/');
      if (!seen.contains(np)) {
        normalized.add(np);
        seen.add(np);
      }
    }

    // Step 3: Determine emptiness per path (empty -> comment)
    final pathIsEmpty = <String, bool>{};
    for (final rel in normalized) {
      final abs = p.join(projectRoot, rel);
      final dir = Directory(abs);
      var empty = true;
      if (dir.existsSync()) {
        // check for any file under dir (recursive)
        for (final ent in dir.listSync(recursive: true, followLinks: false)) {
          if (ent is File) {
            empty = false;
            break;
          }
        }
      } else {
        // if directory doesn't exist (maybe user added path manually) mark as empty
        empty = true;
      }
      pathIsEmpty[rel] = empty;
    }

    // Step 4: Build formatted multiline assets block with chosen indentation (2 spaces under flutter:)
    final assetLines = StringBuffer();
    assetLines.writeln('  assets:');
    for (final rel in normalized) {
      final emptynote = pathIsEmpty[rel]! ? '  # (empty folder — kept for future assets)' : '';
      assetLines.writeln("    - $rel$emptynote");
    }

    // If nothing found, still keep top-level 'assets/' as placeholder
    if (normalized.isEmpty) {
      assetLines.writeln("    - assets/  # (empty folder — kept for future assets)");
    }

    // Step 5: Build formatted multiline fonts block
    final fontsBlock = _buildFontsBlockMultiLine(projectRoot);

    // Step 6: Replace the placeholder single-line representations "  assets: []" and "  fonts: []"
    // in the intermediate YAML with our multiline blocks.
    var finalContent = intermediate;

    // Replace assets: [] (which we ensured exists) with expanded block.
    // We look for the first occurrence of "assets:" under a line that begins with two spaces (flutter section).
    // For simplicity, replace the first 'assets:' occurrence that has '[]' after it.
    final assetEmptyPattern = RegExp(r'(^\s{2}assets:\s*\[\s*\])', multiLine: true);
    if (assetEmptyPattern.hasMatch(finalContent)) {
      finalContent = finalContent.replaceFirst(assetEmptyPattern, assetLines.toString());
    } else {
      // If not found as empty inline, try to replace any existing assets: ... block under flutter
      // We'll replace a block that starts with 2 spaces + 'assets:' and continues with indented lines
      final assetBlockPattern = RegExp(r'(^\s{2}assets:\s*\n(?:\s{4}-.*\n)*)', multiLine: true);
      if (assetBlockPattern.hasMatch(finalContent)) {
        finalContent = finalContent.replaceFirst(assetBlockPattern, assetLines.toString());
      } else {
        // as a fallback, insert the assets block after 'flutter:' line
        final flutterHeader = RegExp(r'(^flutter:\s*\n)', multiLine: true);
        if (flutterHeader.hasMatch(finalContent)) {
          finalContent = finalContent.replaceFirstMapped(flutterHeader, (match) => match.group(0)! + assetLines.toString());
        } else {
          // last resort: append at end under flutter:
          finalContent = '$finalContent\n$assetLines';
        }
      }
    }

    // Replace fonts placeholder
    if (fontsBlock.isNotEmpty) {
      final fontsEmptyPattern = RegExp(r'(^\s{2}fonts:\s*\[\s*\])', multiLine: true);
      if (fontsEmptyPattern.hasMatch(finalContent)) {
        finalContent = finalContent.replaceFirst(fontsEmptyPattern, fontsBlock);
      } else {
        final fontsBlockPattern = RegExp(r'(^\s{2}fonts:\s*\n(?:\s{4}-.*\n)*)', multiLine: true);
        if (fontsBlockPattern.hasMatch(finalContent)) {
          finalContent = finalContent.replaceFirst(fontsBlockPattern, fontsBlock);
        } else {
          // insert after assets block if present
          final assetsInsertPoint = RegExp(r'(^\s{2}assets:\s*\n(?:\s{4}-.*\n)*)', multiLine: true);
          if (assetsInsertPoint.hasMatch(finalContent)) {
              
          } else {
            // as last resort, append
            finalContent = '$finalContent\n$fontsBlock';
          }
        }
      }
    }

    // Step 7: Write final content back to pubspec.yaml
    await _write(finalContent);

    // For diagnostics, compute counts added relative to previous state
    // We'll simply return counts: number of explicit asset paths and number of font asset entries
    final assetsAdded = normalized.length;
    final fontsAdded = _countFontEntriesFromBlock(fontsBlock);

    return {'assetsAdded': assetsAdded, 'fontsAdded': fontsAdded};
  }

  /// Builds a multiline fonts block string based on the current fonts found in assets/fonts.
  /// Format:
  ///   fonts:
  ///     - family: Manrope
  ///       fonts:
  ///         - asset: assets/fonts/Manrope-Bold.ttf
  ///         - asset: assets/fonts/Manrope-Regular.ttf
  String _buildFontsBlockMultiLine(String projectRoot) {
    final fontsRoot = p.join(projectRoot, assetsRootName, 'fonts');
    final families = <String, List<String>>{};

    if (!Directory(fontsRoot).existsSync()) {
      return ''; // nothing to write
    }

    // collect font files recursively under assets/fonts
    for (final ent in Directory(fontsRoot).listSync(recursive: true, followLinks: false)) {
      if (ent is File) {
        final rel = p.relative(ent.path, from: projectRoot).replaceAll('\\', '/');
        final filename = p.basenameWithoutExtension(rel);
        final family = _extractFamilyFromFilename(filename);
        families.putIfAbsent(family, () => []).add(rel);
      }
    }

    if (families.isEmpty) return '';

    final sb = StringBuffer();
    sb.writeln('  fonts:');
    // sort family names to keep stable order (alphabetical)
    final famNames = families.keys.toList()..sort();
    for (final fam in famNames) {
      sb.writeln('    - family: $fam');
      sb.writeln('      fonts:');
      final assets = families[fam]!;
      // keep natural discovery order as found in disk listing above
      for (final a in assets) {
        sb.writeln("        - asset: $a");
      }
    }
    return sb.toString();
  }

  int _countFontEntriesFromBlock(String block) {
    if (block.isEmpty) return 0;
    final matches = RegExp(r'asset:\s*(\S+)').allMatches(block);
    return matches.length;
  }

  String _extractFamilyFromFilename(String filename) {
    // heuristic: part before first '-' or '_' or space
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

  /// Read package name from pubspec.yaml top-level `name` field.
  /// Returns null if it cannot be found.
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
