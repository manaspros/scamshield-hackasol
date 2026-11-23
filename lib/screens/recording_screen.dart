import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/report_upload.dart';
import '../demo/demo_flag.dart' show kAppVersion;
import '../l10n/app_language.dart';
import '../l10n/strings_profile.dart';
import '../models/verdict.dart';
import '../recording/call_explainer.dart';
import '../theme/app_theme.dart' show StatusColors;
import '../theme/tokens.dart';
import '../widgets/a11y.dart';
import '../widgets/action_tile.dart';
import '../widgets/island.dart';
import '../widgets/premium.dart';
import '../widgets/segmented.dart';
import '../widgets/shell_bar.dart' show openReport;
import '../widgets/state_message.dart';
import '../widgets/status_chip.dart';
import 'model_picker_screen.dart';
import 'page_route.dart';
import 'settings_screen.dart' show kDistricts;
import 'speech_model_screen.dart';

/// Client for the native recording channel (K/RecordingChannel.kt).
/// Method calls return false instead of throwing, so the screen shows an error, not a crash.
/// Events (EventChannel `scamshield/recording/events`) are maps:
///   {stage: download|decode|stt|classify|done|error|shared, pct: 0..100,
///    segment?: {startMs, text}            (stt),
///    statement?: {startMs, text, label, triggers}   (classify),
///    ready?: true                         (download finished),
///    report?: {overall, risk, statements: [statement...], topTriggers}   (done),
///    code?: failed|noSpeech|download|cancelled      (error)}
class RecordingApi {
  RecordingApi({MethodChannel? channel, Stream<Object?>? events})
      : channel = channel ?? const MethodChannel('scamshield/recording'),
        events = events ?? _shared;

  /// One platform subscription shared by every screen (the recording screen and Settings › Speech model can be
  /// open at once); a second receiveBroadcastStream() would steal the native sink from the first.
  static final Stream<Object?> _shared = const EventChannel('scamshield/recording/events').receiveBroadcastStream();
  final MethodChannel channel;
  final Stream<Object?> events;

