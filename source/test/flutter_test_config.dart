import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Widget tests otherwise substitute Ahem, whose metrics do not represent
  // the bundled UI font. Use the same bytes in layout tests and goldens.
  await (FontLoader('Editor UI')
        ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
      .load();
  await testMain();
}
