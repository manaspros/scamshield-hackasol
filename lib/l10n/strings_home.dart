import 'app_language.dart';

/// Home page, onboarding, evidence, "about me" and past-alert screens.
// hne wording is a first draft: [VERIFY] with a native Chhattisgarhi speaker. Missing hne falls back to hi.
const homeStrings = Tri(
  hi: {
    'prot_ok': 'आप सुरक्षित हैं', 'prot_off': 'ध्यान दें: {what} बंद है', 'prot_checking': 'जाँच हो रही है…',
    'off_call': 'कॉल सुरक्षा', 'off_msg': 'मैसेज सुरक्षा', 'off_notif': 'अलर्ट',
    'fix': 'ठीक करें',
    'fam_title': 'परिवार का कोड', 'fam_ask': 'फ़ोन करने वाले से यह कोड पूछें',
    'fam_sec': 'सेकंड',
    'fam_pair_t': 'अपने परिवार को सुरक्षित करें',
    'fam_pair_b': 'दो फ़ोन जोड़ें। परिवार का बनकर फ़ोन करने वाले को यह कोड बताना होगा।',
    'fam_pair': 'परिवार से जोड़ें', 'fam_err': 'कोड नहीं मिल सका', 'fam_open': 'परिवार का कोड खोलें',
    'act_evidence': 'सबूत बनाएँ',
    'act_know': 'ScamShield मेरे बारे में क्या जानता है',
    'act_alerts': 'पुरानी धोखाधड़ी चेतावनियाँ',
    'ev_title': 'सबूत', 'ev_working': 'सबूत बन रहा है…',
    'ev_empty_t': 'रिपोर्ट करने लायक कुछ नहीं', 'ev_empty_s': 'पिछले 24 घंटे में कोई धोखाधड़ी या संदिग्ध चेतावनी नहीं मिली।',
    'ev_done': 'सबूत तैयार है', 'ev_done_s': '{n} चेतावनियाँ एक फ़ाइल में सेव हुईं',
    'ev_included': 'इसमें क्या है',
    'ev_note': 'चेतावनी का प्रकार, स्रोत, समय और मिले शब्द। संदेश का पूरा पाठ सेव नहीं होता।',
    'ev_share': 'फ़ाइल शेयर या सेव करें', 'ev_dial': '1930 डायल करें', 'ev_dial_note': 'डायलर खुलेगा। कॉल आप खुद करेंगे।',
    'ev_err': 'सबूत नहीं बन सका', 'ev_share_err': 'फ़ाइल शेयर नहीं हो सकी', 'retry': 'फिर कोशिश करें',
    'kn_title': 'मेरे बारे में', 'kn_intro': 'सिर्फ़ वही जो इस फ़ोन पर है। संदेश का पाठ कभी सेव नहीं होता।',
    'kn_empty_t': 'अभी कुछ नहीं सीखा', 'kn_empty_s': 'अलर्ट चालू होने पर ScamShield आपके बैंक और दुकान के संदेशों से सीखता है।',
    'kn_brands': 'बैंक और दुकानें', 'kn_recent': 'हाल की गतिविधि', 'kn_senders': 'जिनसे संदेश आते हैं',
    'kn_contacts': 'देखे गए नंबर और UPI', 'kn_numbers': '{n} फ़ोन नंबर', 'kn_upi': '{n} UPI आईडी',
    'kn_msgs': '{n} संदेश', 'kn_personal': '{n} निजी नंबरों से {m} संदेश', 'kn_learned': '{n} संदेशों से सीखा', 'kn_err': 'जानकारी नहीं मिल सकी',
    'ev_CREDIT': 'पैसे आए', 'ev_BILL': 'बिल', 'ev_ORDER': 'ऑर्डर', 'ev_OUT_FOR_DELIVERY': 'डिलीवरी के लिए निकला',
    'al_title': 'पुरानी चेतावनियाँ', 'f_all': 'सब', 'f_scam': 'धोखाधड़ी', 'f_susp': 'संदिग्ध',
    'sort_new': 'नया पहले', 'sort_risk': 'सबसे खतरनाक', 'al_empty_t': 'अभी कोई चेतावनी नहीं',
    'al_empty_s': 'अच्छी बात: कुछ संदिग्ध नहीं मिला।', 'al_none': 'इस फ़िल्टर में कुछ नहीं',
    'al_detail': 'चेतावनी का ब्यौरा', 'al_make': 'इसका सबूत बनाएँ', 'al_why': 'क्यों पकड़ा', 'al_conf': 'भरोसा {p}%',
    'al_no_why': 'कोई ब्यौरा सेव नहीं है।', 'al_privacy': 'ScamShield संदेश का पाठ सेव नहीं करता।',
    'kn_del': 'मेरा डेटा मिटाएँ', 'kn_del_t': 'मेरा डेटा मिटाएँ?',
    'kn_del_b': 'ScamShield ने इस फ़ोन पर जो सीखा है वह सब मिट जाएगा: जानकारी, भरोसेमंद और रिपोर्ट किए गए निशान।',
    'kn_del_alerts': 'पुरानी चेतावनियाँ भी मिटाएँ', 'kn_cancel': 'रद्द करें', 'kn_del_ok': 'मिटाएँ', 'kn_deleted': 'मिटा दिया',
    'kn_del_err': 'अभी नहीं मिटा सके। फिर कोशिश करें।',
    'fb_safe': 'यह सुरक्षित है / मैं इन्हें जानता हूँ', 'fb_scam': 'यह ठगी थी',
    'fb_safe_ok': 'हम इस भेजने वाले पर भरोसा करेंगे', 'fb_scam_ok': 'रिपोर्ट हो गई। ये फिर संदेश भेजें तो हम चेताएँगे',
    'fb_none': 'याद रखने को कुछ नहीं: इस चेतावनी में कोई भेजने वाला नहीं है (कॉल और पेस्ट किया टेक्स्ट)।',
    'fb_note': 'सुरक्षित चुनने पर भी OTP माँगने, रिमोट-एक्सेस ऐप या नकली पैसे आने की चेतावनी कभी नहीं छिपेगी।',
    'al_other': 'अन्य',
    'src_caption': 'फ़ोन कॉल', 'src_paste': 'चिपकाया संदेश', 'src_share': 'शेयर किया संदेश', 'src_sms': 'SMS',
    'src_whatsapp': 'WhatsApp', 'src_notification': 'नोटिफ़िकेशन', 'src_recording': 'रिकॉर्डिंग', 'src_signal': 'कॉल संकेत',
    't_now': 'अभी', 't_min': '{n} मिनट पहले', 't_hour': '{n} घंटे पहले', 't_day': '{n} दिन पहले',
    'ob_skip': 'छोड़ें', 'ob_next': 'आगे', 'ob_back': 'पीछे', 'ob_step': 'चरण {n} / {m}',
    'ob1_t': 'ठग जीतने से पहले ScamShield आपको चेताता है',
    'ob1_a': 'कॉल और संदेशों में ठगी के शब्द सुनता है', 'ob1_b': 'तुरंत स्क्रीन पर चेतावनी देता है',
    'ob1_c': 'सब इसी फ़ोन पर चलता है। कुछ अपलोड नहीं होता।',
    'ob2_t': 'ज़रूरी अनुमतियाँ दें',
    'ob3_t': 'परिवार को सुरक्षित करें', 'ob3_b': 'परिवार के फ़ोन से जुड़कर गुप्त कोड पाएँ। असली रिश्तेदार को कोड पता होगा, ठग को नहीं।',
    'ob3_pair': 'अभी जोड़ें', 'ob3_later': 'बाद में',
    'ob4_t': 'सब तैयार है', 'ob4_b': 'परिवार का कोड, पुरानी चेतावनियाँ और सबूत होम पेज पर हैं।', 'ob_start': 'शुरू करें',
    'set_setup': 'सेटअप और अनुमतियाँ', 'set_setup_s': 'देखें ScamShield को क्या चाहिए',
  },
  hne: {
    'prot_ok': 'तुमन सुरक्षित हव', 'prot_off': 'धियान देव: {what} बंद हे',
    'fix': 'ठीक करव',
    'fam_title': 'परिवार के कोड', 'fam_ask': 'फ़ोन करइया ले ए कोड पूछव',
    'fam_pair_t': 'अपन परिवार ल सुरक्षित करव', 'fam_pair': 'परिवार ले जोड़व',
    'act_evidence': 'सबूत बनावव', 'act_know': 'ScamShield मोर बारे म का जानथे',
    'act_alerts': 'जुन्ना ठगी चेतावनी', 'ev_title': 'सबूत',
    'ev_share': 'फ़ाइल शेयर या सेव करव',
    'kn_title': 'मोर बारे म', 'al_title': 'जुन्ना चेतावनी', 'al_make': 'एकर सबूत बनावव',
    'ob_skip': 'छोड़व', 'ob_next': 'आगू', 'ob_back': 'पाछू', 'ob_start': 'सुरु करव',
    'ob4_t': 'सब तैयार हे',
  },
  en: {
    'prot_ok': "You're protected", 'prot_off': 'Needs attention: {what} is off', 'prot_checking': 'Checking…',
    'off_call': 'Call protection', 'off_msg': 'Message protection', 'off_notif': 'Alerts',
    'fix': 'Fix',
    'fam_title': 'Family code', 'fam_ask': 'Ask the caller for this code',
    'fam_sec': 'sec',
    'fam_pair_t': 'Protect your family',
    'fam_pair_b': 'Pair two phones. A caller who says they are family must give the code.',
    'fam_pair': 'Pair with family', 'fam_err': 'Could not get the code', 'fam_open': 'Open family code',
    'act_evidence': 'Make evidence',
    'act_know': 'What ScamShield knows about me',
    'act_alerts': 'Past scam alerts',
    'ev_title': 'Evidence', 'ev_working': 'Making evidence…',
    'ev_empty_t': 'Nothing to report', 'ev_empty_s': 'No scam or suspicious alerts in the last 24 hours.',
    'ev_done': 'Evidence ready', 'ev_done_s': '{n} alerts saved in one file',
    'ev_included': 'What is included',
    'ev_note': 'Alert type, source, time and matched words. Message text is never saved.',
    'ev_share': 'Share or save file', 'ev_dial': 'Call 1930', 'ev_dial_note': 'Opens the dialer. You place the call yourself.',
    'ev_err': 'Could not make evidence', 'ev_share_err': 'Could not share the file', 'retry': 'Try again',
    'kn_title': 'About me', 'kn_intro': 'Only what is on this phone. Message text is never saved.',
    'kn_empty_t': 'Nothing learned yet', 'kn_empty_s': 'ScamShield learns from your bank and shop messages once alerts are on.',
    'kn_brands': 'Banks and shops', 'kn_recent': 'Recent activity', 'kn_senders': 'Senders you hear from',
    'kn_contacts': 'Numbers and UPI IDs seen', 'kn_numbers': '{n} phone numbers', 'kn_upi': '{n} UPI IDs',
    'kn_msgs': '{n} messages', 'kn_personal': '{m} messages from {n} personal numbers', 'kn_learned': 'Learned from {n} messages', 'kn_err': 'Could not load this',
    'ev_CREDIT': 'Money received', 'ev_BILL': 'Bill', 'ev_ORDER': 'Order', 'ev_OUT_FOR_DELIVERY': 'Out for delivery',
    'al_title': 'Past scam alerts', 'f_all': 'All', 'f_scam': 'Scam', 'f_susp': 'Suspicious',
    'sort_new': 'Newest', 'sort_risk': 'Most risky', 'al_empty_t': 'No alerts yet',
    'al_empty_s': 'Good news: nothing suspicious has been found.', 'al_none': 'No alerts match this filter',
    'al_detail': 'Alert details', 'al_make': 'Make evidence for this', 'al_why': 'Why it was flagged', 'al_conf': 'Confidence {p}%',
    'al_no_why': 'No details were saved.', 'al_privacy': 'ScamShield keeps no message text.',
    'kn_del': 'Delete my data', 'kn_del_t': 'Delete my data?',
    'kn_del_b': 'Everything ScamShield learned on this phone will be erased: the knowledge above and your trusted and reported marks.',
    'kn_del_alerts': 'Also delete past alerts', 'kn_cancel': 'Cancel', 'kn_del_ok': 'Delete', 'kn_deleted': 'Deleted',
    'kn_del_err': 'Could not delete right now. Please try again.',
    'fb_safe': 'This is safe / I know them', 'fb_scam': 'This was a scam',
    'fb_safe_ok': "We'll trust this sender", 'fb_scam_ok': "Reported. We'll warn you if they message again",
    'fb_none': 'Nothing to remember: this alert has no sender (calls and pasted text).',
    'fb_note': 'Marking safe never hides warnings about OTP requests, remote-access apps or fake money credits.',
    'al_other': 'Other',
    'src_caption': 'Phone call', 'src_paste': 'Pasted message', 'src_share': 'Shared message', 'src_sms': 'SMS',
    'src_whatsapp': 'WhatsApp', 'src_notification': 'Notification', 'src_recording': 'Recording', 'src_signal': 'Call signal',
    't_now': 'Just now', 't_min': '{n} min ago', 't_hour': '{n} h ago', 't_day': '{n} d ago',
    'ob_skip': 'Skip', 'ob_next': 'Next', 'ob_back': 'Back', 'ob_step': 'Step {n} of {m}',
    'ob1_t': 'ScamShield warns you before a scammer wins',
    'ob1_a': 'Listens for scam words in calls and messages', 'ob1_b': 'Warns you on screen straight away',
    'ob1_c': 'Works on this phone. Nothing is uploaded.',
    'ob2_t': 'Allow what it needs',
    'ob3_t': 'Protect your family', 'ob3_b': 'Pair with a family phone to get a secret code. A real relative knows it, a scammer does not.',
    'ob3_pair': 'Pair now', 'ob3_later': 'Later',
    'ob4_t': "You're all set", 'ob4_b': 'Your family code, past alerts and evidence are on the home page.', 'ob_start': 'Start using ScamShield',
    'set_setup': 'Setup & permissions', 'set_setup_s': 'Check what ScamShield needs',
  },
);

/// [key] in [lang]; `{n}`-style placeholders are replaced from [args].
String homeT(String lang, String key, [Map<String, Object?> args = const {}]) {
  var s = homeStrings(lang, key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Source name (SMS, WhatsApp, phone call...) for the channel's lower-case source value.
String sourceIn(String lang, String source) {
  final k = 'src_$source';
  final s = homeStrings(lang, k);
  return s == k ? source : s;
}

/// "5 min ago" style label; older than a week falls back to an ISO date.
String agoIn(String lang, int tsMs, {int? nowMs}) {
  final d = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - tsMs;
  if (d < 60000) return homeT(lang, 't_now');
  if (d < 3600000) return homeT(lang, 't_min', {'n': d ~/ 60000});
  if (d < 86400000) return homeT(lang, 't_hour', {'n': d ~/ 3600000});
  if (d < 7 * 86400000) return homeT(lang, 't_day', {'n': d ~/ 86400000});
  return DateTime.fromMillisecondsSinceEpoch(tsMs).toIso8601String().substring(0, 10);
}