  Future<bool> _ok(String m) async {
    try {
      return await channel.invokeMethod<bool>(m) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> modelReady() async => (await status()).ready;

  /// Whether a speech model is installed, and which one.
  Future<({bool ready, String? sttId})> status() async {
    try {
      final m = await channel.invokeMapMethod<Object?, Object?>('recording.status');
      return (ready: m?['modelReady'] == true, sttId: m?['sttId'] as String?);
    } on MissingPluginException {
      return (ready: false, sttId: null);
    } on PlatformException {
      return (ready: false, sttId: null);
    }
  }

  /// Call recordings already on the phone (OEM call-recorder folders), newest first. `granted` is false until the
  /// user allows audio access; then [requestAccess] asks for it.
  Future<({bool granted, List<CallRecording> items})> list() async {
    try {
      final m = await channel.invokeMapMethod<Object?, Object?>('recording.list');
      final items = ((m?['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => CallRecording.fromMap(e.cast<Object?, Object?>()))
          .toList();
      return (granted: m?['granted'] == true, items: items);
    } on MissingPluginException {
      return (granted: true, items: const <CallRecording>[]);
    } on PlatformException {
      return (granted: true, items: const <CallRecording>[]);
    }
  }

  Future<void> requestAccess() => _ok('recording.requestAccess');

  /// Holds a listed recording as the pending file; [start] then checks it.
  Future<bool> use(String uri) async {
    try {
      return await channel.invokeMethod<bool>('recording.use', {'uri': uri}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// True when a file was chosen (or one was shared in) and is waiting for [start].
  Future<bool> pending() => _ok('recording.pending');
  Future<bool> pick() => _ok('recording.pick');
  Future<bool> start() => _ok('recording.start');
  Future<bool> downloadModel([String? id]) async {
    try {
      return await channel.invokeMethod<bool>('recording.downloadModel', {'id': id}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
  Future<bool> cancel() => _ok('recording.cancel');
}

/// One call recording found on the phone.
class CallRecording {
  const CallRecording({required this.uri, required this.name, required this.dateMs, required this.durationMs});
  factory CallRecording.fromMap(Map<Object?, Object?> m) => CallRecording(
        uri: '${m['uri'] ?? ''}',
        name: '${m['name'] ?? ''}',
        dateMs: (m['dateMs'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      );
  final String uri, name;
  final int dateMs, durationMs;
}

/// Screen text in Hindi (default), Chhattisgarhi and English; same keys in all three.
class RecordingStrings {
  const RecordingStrings(this.m);
  final Map<String, String> m;
  String operator [](String k) => m[k] ?? k;

  static const hi = RecordingStrings({
    'noModelT': 'पहले बोली का मॉडल लें',
    'noModelS': 'रिकॉर्डिंग सुनने के लिए ScamShield को एक छोटा ऑफ़लाइन मॉडल चाहिए। अपने फ़ोन के हिसाब से चुनें।',
    'chipOffline': 'बिना इंटरनेट', 'chipSize': '36 MB से', 'chipPrivate': 'आवाज़ फ़ोन में ही',
    'getModel': 'बोली का मॉडल लें', 'opensSettings': 'सेटिंग › बोली का मॉडल खुलेगा',
    'upload': 'रिकॉर्डिंग फ़ाइल चुनें', 'uploadSub': 'इस फ़ोन से MP3, M4A, WAV या AMR',
    'fromCalls': 'आपकी कॉल रिकॉर्डिंग', 'found': '{n} मिलीं',
    'allowT': 'कॉल रिकॉर्डिंग दिखाने दें', 'allowS': 'ताकि आप फ़ाइल ढूँढे बिना सीधे चुन सकें', 'allow': 'अनुमति दें',
    'noneFound': 'कोई कॉल रिकॉर्डिंग नहीं मिली। ऊपर से फ़ाइल चुनें।',
    'today': 'आज', 'yesterday': 'कल', 'months': 'जन,फ़र,मार्च,अप्रैल,मई,जून,जुल,अग,सित,अक्टू,नव,दिस',
    'live': 'लाइव पाठ', 'heard': '{a} में से {b} सुना', 'readyPill': 'पाठ तैयार · {n} पंक्तियाँ',
    'aiT': 'पूरी कॉल पढ़ी जा रही है…', 'aiS': 'फ़ोन पर चलने वाला AI पूरी बातचीत एक साथ देखकर आसान भाषा में समझाता है।',
    'ai1': 'कौन बोल रहा है और क्यों', 'ai2': 'दबाव, राज़ और पैसे की माँग', 'ai3': 'आपके लिए आसान समझ',
    'byAi': 'AI ने समझाया', 'riskFor': 'पूरी कॉल का ख़तरा', 'what': 'क्या हुआ', 'flags': 'कॉल में ख़तरे के संकेत', 'todo': 'अब क्या करें',
    'fullT': 'पूरा पाठ', 'fullS': '{n} पंक्तियाँ', 'confirmQ': 'क्या सच में ठगी थी?', 'confirmS': 'आपके जवाब से ScamShield बेहतर बनता है।',
    'yes': 'हाँ, ठगी', 'no': 'नहीं', 'unsure': 'पता नहीं', 'thanks': 'धन्यवाद! आपका जवाब मिल गया।',
    'shareT': 'दूसरों को बचाएँ?', 'shareB': 'यह कॉल ScamShield के साथ साझा करें, ताकि आपके ज़िले के लोगों को इसी चाल से सावधान किया जा सके।',
    'sentH': 'क्या भेजा जाएगा', 'sentDistrict': 'ज़िला', 'sentText': 'कॉल का पाठ, नंबर छिपे हुए', 'sentAi': 'AI का नतीजा और आपका जवाब',
    'never': 'कभी नहीं भेजा जाता: आपका नंबर, आवाज़, आपका नाम', 'share': 'साझा करें', 'noThanks': 'नहीं, धन्यवाद',
    'shared': 'साझा हो गया। धन्यवाद!', 'shareFail': 'अभी नहीं भेज सके। बाद में फिर कोशिश करें।',
    'noAi': 'साफ़ समझ के लिए AI मॉडल लें', 'noAiS': 'अभी यह नतीजा सिर्फ़ शब्दों की जाँच से है।', 'pickDistrict': 'अपना ज़िला चुनें',
    'explainLang': 'समझाने की भाषा', 'ans_true': 'ठगी', 'ans_false': 'ठगी नहीं', 'ans_null': 'पता नहीं',
    'title': 'कॉल की रिकॉर्डिंग जाँचें',
    'pick': 'रिकॉर्डिंग चुनें',
    'pickSub': 'फ़ोन में रखी कॉल रिकॉर्डिंग खोलें।',
    'download': 'पहले बोली पहचानने वाला मॉडल लें',
    'downloadSub': 'सिर्फ़ एक बार, लगभग 42 MB। उसके बाद बिना इंटरनेट चलेगा।',
    'cancel': 'रोकें',
    'stage_download': 'मॉडल उतर रहा है',
    'stage_decode': 'आवाज़ खोली जा रही है',
    'stage_stt': 'बात सुनकर लिखी जा रही है',
    'stage_classify': 'हर बात जाँची जा रही है',
    'riskTitle': 'पूरी कॉल का ख़तरा',
    'triggers': 'शक वाले शब्द',
    'timeline': 'कॉल में क्या-क्या कहा गया',
    'report': 'शिकायत दर्ज करें',
    'reportSub': 'सबूत और 1930 की मदद',
    'privacy': 'आवाज़ और लिखा हुआ पाठ सिर्फ़ इस स्क्रीन पर रहता है। ऐप इन्हें सहेजता नहीं।',
    'err_failed': 'रिकॉर्डिंग जाँची नहीं जा सकी। दूसरी फ़ाइल चुनें।',
    'err_noSpeech': 'इसमें बोली नहीं मिली। दूसरी फ़ाइल चुनें।',
    'err_download': 'मॉडल नहीं उतर सका। इंटरनेट देखकर फिर कोशिश करें।',
    'l_safe': 'सामान्य',
    'l_suspicious': 'सावधान',
    'l_scam': 'ठगी',
    'empty': 'कॉल की रिकॉर्डिंग चुनें, हम बताएँगे कि कहीं ठगी तो नहीं',
    'listening': 'सुन रहे हैं… लंबी रिकॉर्डिंग में कुछ मिनट लग सकते हैं',
    'counter': 'जाँची गई बातें: {n}',
    'retry': 'फिर कोशिश करें',
    'sum_safe': 'इस कॉल में ठगी के संकेत नहीं मिले।',
    'sum_suspicious': 'इस कॉल में कुछ बातें शक वाली हैं। सावधान रहें।',
    'sum_scam': 'इस कॉल में ठगी के संकेत हैं। पैसे या OTP न दें।',
    'firstFlag': 'पहली चेतावनी {t} पर आई',
  });

  static const hne = RecordingStrings({
    'noModelT': 'पहिली बोली के मॉडल लव',
    'noModelS': 'रिकॉर्डिंग सुने बर ScamShield ल एक छोटे ऑफ़लाइन मॉडल चाही। अपन फ़ोन के हिसाब ले चुनव।',
    'chipOffline': 'बिना इंटरनेट', 'chipSize': '36 MB ले', 'chipPrivate': 'अवाज फ़ोन म ही',
    'getModel': 'बोली के मॉडल लव', 'opensSettings': 'सेटिंग › बोली के मॉडल खुलही',
    'upload': 'रिकॉर्डिंग फाइल चुनव', 'uploadSub': 'ए फ़ोन ले MP3, M4A, WAV या AMR',
    'fromCalls': 'तुंहर कॉल रिकॉर्डिंग', 'found': '{n} मिलिस',
    'allowT': 'कॉल रिकॉर्डिंग देखाय दव', 'allowS': 'ताकि फाइल खोजे बिना सीधा चुन सकव', 'allow': 'अनुमति दव',
    'noneFound': 'कोनो कॉल रिकॉर्डिंग नइ मिलिस। ऊपर ले फाइल चुनव।',
    'today': 'आज', 'yesterday': 'काली', 'months': 'जन,फ़र,मार्च,अप्रैल,मई,जून,जुल,अग,सित,अक्टू,नव,दिस',
    'live': 'लाइव पाठ', 'heard': '{a} म ले {b} सुनिस', 'readyPill': 'पाठ तइयार · {n} लाइन',
    'aiT': 'पूरा कॉल पढ़े जात हे…', 'aiS': 'फ़ोन म चलइया AI पूरा गोठ ल एक संग देख के सरल भासा म समझाथे।',
    'ai1': 'कोन गोठियावत हे अउ काबर', 'ai2': 'दबाव, राज अउ पइसा के माँग', 'ai3': 'तुंहर बर सरल समझ',
    'byAi': 'AI ह समझाइस', 'riskFor': 'पूरा कॉल के खतरा', 'what': 'का होइस', 'flags': 'कॉल म खतरा के संकेत', 'todo': 'अब का करव',
    'fullT': 'पूरा पाठ', 'fullS': '{n} लाइन', 'confirmQ': 'का सिरतोन ठगी रहिस?', 'confirmS': 'तुंहर जवाब ले ScamShield बढ़िया बनथे।',
    'yes': 'हव, ठगी', 'no': 'नहीं', 'unsure': 'पता नइ', 'thanks': 'धन्यवाद! तुंहर जवाब मिलगे।',
    'shareT': 'दूसर मन ल बचावव?', 'shareB': 'ए कॉल ल ScamShield संग साझा करव, ताकि तुंहर जिला के मनखे ल इही चाल ले सावधान करे जा सकय।',
    'sentH': 'का भेजे जाही', 'sentDistrict': 'जिला', 'sentText': 'कॉल के पाठ, नंबर लुकाय', 'sentAi': 'AI के नतीजा अउ तुंहर जवाब',
    'never': 'कभू नइ भेजे जाय: तुंहर नंबर, अवाज, तुंहर नाँव', 'share': 'साझा करव', 'noThanks': 'नहीं, धन्यवाद',
    'shared': 'साझा होगे। धन्यवाद!', 'shareFail': 'अभी नइ भेज सकेन। बाद म फेर कोसिस करव।',
    'noAi': 'साफ समझ बर AI मॉडल लव', 'noAiS': 'अभी ए नतीजा सिरिफ सब्द जाँच ले हे।', 'pickDistrict': 'अपन जिला चुनव',
    'explainLang': 'समझाय के भासा', 'ans_true': 'ठगी', 'ans_false': 'ठगी नइ', 'ans_null': 'पता नइ',
    'title': 'कॉल के रिकॉर्डिंग जांचव',
    'pick': 'रिकॉर्डिंग चुनव',
    'pickSub': 'फोन म रखाय कॉल रिकॉर्डिंग खोलव।',
    'download': 'पहिली बोली चिन्हइया मॉडल लव',
    'downloadSub': 'सिरिफ एक पईंत, लगभग 42 MB। तेकर बाद बिना इंटरनेट चलही।',
    'cancel': 'रोकव',
    'stage_download': 'मॉडल उतरत हे',
    'stage_decode': 'अवाज खोले जात हे',
    'stage_stt': 'गोठ सुन के लिखे जात हे',
    'stage_classify': 'हर गोठ जांचे जात हे',
    'riskTitle': 'पूरा कॉल के खतरा',
    'triggers': 'शक वाले सब्द',
    'timeline': 'कॉल म का-का कहे गिस',
    'report': 'शिकायत दर्ज करव',
    'reportSub': 'सबूत अउ 1930 के मदद',
    'privacy': 'अवाज अउ लिखे पाठ सिरिफ ए स्क्रीन म रहिथे। ऐप ह एला सहेजय नइ।',
    'err_failed': 'रिकॉर्डिंग जांचे नइ जा सकिस। दूसर फाइल चुनव।',
    'err_noSpeech': 'एमा बोली नइ मिलिस। दूसर फाइल चुनव।',
    'err_download': 'मॉडल नइ उतर सकिस। इंटरनेट देख के फेर कोसिस करव।',
    'l_safe': 'सामान्य',
    'l_suspicious': 'सावधान',
    'l_scam': 'ठगी',
    'empty': 'कॉल के रिकॉर्डिंग चुनव, हम बताबो कि कहूँ ठगी तो नइहे',
    'listening': 'सुनत हन… लंबा रिकॉर्डिंग म कुछ मिनट लग सकथे',
    'counter': 'जांचे गोठ: {n}',
    'retry': 'फेर कोसिस करव',
    'sum_safe': 'ए कॉल म ठगी के संकेत नइ मिलिस।',
    'sum_suspicious': 'ए कॉल म कुछ गोठ शक वाले हें। सावधान रहव।',
    'sum_scam': 'ए कॉल म ठगी के संकेत हे। पइसा या OTP झन देव।',
    'firstFlag': 'पहिली चेतावनी {t} म आइस',
  });

  static const en = RecordingStrings({
    'noModelT': 'First, get the speech model',
    'noModelS': 'ScamShield needs a small offline model to listen to a recording. Choose the one that suits your phone.',
    'chipOffline': 'Works offline', 'chipSize': 'From 36 MB', 'chipPrivate': 'Audio stays on phone',
    'getModel': 'Get speech model', 'opensSettings': 'Opens Settings › Speech model',
    'upload': 'Upload a recording file', 'uploadSub': 'MP3, M4A, WAV or AMR from this phone',
    'fromCalls': 'From your call recordings', 'found': '{n} found',
    'allowT': 'Show my call recordings', 'allowS': 'Pick one directly instead of searching for the file', 'allow': 'Allow',
    'noneFound': 'No call recordings found. Use Upload above.',
    'today': 'Today', 'yesterday': 'Yesterday', 'months': 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec',
    'live': 'Live transcript', 'heard': '{a} of {b} heard', 'readyPill': 'Transcript ready · {n} lines',
    'aiT': 'Reading the whole call…', 'aiS': 'The on-device AI looks at everything that was said, together, and explains it simply.',
    'ai1': 'Who is calling and why', 'ai2': 'Pressure, secrets and money asks', 'ai3': 'A simple explanation for you',
    'byAi': 'Explained by on-device AI', 'riskFor': 'risk for the whole call', 'what': 'What happened', 'flags': 'Red flags in the call', 'todo': 'What to do now',
    'fullT': 'Full transcript', 'fullS': '{n} lines', 'confirmQ': 'Was this really a scam?', 'confirmS': 'Your answer helps ScamShield get better.',
    'yes': 'Yes, scam', 'no': 'No', 'unsure': 'Not sure', 'thanks': 'Thanks! Your answer is saved.',
    'shareT': 'Help protect others?', 'shareB': 'Share this call with ScamShield so we can warn people in your district about the same trick.',
    'sentH': 'What is sent', 'sentDistrict': 'District', 'sentText': 'Call text, numbers hidden', 'sentAi': 'AI result and your answer',
    'never': 'Never sent: your number, the audio, your name', 'share': 'Share', 'noThanks': 'No thanks',
    'shared': 'Shared. Thank you!', 'shareFail': 'Could not send right now. Please try again later.',
    'noAi': 'Get the AI model for a clear explanation', 'noAiS': 'This result comes from a keyword check only.', 'pickDistrict': 'Choose your district',
    'explainLang': 'Explanation language', 'ans_true': 'Scam', 'ans_false': 'Not a scam', 'ans_null': 'Not sure',
    'title': 'Check a call recording',
    'pick': 'Pick a recording',
    'pickSub': 'Open a call recording saved on this phone.',
    'download': 'First get the speech model',
    'downloadSub': 'One time, about 42 MB. After that it works offline.',
    'cancel': 'Stop',
    'stage_download': 'Downloading the model',
    'stage_decode': 'Opening the audio',
    'stage_stt': 'Listening and writing it down',
    'stage_classify': 'Checking each statement',
    'riskTitle': 'Risk for the whole call',
    'triggers': 'Suspicious phrases',
    'timeline': 'What was said in the call',
    'report': 'Report a scam',
    'reportSub': 'Evidence and the 1930 helpline',
    'privacy': 'The audio and the text stay on this screen only. The app does not save them.',
    'err_failed': 'Could not check this recording. Pick another file.',
    'err_noSpeech': 'No speech found in this file. Pick another file.',
    'err_download': 'Could not download the model. Check the internet and try again.',
    'l_safe': 'Normal',
    'l_suspicious': 'Be careful',
    'l_scam': 'Scam',
    'empty': 'Pick a call recording and we will tell you if it is a scam',
    'listening': 'Listening… a long recording can take a few minutes',
    'counter': '{n} statements checked',
    'retry': 'Try again',
    'sum_safe': 'No signs of a scam were found in this call.',
    'sum_suspicious': 'Some things in this call look suspicious. Be careful.',
    'sum_scam': 'This call shows signs of a scam. Do not give money or an OTP.',
    'firstFlag': 'First warning came at {t}',
  });

  static const all = {'hi': hi, 'hne': hne, 'en': en};
  static RecordingStrings of(String lang) => all[lang] ?? hi;
}

class _Stmt {
  _Stmt(Map<Object?, Object?> m)
      : startMs = (m['startMs'] as num?)?.toInt() ?? 0,
        text = '${m['text'] ?? ''}',
        label = parseLabel(m['label']),
        triggers = ((m['triggers'] as List?) ?? const []).map((e) => '$e').toList();
  final int startMs;
  final String text;
  final RiskLabel label;
  final List<String> triggers;
}

class _Report {
  _Report(Map<Object?, Object?> m)
      : overall = parseLabel(m['overall']),
        risk = ((m['risk'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        statements = ((m['statements'] as List?) ?? const []).map((e) => _Stmt((e as Map).cast<Object?, Object?>())).toList(),
        topTriggers = ((m['topTriggers'] as List?) ?? const []).map((e) => '$e').toList();
  final RiskLabel overall;
  final double risk;
  final List<_Stmt> statements;
  final List<String> topTriggers;
}

/// idle: pick a file · working: transcribing · explaining: the AI reads the whole call · done · error.
enum _Phase { idle, working, explaining, done, error }

/// Recorded-call screen. Pick an audio file (upload, the phone's own call recordings, or a share), watch one live
/// transcript build up, then the on-device AI reads the whole call at once and explains it. The user confirms
/// whether it was a scam and may share it (with consent) to the district dashboard.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key, this.initialLang, this.api, this.explainer = const CallExplainer(), this.sender = const HttpReportSender()});
  final String? initialLang; // null: follow the app-wide language

  /// Injected in tests; the default talks to the native channel.
  final RecordingApi? api;
  final CallExplainer explainer;
  final ReportSender sender;
  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> with WidgetsBindingObserver {
  late final RecordingApi _api = widget.api ?? RecordingApi();
  // The language switch is a TEMPORARY per-view override: _lang starts from the app-wide language
  // (an explicit initialLang wins for the first read) and re-syncs whenever the global value changes.
  late String _lang = widget.initialLang ?? AppLanguage.code;
  String? _lastGlobal;
  StreamSubscription<Object?>? _sub;
  _Phase _phase = _Phase.idle;
  bool _modelReady = true; // optimistic until native says otherwise, so the pick card never flickers
  String _stage = 'decode';
  int _pct = 0;
  String _errKey = 'err_failed';
  final List<Line> _lines = [];
  final List<_Stmt> _live = [];
  _Report? _report;
  CallExplanation? _ai;
  bool _aiTried = false;
  int _durationMs = 0;
  ({bool granted, List<CallRecording> items})? _calls;
  bool? _answer;
  bool _answered = false;
  final _transcriptScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _api.events.listen(_onEvent, onError: (_) {});
    _restore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final g = AppLanguage.of(context);
    if (_lastGlobal == null) {
      if (widget.initialLang == null) _lang = g;
    } else if (g != _lastGlobal) {
      _lang = g;
    }
    _lastGlobal = g;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the permission dialog or the file manager: refresh the list.
    if (state == AppLifecycleState.resumed && _phase == _Phase.idle) _loadCalls();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _transcriptScroll.dispose();
    // Leaving the screen ends the session: stop work and drop the pending file.
    if (_phase == _Phase.working) _api.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final ready = await _api.modelReady();
    final pending = await _api.pending(); // a file shared in before this screen existed
    if (!mounted) return;
    setState(() => _modelReady = ready);
    if (pending && ready && _phase == _Phase.idle) {
      _start();
    } else if (ready) {
      _loadCalls();
    }
  }

  Future<void> _loadCalls() async {
    if (!_modelReady) return;
    final c = await _api.list();
    if (mounted) setState(() => _calls = c);
  }

  Future<void> _getModel() async {
    await pushTitled(context, SpeechStrings.t(AppLanguage.code, 'title'), const SpeechModelScreen());
    if (mounted) _restore();
  }

  Future<void> _pick() async {
    if (await _api.pick() && mounted) _start();
  }

  Future<void> _useCall(CallRecording c) async {
    if (await _api.use(c.uri) && mounted) {
      _durationMs = c.durationMs;
      _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.working;
      _stage = 'decode';
      _pct = 0;
      _lines.clear();
      _live.clear();
      _report = null;
      _ai = null;
      _aiTried = false;
      _answer = null;
      _answered = false;
    });
    if (!await _api.start() && mounted) _fail('err_failed');
  }

  Future<void> _cancel() async {
    await _api.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
    _loadCalls();
  }

  void _fail(String key) => setState(() {
        _phase = _Phase.error;
        _errKey = key;
      });

  void _onEvent(Object? raw) {
    if (!mounted || raw is! Map) return;
    final e = raw.cast<Object?, Object?>();
    final stage = '${e['stage']}';
    final pct = (e['pct'] as num?)?.toInt();
    setState(() {
      switch (stage) {
        case 'shared':
          if (_phase != _Phase.working && _modelReady) Future.microtask(_start);
        case 'download':
          if (e['ready'] == true) _modelReady = true; // finished from Settings › Speech model
        case 'decode' || 'stt' || 'classify':
          if (_phase != _Phase.working) return;
          _stage = stage;
          _pct = pct ?? _pct;
          final seg = e['segment'];
          if (seg is Map && '${seg['text'] ?? ''}'.trim().isNotEmpty) {
            _lines.add(Line((seg['startMs'] as num?)?.toInt() ?? 0, '${seg['text']}'.trim()));
            _scrollTranscript();
          }
          final st = e['statement'];
          if (st is Map) _live.add(_Stmt(st.cast<Object?, Object?>()));
        case 'done':
          final r = e['report'];
          if (r is! Map) {
            _fail('err_failed');
          } else {
            _report = _Report(r.cast<Object?, Object?>());
            if (_lines.isEmpty) _lines.addAll(_report!.statements.map((s) => Line(s.startMs, s.text)));
            _phase = _Phase.explaining;
            Future.microtask(_explain);
          }
        case 'error':
          if (e['code'] == 'cancelled') {
            _phase = _Phase.idle;
          } else {
            _fail(switch ('${e['code']}') {
              'noSpeech' => 'err_noSpeech',
              'download' => 'err_download',
              _ => 'err_failed',
            });
          }
      }
    });
  }

  void _scrollTranscript() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_transcriptScroll.hasClients) return;
        _transcriptScroll.animateTo(_transcriptScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });

  /// The whole transcript goes to the on-device model in one prompt. No model (or an unusable answer): the keyword
  /// report is shown instead. The AI card stays up for at least a moment so the hand-off reads as one smooth step.
  Future<void> _explain() async {
    final r = _report;
    if (r == null) return;
    final ready = await widget.explainer.llm.ready();
    if (!ready) {
      if (mounted) setState(() => _phase = _Phase.done);
      return;
    }
    final flagged = <int>{
      for (final (i, l) in _lines.indexed)
        if (r.statements.any((s) => s.label != RiskLabel.safe && s.startMs == l.startMs)) i,
    };
    final started = DateTime.now();
    final ai = await widget.explainer.explain(lines: _lines, lang: _lang, flagged: flagged, hints: r.topTriggers, ruleRisk: r.risk);
    final wait = const Duration(milliseconds: 900) - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (!mounted) return;
    setState(() {
      _ai = ai;
      _aiTried = true;
      _phase = _Phase.done;
    });
  }

  void _setLang(String code) {
    if (code == _lang) return;
    setState(() => _lang = code);
    // The explanation is written in one language: ask again in the new one.
    if (_phase == _Phase.done && _aiTried) {
      setState(() => _phase = _Phase.explaining);
      _explain();
    }
  }

  String _clock(int ms) =>
      '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  String _dur(int ms) => '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  /// "Today, 4:32 PM · 3:14"
  String _when(RecordingStrings s, CallRecording c) {
    final d = DateTime.fromMillisecondsSinceEpoch(c.dateMs);
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    final date = diff == 0
        ? s['today']
        : diff == 1
            ? s['yesterday']
            : '${d.day} ${s['months'].split(',')[d.month - 1]}';
    return c.durationMs > 0 ? '$date, $time · ${_dur(c.durationMs)}' : '$date, $time';
  }

  String _label(RecordingStrings s, RiskLabel l) => s['l_${l.name}'];

  void _openReport() => openReport(context);

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = RecordingStrings.of(_lang);
    final t = Theme.of(context);
    final p = palOf(context);
    final noModel = !_modelReady && _phase == _Phase.idle;
    final body = switch (_phase) {
      _Phase.idle when noModel => _noModel(t, p, s),
      _Phase.idle => _ready(t, p, s),
      _Phase.working => _transcribing(t, p, s),
      _Phase.explaining => _handoff(t, p, s),
      _Phase.done => _result(t, p, s),
      _Phase.error => _error(t, s),
    };
    return AnimatedSwitcher(
      duration: motion(context, const Duration(milliseconds: 450)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
      ),
      child: KeyedSubtree(key: ValueKey('${_phase.name}$noModel'), child: body),
    );
  }

  Widget _privacy(ThemeData t, Pal p, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline_rounded, size: 20, color: p.muted),
        const SizedBox(width: Sp.s),
        Expanded(child: Text(text, key: const Key('privacy_line'), style: t.textTheme.bodySmall?.copyWith(color: p.muted))),
      ]);

  // ---- no speech model: one centred action that leads to Settings › Speech model
  Widget _noModel(ThemeData t, Pal p, RecordingStrings s) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.l),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - Sp.l * 2),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _PulseHero(icon: Icons.graphic_eq_rounded),
              const SizedBox(height: Sp.xl),
              Semantics(
                header: true,
                child: Text(s['noModelT'], textAlign: TextAlign.center, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: Sp.s),
              Text(s['noModelS'], textAlign: TextAlign.center, style: t.textTheme.bodyLarge?.copyWith(color: p.muted, height: 1.45)),
              const SizedBox(height: Sp.l),
              Wrap(alignment: WrapAlignment.center, spacing: Sp.s, runSpacing: Sp.s, children: [
                for (final k in const ['chipOffline', 'chipSize', 'chipPrivate'])
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEEEEF1),
                      borderRadius: BorderRadius.circular(Rad.pill),
                    ),
                    child: Text(s[k], style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: Sp.xl),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Rad.pill),
                  boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.32), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: FilledButton(
                  key: const Key('btn_get_model'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 58), padding: const EdgeInsets.symmetric(horizontal: Sp.xl)),
                  onPressed: _getModel,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(s['getModel'], textAlign: TextAlign.center)),
                    const SizedBox(width: Sp.s),
                    const Icon(Icons.arrow_forward_rounded, size: 22),
                  ]),
                ),
              ),
              const SizedBox(height: Sp.s),
              Text(s['opensSettings'], textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: p.muted)),
              const SizedBox(height: Sp.xl),
              _privacy(t, p, s['privacy']),
            ]),
          ),
        ),
      );

  // ---- ready: upload card, then the phone's call recordings
  Widget _ready(ThemeData t, Pal p, RecordingStrings s) {
    final calls = _calls;
    return ListView(padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl), children: [
      _FadeUp(
        child: Material(
          color: p.accent,
          borderRadius: BorderRadius.circular(RadX.card),
          elevation: 0,
          child: InkWell(
            key: const Key('btn_pick'),
            borderRadius: BorderRadius.circular(RadX.card),
            onTap: _pick,
            child: Padding(
              padding: const EdgeInsets.all(Sp.l + 2),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: p.onAccent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(15)),
                  child: Icon(Icons.upload_rounded, color: p.onAccent, size: 28),
                ),
                const SizedBox(width: Sp.m + 2),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['upload'], style: t.textTheme.titleMedium?.copyWith(color: p.onAccent, fontWeight: FontWeight.w700)),
                    Text(s['uploadSub'], style: t.textTheme.bodySmall?.copyWith(color: p.onAccent.withValues(alpha: 0.85))),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: p.onAccent),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: Sp.l + 4),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(s['fromCalls'].toUpperCase(),
                style: t.textTheme.labelMedium?.copyWith(color: p.muted, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
        ),
        if (calls != null && calls.items.isNotEmpty)
          Text(s['found'].replaceAll('{n}', '${calls.items.length}'), style: t.textTheme.bodySmall?.copyWith(color: p.muted)),
      ]),
      const SizedBox(height: Sp.s),
      if (calls == null)
        const Padding(padding: EdgeInsets.all(Sp.xl), child: Center(child: CircularProgressIndicator()))
      else if (!calls.granted)
        _FadeUp(
          delay: 80,
          child: PGroup(children: [
            PRow(
              key: const Key('calls_allow'),
              label: s['allowT'],
              subtitle: s['allowS'],
              leading: IconBadge(icon: Icons.folder_open_rounded, color: p.accent, tint: p.accentTint, size: 40, iconSize: 22),
              value: s['allow'],
              onTap: _api.requestAccess,
              last: true,
            ),
          ]),
        )
      else if (calls.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.l, horizontal: Sp.xs),
          child: Text(s['noneFound'], key: const Key('calls_empty'), style: t.textTheme.bodyMedium?.copyWith(color: p.muted)),
        )
      else
        _FadeUp(
          delay: 80,
          child: PGroup(children: [
            for (final (i, c) in calls.items.indexed)
              PRow(
                key: Key('call_$i'),
                label: c.name,
                subtitle: _when(s, c),
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: p.accentTint,
                  child: Text(_initials(c.name), style: t.textTheme.labelLarge?.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
                ),
                onTap: () => _useCall(c),
                last: i == calls.items.length - 1,
              ),
          ]),
        ),
      const SizedBox(height: Sp.xl),
      _privacy(t, p, s['privacy']),
    ]);
  }

  static String _initials(String name) {
    final n = name.trim();
    if (n.isEmpty) return '•';
    if (RegExp(r'^[+\d]').hasMatch(n)) return n.startsWith('+') ? '+' : '#';
    final parts = n.split(RegExp(r'[\s_-]+')).where((w) => w.isNotEmpty).toList();
    return parts.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }

  // ---- transcribing: one running paragraph that grows as the call is heard
  Widget _transcribing(ThemeData t, Pal p, RecordingStrings s) {
    final heardMs = _lines.isEmpty ? 0 : _lines.last.startMs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const _PulseDot(icon: Icons.mic_rounded),
              const SizedBox(width: Sp.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(s['stage_$_stage'], key: const Key('progress_stage'), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (_durationMs > 0 && heardMs > 0)
                    Text(s['heard'].replaceAll('{a}', _dur(_durationMs)).replaceAll('{b}', _dur(heardMs)),
                        style: t.textTheme.bodySmall?.copyWith(color: p.muted)),
                ]),
              ),
              ExcludeSemantics(child: Text('$_pct%', style: t.textTheme.titleMedium?.copyWith(color: p.accent, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: Sp.m),
            ClipRRect(
              borderRadius: BorderRadius.circular(Rad.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _pct / 100),
                duration: motion(context, const Duration(milliseconds: 400)),
                builder: (_, v, _) => LinearProgressIndicator(
                  key: const Key('progress_bar'),
                  value: _pct > 0 ? v : null,
                  semanticsLabel: s['stage_$_stage'],
                  semanticsValue: '$_pct%',
                  minHeight: 6,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: Sp.m),
        Expanded(
          child: PCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const _Bars(),
                const SizedBox(width: Sp.s),
                Text(s['live'].toUpperCase(), style: t.textTheme.labelMedium?.copyWith(color: p.muted, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              ]),
              const SizedBox(height: Sp.m),
              Expanded(
                child: SingleChildScrollView(
                  controller: _transcriptScroll,
                  child: _lines.isEmpty
                      ? Text(s['listening'], key: const Key('progress_hint'), style: t.textTheme.bodyLarge?.copyWith(color: p.muted))
                      : _LiveParagraph(key: const Key('live_transcript'), lines: [for (final l in _lines) l.text]),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: Sp.s),
        Center(
          child: OutlinedButton(
            key: const Key('btn_cancel'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(140, 48), shape: const StadiumBorder()),
            onPressed: _cancel,
            child: Text(s['cancel']),
          ),
        ),
      ]),
    );
  }

  // ---- hand-off: the transcript folds into a pill, the AI card fades in
  Widget _handoff(ThemeData t, Pal p, RecordingStrings s) {
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    return ListView(padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl), children: [
      Center(
        child: _FadeUp(
          child: Container(
            padding: const EdgeInsets.fromLTRB(Sp.s + 2, Sp.s, Sp.m + 2, Sp.s),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Rad.pill), boxShadow: Elev.card(t.brightness)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 12, backgroundColor: st.safe, child: Icon(Icons.check_rounded, size: 16, color: p.isDark ? Colors.black : Colors.white)),
              const SizedBox(width: Sp.s),
              Flexible(child: Text(s['readyPill'].replaceAll('{n}', '${_lines.length}'), style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
      const SizedBox(height: Sp.l),
      _FadeUp(
        delay: 250,
        child: PCard(
          key: const Key('ai_card'),
          radius: RadX.island,
          padding: const EdgeInsets.fromLTRB(Sp.l + 4, Sp.xl, Sp.l + 4, Sp.xl),
          child: Column(children: [
            const _PulseHero(icon: Icons.auto_awesome_rounded, size: 96),
            const SizedBox(height: Sp.l),
            Semantics(liveRegion: true, child: Text(s['aiT'], textAlign: TextAlign.center, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            const SizedBox(height: Sp.xs),
            Text(s['aiS'], textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: p.muted, height: 1.45)),
            const SizedBox(height: Sp.l),
            for (final (i, k) in const ['ai1', 'ai2', 'ai3'].indexed)
              _FadeUp(
                delay: 500 + i * 300,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    if (i == 0)
                      CircleAvatar(radius: 11, backgroundColor: st.safe, child: Icon(Icons.check_rounded, size: 14, color: p.isDark ? Colors.black : Colors.white))
                    else
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: i == 1 ? CircularProgressIndicator(strokeWidth: 2.5, color: p.accent) : DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.hairline, width: 2))),
                      ),
                    const SizedBox(width: Sp.m),
                    Expanded(child: Text(s[k], style: t.textTheme.bodyLarge?.copyWith(color: i == 2 ? p.muted : null, fontWeight: i == 1 ? FontWeight.w600 : null))),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }

  // ---- result: the AI explanation (or the keyword report), confirmation, sharing
  Widget _result(ThemeData t, Pal p, RecordingStrings s) {
    final r = _report!;
    final ai = _ai;
    final sc = t.extension<StatusColors>() ?? StatusColors.light;
    final verdict = ai?.verdict ?? r.overall;
    final riskPct = ai?.risk ?? (r.risk * 100).round();
    final solid = sc.solid(verdict);
    final chips = ai != null ? [for (final f in ai.flags) _shortQuote(f.quote)] : r.topTriggers;
    final first = r.statements.where((x) => x.label != RiskLabel.safe).firstOrNull;
    var k = 0;
    Widget step(Widget w) => _FadeUp(delay: 80 * k++, child: Padding(padding: const EdgeInsets.only(bottom: Sp.m + 2), child: w));
    return ListView(padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.xl), children: [
      step(Container(
        key: const Key('risk_card'),
        padding: const EdgeInsets.all(Sp.l + 2),
        decoration: BoxDecoration(
          color: sc.tintOver(verdict, p.surface),
          borderRadius: BorderRadius.circular(RadX.card),
          border: Border.all(color: solid.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusChip(label: verdict, text: _label(s, verdict)),
            const Spacer(),
            if (ai != null)
              Flexible(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: p.muted),
                  const SizedBox(width: 4),
                  Flexible(child: Text(s['byAi'], overflow: TextOverflow.ellipsis, style: t.textTheme.labelSmall?.copyWith(color: p.muted, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
          const SizedBox(height: Sp.m),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: Sp.s, children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: riskPct),
              duration: motion(context, const Duration(milliseconds: 900)),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text('$v%',
                  key: const Key('risk_value'),
                  style: t.textTheme.displaySmall?.copyWith(color: solid, fontWeight: FontWeight.w800, height: 1)),
            ),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s['riskFor'], style: t.textTheme.bodyMedium?.copyWith(color: p.muted))),
          ]),
          const SizedBox(height: Sp.m),
          Text(ai?.summary ?? s['sum_${r.overall.name}'], key: const Key('summary'), style: t.textTheme.bodyLarge?.copyWith(height: 1.45)),
          if (ai == null && first != null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.xs),
              child: Text(s['firstFlag'].replaceAll('{t}', _clock(first.startMs)), style: t.textTheme.bodySmall?.copyWith(color: p.muted)),
            ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: Sp.m),
            Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
              for (final (i, c) in chips.take(5).indexed) _Pill(key: Key('trigger_$i'), text: c, color: solid),
            ]),
          ],
        ]),
      )),
      if (ai == null && _aiTried == false)
        step(PCard(
          key: const Key('no_ai'),
          onTap: () => pushTitled(context, profileT(AppLanguage.code, 'm_title'), const ModelPickerScreen()),
          child: Row(children: [
            IconBadge(icon: Icons.auto_awesome_rounded, color: p.accent, tint: p.accentTint, size: 40, iconSize: 22),
            const SizedBox(width: Sp.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['noAi'], style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(s['noAiS'], style: t.textTheme.bodySmall?.copyWith(color: p.muted)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: p.muted),
          ]),
        )),
      if (ai != null && ai.steps.isNotEmpty)
        step(_section(t, p, s['what'], [
          for (final (i, x) in ai.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.s + 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 13, backgroundColor: p.accentTint, child: Text('${i + 1}', style: t.textTheme.labelMedium?.copyWith(color: p.accent, fontWeight: FontWeight.w800))),
                const SizedBox(width: Sp.m),
                Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(x, style: t.textTheme.bodyLarge))),
              ]),
            ),
        ])),
      if (ai != null && ai.flags.isNotEmpty)
        step(_section(t, p, s['flags'], [
          for (final (i, f) in ai.flags.indexed)
            Padding(
              key: Key('flag_$i'),
              padding: const EdgeInsets.only(bottom: Sp.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(Sp.m),
                  decoration: BoxDecoration(color: solid.withValues(alpha: p.isDark ? 0.14 : 0.08), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (f.startMs != null)
                      Text(_clock(f.startMs!), style: t.textTheme.labelSmall?.copyWith(color: solid, fontWeight: FontWeight.w800)),
                    Text('“${f.quote}”', style: t.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic, height: 1.4)),
                  ]),
                ),
                if (f.why.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.s, Sp.xs, 0),
                    child: Text(f.why, style: t.textTheme.bodyMedium?.copyWith(color: p.muted, height: 1.4)),
                  ),
              ]),
            ),
        ])),
      if (ai == null)
        step(_section(t, p, s['timeline'], [
          for (final (i, st) in r.statements.indexed) _row(t, s, i, st, last: i == r.statements.length - 1),
        ])),
      if ((ai?.todo.isNotEmpty ?? false) || verdict != RiskLabel.safe)
        step(_section(t, p, s['todo'], [
          for (final x in ai?.todo ?? const <String>[])
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_rounded, color: p.accent, size: 22),
                const SizedBox(width: Sp.s + 2),
                Expanded(child: Text(x, style: t.textTheme.bodyLarge)),
              ]),
            ),
          if (verdict != RiskLabel.safe) ...[
            const SizedBox(height: Sp.s),
            ActionTile(key: const Key('btn_report'), icon: Icons.report_problem, label: s['report'], caption: s['reportSub'], onTap: _openReport),
          ],
        ])),
      step(_confirm(t, p, s)),
      step(_fullTranscript(t, p, s, ai, r)),
      step(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: Sp.xs, bottom: Sp.s),
          child: Text(s['explainLang'], style: t.textTheme.bodySmall?.copyWith(color: p.muted)),
        ),
        Segmented<String>(
          value: _lang,
          onChanged: _setLang,
          items: [
            for (final (code, label) in const [('hi', 'हिन्दी'), ('hne', 'छत्तीसगढ़ी'), ('en', 'English')]) (code, label, null, Key('lang_$code')),
          ],
        ),
      ])),
      _privacy(t, p, s['privacy']),
    ]);
  }

  static String _shortQuote(String q) {
    final w = q.split(RegExp(r'\s+'));
    return w.length <= 5 ? q : '${w.take(5).join(' ')}…';
  }

  Widget _section(ThemeData t, Pal p, String title, List<Widget> children) => PCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            header: true,
            child: Text(title.toUpperCase(), style: t.textTheme.labelMedium?.copyWith(color: p.muted, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
          const SizedBox(height: Sp.m),
          ...children,
        ]),
      );

  Widget _confirm(ThemeData t, Pal p, RecordingStrings s) {
    final sc = t.extension<StatusColors>() ?? StatusColors.light;
    return AnimatedSwitcher(
      duration: motion(context, const Duration(milliseconds: 300)),
      child: _answered
          ? PCard(
              key: const Key('confirm_done'),
              child: Row(children: [
                Icon(Icons.favorite_rounded, color: sc.safe),
                const SizedBox(width: Sp.m),
                Expanded(child: Text(s['thanks'], style: t.textTheme.bodyLarge)),
              ]),
            )
          : Container(
              key: const Key('confirm_card'),
              padding: const EdgeInsets.all(Sp.l + 2),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(RadX.card),
                border: Border.all(color: p.accent, width: 2),
                boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 10))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s['confirmQ'], style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(s['confirmS'], style: t.textTheme.bodyMedium?.copyWith(color: p.muted)),
                const SizedBox(height: Sp.m + 2),
                Wrap(spacing: Sp.s, runSpacing: Sp.s, children: [
                  FilledButton(
                    key: const Key('ans_yes'),
                    style: FilledButton.styleFrom(backgroundColor: sc.scam, foregroundColor: p.isDark ? Colors.black : Colors.white, minimumSize: const Size(0, 52)),
                    onPressed: () => _answerWith(true),
                    child: Text(s['yes']),
                  ),
                  FilledButton.tonal(
                    key: const Key('ans_no'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                    onPressed: () => _answerWith(false),
                    child: Text(s['no']),
                  ),
                  OutlinedButton(
                    key: const Key('ans_unsure'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                    onPressed: () => _answerWith(null),
                    child: Text(s['unsure']),
                  ),
                ]),
              ]),
            ),
    );
  }

  Widget _fullTranscript(ThemeData t, Pal p, RecordingStrings s, CallExplanation? ai, _Report r) {
    final sc = t.extension<StatusColors>() ?? StatusColors.light;
    final hot = <int>{
      for (final f in ai?.flags ?? const <RedFlag>[]) if (f.startMs != null) f.startMs!,
      if (ai == null) for (final x in r.statements) if (x.label != RiskLabel.safe) x.startMs,
    };
    return PCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: t.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('full_transcript'),
          tilePadding: const EdgeInsets.symmetric(horizontal: Sp.l, vertical: Sp.xs),
          childrenPadding: const EdgeInsets.fromLTRB(Sp.l, 0, Sp.l, Sp.l),
          leading: Icon(Icons.notes_rounded, color: p.accent),
          title: Text(s['fullT'], style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(s['fullS'].replaceAll('{n}', '${_lines.length}'), style: t.textTheme.bodySmall?.copyWith(color: p.muted)),
          children: [
            for (final l in _lines)
              Container(
                margin: const EdgeInsets.only(bottom: Sp.xs),
                padding: const EdgeInsets.symmetric(horizontal: Sp.s, vertical: Sp.xs),
                decoration: hot.contains(l.startMs)
                    ? BoxDecoration(color: sc.scam.withValues(alpha: p.isDark ? 0.16 : 0.08), borderRadius: BorderRadius.circular(8))
                    : null,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 52, child: Text(_clock(l.startMs), style: t.textTheme.bodySmall?.copyWith(color: p.muted))),
                  Expanded(child: Text(l.text, style: t.textTheme.bodyMedium)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  // ---- confirm, then (with consent) share
  Future<void> _answerWith(bool? v) async {
    setState(() {
      _answer = v;
      _answered = true;
    });
    if (v == null) return;
    final s = RecordingStrings.of(_lang);
    final district = await _district();
    if (!mounted) return;
    final share = await showIslandSheet<bool>(context, builder: (ctx) => _ShareSheet(s: s, district: district ?? '—', answer: s['ans_$v']));
    if (share != true || !mounted) return;
    final d = district ?? await _pickDistrict(s);
    if (d == null || !mounted) return;
    final r = _report!;
    final ok = await widget.sender.send(CallReportUpload(
      district: d,
      transcript: _lines.map((l) => l.text).join('\n'),
      llm: _ai?.toJson() ??
          {'verdict': r.overall.name, 'risk': (r.risk * 100).round(), 'summary': '', 'redFlags': [for (final x in r.topTriggers) {'quote': x, 'why': ''}], 'source': 'rules'},
      ruleRisk: r.risk,
      userValidated: _answer,
      lang: _lang,
      appVersion: kAppVersion,
    ));
    if (!mounted) return;
    showIsland(context, s[ok ? 'shared' : 'shareFail'], tone: ok ? IslandTone.success : IslandTone.danger);
  }

  static const _prefs = MethodChannel('scamshield/prefs');

  Future<String?> _district() async {
    try {
      final d = await _prefs.invokeMethod<String>('getString', {'key': 'district'}).timeout(const Duration(seconds: 1), onTimeout: () => null);
      return kDistricts.contains(d) ? d : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String?> _pickDistrict(RecordingStrings s) async {
    final d = await showIslandSheet<String>(context, builder: (ctx) {
      final th = Theme.of(ctx);
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s['pickDistrict'], style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Sp.s),
        SizedBox(
          height: 360,
          child: ListView(children: [
            for (final d in kDistricts) ListTile(title: Text(d), onTap: () => Navigator.pop(ctx, d)),
          ]),
        ),
      ]);
    });
    if (d != null) {
      try {
        await _prefs.invokeMethod<void>('setString', {'key': 'district', 'value': d});
      } on MissingPluginException {
        // tests
      } on PlatformException {
        // not saved; still used for this report
      }
    }
    return d;
  }

  // Download failures go to Settings; the rest reopen the file picker.
  Widget _error(ThemeData t, RecordingStrings s) => Center(
        child: KeyedSubtree(
          key: const Key('error_text'),
          child: StateMessage(
            icon: Icons.error_outline,
            title: s[_errKey],
            actionLabel: s['retry'],
            onAction: () {
              if (_errKey == 'err_download') {
                _getModel();
              } else {
                setState(() => _phase = _Phase.idle);
                _loadCalls();
              }
            },
          ),
        ),
      );

  // Keyword-report row (no AI model): status rail, time, the line said and its verdict.
  Widget _row(ThemeData t, RecordingStrings s, int i, _Stmt st, {required bool last}) {
    final sc = t.extension<StatusColors>() ?? StatusColors.light;
    final c = sc.solid(st.label);
    return IntrinsicHeight(
      key: Key('row_$i'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 20,
          child: Column(children: [
            Container(width: 14, height: 14, margin: const EdgeInsets.only(top: Sp.xs), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            if (last) const Spacer() else Expanded(child: Container(width: 3, margin: const EdgeInsets.only(top: Sp.xs), color: c.withValues(alpha: 0.5))),
          ]),
        ),
        const SizedBox(width: Sp.m),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Sp.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_clock(st.startMs), key: Key('row_time_$i'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              Text(st.text, style: t.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
              const SizedBox(height: Sp.s),
              StatusChip(label: st.label, text: _label(s, st.label)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The consent sheet: what is sent, what never is, and two clear choices.
class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.s, required this.district, required this.answer});
  final RecordingStrings s;
  final String district, answer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = palOf(context);
    final sc = t.extension<StatusColors>() ?? StatusColors.light;
    Widget yes(String text, [String? value]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(radius: 12, backgroundColor: sc.safe.withValues(alpha: 0.16), child: Icon(Icons.check_rounded, size: 15, color: sc.safe)),
            const SizedBox(width: Sp.m),
            Expanded(child: Text(text, style: t.textTheme.bodyLarge)),
            if (value != null) Text(value, style: t.textTheme.bodyMedium?.copyWith(color: p.muted)),
          ]),
        );
    // Scrolls on small phones and at large text; the two buttons stay at the end of the list.
    return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerLeft, child: IconBadge(icon: Icons.shield_rounded, color: p.accent, tint: p.accentTint, size: 56, iconSize: 30)),
      const SizedBox(height: Sp.m),
      Text(s['shareT'], style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: Sp.xs),
      Text(s['shareB'], style: t.textTheme.bodyLarge?.copyWith(color: p.muted, height: 1.45)),
      const SizedBox(height: Sp.m),
      Container(
        padding: const EdgeInsets.fromLTRB(Sp.m + 2, Sp.s, Sp.m + 2, Sp.s),
        decoration: BoxDecoration(color: p.isDark ? const Color(0xFF2C2C2E) : p.page, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs, bottom: 2),
            child: Text(s['sentH'].toUpperCase(), style: t.textTheme.labelSmall?.copyWith(color: p.muted, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
          yes(s['sentDistrict'], district),
          yes(s['sentText']),
          yes(s['sentAi'], answer),
          Divider(color: p.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(Icons.block_rounded, size: 22, color: p.muted),
              const SizedBox(width: Sp.m),
              Expanded(child: Text(s['never'], style: t.textTheme.bodyMedium?.copyWith(color: p.muted))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: Sp.l),
      FilledButton(
        key: const Key('share_yes'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: const StadiumBorder()),
        onPressed: () => Navigator.pop(context, true),
        child: Text(s['share']),
      ),
      TextButton(key: const Key('share_no'), onPressed: () => Navigator.pop(context, false), child: Text(s['noThanks'])),
    ]));
  }
}

/// Coloured pill with a dot: a red-flag phrase in the verdict card.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.m, vertical: 7),
      decoration: BoxDecoration(color: color.withValues(alpha: p.isDark ? 0.18 : 0.12), borderRadius: BorderRadius.circular(Rad.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// The running transcript: one paragraph; the newest words fade in from soft to full ink.
class _LiveParagraph extends StatelessWidget {
  const _LiveParagraph({super.key, required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base = t.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.6);
    final ink = base?.color ?? t.colorScheme.onSurface;
    final old = lines.take(lines.length - 1).join(' ');
    return TweenAnimationBuilder<double>(
      key: ValueKey(lines.length),
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, const Duration(milliseconds: 600)),
      curve: Curves.easeOut,
      builder: (_, v, _) => Text.rich(
        TextSpan(style: base, children: [
          if (old.isNotEmpty) TextSpan(text: '$old '),
          TextSpan(text: lines.last, style: TextStyle(color: ink.withValues(alpha: 0.15 + 0.85 * v))),
        ]),
      ),
    );
  }
}

/// Fades and lifts its child in once, after [delay] ms. Still when the system asks for reduced motion.
class _FadeUp extends StatefulWidget {
  const _FadeUp({required this.child, this.delay = 0});
  final Widget child;
  final int delay;
  @override
  State<_FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<_FadeUp> with SingleTickerProviderStateMixin {
  // The delay is the first part of one controller (no timers, so nothing is left pending when the screen closes).
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: 500 + widget.delay));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Interval(widget.delay / (500 + widget.delay), 1, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a), child: widget.child),
    );
  }
}

