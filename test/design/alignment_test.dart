import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/theme/app_theme.dart';
import 'package:scamshield/widgets/premium.dart';

/// Section links ("See all", "Add member") and row values ("Add", a saved value) sit on the right edge,
/// not floating mid-row (they used to be Flexible next to an Expanded, which split the row 50/50).
void main() {
  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: ListView(children: [child]))),
    ));
  }

  testWidgets('section link is flush with the right edge', (t) async {
    await pump(t, PSection(title: 'Recent attempts', action: 'See all', onAction: () {}));
    expect(t.getRect(find.text('See all')).right, closeTo(344, 1));
    await pump(t, PSection(title: 'Family', action: 'Add member', onAction: () {}));
    expect(t.getRect(find.text('Add member')).right, closeTo(344, 1));
  });

  testWidgets('row values end at the chevron, the same in every row', (t) async {
    await pump(
      t,
      PGroup(children: [
        PRow(label: 'Name', value: 'Add', onTap: () {}),
        PRow(label: 'District', value: 'Raipur', onTap: () {}),
        PRow(label: 'Comfort with phones', value: 'Medium', onTap: () {}, last: true),
      ]),
    );
    final ends = [for (final v in ['Add', 'Raipur', 'Medium']) t.getRect(find.text(v)).right];
    final chevron = t.getRect(find.byIcon(Icons.chevron_right_rounded).first).left;
    for (final e in ends) {
      expect(e, closeTo(ends.first, 0.5));
      expect(chevron - e, lessThan(8));
    }
  });
}
