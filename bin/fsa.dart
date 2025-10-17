import 'package:fsa/src/cli.dart';


Future<void> main(List<String> args) async {
  await Cli().run(args);
}