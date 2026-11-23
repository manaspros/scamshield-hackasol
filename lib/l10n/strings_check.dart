import 'app_language.dart';

/// Check tab (try_api_screen.dart). In hi/hne a '*_sub' key is the small English second line; en has none.
/// Placeholders {0}, {1} are filled by [checkT].
const checkStrings = Tri(
  hi: {
    'advice_title': 'घबराएँ नहीं। अभी यह करें:',
    'pay1': 'पैसे न भेजें, कॉल काट दें', 'pay2': 'OTP या PIN किसी को न बताएँ',
    'sus1': 'जल्दबाज़ी न करें, कॉल काट दें', 'sus2': 'पहले अपने परिवार से पूछें',
    'helpline': '1930 पर कॉल करें',
    'helpline_cap': 'साइबर ठगी की मुफ़्त हेल्पलाइन। डायल खुलेगा, हरा बटन आप खुद दबाएँ।',
    'caution': 'पैसे भेजने से पहले जाँचें', 'caution_sub': 'Check before paying',
    'risky': 'यह UPI ID रिफंड, हेल्पडेस्क या इनाम जैसा लगता है।',
    'risky_sub': 'This UPI ID looks like a refund, helpdesk or prize account',
    'mismatch': 'QR में नाम: {0} — आपको बताया गया नाम: {1}',
    'mismatch_imp': 'पैसे भेजने से पहले नाम मिलाएँ', 'mismatch_sub': 'Name does not match this UPI ID',
    'collect': 'यह QR पैसे माँगता है। इसे स्कैन करने से पैसे जाते हैं, आते नहीं।',
    'collect_sub': 'This QR requests money; scanning it sends money, it never receives money.',
    'no_name': 'नाम नहीं मिला', 'payee': 'पैसे पाने वाला', 'sending': 'आप भेज रहे हैं',
    'upi_invalid': 'यह UPI लिंक सही नहीं लगता। upi://pay?pa=... वाला पूरा लिंक डालें।\nNot a valid UPI link.',
    'upi_link_lbl': 'UPI लिंक / QR टेक्स्ट · UPI link / QR text',
    'upi_name_lbl': 'आपको बताया गया नाम (चाहें तो) · Name I was told',
    'check_link': 'लिंक जाँचें · Check link',
    'scan': 'QR स्कैन करें', 'paste_upi': 'UPI लिंक चिपकाएँ',
    'qr_unavail': 'QR स्कैनर उपलब्ध नहीं है। लिंक चिपकाएँ। · QR scanner not available; paste the link instead.',
    'short_safe': 'सुरक्षित', 'short_suspicious': 'सावधान', 'short_scam': 'धोखाधड़ी',
    'empty': 'कोई संदिग्ध मैसेज यहाँ चिपकाएँ, हम बताएँगे कि ठगी तो नहीं',
    'earlier': 'पिछली जाँचें',
    'hint': 'संदेश यहाँ चिपकाएँ', 'input_empty': 'पहले मैसेज डालें',
    'failed': 'जाँच नहीं हो पाई, फिर कोशिश करें', 'failed_sub': "Couldn't check, try again",
    'retry': 'दोबारा जाँचें',
    'busy': 'जाँच हो रही है…', 'run': 'मैसेज जाँचें',
  },
  hne: {
    'advice_title': 'घबरावव झन। अभी ए करव:',
    'pay1': 'पइसा झन भेजव, काल काट देव', 'pay2': 'OTP या PIN कखरो ला झन बतावव',
    'sus1': 'हड़बड़ी झन करव, काल काट देव', 'sus2': 'पहिली अपन परिवार ले पूछव',
    'helpline': '1930 मा काल करव',
    'caution': 'पइसा भेजे के पहिली जाँचव',
    'scan': 'QR स्कैन करव', 'paste_upi': 'UPI लिंक चिपकावव',
    'empty': 'कोनो शक वाला मैसेज इहाँ चिपकावव, हम बताबो कि ठगी तो नइ ए',
    'earlier': 'पिछू के जाँच',
    'hint': 'संदेश इहाँ चिपकावव', 'input_empty': 'पहिली मैसेज डारव',
    'failed': 'जाँच नइ हो पाइस, फेर कोसिस करव', 'retry': 'फेर जाँचव',
    'busy': 'जाँच होवत हे…', 'run': 'मैसेज जाँचव',
  },
  en: {
    'advice_title': 'Stay calm. Do this now:',
    'pay1': 'Do not send money, hang up', 'pay2': 'Never share your OTP or PIN',
    'sus1': 'Do not rush, hang up', 'sus2': 'Ask your family first',
    'helpline': 'Call 1930',
    'helpline_cap': 'Free cyber-fraud helpline. The dialer opens; you press the green button yourself.',
    'caution': 'Check before paying',
    'risky': 'This UPI ID looks like a refund, helpdesk or prize account.',
    'mismatch': 'Name in QR: {0}. Name you were told: {1}',
    'mismatch_imp': 'Match the name before paying',
    'collect': 'This QR asks for money. Scanning it sends money; it never receives money.',
    'no_name': 'Name not found', 'payee': 'Payee', 'sending': 'You are sending',
    'upi_invalid': 'This UPI link does not look right. Paste the full link that starts with upi://pay?pa=...',
    'upi_link_lbl': 'UPI link / QR text',
    'upi_name_lbl': 'Name I was told (optional)',
    'check_link': 'Check link',
    'scan': 'Scan QR', 'paste_upi': 'Paste UPI link',
    'qr_unavail': 'QR scanner not available. Paste the link instead.',
    'short_safe': 'Safe', 'short_suspicious': 'Careful', 'short_scam': 'Scam',
    'empty': 'Paste a suspicious message here and we will tell you if it is a scam',
    'earlier': 'Earlier checks',
    'hint': 'Paste the message here', 'input_empty': 'Enter a message first',
    'failed': 'Could not check. Please try again.',
    'retry': 'Try again',
    'busy': 'Checking…', 'run': 'Check message',
  },
);

String checkT(String lang, String key, [List<String> args = const []]) {
  var s = checkStrings(lang, key);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', args[i]);
  }
  return s;
}