/// Accent tile with soft rings and an expanding pulse (no-model hero, AI hand-off).
class _PulseHero extends StatefulWidget {
  const _PulseHero({required this.icon, this.size = 104});
  final IconData icon;
  final double size;
  @override
  State<_PulseHero> createState() => _PulseHeroState();
}

class _PulseHeroState extends State<_PulseHero> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) _c.repeat(count: 40);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final s = widget.size;
    return SizedBox(
      width: s * 2.1,
      height: s * 2.1,
      child: Stack(alignment: Alignment.center, children: [
        Container(width: s * 2.1, height: s * 2.1, decoration: BoxDecoration(color: p.accent.withValues(alpha: p.isDark ? 0.10 : 0.06), shape: BoxShape.circle)),
        Container(width: s * 1.6, height: s * 1.6, decoration: BoxDecoration(color: p.accent.withValues(alpha: p.isDark ? 0.18 : 0.10), shape: BoxShape.circle)),
        AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Opacity(
            opacity: (1 - _c.value) * 0.6,
            child: Transform.scale(
              scale: 0.85 + _c.value * 0.5,
              child: Container(width: s * 1.27, height: s * 1.27, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.accent, width: 2))),
            ),
          ),
        ),
        Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(s * 0.31),
            boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 36, offset: const Offset(0, 16))],
          ),
          child: Icon(widget.icon, color: p.onAccent, size: s * 0.5),
        ),
      ]),
    );
  }
}

/// Small accent circle with a breathing glow: "listening now".
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.icon});
  final IconData icon;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) _c.repeat(count: 40);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: p.accent,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.45 * (1 - _c.value)), spreadRadius: 14 * _c.value)],
        ),
        child: child,
      ),
      child: Icon(widget.icon, color: p.onAccent, size: 20),
    );
  }
}

/// Four little level bars next to "Live transcript".
class _Bars extends StatefulWidget {
  const _Bars();
  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) _c.repeat(count: 40);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    return SizedBox(
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 3,
              height: 4 + 12 * (0.5 + 0.5 * math.sin((_c.value + i * 0.2) * 2 * math.pi)).abs(),
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2)),
            ),
        ]),
      ),
    );
  }
}
