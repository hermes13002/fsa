import 'dart:io';
import 'dart:developer';
import 'package:path/path.dart' as p;
import 'scanner.dart';
import 'pubspec_editor.dart';
import 'generator.dart';

class Cli {
  Future<void> run(List<String> args) async {
    if (args.isEmpty || args.first != 'generate') {
      log('Usage: fsa generate');
      exitCode = 64;
      return;
    }

    final projectRoot = Directory.current.path;
    log('Scanning project at: $projectRoot');

    final scanner = Scanner(projectRoot);
    final scanResult = scanner.scanAssetsRecursive();

    log('Found ${scanResult.totalFiles} asset files across ${scanResult.groups.length} groups.');
    log('Preparing to update pubspec.yaml (safe mode)...');

    final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
    final editor = PubspecEditor(pubspecPath);
    try {
      await editor.ensureFlutterSection();
    } catch (e) {
      log('Error: ${e.toString()}');
      return;
    }

    // Use the new async API which returns a map with counts
    final counts = await editor.updateAssetsAndFontsExplicit();
    final assetsAdded = counts['assetsAdded'] ?? 0;
    final fontsAdded = counts['fontsAdded'] ?? 0;
    if (assetsAdded > 0 || fontsAdded > 0) {
      log('Updated pubspec.yaml: +$assetsAdded asset entries, +$fontsAdded font entries.');
    } else {
      log('No changes required in pubspec.yaml.');
    }

    log('Generating Dart asset class at lib/core/assets/app_assets.dart...');
    final generator = Generator(projectRoot);
    await generator.generate(scanResult);

    final pkgName = editor.getPackageName();
    final importPath = pkgName != null
        ? "package:$pkgName/core/assets/app_assets.dart"
        : "package:<your_package>/core/assets/app_assets.dart";
    log('Done. Import from: $importPath');
  }
}
