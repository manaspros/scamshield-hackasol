import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/llm_api.dart';
import '../api/speech_api.dart';
import '../l10n/app_language.dart';
import '../l10n/strings_report_chat.dart';
import '../models/verdict.dart';
import '../profile/user_profile.dart';
import '../report/report_chat_engine.dart';
import '../report/report_chat_view.dart';
import '../report/report_history.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/island.dart';
import '../widgets/press_scale.dart';
import '../widgets/state_message.dart';

/// Client for the native handoff channel (K/HandoffChannel.kt).
/// Every call returns null/false instead of throwing, so the screen still works
/// (1930 button included) when the native side is missing or fails.
class HandoffApi {
  const HandoffApi([this.channel = const MethodChannel('scamshield/handoff')]);
  final MethodChannel channel;

  Future<Map<Object?, Object?>?> _map(String m, [Object? args]) async {
    try {
      final r = await channel.invokeMethod<Object?>(m, args);
      return r is Map ? r.cast<Object?, Object?>() : null; // any other shape reads as "failed"
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> _ok(String m, Map<String, Object?> args) async {
    try {
      return await channel.invokeMethod<bool>(m, args) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<Object?, Object?>?> pack({required bool moneyLost}) => _map('report.pack', {'moneyLost': moneyLost});
  Future<Map<Object?, Object?>?> goldenStatus() => _map('golden.status');
  Future<Map<Object?, Object?>?> goldenStart({bool restart = false}) => _map('golden.start', {'restart': restart});
  Future<bool> goldenShare(Map<String, String> fields, {List<String> attachments = const []}) =>
      _ok('golden.share', {'fields': fields, 'attachments': attachments});
  Future<bool> dial(String number) => _ok('dial', {'number': number});

  /// Dialer for a family contact the user saved (digits only; the user still presses call).
  Future<bool> dialContact(String number) => _ok('dial.contact', {'number': number});

  /// System file picker (images, PDF, audio). Picked files are copied into the app cache;
  /// returns [{path,name,mime,size}], an empty list when cancelled, or null on failure.
  Future<List<Map<Object?, Object?>>?> pickAttachments() async {
    try {
      final l = await channel.invokeMethod<Object?>('attach.pick');
      if (l != null && l is! List) return null;
      return [for (final e in (l as List?) ?? const []) if (e is Map) e.cast<Object?, Object?>()];
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
  Future<bool> open(String url) => _ok('open', {'url': url});
}

const _hiLabels = <String, String>{
  't_OTP': 'OTP',
  't_KYC': 'KYC',
  't_DIGITAL_ARREST': 'डिजिटल अरेस्ट',
  't_COURIER_CUSTOMS': 'कूरियर / कस्टम',
  't_FAKE_QR': 'नकली QR',
  't_LOAN_APP': 'लोन ऐप',
  't_INVESTMENT': 'निवेश',
  't_JOB': 'नौकरी',
  't_MISTAKEN_TRANSFER': 'गलत ट्रांसफ़र',
  't_OTHER': 'अन्य',
  's_caption': 'फ़ोन कॉल',
  's_sms': 'SMS',
  's_whatsapp': 'WhatsApp',
  's_paste': 'चिपकाया संदेश',
  's_share': 'शेयर किया संदेश',
  's_notification': 'नोटिफ़िकेशन',
  's_recording': 'रिकॉर्डिंग',
  's_signal': 'संकेत',
};

/// Screen text in Hindi (default), Chhattisgarhi and English; same keys in all three.
class ReportStrings {
  const ReportStrings(this.m);
  final Map<String, String> m;
  String operator [](String k) => m[k] ?? k;

  static const hi = ReportStrings({
    ..._hiLabels,
    'title': 'शिकायत दर्ज करें',
    'pathLost': 'मेरे पैसे कट गए',
    'pathLostSub': 'अभी 1930 पर कॉल करें',
    'pathNot': 'अभी पैसे नहीं गए',
    'pathNotSub': 'ठग के नंबर की शिकायत करें',
    'start': 'मैं ठगा गया: 60 मिनट शुरू करें',
    'startSub': 'पहले घंटे में बताने पर बैंक पैसे रोक सकता है।',
    'goldenTitle': 'सुनहरा घंटा',
    'goldenHint': 'पहले घंटे में शिकायत करने से पैसा वापस मिलने की संभावना सबसे ज़्यादा',
    'expired': 'समय पूरा हुआ। फिर भी 1930 पर कॉल करें।',
    'restart': 'नया मामला शुरू करें',
    'calm': 'घबराएँ नहीं। ये कदम अभी उठाएँ।',
    'loading': 'तैयार हो रहा है…',
    'dialCta': '1930 पर कॉल करें',
    'step1': 'सबसे पहले 1930 पर कॉल करें',
    'stepPortal': 'cybercrime.gov.in पर शिकायत दर्ज करें',
    'stepChakshu': 'चक्षु पर शक वाला नंबर बताएँ',
    'stepShots': 'स्क्रीनशॉट सँभालकर रखें',
    'dialHint': 'डायल खुलेगा। हरा बटन आप खुद दबाएँ।',
    'portal': 'साइबर क्राइम पोर्टल खोलें',
    'chakshu': 'चक्षु: शक वाला नंबर बताएँ',
    'evidence': 'सबूत की सूची',
    'evidenceAuto': 'ऐप ने ये अपने आप जोड़े हैं।',
    'evidenceNone': 'कोई चेतावनी नहीं मिली। नीचे खुद लिखें।',
    'yours': 'आप खुद भरें',
    'f_scammer_number': 'ठग का फ़ोन नंबर या UPI ID',
    'f_amount': 'कितने रुपये गए',
    'more': 'अधिक जानकारी',
    'f_utr': 'बैंक मैसेज वाला लेन-देन नंबर',
    'f_screenshots': 'स्क्रीनशॉट के बारे में लिखें (चाहें तो)',
    'share': 'सबूत की फ़ाइल बनाकर भेजें',
    'openErr': 'यह नहीं खुल सका। 1930 खुद डायल करें।',
    'shareErr': 'सबूत नहीं बन सका। फिर कोशिश करें।',
    'startErr': 'घड़ी शुरू नहीं हो सकी। 1930 पर कॉल करें।',
    'minLeft': '{n} मिनट बाकी',
  });

  static const hne = ReportStrings({
    ..._hiLabels,
    'title': 'शिकायत दर्ज करव',
    'pathLost': 'मोर पइसा कट गे',
    'pathLostSub': 'अभी 1930 म फोन करव',
    'pathNot': 'अभी पइसा नइ गे हे',
    'pathNotSub': 'ठग के नंबर के शिकायत करव',
    'start': 'मंय ठगाय गेंव: 60 मिनट सुरू करव',
    'startSub': 'पहिली घंटा म बताहू त बैंक पइसा रोक सकथे।',
    'goldenTitle': 'सोना कस घंटा',
    'goldenHint': 'पहिली घंटा म शिकायत करे ले पइसा लहुटे के संभावना सबले जादा',
    'expired': 'समे पूरा होगे। तभो ले 1930 म फोन करव।',
    'restart': 'नवा मामला सुरू करव',
    'calm': 'घबरावव झन। ए कदम अभी उठावव।',
    'loading': 'तियार होवत हे…',
    'dialCta': '1930 म फोन करव',
    'step1': 'सबले पहिली 1930 म फोन करव',
    'stepPortal': 'cybercrime.gov.in म शिकायत दर्ज करव',
    'stepChakshu': 'चक्षु म शक वाले नंबर बतावव',
    'stepShots': 'स्क्रीनशॉट सम्हाल के राखव',
    'dialHint': 'डायल खुलही। हरियर बटन तुमन खुद दबावव।',
    'portal': 'साइबर क्राइम पोर्टल खोलव',
    'chakshu': 'चक्षु: शक वाले नंबर बतावव',
    'evidence': 'सबूत के सूची',
    'evidenceAuto': 'ऐप ह ए मन ल अपने जोड़े हे।',
    'evidenceNone': 'कोनो चेतावनी नइ मिलिस। तल म खुद लिखव।',
    'yours': 'तुमन खुद भरव',
    'f_scammer_number': 'ठग के फोन नंबर या UPI ID',
    'f_amount': 'कतका रुपिया गे',
    'more': 'अउ जानकारी',
    'f_utr': 'बैंक मैसेज वाले लेन-देन नंबर',
    'f_screenshots': 'स्क्रीनशॉट के बारे म लिखव (मन होवय त)',
    'share': 'सबूत के फाइल बनाके भेजव',
    'openErr': 'ए नइ खुल सकिस। 1930 खुद डायल करव।',
    'shareErr': 'सबूत नइ बन सकिस। फेर कोसिस करव।',
    'startErr': 'घड़ी सुरू नइ हो सकिस। 1930 म फोन करव।',
    'minLeft': '{n} मिनट बाकी',
  });

  static const en = ReportStrings({
    't_OTP': 'OTP',
    't_KYC': 'KYC',
    't_DIGITAL_ARREST': 'Digital arrest',
    't_COURIER_CUSTOMS': 'Courier / customs',
    't_FAKE_QR': 'Fake QR',
    't_LOAN_APP': 'Loan app',
    't_INVESTMENT': 'Investment',
    't_JOB': 'Job offer',
    't_MISTAKEN_TRANSFER': 'Mistaken transfer',
    't_OTHER': 'Other',
    's_caption': 'Phone call',
    's_sms': 'SMS',
    's_whatsapp': 'WhatsApp',
    's_paste': 'Pasted message',
    's_share': 'Shared message',
    's_notification': 'Notification',
    's_recording': 'Recording',
    's_signal': 'Signal',
    'title': 'Report a scam',
    'pathLost': 'I lost money',
    'pathLostSub': 'Call 1930 now',
    'pathNot': 'No money lost yet',
    'pathNotSub': 'Report the scammer\'s number',
    'start': 'I got scammed: start 60 minutes',
    'startSub': 'Report in the first hour and the bank may be able to freeze the money.',
    'goldenTitle': 'Golden hour',
    'goldenHint': 'Reporting in the first hour gives the best chance of getting your money back.',
    'expired': 'Time is up. Still call 1930.',
    'restart': 'Start a new case',
    'calm': 'Don\'t panic. Take these steps now.',
    'loading': 'Getting ready…',
    'dialCta': 'Call 1930',
    'step1': 'Call 1930 first',
    'stepPortal': 'Report at cybercrime.gov.in',
    'stepChakshu': 'Report the suspect number on Chakshu',
    'stepShots': 'Keep your screenshots',
    'dialHint': 'The dialer opens. You press the green button.',
    'portal': 'Open the cybercrime portal',
    'chakshu': 'Chakshu: report the suspect number',
    'evidence': 'Evidence checklist',
    'evidenceAuto': 'The app added these for you.',
    'evidenceNone': 'No warnings found. Write the details below.',
    'yours': 'You fill in',
    'f_scammer_number': 'Scammer phone number or UPI ID',
    'f_amount': 'Amount lost (INR)',
    'more': 'More details',
    'f_utr': 'Transaction number from the bank message',
    'f_screenshots': 'Notes about your screenshots (optional)',
    'share': 'Make and send evidence file',
    'openErr': 'Could not open this. Dial 1930 yourself.',
    'shareErr': 'Could not build the evidence file. Try again.',
    'startErr': 'Could not start the clock. Call 1930.',
    'minLeft': '{n} minutes left',
  });

  static const all = {'hi': hi, 'hne': hne, 'en': en};
  static ReportStrings of(String lang) => all[lang] ?? hi;
}

const _goldenMs = 60 * 60 * 1000;

class _Pack {
  _Pack(this.m);
  // Shown when native cannot build a pack: the helpline must always be one tap away.
  factory _Pack.fallback() => _Pack({
        'targets': [
          {'phone': '1930'}
        ],
      });
  final Map<Object?, Object?> m;
  List<Map<Object?, Object?>> _list(String k) =>
      ((m[k] as List?) ?? const []).map((e) => (e as Map).cast<Object?, Object?>()).toList();
  late final targets = _list('targets');
  late final evidence = _list('evidence');
}

/// One line in the chat. Scripted bot lines keep a builder so they re-render in a newly picked language;
/// Gemma's wording and the user's own words are fixed text.
class _Msg {
  _Msg.bot(String Function(String lang) this.render, {this.evidence}) : text = null, user = false, voice = false, files = const [];
  _Msg.botText(String this.text) : render = null, user = false, voice = false, evidence = null, files = const [];
  _Msg.user(String this.text, {this.voice = false}) : render = null, user = true, evidence = null, files = const [];
  _Msg.files(this.files) : text = null, render = null, user = true, voice = false, evidence = null;

  final String? text;
  final String Function(String lang)? render;
  final bool user, voice;
  final Map<Object?, Object?>? evidence;
  final List<ChatAttachment> files;
}

/// Report screen. The user picks "I lost money" (starts the 60-minute golden-hour clock, 1930 + portal) or
/// "No money lost yet" (Chakshu + 1930); then a chatbot interviews them, worded for their age, gender and job
/// (from Profile) and always in the app language. Voice answers use the phone's Google recogniser; screenshots
/// can be attached; the answers become the evidence ZIP. The 1930 button stays pinned at the bottom.
class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    this.initialLang,
    this.api = const HandoffApi(),
    this.speech = const SpeechApi(),
    this.llm = const ReportChatLlm(),
    this.profile,
  });

  /// Tests only: pins the language instead of following the app-wide one.
  final String? initialLang;
  final HandoffApi api;
  final SpeechApi speech;

  /// Rewords questions with on-device Gemma when a model is loaded; null keeps the script.
  final ReportChatLlm? llm;

  /// Defaults to the saved profile.
  final UserProfile? profile;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool? _lost; // null until the user picks a path
  _Pack? _pack;
  bool _loading = false;
  int? _remainingMs; // non-null once the golden hour has started
  bool _goldenFailed = false;
  Timer? _timer;

  ReportInterview? _iv;
  final _msgs = <_Msg>[];
  Slot? _asking; // the question whose quick replies are showing
  BotTurn? _llmTurn; // set when Gemma wrote the current question (its own wording and options)
  bool _thinking = false;
  int _seq = 0; // bumps on every path change so late async work is dropped
  String? _recordId; // this report in the history
  int _createdMs = 0;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  StreamSubscription<SpeechEvent>? _speechSub;
  bool _listening = false;
  String _partial = '';
  // One voice answer can span several recogniser sessions (Android stops at pauses): finished pieces collect here.
  String _heard = '';
  bool _holding = false, _cancelArmed = false, _stopping = false;
  int _restarts = 0;
  Timer? _finishTimer;
  DateTime _lastLevel = DateTime(0);
  final _levels = List<double>.filled(24, 0.1);

  String get _lang => widget.initialLang ?? AppLanguage.of(context);
  UserProfile get _profile => widget.profile ?? ProfileStore.profile.value;
  ChatScale get _scale => ChatScale(large: _iv?.persona.lowTech ?? false);

  @override
  void initState() {
    super.initState();
    ReportHistory.load();
    _restore();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _speechSub?.cancel();
    _finishTimer?.cancel();
    if (_listening) widget.speech.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // The start time lives natively, so a rebuilt screen picks the clock up again (and its case).
  Future<void> _restore() async {
    final g = await widget.api.goldenStatus();
    if (!mounted || g == null || g['started'] != true || _lost != null) return;
    _applyGolden(g);
    // Carry on with this case's unfinished report (from the history) instead of starting over.
    await ReportHistory.load();
    if (!mounted || _iv != null) return;
    final start = (g['startMs'] as num?)?.toInt() ?? 0;
    final open = ReportHistory.items.value.where((r) => r.lost && !r.finished && r.updatedMs >= start).firstOrNull;
    if (open != null) {
      _openRecord(open);
    } else {
      _startInterview(true);
    }
  }

  void _applyGolden(Map<Object?, Object?> g) {
    final left = (g['remainingMs'] as num).toInt();
    setState(() {
      _lost = true;
      _pack = _Pack((g['pack'] as Map).cast<Object?, Object?>());
      _remainingMs = left;
      _goldenFailed = false;
    });
    _timer?.cancel();
    // shortcut: counts down by ticks, not wall clock; resyncs from native on the next rebuild.
    if (left > 0) _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer t) {
    final left = (_remainingMs! - 1000).clamp(0, _goldenMs).toInt();
    setState(() => _remainingMs = left);
    if (left == 0) t.cancel();
  }

  Future<void> _choose(bool lost) async {
    if (_lost == lost && _iv != null) return;
    final seq = ++_seq;
    setState(() {
      _lost = lost;
      _pack = null;
      _loading = true;
    });
    final m = await widget.api.pack(moneyLost: lost);
    if (!mounted || seq != _seq) return;
    setState(() {
      _pack = m == null ? _Pack.fallback() : _Pack(m);
      _loading = false;
    });
    // Losing money is the golden-hour case: the clock starts as soon as the user says so.
    if (lost && (_remainingMs == null || _remainingMs == 0)) await _startGolden();
    if (!mounted || seq != _seq) return;
    _startInterview(lost);
  }

  Future<void> _startGolden() async {
    final g = await widget.api.goldenStart(restart: _remainingMs == 0);
    if (!mounted) return;
    if (g == null || g['started'] != true) {
      setState(() => _goldenFailed = true);
      _toast(ReportStrings.of(_lang)['startErr']);
    } else {
      final keep = _pack;
      _applyGolden(g);
      if (keep != null && (_pack?.evidence.isEmpty ?? true)) setState(() => _pack = keep);
    }
  }

  (String?, String?) get _family {
    final c = ProfileStore.contacts.value.where((c) => (c.phone ?? '').trim().isNotEmpty).firstOrNull;
    if (c == null) return (null, null);
    return (c.relation.trim().isEmpty ? c.name : '${c.relation.trim()} ${c.name}', c.phone);
  }

  void _startInterview(bool lost) {
    final evidence = _pack?.evidence ?? const [];
    final (familyName, familyPhone) = _family;
    final iv = ReportInterview(
      lost: lost,
      persona: Persona.of(_profile),
      evidence: evidence,
      familyName: familyName,
      familyPhone: familyPhone,
    );
    setState(() {
      _iv = iv;
      _recordId = null;
      _msgs.clear();
      _asking = null;
      _llmTurn = null;
      final e = iv.latestEvidence;
      _msgs.add(e == null
          ? _Msg.bot((l) => rcFor(l, 'intro_none', iv.persona.variant))
          : _Msg.bot((l) => rc(l, 'intro_found', {'n': evidence.length}), evidence: e));
    });
    _ask();
  }

  /// The chat so far as plain lines, for the model.
  List<(bool, String)> _transcript(String lang) => [
        for (final m in _msgs)
          if (m.files.isEmpty) (m.user, m.text ?? m.render!(lang)) else (true, '[sent ${m.files.length} file(s)]'),
      ];

  /// Next question. For the complaint's facts, on-device Gemma reads what is missing and the chat and writes the
  /// question itself (and pulls facts out of the last answer); without a model, or if its reply is unusable,
  /// the scripted question for the next missing fact is used. Helplines, screenshots and "anything else" stay scripted.
  Future<void> _ask() async {
    final iv = _iv;
    if (iv == null) return;
    final seq = _seq;
    var slot = iv.nextSlot();
    final llm = widget.llm;
    if (slot != null && dataSlots.contains(slot) && llm != null && LlmStatus.ready.value) {
      final lang = _lang;
      setState(() => _thinking = true);
      _scrollToEnd();
      final t = await llm.next(iv, lang, _profile.promptContext(), _transcript(lang));
      if (!mounted || seq != _seq || _iv != iv) return;
      _thinking = false;
      if (t != null) {
        iv.applyExtracted(t.extracted);
        slot = iv.nextSlot();
        final ask = t.ask;
        if (t.hasQuestion && ask != null && iv.missingData.contains(ask)) {
          final turn = BotTurn(
            slot: ask,
            text: t.question!,
            byLlm: true,
            numeric: ask == Slot.amount,
            choices: [for (final o in t.options) ChatChoice(o, o)],
          );
          setState(() {
            _msgs.add(_Msg.botText(turn.text));
            _asking = ask;
            _llmTurn = turn;
          });
          _save();
          _scrollToEnd();
          return;
        }
      }
    }
    final next = slot;
    setState(() {
      _thinking = false;
      _llmTurn = null;
      _asking = next;
      if (next != null) _msgs.add(_Msg.bot((l) => iv.turn(next, l).text));
    });
    _save();
    _scrollToEnd();
  }

  // ---- history ----------------------------------------------------------------------------------------------

  /// Saves this report (once it holds an answer or a file) so the user can come back to it.
  void _save() {
    final iv = _iv;
    if (iv == null || (iv.answers.isEmpty && iv.attachments.isEmpty)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_recordId == null) {
      _recordId = '$now';
      _createdMs = now;
    }
    final lang = _lang;
    int idx(ChatAttachment f) => iv.attachments.indexWhere((a) => a.path == f.path);
    ReportHistory.save(ReportRecord(
      id: _recordId!,
      createdMs: _createdMs,
      updatedMs: now,
      interview: iv.toJson(),
      lines: [
        for (final m in _msgs)
          if (m.files.isNotEmpty)
            SavedLine(user: true, text: '', files: [for (final f in m.files) if (idx(f) >= 0) idx(f)])
          else
            SavedLine(user: m.user, text: m.text ?? m.render!(lang), voice: m.voice),
      ],
    ));
  }

  /// Reopens a saved report: its chat, its answers, and the next question if it was left unfinished.
  Future<void> _openRecord(ReportRecord r) async {
    final seq = ++_seq;
    final (familyName, familyPhone) = _family;
    final iv = ReportInterview.fromJson(r.interview,
        persona: Persona.of(_profile), familyName: familyName, familyPhone: familyPhone);
    setState(() {
      _lost = iv.lost;
      _iv = iv;
      _recordId = r.id;
      _createdMs = r.createdMs;
      _asking = null;
      _llmTurn = null;
      _thinking = false;
      _msgs
        ..clear()
        ..addAll([
          for (final l in r.lines)
            if (l.files.isNotEmpty)
              _Msg.files([for (final i in l.files) if (i < iv.attachments.length) iv.attachments[i]])
            else if (l.user)
              _Msg.user(l.text, voice: l.voice)
            else
              _Msg.botText(l.text),
        ]);
      if (!iv.done) {
        // The pending question is asked again below: drop the unanswered bot lines at the end so it is not shown twice.
        while (_msgs.isNotEmpty && !_msgs.last.user && _msgs.last.evidence == null && _msgs.length > 1) {
          _msgs.removeLast();
        }
        _msgs.add(_Msg.bot((l) => rc(l, 'history_restored')));
      }
    });
    // Portal / Chakshu buttons come from the pack for this outcome.
    final m = await widget.api.pack(moneyLost: iv.lost);
    if (!mounted || seq != _seq) return;
    if (_pack == null || (_pack!.m['moneyLost'] != iv.lost && m != null)) {
      setState(() => _pack = m == null ? _Pack.fallback() : _Pack(m));
    }
    if (!iv.done) {
      _ask();
    } else {
      _scrollToEnd();
    }
  }

  void _newReport() {
    _seq++;
    setState(() {
      _lost = null;
      _iv = null;
      _recordId = null;
      _asking = null;
      _llmTurn = null;
      _thinking = false;
      _msgs.clear();
    });
  }

  Future<void> _showHistory() async {
    final lang = _lang;
    await ReportHistory.load();
    if (!mounted) return;
    final picked = await showIslandSheet<ReportRecord>(
      context,
      builder: (ctx) => _HistorySheet(lang: lang, currentId: _recordId),
    );
    if (picked != null && mounted) _openRecord(picked);
  }

  /// Bot lines that follow certain answers (reassurance after an OTP was shared, a hint for job scams).
  void _afterAnswer(Slot s, String value) {
    final iv = _iv!;
    if (s == Slot.sharedOtp && value == 'yes') _msgs.add(_Msg.bot((l) => rc(l, 'otp_yes')));
    if (s == Slot.scamType && iv.persona.young && iv.scamType == 'JOB') _msgs.add(_Msg.bot((l) => rc(l, 'type_young_hint')));
  }

  Future<void> _pick(ChatChoice c) async {
    final iv = _iv, slot = _asking;
    if (iv == null || slot == null) return;
    switch (c.action) {
      case ChoiceAction.attach:
        await _attach();
        return;
      case ChoiceAction.call181:
        await _run(widget.api.dial('181'), 'openErr');
      case ChoiceAction.callFamily:
        await _run(widget.api.dialContact(iv.familyPhone ?? ''), 'openErr');
      case ChoiceAction.finish:
      case ChoiceAction.none:
        break;
    }
    if (!mounted || _iv != iv) return;
    setState(() {
      _msgs.add(_Msg.user(c.label));
      iv.answer(slot, c.value, label: c.label);
      _afterAnswer(slot, iv.answers[slot] ?? c.value);
      _asking = null;
      _llmTurn = null;
    });
    _ask();
  }

  void _send({bool voice = false, String? text}) {
    final iv = _iv;
    final words = (text ?? _input.text).trim();
    if (iv == null || words.isEmpty) return;
    if (text == null) _input.clear();
    final slot = _asking ?? iv.nextSlot();
    setState(() {
      _msgs.add(_Msg.user(words, voice: voice));
      if (slot == null) {
        // After the summary: extra words go into the notes.
        final prev = iv.answers[Slot.extra] ?? '';
        iv.answers[Slot.extra] = prev.isEmpty ? words : '$prev; $words';
        _msgs.add(_Msg.bot((l) => rc(l, 'ack')));
      } else {
        iv.answer(slot, words);
        _afterAnswer(slot, iv.answers[slot] ?? words);
      }
      _asking = null;
      _llmTurn = null;
    });
    _ask();
  }

  Future<void> _attach() async {
    final iv = _iv;
    if (iv == null) return;
    final picked = await widget.api.pickAttachments();
    if (!mounted || _iv != iv) return;
    if (picked == null) {
      _toast(rc(_lang, 'attach_err'));
      return;
    }
    final files = [for (final m in picked) ?ChatAttachment.fromMap(m)];
    if (files.isEmpty) return; // cancelled
    final wasProof = _asking == Slot.proof;
    setState(() {
      _msgs.add(_Msg.files(files));
      iv.addAttachments(files);
      _msgs.add(_Msg.bot((l) => rc(l, 'attached', {'n': files.length})));
      if (wasProof) _asking = null;
    });
    if (wasProof) {
      _ask();
    } else {
      _save();
      _scrollToEnd();
    }
  }

  /// Tap on the mic: start listening, or (when already listening) stop and send what was heard.
  Future<void> _mic() async {
    if (_listening) return _stopVoice();
    await _beginVoice(hold: false);
  }

  /// Press and hold the mic: listen until the finger lifts.
  Future<void> _holdStart() async {
    if (_listening) return;
    await _beginVoice(hold: true);
  }

  /// Finger lifted: send, or drop everything when it slid away to cancel.
  void _holdEnd(bool cancel) {
    if (!_listening) return;
    if (cancel) {
      _cancelVoice();
    } else {
      _stopVoice();
    }
  }

  Future<void> _beginVoice({required bool hold}) async {
    _focus.unfocus();
    _speechSub?.cancel();
    _speechSub = widget.speech.stream().listen(_onSpeech, onError: (_) => _finishVoice());
    setState(() {
      _listening = true;
      _holding = hold;
      _cancelArmed = false;
      _stopping = false;
      _partial = '';
      _heard = '';
      _restarts = 0;
      _levels.fillRange(0, _levels.length, 0.1);
    });
    _scrollToEnd();
    await _startRecognizer();
  }

  Future<void> _startRecognizer() async {
    final r = await widget.speech.start(_lang);
    if (!mounted || !_listening) return;
    switch (r.status) {
      case SpeechStatus.live:
        return;
      case SpeechStatus.done: // the system dialog already returned the words
        _heard = _join(_heard, r.text);
        _finishVoice();
      case SpeechStatus.denied:
        _endVoice();
        _toast(rc(_lang, 'mic_denied'));
      case SpeechStatus.unavailable:
        _endVoice();
        _toast(rc(_lang, 'mic_none'));
      case SpeechStatus.failed:
        _endVoice();
        _toast(rc(_lang, 'mic_err'));
    }
  }

  static String _join(String a, String b) => [a.trim(), b.trim()].where((x) => x.isNotEmpty).join(' ');

  /// The recogniser stopped by itself (a pause). Keep listening unless the user has finished.
  void _continueOrFinish() {
    if (_stopping || !_listening || _restarts >= 30) return _finishVoice();
    _restarts++;
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted && _listening && !_stopping) _startRecognizer();
    });
  }

  void _onSpeech(SpeechEvent e) {
    if (!mounted || !_listening) return;
    switch (e.type) {
      case 'partial':
        setState(() => _partial = e.text);
      case 'rms':
        // ~20 updates a second from Android: redraw at most every 60 ms so the waveform does not jitter.
        final now = DateTime.now();
        if (now.difference(_lastLevel).inMilliseconds < 60) return;
        _lastLevel = now;
        setState(() {
          _levels.removeAt(0);
          _levels.add(e.level);
        });
      case 'final':
        setState(() {
          _heard = _join(_heard, e.text.isNotEmpty ? e.text : _partial);
          _partial = '';
        });
        _continueOrFinish();
      case 'error':
        if (e.code == 'NO_PERMISSION') {
          _endVoice();
          _toast(rc(_lang, 'mic_denied'));
          return;
        }
        // NO_MATCH (silence) and busy/client errors mid-session: keep the words so far and carry on.
        setState(() {
          _heard = _join(_heard, _partial);
          _partial = '';
        });
        _continueOrFinish();
      case 'end':
        // Bookkeeping from the native side after each session; the screen decides when listening ends.
        break;
    }
  }

  /// Stop listening and send. Waits briefly for the recogniser's last words.
  Future<void> _stopVoice() async {
    if (!_listening || _stopping) return;
    setState(() => _stopping = true);
    _finishTimer?.cancel();
    _finishTimer = Timer(const Duration(milliseconds: 1800), _finishVoice);
    await widget.speech.stop();
  }

  void _cancelVoice() {
    widget.speech.cancel();
    _endVoice();
    _toast(rc(_lang, 'mic_cancelled'));
  }

  /// Sends everything heard in this voice answer.
  void _finishVoice() {
    if (!_listening) return;
    final text = _join(_heard, _partial);
    widget.speech.cancel();
    _endVoice();
    if (text.isNotEmpty) {
      _send(voice: true, text: text);
    } else {
      _toast(rc(_lang, 'mic_err'));
    }
  }

  void _endVoice() {
    _finishTimer?.cancel();
    _finishTimer = null;
    _speechSub?.cancel();
    _speechSub = null;
    if (mounted && _listening) {
      setState(() {
        _listening = false;
        _holding = false;
        _cancelArmed = false;
        _stopping = false;
      });
    }
  }

  Future<void> _run(Future<bool> call, String errKey) async {
    final ok = await call;
    if (mounted && !ok) _toast(ReportStrings.of(_lang)[errKey]);
  }

  void _toast(String msg) => showIsland(context, msg);

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      });

  String _clock(int ms) =>
      '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';

  // The helpline comes from the pack; 1930 is the fallback so the button works before a path is chosen.
  String get _phone => _pack?.targets.map((e) => e['phone']).whereType<String>().firstOrNull ?? '1930';

  @override
  Widget build(BuildContext context) {
    final lang = _lang;
    final s = ReportStrings.of(lang);
    final p = palOf(context);
    final iv = _iv;
    final turn = (iv == null || _asking == null)
        ? null
        : (_llmTurn != null && _llmTurn!.slot == _asking ? _llmTurn : iv.turn(_asking!, lang));
    final done = iv != null && iv.done && !_thinking;
    return Column(children: [
      // Past reports / new report: pinned so they are reachable however long the chat gets.
      ValueListenableBuilder<List<ReportRecord>>(
        valueListenable: ReportHistory.items,
        builder: (_, saved, _) => saved.isEmpty && iv == null
            ? const SizedBox.shrink()
            : _chrome(Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.s),
                child: Row(children: [
                  if (saved.isNotEmpty)
                    Flexible(
                      child: TextButton.icon(
                        key: const Key('btn_history'),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: p.accent),
                        onPressed: _showHistory,
                        icon: const Icon(Icons.history_rounded, size: 20),
                        label: Text('${rc(lang, 'history')} (${saved.length})', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  const Spacer(),
                  if (iv != null)
                    Flexible(
                      child: TextButton.icon(
                        key: const Key('btn_new_report'),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: p.accent),
                        onPressed: _newReport,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: Text(rc(lang, 'history_new'), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ]),
              )),
      ),
      // A running clock is pinned above the chat so it never scrolls away; expired / failed states sit in the chat.
      if (_lost == true && _remainingMs != null)
        _chrome(Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.l), child: _golden(s))),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(Sp.l, Sp.s, Sp.l, Sp.l),
          children: [
            Text(rc(lang, 'calm'), style: TextStyle(fontSize: 15, color: p.muted)),
            const SizedBox(height: Sp.m),
            _paths(s),
            if (_lost == true && _remainingMs == null && _goldenFailed) _golden(s),
            if (_loading) StateMessage(loading: true, title: s['loading']),
            const SizedBox(height: Sp.m),
            for (final (i, m) in _msgs.indexed) ...[
              _message(m, lang, s, avatar: i == _msgs.length - 1 || _msgs[i + 1].user),
              const SizedBox(height: Sp.s + 2),
            ],
            if (_thinking) ...[TypingBubble(label: rc(lang, 'thinking')), const SizedBox(height: Sp.s)],
            if (turn != null && turn.choices.isNotEmpty && !_thinking)
              QuickReplies(choices: turn.choices, onPick: _pick, scale: _scale),
            if (done) ...[const SizedBox(height: Sp.s), _summary(lang, s, iv)],
          ],
        ),
      ),
      if (_listening)
        _chrome(ListeningPanel(
          partial: _join(_heard, _partial),
          levels: _levels,
          caption: _cancelArmed
              ? rc(lang, 'hold_cancel')
              : _holding
                  ? rc(lang, 'hold_hint')
                  : '${rc(lang, 'listening_sub', {'lang': _langName(lang)})} · ${rc(lang, 'tap_hint')}',
          stopLabel: rc(lang, 'stop'),
          onStop: _mic,
          scale: _scale,
          holding: _holding,
          cancelArmed: _cancelArmed,
        ), key: const ValueKey('listening_panel')),
      // While the mic is held the bar stays, so the finger keeps its button; in tap mode the panel replaces it.
      if (iv != null && (!_listening || _holding))
        _chrome(ChatInputBar(
          controller: _input,
          focusNode: _focus,
          hint: rc(lang, done ? 'ph_done' : 'ph'),
          attachLabel: rc(lang, 'attach'),
          micLabel: rc(lang, 'mic'),
          sendLabel: rc(lang, 'send'),
          numeric: turn?.numeric ?? false,
          onAttach: _attach,
          onMic: _mic,
          onSend: _send,
          micHint: rc(lang, 'mic_tip'),
          holding: _holding,
          onHoldStart: _holdStart,
          onHoldEnd: _holdEnd,
          onHoldSlide: (armed) => setState(() => _cancelArmed = armed),
        ), key: const ValueKey('input_bar')), // keyed: the panel appearing above must not rebuild it mid-hold
      // SafeArea: Android draws edge to edge, so without it the 1930 button sits under the system navigation bar.
      SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: Sp.s),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.l, Sp.xs, Sp.l, Sp.m),
        child: FilledButton.icon(
          key: Key('btn_dial_$_phone'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
          onPressed: () => _run(widget.api.dial(_phone), 'openErr'),
          icon: const Icon(Icons.phone, size: 26),
          label: Text(s['dialCta'], textAlign: TextAlign.center),
        ),
      )),
    ]);
  }

  // Pinned controls stop growing at 1.3x text (like the app bar) so the chat keeps room at 2x; the chat itself scales fully.
  static Widget _chrome(Widget child, {Key? key}) => Builder(
      key: key, builder: (context) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child));

  static String _langName(String l) => switch (l) { 'en' => 'English', 'hne' => 'छत्तीसगढ़ी', _ => 'हिंदी' };

  Widget _message(_Msg m, String lang, ReportStrings s, {required bool avatar}) {
    final scale = _scale;
    if (m.files.isNotEmpty) return AttachmentStrip(files: m.files);
    if (m.user) return UserBubble(text: m.text!, voice: m.voice, voiceTag: rc(lang, 'voice_tag'), scale: scale);
    final text = m.text ?? m.render!(lang);
    final e = m.evidence;
    if (e == null) return BotBubble(text: text, scale: scale, avatar: avatar);
    final type = e['scamType'] as String?;
    final src = e['source'] as String? ?? '';
    final triggers = ((e['triggers'] as List?) ?? const []).map((x) => '$x').toList();
    final p = palOf(context);
    return BotBubble(
      scale: scale,
      avatar: avatar,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: TextStyle(fontSize: scale.body, height: 1.45, color: p.ink)),
        const SizedBox(height: Sp.s),
        EvidenceChip(
          time: '${e['time'] ?? ''} · ${s['s_$src']}',
          title: type == null ? s['t_OTHER'] : s['t_$type'],
          quote: triggers.isEmpty ? null : triggers.join(', '),
        ),
      ]),
    );
  }

  Widget _paths(ReportStrings s) {
    final wide = MediaQuery.sizeOf(context).width >= 340 && MediaQuery.textScalerOf(context).scale(16) <= 21;
    final a = _pathCard(const Key('path_lost'), true, Icons.currency_rupee_rounded, s['pathLost'], s['pathLostSub']);
    final b = _pathCard(const Key('path_notyet'), false, Icons.verified_user_outlined, s['pathNot'], s['pathNotSub']);
    if (wide) {
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: a),
          const SizedBox(width: 10),
          Expanded(child: b),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 10), b]);
  }

  Widget _pathCard(Key key, bool lost, IconData icon, String title, String sub) {
    final p = palOf(context);
    final on = _lost == lost;
    return PressScale(
      child: Semantics(
        button: true,
        selected: on,
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadX.card),
            side: BorderSide(color: on ? p.accent : p.hairline, width: on ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: key,
            onTap: () => _choose(lost),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kTouch),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: on ? p.accentTint : p.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: on ? p.accent : p.ink),
                  ),
                  const SizedBox(height: Sp.s),
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
                  Text(sub, style: TextStyle(fontSize: 13, color: p.muted)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Slim golden-hour bar: tinted, a big clock and a thin bar; on expiry a restart button.
  Widget _golden(ReportStrings s) {
    final t = Theme.of(context);
    final p = palOf(context);
    final st = t.extension<StatusColors>() ?? StatusColors.light;
    final ms = _remainingMs;
    if (ms == null) {
      return Padding(
        padding: const EdgeInsets.only(top: Sp.m),
        child: OutlinedButton.icon(
          key: const Key('golden_start'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kTouch)),
          onPressed: _startGolden,
          icon: const Icon(Icons.timer_outlined),
          label: Text(s['start'], textAlign: TextAlign.center),
        ),
      );
    }
    final expired = ms == 0;
    return Container(
      margin: const EdgeInsets.only(top: Sp.m),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: st.tintOver(RiskLabel.scam, p.page), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.timer_outlined, size: 20, color: st.scam),
          const SizedBox(width: Sp.s),
          Expanded(
            child: Text(expired ? s['expired'] : s['goldenTitle'],
                key: expired ? const Key('golden_hint') : null,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: st.scam)),
          ),
          Text(_clock(ms),
              key: const Key('golden_timer'),
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: st.scam,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: Sp.s),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ms / _goldenMs,
            minHeight: 4,
            semanticsLabel: s['minLeft'].replaceFirst('{n}', '${(ms / 60000).ceil()}'),
            color: st.scam,
            backgroundColor: p.hairline,
          ),
        ),
        if (expired) ...[
          const SizedBox(height: Sp.s),
          OutlinedButton(
            key: const Key('golden_restart'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _startGolden,
            child: Text(s['restart'], textAlign: TextAlign.center),
          ),
        ],
      ]),
    );
  }

  Widget _summary(String lang, ReportStrings s, ReportInterview iv) {
    final p = palOf(context);
    final urls = [for (final x in _pack?.targets ?? const <Map<Object?, Object?>>[]) if (x['url'] is String) x['url'] as String];
    final canShare = iv.lost && _remainingMs != null;
    return ReportSummaryCard(
      title: rc(lang, 'ready'),
      subtitle: rc(lang, 'ready_sub'),
      editLabel: rc(lang, 'edit'),
      rows: iv.summary(lang),
      onEdit: () => _edit(iv),
      actions: [
        if (canShare)
          FilledButton(
            key: const Key('btn_share'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: p.ink,
              foregroundColor: p.page,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _run(
                widget.api.goldenShare(iv.fields(lang), attachments: [for (final f in iv.attachments) f.path]), 'shareErr'),
            child: Text(rc(lang, 'make'), textAlign: TextAlign.center),
          ),
        for (final url in urls)
          OutlinedButton.icon(
            key: Key('btn_open_${Uri.parse(url).host}'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _run(widget.api.open(url), 'openErr'),
            icon: Icon(Uri.parse(url).host.contains('cybercrime') ? Icons.language : Icons.report_outlined),
            label: Text(s[Uri.parse(url).host.contains('cybercrime') ? 'portal' : 'chakshu'], textAlign: TextAlign.center),
          ),
      ],
    );
  }

  // Hand edits to the three facts the police form needs most.
  Future<void> _edit(ReportInterview iv) async {
    final lang = _lang;
    final s = ReportStrings.of(lang);
    String cur(Slot k) {
      final v = iv.answers[k] ?? '';
      return const {'unknown', 'none'}.contains(v) ? '' : v;
    }

    final initial = {
      'scammer_number': cur(Slot.scammerId),
      if (iv.lost) 'amount': cur(Slot.amount),
      if (iv.lost) 'utr': cur(Slot.utr),
    };
    final edited = await showIslandSheet<Map<String, String>>(
      context,
      builder: (_) => _EditSheet(
        title: rc(lang, 'edit_title'),
        save: rc(lang, 'save'),
        labels: {for (final k in initial.keys) k: s['f_$k']},
        initial: initial,
      ),
    );
    if (edited != null && mounted) setState(() => iv.applyEdits(edited));
  }
}

/// Owns its controllers, so they live exactly as long as the sheet (including its closing animation).
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.title, required this.save, required this.labels, required this.initial});
  final String title, save;
  final Map<String, String> labels, initial;
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _ctrl = {for (final e in widget.initial.entries) e.key: TextEditingController(text: e.value)};

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        for (final e in _ctrl.entries) ...[
          const SizedBox(height: Sp.m),
          TextField(
            key: Key('field_${e.key}'),
            controller: e.value,
            keyboardType: e.key == 'amount' ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText: widget.labels[e.key]),
          ),
        ],
        const SizedBox(height: Sp.l),
        FilledButton(
          key: const Key('btn_save_edit'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).pop({for (final e in _ctrl.entries) e.key: e.value.text}),
          child: Text(widget.save),
        ),
      ]);
}

