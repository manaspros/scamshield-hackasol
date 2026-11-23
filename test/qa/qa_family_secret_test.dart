import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/family_screen.dart';

import 'qa_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final e in themes.entries) {
    testWidgets('QA_family_showSecret_uniqueKeys_noOverflow_${e.key}_scale2', (t) async {
      final fam = FakeChannel('scamshield/family', (c) async => switch (c.method) {
            'family.status' => {'paired': false},
            'family.newSecret' => 'ABCDEFGHIJKLMNOP',
            'family.code' => {'code': '123456', 'remainingSec': 20},
            _ => null,
          })..install();
      await show(t, e.value(), const FamilyScreen(initialLang: 'en'));
      await tapVisible(t, find.byKey(const Key('family_show')));
      await t.pumpAndSettle();
      expect(fam.named('family.newSecret'), hasLength(1));
      expect(t.takeException(), isNull); // currently: "Duplicate keys found" (family_secret_group x4)
      expect(find.byKey(const Key('family_secret_group')), findsNWidgets(4));
      await tapVisible(t, find.byKey(const Key('family_done')));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('family_code')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  }
}
