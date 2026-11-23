import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/theme/app_theme.dart';

/// Disk-backed bundle so lesson JSON loads without the asset manifest.
class DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(File(key).readAsBytesSync()));
}

final themes = <String, ThemeData Function()>{'light': AppTheme.light, 'dark': AppTheme.dark};

/// Records calls on a fake channel; [handler] supplies replies.
class FakeChannel {
  FakeChannel(this.name, this.handler);
  final String name;
  final Future<Object?> Function(MethodCall) handler;
  final calls = <MethodCall>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (c) async {
      calls.add(c);
      return handler(c);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), null));
  }

  List<MethodCall> named(String m) => calls.where((c) => c.method == m).toList();
}

/// Fakes the live-event EventChannel (listen/cancel accepted) and returns an emitter.
void Function(Map<String, Object?>) fakeEvents() {
  const name = 'scamshield/events';
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel(name), (_) async => null);
  addTearDown(() => m.setMockMethodCallHandler(const MethodChannel(name), null));
  return (e) => m.handlePlatformMessage(
      name, const StandardMethodCodec().encodeSuccessEnvelope(e), (_) {});
}

/// Pumps [home] at 360x740 logical, text scale [scale], with the app's real theme.
Future<void> show(WidgetTester t, ThemeData theme, Widget home,
    {double scale = 2.0, bool settle = true}) async {
  t.view.physicalSize = const Size(360, 740);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: theme,
    builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
    home: Scaffold(body: home),
  ));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Builds (lazy lists) and scrolls [f] into view; fails if it does not exist.
Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    // Lazy lists: jump to the top, then scan down. Driven by the controller, not drag gestures, because a
    // drag that starts on a text field selects text instead of scrolling.
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    pos.jumpTo(pos.minScrollExtent);
    await t.pump();
    while (f.evaluate().isEmpty && pos.pixels < pos.maxScrollExtent) {
      pos.jumpTo((pos.pixels + 150).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await t.pump();
    }
  }
  expect(f, findsOneWidget, reason: 'action not found');
  await t.ensureVisible(f);
}

/// Scrolls [f] into view and taps it; fails if it cannot be hit.
Future<void> tapVisible(WidgetTester t, Finder f) async {
  await reveal(t, f);
  // a just-typed text field scrolls itself into view with a short animation: let it finish before aiming the tap
  await t.pump(const Duration(milliseconds: 400));
  // layout can still shift under a focused field (action bar, caret scroll): re-aim until the target is hittable
  for (var i = 0; i < 4 && f.hitTestable().evaluate().isEmpty; i++) {
    await reveal(t, f);
    await t.pump(const Duration(milliseconds: 400));
  }
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 50));
}

/// Tap target must be at least 48 logical px tall and wide (DESIGN.md).
void expectTapTarget(WidgetTester t, Finder f, {double min = 48}) {
  final s = t.getSize(f);
  expect(s.height, greaterThanOrEqualTo(min), reason: 'tap target height ${s.height}');
  expect(s.width, greaterThanOrEqualTo(min), reason: 'tap target width ${s.width}');
}
