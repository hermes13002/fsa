import 'dart:io';
// import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:fsa/src/scanner.dart';
import 'package:fsa/src/pubspec_editor.dart';
import 'package:fsa/src/generator.dart';
import 'package:fsa/src/cli.dart';

void main() {
  late Directory tempDir;
  late String projectRoot;

  setUp(() async {
    // Create a temporary test directory
    tempDir = await Directory.systemTemp.createTemp('fsa_test_');
    projectRoot = tempDir.path;
  });

  tearDown(() async {
    // Clean up temporary directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Scanner Tests', () {
    test('should return empty result when assets directory does not exist', () {
      final scanner = Scanner(projectRoot);
      final result = scanner.scanAssetsRecursive();

      expect(result.groups, isEmpty);
      expect(result.totalFiles, equals(0));
    });

    test('should scan assets with nested folders correctly', () async {
      // Create mock assets structure
      final assetsDir = Directory(p.join(projectRoot, 'assets'));
      final imagesDir = Directory(p.join(assetsDir.path, 'images'));
      final iconsDir = Directory(p.join(imagesDir.path, 'icons'));
      await iconsDir.create(recursive: true);

      // Create test files
      await File(p.join(imagesDir.path, 'logo.png')).writeAsString('mock');
      await File(p.join(iconsDir.path, 'home.svg')).writeAsString('mock');

      final scanner = Scanner(projectRoot);
      final result = scanner.scanAssetsRecursive();

      expect(result.totalFiles, equals(2));
      expect(result.groups.length, equals(1));
      expect(result.groups.first.groupName, equals('images'));
      expect(result.groups.first.files.length, equals(2));
    });

    test('should handle top-level files under assets/', () async {
      final assetsDir = Directory(p.join(projectRoot, 'assets'));
      await assetsDir.create(recursive: true);
      await File(p.join(assetsDir.path, 'config.json')).writeAsString('{}');

      final scanner = Scanner(projectRoot);
      final result = scanner.scanAssetsRecursive();

      expect(result.totalFiles, equals(1));
      expect(result.groups.any((g) => g.groupName == ''), isTrue);
    });

    test('should scan multiple asset groups', () async {
      final assetsDir = Directory(p.join(projectRoot, 'assets'));
      final imagesDir = Directory(p.join(assetsDir.path, 'images'));
      final fontsDir = Directory(p.join(assetsDir.path, 'fonts'));
      await imagesDir.create(recursive: true);
      await fontsDir.create(recursive: true);

      await File(p.join(imagesDir.path, 'logo.png')).writeAsString('mock');
      await File(p.join(fontsDir.path, 'Roboto-Regular.ttf')).writeAsString('mock');

      final scanner = Scanner(projectRoot);
      final result = scanner.scanAssetsRecursive();

      expect(result.totalFiles, equals(2));
      expect(result.groups.length, equals(2));
      expect(result.groups.any((g) => g.groupName == 'images'), isTrue);
      expect(result.groups.any((g) => g.groupName == 'fonts'), isTrue);
    });
  });

  group('PubspecEditor Tests', () {
    test('should create flutter section if missing', () async {
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      await File(pubspecPath).writeAsString('name: test_app\n');

      final editor = PubspecEditor(pubspecPath);
      await editor.ensureFlutterSection();

      final content = await File(pubspecPath).readAsString();
      expect(content, contains('flutter:'));
    });

    test('should throw exception if pubspec.yaml does not exist', () async {
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      final editor = PubspecEditor(pubspecPath);

      expect(() => editor.ensureFlutterSection(), throwsException);
    });

    test('should extract package name from pubspec', () async {
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      await File(pubspecPath).writeAsString('name: my_test_package\nflutter:\n');

      final editor = PubspecEditor(pubspecPath);
      await editor.ensureFlutterSection();

      expect(editor.getPackageName(), equals('my_test_package'));
    });

    test('should update assets with explicit nested folders', () async {
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      await File(pubspecPath).writeAsString('name: test_app\nflutter:\n');

      // Create assets structure
      final assetsDir = Directory(p.join(projectRoot, 'assets'));
      final imagesDir = Directory(p.join(assetsDir.path, 'images'));
      final iconsDir = Directory(p.join(imagesDir.path, 'icons'));
      await iconsDir.create(recursive: true);
      await File(p.join(iconsDir.path, 'home.png')).writeAsString('mock');

      final editor = PubspecEditor(pubspecPath);
      await editor.ensureFlutterSection();
      final counts = await editor.updateAssetsAndFontsExplicit();

      final content = await File(pubspecPath).readAsString();
      expect(content, contains('assets:'));
      expect(content, contains('- assets/images/'));
      expect(content, contains('- assets/images/icons/'));
      expect(counts['assetsAdded'], greaterThan(0));
    });

    test('should handle empty folders with comments', () async {
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      await File(pubspecPath).writeAsString('name: test_app\nflutter:\n');

      // Create empty folder structure
      final assetsDir = Directory(p.join(projectRoot, 'assets'));
      final imagesDir = Directory(p.join(assetsDir.path, 'images'));
      await imagesDir.create(recursive: true);

      final editor = PubspecEditor(pubspecPath);
      await editor.ensureFlutterSection();
      await editor.updateAssetsAndFontsExplicit();

      final content = await File(pubspecPath).readAsString();
      expect(content, contains('empty folder'));
    });

    test('should generate fonts block with family structure', () async {
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      await File(pubspecPath).writeAsString('name: test_app\nflutter:\n');

      // Create fonts
      final fontsDir = Directory(p.join(projectRoot, 'assets', 'fonts'));
      await fontsDir.create(recursive: true);
      await File(p.join(fontsDir.path, 'Roboto-Regular.ttf')).writeAsString('mock');
      await File(p.join(fontsDir.path, 'Roboto-Bold.ttf')).writeAsString('mock');

      final editor = PubspecEditor(pubspecPath);
      await editor.ensureFlutterSection();
      final counts = await editor.updateAssetsAndFontsExplicit();

      final content = await File(pubspecPath).readAsString();
      expect(content, contains('fonts:'));
      expect(content, contains('family: Roboto'));
      expect(counts['fontsAdded'], equals(2));
    });
  });

  group('Generator Tests', () {
    test('should generate app_assets.dart file', () async {
      final imagesDir = Directory(p.join(projectRoot, 'assets', 'images'));
      await imagesDir.create(recursive: true);
      await File(p.join(imagesDir.path, 'logo.png')).writeAsString('mock');

      final scanner = Scanner(projectRoot);
      final scanResult = scanner.scanAssetsRecursive();

      final generator = Generator(projectRoot);
      await generator.generate(scanResult);

      final outputFile = File(p.join(projectRoot, 'lib', 'core', 'assets', 'app_assets.dart'));
      expect(await outputFile.exists(), isTrue);

      final content = await outputFile.readAsString();
      expect(content, contains('class AppAssets'));
      expect(content, contains('class AppImages'));
      expect(content, contains('GENERATED CODE'));
    });

    test('should generate correct constant names', () async {
      final imagesDir = Directory(p.join(projectRoot, 'assets', 'images', 'icons'));
      await imagesDir.create(recursive: true);
      await File(p.join(imagesDir.path, 'home-icon.png')).writeAsString('mock');
      await File(p.join(imagesDir.path, 'user_profile.svg')).writeAsString('mock');

      final scanner = Scanner(projectRoot);
      final scanResult = scanner.scanAssetsRecursive();

      final generator = Generator(projectRoot);
      await generator.generate(scanResult);

      final outputFile = File(p.join(projectRoot, 'lib', 'core', 'assets', 'app_assets.dart'));
      final content = await outputFile.readAsString();

      expect(content, contains('ICONS_HOME_ICON_PNG'));
      expect(content, contains('ICONS_USER_PROFILE_SVG'));
    });

    test('should handle files starting with digits', () async {
      final imagesDir = Directory(p.join(projectRoot, 'assets', 'images'));
      await imagesDir.create(recursive: true);
      await File(p.join(imagesDir.path, '3d-model.png')).writeAsString('mock');

      final scanner = Scanner(projectRoot);
      final scanResult = scanner.scanAssetsRecursive();

      final generator = Generator(projectRoot);
      await generator.generate(scanResult);

      final outputFile = File(p.join(projectRoot, 'lib', 'core', 'assets', 'app_assets.dart'));
      final content = await outputFile.readAsString();

      expect(content, contains('_3D_MODEL_PNG'));
    });

    test('should generate font families class', () async {
      final fontsDir = Directory(p.join(projectRoot, 'assets', 'fonts'));
      await fontsDir.create(recursive: true);
      await File(p.join(fontsDir.path, 'Manrope-Regular.ttf')).writeAsString('mock');
      await File(p.join(fontsDir.path, 'Manrope-Bold.ttf')).writeAsString('mock');

      final scanner = Scanner(projectRoot);
      final scanResult = scanner.scanAssetsRecursive();

      final generator = Generator(projectRoot);
      await generator.generate(scanResult);

      final outputFile = File(p.join(projectRoot, 'lib', 'core', 'assets', 'app_assets.dart'));
      final content = await outputFile.readAsString();

      expect(content, contains('class AppFontFamilies'));
      expect(content, contains('MANROPE'));
    });

    test('should include summary comments', () async {
      final imagesDir = Directory(p.join(projectRoot, 'assets', 'images'));
      final fontsDir = Directory(p.join(projectRoot, 'assets', 'fonts'));
      await imagesDir.create(recursive: true);
      await fontsDir.create(recursive: true);
      await File(p.join(imagesDir.path, 'logo.png')).writeAsString('mock');
      await File(p.join(fontsDir.path, 'Roboto-Regular.ttf')).writeAsString('mock');

      final scanner = Scanner(projectRoot);
      final scanResult = scanner.scanAssetsRecursive();

      final generator = Generator(projectRoot);
      await generator.generate(scanResult);

      final outputFile = File(p.join(projectRoot, 'lib', 'core', 'assets', 'app_assets.dart'));
      final content = await outputFile.readAsString();

      expect(content, contains('Images: 1'));
      expect(content, contains('Fonts: 1'));
    });
  });

  group('CLI Tests', () {
    test('should show usage when no arguments provided', () async {
      final cli = Cli();
      await cli.run([]);
      
      expect(exitCode, equals(64));
    });

    test('should show usage for invalid command', () async {
      final cli = Cli();
      await cli.run(['invalid']);
      
      expect(exitCode, equals(64));
    });

    test('should run full generation process', () async {
      // Setup test project
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      await File(pubspecPath).writeAsString('name: test_project\nflutter:\n');

      final imagesDir = Directory(p.join(projectRoot, 'assets', 'images'));
      await imagesDir.create(recursive: true);
      await File(p.join(imagesDir.path, 'logo.png')).writeAsString('mock');

      // Change to project directory
      final originalDir = Directory.current;
      Directory.current = projectRoot;

      try {
        final cli = Cli();
        await cli.run(['generate']);

        // Verify pubspec was updated
        final pubspecContent = await File(pubspecPath).readAsString();
        expect(pubspecContent, contains('assets:'));

        // Verify generated file exists
        final outputFile = File(p.join(projectRoot, 'lib', 'core', 'assets', 'app_assets.dart'));
        expect(await outputFile.exists(), isTrue);
      } finally {
        Directory.current = originalDir;
      }
    });
  });

  group('Integration Tests', () {
    test('should handle complete workflow with multiple asset types', () async {
      // Setup comprehensive test project
      final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
      await File(pubspecPath).writeAsString('name: integration_test\nflutter:\n');

      // Create various asset types
      final imagesDir = Directory(p.join(projectRoot, 'assets', 'images'));
      final fontsDir = Directory(p.join(projectRoot, 'assets', 'fonts'));
      final lottieDir = Directory(p.join(projectRoot, 'assets', 'lottie'));
      
      await imagesDir.create(recursive: true);
      await fontsDir.create(recursive: true);
      await lottieDir.create(recursive: true);

      await File(p.join(imagesDir.path, 'logo.png')).writeAsString('mock');
      await File(p.join(fontsDir.path, 'Roboto-Regular.ttf')).writeAsString('mock');
      await File(p.join(lottieDir.path, 'loading.json')).writeAsString('{}');

      // Run scanner
      final scanner = Scanner(projectRoot);
      final scanResult = scanner.scanAssetsRecursive();

      expect(scanResult.totalFiles, equals(3));
      expect(scanResult.groups.length, equals(3));

      // Update pubspec
      final editor = PubspecEditor(pubspecPath);
      await editor.ensureFlutterSection();
      await editor.updateAssetsAndFontsExplicit();

      // Generate code
      final generator = Generator(projectRoot);
      await generator.generate(scanResult);

      // Verify all outputs
      final pubspecContent = await File(pubspecPath).readAsString();
      expect(pubspecContent, contains('assets/images/'));
      expect(pubspecContent, contains('assets/fonts/'));
      expect(pubspecContent, contains('assets/lottie/'));

      final outputFile = File(p.join(projectRoot, 'lib', 'core', 'assets', 'app_assets.dart'));
      final generatedContent = await outputFile.readAsString();
      expect(generatedContent, contains('class AppImages'));
      expect(generatedContent, contains('class AppFonts'));
      expect(generatedContent, contains('class AppLottie'));
    });
  });
}
