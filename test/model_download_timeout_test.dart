import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/api/model_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('scamshield/api');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(ch, null));
  final spec = kFallbackCatalog.first;

  test('a slow start (HEAD request on a slow link) reads as PENDING, not "Not available"', () async {
    final never = Completer<Object?>();
    messenger.setMockMethodCallHandler(ch, (c) async => switch (c.method) {
          'downloadModel' => never.future, // still checking the link when the timeout fires
          'modelStatus' => {'status': 'NOT_FOUND'},
          _ => null,
        });
    final r = await const ModelApi(downloadTimeout: Duration(milliseconds: 50)).download(spec);
    expect(r['status'], 'PENDING');
  });

  test('no native side at all is still an error', () async {
    final r = await const ModelApi(downloadTimeout: Duration(milliseconds: 50)).download(spec);
    expect(r['status'], 'ERROR');
  });

  test('a prompt reply is passed through', () async {
    messenger.setMockMethodCallHandler(ch, (c) async => c.method == 'downloadModel' ? {'status': 'PENDING', 'done': 0} : null);
    expect((await const ModelApi().download(spec))['done'], 0);
  });
}
