import 'app_language.dart';

/// Setup screen. In hi/hne the Hindi line leads and English is the small second line (keys ending
/// `_s`); in en the screen is English only, so en has no `_s` keys. Placeholders use {x}.
const setupStrings = Tri(
  hi: {
    'hero_none': 'चलिए सुरक्षा चालू करें', 'hero_some': 'बस थोड़ा और', 'hero_all': 'पूरी तरह सुरक्षित',
    'hero_left': '{n} कदम बाकी', 'hero_left1': 'बस 1 कदम बाकी', 'hero_all_s': 'कॉल, मैसेज और चेतावनी, सब चालू हैं।',
    'sec_required': 'ज़रूरी', 'sec_check': 'जाँच कर देखें', 'sec_optional': 'वैकल्पिक',
    's_call': 'कॉल सुरक्षा', 's_call_d': 'कॉल के कैप्शन पढ़ता है', 's_cap': 'लाइव कैप्शन', 's_cap_d': 'बोली को लिखाई में बदलता है',
    's_notif': 'ठगी की चेतावनी', 's_notif_d': 'तुरंत चेतावनी दिखाता है', 's_msg': 'मैसेज सुरक्षा', 's_msg_d': 'SMS और WhatsApp जाँचता है',
    'not_on': 'अभी चालू नहीं', 'on': 'चालू', 'turned_on': 'मैंने चालू कर दिया',
    'why_call': 'कॉल के कैप्शन पढ़ने देता है ताकि ठगी की बात होते ही ScamShield आपको चेता सके।',
    'why_cap': 'Android कॉल की बातें स्क्रीन पर लिखता है, ScamShield उन्हें पढ़ता है। हर कॉल पर यह इसे खुद चालू करने की कोशिश भी करता है।',
    'how_call_1': '"एक्सेसिबिलिटी खोलें" दबाएँ', 'how_call_2': '"ScamShield कॉल सुरक्षा" चुनें', 'how_call_3': 'इसे चालू करें और पुष्टि करें',
    'how_cap_1': 'आवाज़ का बटन दबाएँ', 'how_cap_2': 'स्लाइडर के नीचे कैप्शन का निशान दबाएँ', 'how_cap_3': '"कॉल के कैप्शन" भी चालू करें',
    'how_notif_1': 'नीचे का बटन दबाएँ', 'how_notif_2': 'Android के सवाल पर "अनुमति दें" चुनें',
    'how_msg_1': '"नोटिफ़िकेशन ऐक्सेस खोलें" दबाएँ', 'how_msg_2': 'ScamShield चुनें', 'how_msg_3': 'इसे चालू करें',
    'bub_row': 'चेतावनी बबल', 'bub_row_d': 'देखें ठगी की चेतावनी कैसी दिखती है', 'show': 'दिखाएँ',
    'mic_row': 'कॉल ऑडियो जाँच', 'mic_row_d': 'क्या यह फ़ोन कॉल सुन सकता है?', 'beta': 'बीटा',
    'ai_row': 'फ़ोन पर AI', 'ai_ready': '{m} तैयार है', 'ai_none': 'डाउनलोड नहीं · वैकल्पिक',
    'count': '{n} / 4 ज़रूरी कदम पूरे',
    'done': 'हो गया', 'todo': 'बाकी है', 'done_sem': '{title}, हो गया',
    'fail_title': 'सेटअप की स्थिति नहीं मिल सकी', 'fail_sub': 'फिर कोशिश करें', 'retry': 'फिर कोशिश करें',
    'checking': 'स्थिति जाँची जा रही है…',
    'privacy': 'ScamShield सिर्फ़ स्क्रीन के कैप्शन पढ़ता है। आवाज़ रिकॉर्ड नहीं होती।',
    'privacy_s': 'Reads on-screen captions only. No audio recorded.',
    'adv': 'उन्नत', 'adv_s': 'Advanced (optional)',
    'pre': 'अब Android आपसे पूछेगा। यह सामान्य है।', 'pre_s': 'Android will now ask you to confirm. This is normal.',
    'why_service': 'ठगी की बात पर तुरंत चेतावनी देने के लिए ScamShield को कॉल कैप्शन पढ़ने होंगे।',
    'why_notif': 'ठगी पकड़े जाने पर फ़ोन पर चेतावनी दिखाने के लिए सूचनाओं की अनुमति चाहिए।',
    'why_msg': 'SMS और WhatsApp के ठग संदेश पकड़ने के लिए ScamShield को आने वाली सूचनाएँ पढ़नी होंगी। यह सिर्फ़ इसी फ़ोन पर होता है।',
    'prim_cap': 'मैंने लाइव कैप्शन चालू कर लिया',
    'call_title': 'कॉल सुरक्षा चालू करें', 'call_s': 'Turn on call protection',
    'call_body': 'Settings → Accessibility → ScamShield call protection → On.\n'
        'ScamShield only reads on-screen caption text. No audio is recorded and nothing leaves your phone.',
    'open_acc': 'एक्सेसिबिलिटी खोलें', 'open_acc_s': 'Open Accessibility',
    'cap_title': 'लाइव कैप्शन चालू करें', 'cap_s': 'Turn on Live Caption (once, it stays on)',
    'cap_body': 'वॉल्यूम बटन दबाएँ, नीचे कैप्शन का निशान दबाएँ।\n'
        'Press a volume key, tap the captions icon.\n'
        'Pixel: Settings → Sound → Live Caption (also turn on "Caption calls").\n'
        'Samsung: Settings → Accessibility → Hearing enhancements → Live Caption.\n'
        'ScamShield checks every call and tries to switch it on automatically if it is off.',
    'open_cap': 'कैप्शन सेटिंग खोलें', 'open_cap_s': 'Open caption settings',
    'notif_title': 'अलर्ट सूचनाएँ चालू करें',
    'notif_body': 'स्कैम मिलने पर फ़ोन पर तुरंत चेतावनी दिखेगी, साथ में "रिपोर्ट करें" बटन।\n'
        'Allow notifications so a scam warning pops up with a Report button.',
    'notif_on': 'सूचनाएँ चालू हैं', 'notif_enable': 'सूचनाएँ चालू करें',
    'msg_title': 'मैसेज सुरक्षा चालू करें',
    'msg_body': 'ScamShield फ़ोन पर आए मैसेज (SMS, WhatsApp) की सूचनाएँ पढ़ता है, सिर्फ़ इसी फ़ोन पर। कुछ भी फ़ोन से बाहर नहीं जाता।\n'
        'ScamShield reads message notifications on the phone only; nothing leaves the phone. '
        'Settings → Notification access → ScamShield → On.',
    'msg_on': 'चालू है', 'msg_open': 'नोटिफ़िकेशन एक्सेस खोलें',
    'model_title': 'ऑन-डिवाइस AI मॉडल', 'model_s': 'On-device AI model (Gemma 3 1B)',
    'model_status': 'Status: {s} {m}\n', 'model_file': 'File: {p} ({mb} MB)\n',
    'model_body': 'Without the model, ScamShield still works using rules only.\n'
        'Download it once (~555 MB, Wi-Fi recommended). It keeps downloading in the background.',
    'model_dl': 'मॉडल डाउनलोड करें', 'model_dl_s': 'Download model',
    'cancel': 'रद्द करें', 'cancel_s': 'Cancel',
    'copying': 'कॉपी हो रहा है…', 'copying_s': 'Copying (≈550 MB)…',
    'import': '.task फ़ाइल जोड़ें', 'import_s': 'Import .task file',
    'reload': 'मॉडल फिर लोड करें', 'reload_s': 'Reload model',
    'import_failed': 'Import failed: {e}',
    'mic_title': 'कॉल ऑडियो टेस्ट', 'mic_s': 'Call audio test (can the mic hear calls on this phone?)',
    'mic_body': 'Allow the microphone, then make a call ON SPEAKER and keep talking for ~15 s.\n'
        'ScamShield records 3 s from each mic source and shows the result in the Live tab '
        '(HAS_AUDIO / SILENT) with a play button. Nothing is uploaded.',
    'mic_ok': 'माइक्रोफ़ोन की अनुमति मिल गई', 'mic_ok_s': 'Microphone allowed',
    'mic_allow': 'माइक्रोफ़ोन की अनुमति दें', 'mic_allow_s': 'Allow microphone',
    'mic_next': 'अगली कॉल पर जाँचें', 'mic_next_s': 'Test on my next call',
    'mic_now': 'अभी जाँचें (बिना कॉल)', 'mic_now_s': 'Test now (no call)',
    'mic_armed': 'Armed: make a call on speaker now. Results appear in the Live tab.',
    'bub_title': 'चेतावनी बबल जाँचें', 'bub_s': 'Test the warning bubble',
    'bub_body': 'Shows a sample SCAM warning on top of the screen, exactly as it appears during a call.',
    'bub_show': 'टेस्ट बबल दिखाएँ', 'bub_show_s': 'Show test bubble',
  },
  hne: {
    'hero_some': 'बस थोरकुन अउ', 'turned_on': 'मँय चालू कर देंव', 'on': 'चालू',
    'count': '{n} / 4 जरूरी कदम पूरा',
    'done': 'हो गे', 'todo': 'बाकी हे', 'done_sem': '{title}, हो गे',
    'fail_sub': 'फेर कोसिस करव', 'retry': 'फेर कोसिस करव',
    'prim_cap': 'मैं लाइव कैप्शन चालू कर लेंव',
    'call_title': 'काल सुरक्षा चालू करव',
    'cap_title': 'लाइव कैप्शन चालू करव',
    'notif_title': 'अलर्ट सूचना चालू करव', 'notif_on': 'सूचना चालू हे', 'notif_enable': 'सूचना चालू करव',
    'msg_title': 'मैसेज सुरक्षा चालू करव', 'msg_on': 'चालू हे',
    'cancel': 'रद्द करव', 'bub_title': 'चेतावनी बबल जाँचव',
  },
  en: {
    'hero_none': "Let's turn on protection", 'hero_some': 'Almost there', 'hero_all': 'Fully protected',
    'hero_left': '{n} steps left', 'hero_left1': 'Just 1 step left', 'hero_all_s': 'Calls, messages and warnings are all covered.',
    'sec_required': 'Required', 'sec_check': 'Check it works', 'sec_optional': 'Optional',
    's_call': 'Call protection', 's_call_d': 'Reads call captions', 's_cap': 'Live Caption', 's_cap_d': 'Turns speech into text',
    's_notif': 'Scam alerts', 's_notif_d': 'Pops up a warning', 's_msg': 'Message protection', 's_msg_d': 'Checks SMS and WhatsApp',
    'not_on': 'Not on yet', 'on': 'On', 'turned_on': 'I turned it on',
    'why_call': 'Lets ScamShield read call captions so it can warn you the moment a scam is spoken.',
    'why_cap': 'Android turns the call into text on screen and ScamShield reads that text. It also tries to switch it on for each call.',
    'how_call_1': 'Tap Open Accessibility', 'how_call_2': 'Choose "ScamShield call protection"', 'how_call_3': 'Turn it on and confirm',
    'how_cap_1': 'Press a volume key', 'how_cap_2': 'Tap the captions icon under the slider', 'how_cap_3': 'Turn on "Caption calls" too',
    'how_notif_1': 'Tap the button below', 'how_notif_2': 'Choose "Allow" when Android asks',
    'how_msg_1': 'Tap Open notification access', 'how_msg_2': 'Choose ScamShield', 'how_msg_3': 'Turn it on',
    'bub_row': 'Warning bubble', 'bub_row_d': 'See how a scam warning looks', 'show': 'Show',
    'mic_row': 'Call audio test', 'mic_row_d': 'Can this phone hear calls?', 'beta': 'Beta',
    'ai_row': 'On-device AI', 'ai_ready': '{m} is ready', 'ai_none': 'Not downloaded · optional',
    'count': '{n} / 4 required steps done',
    'done': 'Done', 'todo': 'To do', 'done_sem': '{title}, done',
    'fail_title': 'Could not get the setup status', 'retry': 'Try again',
    'checking': 'Checking status…',
    'privacy': 'ScamShield only reads on-screen captions. No audio is recorded.',
    'adv': 'Advanced (optional)',
    'pre': 'Android will now ask you to confirm. This is normal.',
    'why_service': 'ScamShield needs to read call captions so it can warn you the moment a scam is spoken.',
    'why_notif': 'Notification permission is needed to show a warning on your phone when a scam is caught.',
    'why_msg': 'ScamShield needs to read incoming notifications to catch scam SMS and WhatsApp messages. This happens on this phone only.',
    'prim_cap': 'I turned on Live Caption',
    'call_title': 'Turn on call protection',
    'call_body': 'Settings → Accessibility → ScamShield call protection → On.\n'
        'ScamShield only reads on-screen caption text. No audio is recorded and nothing leaves your phone.',
    'open_acc': 'Open Accessibility',
    'cap_title': 'Turn on Live Caption',
    'cap_body': 'Press a volume key, tap the captions icon.\n'
        'Pixel: Settings → Sound → Live Caption (also turn on "Caption calls").\n'
        'Samsung: Settings → Accessibility → Hearing enhancements → Live Caption.\n'
        'ScamShield checks every call and tries to switch it on automatically if it is off.',
    'open_cap': 'Open caption settings',
    'notif_title': 'Turn on alert notifications',
    'notif_body': 'Allow notifications so a scam warning pops up with a Report button.',
    'notif_on': 'Notifications are on', 'notif_enable': 'Turn on notifications',
    'msg_title': 'Turn on message protection',
    'msg_body': 'ScamShield reads message notifications (SMS, WhatsApp) on the phone only; nothing leaves the phone. '
        'Settings → Notification access → ScamShield → On.',
    'msg_on': 'On', 'msg_open': 'Open notification access',
    'model_title': 'On-device AI model (Gemma 3 1B)',
    'model_status': 'Status: {s} {m}\n', 'model_file': 'File: {p} ({mb} MB)\n',
    'model_body': 'Without the model, ScamShield still works using rules only.\n'
        'Download it once (~555 MB, Wi-Fi recommended). It keeps downloading in the background.',
    'model_dl': 'Download model', 'cancel': 'Cancel', 'copying': 'Copying (≈550 MB)…',
    'import': 'Import .task file', 'reload': 'Reload model',
    'import_failed': 'Import failed: {e}',
    'mic_title': 'Call audio test (can the mic hear calls on this phone?)',
    'mic_body': 'Allow the microphone, then make a call ON SPEAKER and keep talking for ~15 s.\n'
        'ScamShield records 3 s from each mic source and shows the result in the Live tab '
        '(HAS_AUDIO / SILENT) with a play button. Nothing is uploaded.',
    'mic_ok': 'Microphone allowed', 'mic_allow': 'Allow microphone',
    'mic_next': 'Test on my next call', 'mic_now': 'Test now (no call)',
    'mic_armed': 'Armed: make a call on speaker now. Results appear in the Live tab.',
    'bub_title': 'Test the warning bubble',
    'bub_body': 'Shows a sample SCAM warning on top of the screen, exactly as it appears during a call.',
    'bub_show': 'Show test bubble',
  },
);

String setupT(String lang, String key, [Map<String, Object?> args = const {}]) {
  var s = setupStrings(lang, key);
  for (final e in args.entries) {
    s = s.replaceAll('{${e.key}}', '${e.value}');
  }
  return s;
}
