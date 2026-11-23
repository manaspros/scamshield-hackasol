import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/screens/live_feed_screen.dart';

import 'qa_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final e in themes.entries) {
    testWidgets('QA_liveFeed_noOverflow_listUsable_360x740_${e.key}_scale2', (t) async {
      final emit = fakeEvents();
      await show(t, e.value(), const LiveFeedScreen());
      expect(t.takeException(), isNull); // empty state must not overflow
      emit({'type': 'error', 'where': 'model', 'message': 'boom'});
      emit({'type': 'service', 'connected': false});
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // the feed list must keep a usable share of the screen (>= 25% of 740) under the status card
      expect(t.getSize(find.byType(ListView)).height, greaterThanOrEqualTo(185));
      expect(find.text('Protection service stopped'), findsOneWidget);
    });
  }
}