/// Saved reports, newest first. Tap one to reopen it; the bin deletes it (and its screenshots).
class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.lang, this.currentId});
  final String lang;
  final String? currentId;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
  }

  String _title(ReportRecord r) {
    final t = r.scamType;
    if (t == null) return rc(lang, 'k_type');
    final own = '${r.labels['scamType'] ?? ''}';
    if (t == 'OTHER' && own.isNotEmpty && !kScamTypes.contains(own)) return own;
    final k = 'st_$t';
    final v = rc(lang, k);
    return v == k ? rc(lang, 'st_OTHER') : v;
  }

  @override
  Widget build(BuildContext context) {
    final p = palOf(context);
    final th = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: ValueListenableBuilder<List<ReportRecord>>(
        valueListenable: ReportHistory.items,
        builder: (context, items, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(rc(lang, 'history'), style: th.textTheme.titleLarge),
          const SizedBox(height: Sp.s),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.l),
              child: Text(rc(lang, 'history_empty'), style: TextStyle(color: p.muted)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: p.hairline),
                itemBuilder: (context, i) {
                  final r = items[i];
                  final amount = int.tryParse('${r.answers['amount'] ?? ''}');
                  final sub = [
                    _when(r.createdMs),
                    rc(lang, r.lost ? 'history_lost' : 'history_notlost'),
                    if (amount != null) '₹${formatInr(amount)}',
                  ].join(' · ');
                  final st = th.extension<StatusColors>() ?? StatusColors.light;
                  return InkWell(
                    key: Key('hist_${r.id}'),
                    onTap: () => Navigator.of(context).pop(r),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Sp.s),
                        child: Row(children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: r.finished ? p.accentTint : st.tintOver(RiskLabel.suspicious, p.surface),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(r.finished ? Icons.task_alt_rounded : Icons.edit_note_rounded,
                                color: r.finished ? p.accent : st.suspicious, size: 22),
                          ),
                          const SizedBox(width: Sp.m),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_title(r), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
                              Text(sub, style: TextStyle(fontSize: 13, color: p.muted)),
                              Text(rc(lang, r.finished ? 'history_done' : 'history_draft'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: r.finished ? p.accent : st.suspicious)),
                            ]),
                          ),
                          IconButton(
                            key: Key('hist_del_${r.id}'),
                            tooltip: rc(lang, 'history_delete'),
                            onPressed: r.id == currentId ? null : () => ReportHistory.delete(r.id),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}
