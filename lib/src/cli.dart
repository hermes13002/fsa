import 'dart:io';
import 'package:path/path.dart' as p;
import 'scanner.dart';
import 'pubspec_editor.dart';
import 'generator.dart';

class Cli {
  Future<void> run(List<String> args) async {
    if (args.isEmpty || args.first != 'generate') {
      print('Usage: fsa generate');
      exitCode = 64;
      return;
    }

    final projectRoot = Directory.current.path;
    print('Scanning project at: $projectRoot');

    final scanner = Scanner(projectRoot);
    final scanResult = scanner.scanAssetsRecursive();

    print('Found ${scanResult.totalFiles} asset files across ${scanResult.groups.length} groups.');
    print('Preparing to update pubspec.yaml (safe mode)...');

    final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
    final editor = PubspecEditor(pubspecPath);
    try {
      await editor.ensureFlutterSection();
    } catch (e) {
      print('Error: ${e.toString()}');
      return;
    }

    // Use the new async API which returns a map with counts
    final counts = await editor.updateAssetsAndFontsExplicit();
    final assetsAdded = counts['assetsAdded'] ?? 0;
    final fontsAdded = counts['fontsAdded'] ?? 0;
    if (assetsAdded > 0 || fontsAdded > 0) {
      print('Updated pubspec.yaml: +$assetsAdded asset entries, +$fontsAdded font entries.');
    } else {
      print('No changes required in pubspec.yaml.');
    }

    print('Generating Dart asset class at lib/core/assets/app_assets.dart...');
    final generator = Generator(projectRoot);
    await generator.generate(scanResult);

    final pkgName = editor.getPackageName();
    final importPath = pkgName != null
        ? "package:$pkgName/core/assets/app_assets.dart"
        : "package:<your_package>/core/assets/app_assets.dart";
    print('Done. Import from: $importPath');
  }
}
