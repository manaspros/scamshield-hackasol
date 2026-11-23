import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/llm_api.dart';
import 'package:scamshield/learn/learn_plan.dart';
import 'package:scamshield/profile/user_profile.dart';
import 'package:scamshield/screens/onboarding_screen.dart';
import 'package:scamshield/theme/theme_controller.dart';

/// Every test starts with onboarding already finished (as for a returning user);
/// the HOME_ onboarding tests reset it themselves.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    Onboarding.debugSet(true);
    // App-wide stores are static: start every test from an empty profile, plan, system theme and no model.
    LearnStore.debugReset();
    ProfileStore.debugReset();
    ThemeController.debugReset();
    LlmStatus.ready.value = false;
  });
  await testMain();
}
