import '../models/verdict.dart';
import 'app_language.dart';

/// Tab titles, nav labels, app-bar button, Help hub and the verdict card (shared by every screen).
const shellStrings = Tri(
  hi: {
    'tab_setup': 'सेटअप', 'tab_check': 'जाँच', 'tab_live': 'लाइव', 'tab_learn': 'सीखें', 'tab_help': 'मदद',
    'help_me': 'मदद चाहिए?', 'help_1930': 'ठगे गए? 1930',
    'report': 'रिपोर्ट करें', 'report_title': 'रिपोर्ट', 'report_cap': 'Report a scam (1930)',
    'family': 'परिवार कोड', 'family_cap': 'Family code',
    'settings': 'सेटिंग', 'settings_cap': 'Settings',
    'recording': 'कॉल रिकॉर्डिंग', 'recording_title': 'रिकॉर्डिंग', 'recording_cap': 'Check a recorded call',
    'demo': 'डेमो लैब', 'demo_cap': 'Demo Lab',
    'help_sub': 'Help',
    'why': 'क्यों?', 'why_colon': 'क्यों:',
    'head_safe': 'सुरक्षित', 'head_suspicious': 'सावधान', 'head_scam': 'धोखाधड़ी!',
    'label_safe': 'सामान्य बातचीत', 'label_suspicious': 'सावधान रहें', 'label_scam': 'धोखाधड़ी हो सकती है',
  },
  hne: {
    'tab_learn': 'सीखव', 'help_me': 'मदद चाही?', 'help_1930': 'ठगाय गेव? 1930',
    'report': 'रिपोर्ट करव', 'recording': 'काल रिकॉर्डिंग',
    'label_suspicious': 'सावधान रहव', 'label_scam': 'ठगी होए सकत हे',
  },
  en: {
    'tab_setup': 'Setup', 'tab_check': 'Check', 'tab_live': 'Live', 'tab_learn': 'Learn', 'tab_help': 'Help',
    'help_me': 'Need help?', 'help_1930': 'Scammed? 1930',
    'report': 'Report a scam', 'report_title': 'Report', 'report_cap': 'दर्ज करें · 1930',
    'family': 'Family code', 'family_cap': 'परिवार कोड',
    'settings': 'Settings', 'settings_cap': 'सेटिंग',
    'recording': 'Call recording', 'recording_title': 'Recording', 'recording_cap': 'Check a recorded call',
    'demo': 'Demo Lab', 'demo_cap': 'डेमो लैब',
    'help_sub': 'मदद',
    'why': 'Why?', 'why_colon': 'Why:',
    'head_safe': 'Safe', 'head_suspicious': 'Be careful', 'head_scam': 'Scam!',
    'label_safe': 'Normal conversation', 'label_suspicious': 'Stay alert', 'label_scam': 'This may be a scam',
  },
);

String shellT(String lang, String key) => shellStrings(lang, key);

extension VerdictL10n on RiskLabel {
  String headlineIn(String lang) => shellStrings(lang, 'head_$name');
  String textIn(String lang) => shellStrings(lang, 'label_$name');
}

const _scamTypes = Tri(
  hi: {
    'OTP': 'ओटीपी माँगना', 'KYC': 'केवाईसी धोखा', 'DIGITAL_ARREST': 'डिजिटल अरेस्ट',
    'COURIER_CUSTOMS': 'कूरियर / कस्टम्स धोखा', 'FAKE_QR': 'नकली क्यूआर', 'LOAN_APP': 'लोन ऐप धोखा',
    'INVESTMENT': 'निवेश धोखा', 'JOB': 'नौकरी का झाँसा', 'MISTAKEN_TRANSFER': 'गलती से भेजे पैसे',
    'OTHER': 'अन्य धोखाधड़ी',
  },
  en: {
    'OTP': 'OTP theft', 'KYC': 'KYC fraud', 'DIGITAL_ARREST': 'Digital arrest',
    'COURIER_CUSTOMS': 'Courier / customs', 'FAKE_QR': 'Fake QR', 'LOAN_APP': 'Loan app',
    'INVESTMENT': 'Investment fraud', 'JOB': 'Job scam', 'MISTAKEN_TRANSFER': 'Mistaken transfer',
    'OTHER': 'Other scam',
  },
);

/// Scam-type chip text in the app language; null for an unknown or absent type.
String? scamTypeIn(Verdict v, String lang) {
  final k = v.scamType?.toUpperCase();
  return k == null || !_scamTypes.hi.containsKey(k) ? null : _scamTypes(lang, k);
}
