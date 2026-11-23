import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/onboarding_screen.dart';

/// Every test starts with onboarding already finished (as for a returning user);
/// the HOME_ onboarding tests reset it themselves.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => Onboarding.debugSet(true));
  await testMain();
}
