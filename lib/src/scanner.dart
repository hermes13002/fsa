import 'dart:io';
import 'package:path/path.dart' as p;

class AssetGroup {
  final String groupName; // top-level folder under assets, e.g. images, fonts
  final List<File> files; // files in discovery order (recursive)
  AssetGroup(this.groupName, this.files);
}

class ScanResult {
  final List<AssetGroup> groups;
  ScanResult(this.groups);
  int get totalFiles => groups.fold(0, (s, g) => s + g.files.length);
}

class Scanner {
  final String projectRoot;
  final String assetsDirName;

  Scanner(this.projectRoot, {this.assetsDirName = 'assets'});

  ScanResult scanAssetsRecursive() {
    final assetsPath = p.join(projectRoot, assetsDirName);
    final assetsDir = Directory(assetsPath);
    final groups = <AssetGroup>[];

    if (!assetsDir.existsSync()) {
      print('No assets/ directory found at $assetsPath');
      return ScanResult(groups);
    }

    // Get top-level entries under assets/ (directories)
    final topEntries = assetsDir.listSync(followLinks: false);
    for (final e in topEntries) {
      if (e is Directory) {
        final groupName = p.basename(e.path);
        final files = <File>[];
        // Walk recursively, preserving natural filesystem order
        for (final entity in e.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            files.add(entity);
          }
        }
        if (files.isNotEmpty) groups.add(AssetGroup(groupName, files));
      } else if (e is File) {
        // top-level files directly under assets/ -> group name '' (empty)
        final existing = groups.firstWhere((g) => g.groupName == '', orElse: () {
          final g = AssetGroup('', <File>[]);
          groups.add(g);
          return g;
        });
        existing.files.add(e);
      }
    }

    return ScanResult(groups);
  }
}
