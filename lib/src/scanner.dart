import 'dart:io';
import 'package:path/path.dart' as p;

class AssetGroup {
  final String groupName; // top-level folder under assets, like images or fonts
  final List<File> files; // files in the order we found them (recursive)
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

    // get top-level stuff under assets/ (directories)
    final topEntries = assetsDir.listSync(followLinks: false);
    for (final e in topEntries) {
      if (e is Directory) {
        final groupName = p.basename(e.path);
        final files = <File>[];
        // walk recursively, keep natural filesystem order
        for (final entity in e.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            files.add(entity);
          }
        }
        if (files.isNotEmpty) groups.add(AssetGroup(groupName, files));
      } else if (e is File) {
        // top-level files directly under assets/ -> group name is empty string
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
