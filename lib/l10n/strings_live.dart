import 'app_language.dart';

/// Live tab (live_feed_screen.dart). In hi/hne a '*_sub' key is the small English second line; en has none.
/// Placeholders {0}, {1} are filled by [liveT].
const liveStrings = Tri(
  hi: {
    'advice_title': 'घबराएँ नहीं। अभी यह करें:',
    'pay1': 'पैसे न भेजें, कॉल काट दें', 'pay2': 'OTP या PIN किसी को न बताएँ',
    'sus1': 'जल्दबाज़ी न करें, कॉल काट दें', 'sus2': 'पहले अपने परिवार से पूछें',
    'call_on': 'कॉल शुरू हुई', 'call_on_sub': 'Call started',
    'call_off': 'कॉल खत्म हुई', 'call_off_sub': 'Call ended',
    'signal': 'कॉल के दौरान संकेत: {0}', 'signal_sub': 'In-call signal: {1} ({0})',
    'mic_has': 'माइक जाँच ({0}): आवाज़ मिली',
    'mic_silent': 'माइक जाँच ({0}): आवाज़ नहीं मिली',
    'mic_bad': 'माइक जाँच ({0}): माइक में दिक्कत',
    'mic_done': 'माइक जाँच पूरी हुई। हर रिकॉर्डिंग सुनें: क्या कॉल करने वाले की आवाज़ आती है?',
    'mic_done_sub': 'Mic test finished. Play each recording: can you hear the CALLER?',
    'svc_on': 'सुरक्षा सेवा जुड़ गई', 'svc_on_sub': 'Protection service connected',
    'svc_off': 'सुरक्षा सेवा बंद हो गई', 'svc_off_sub': 'Protection service stopped',
    'play': 'सुनें',
    'feed_stopped': 'लाइव फ़ीड रुक गया', 'feed_stopped_sub': 'नीचे दबाकर फिर जोड़ें',
    'retry': 'फिर कोशिश करें',
    'no_calls': 'अभी कोई कॉल नहीं जाँची गई', 'no_calls_sub': 'कॉल आने पर यहाँ चेतावनी दिखेगी',
    'enable_caption': 'लाइव कैप्शन चालू करें',
    'previous': 'पिछली जाँच',
    'in_call': 'कॉल चल रही है', 'no_call': 'अभी कोई कॉल नहीं',
    'prot_on': 'सुरक्षा चालू है', 'prot_off': 'सुरक्षा बंद है — सेटअप में चालू करें',
    'caption_wait': 'Live Caption का टेक्स्ट आने की प्रतीक्षा…',
    'otp': 'कॉल के दौरान OTP आया। किसी को न बताएँ।',
    'otp_sub': 'An OTP arrived during the call. Do not share it.',
    'helpline': '1930 पर कॉल करें', 'helpline_cap': 'साइबर ठगी की मुफ़्त हेल्पलाइन',
  },
  hne: {
    'advice_title': 'घबरावव झन। अभी ए करव:',
    'pay1': 'पइसा झन भेजव, काल काट देव', 'pay2': 'OTP या PIN कखरो ला झन बतावव',
    'sus1': 'हड़बड़ी झन करव, काल काट देव', 'sus2': 'पहिली अपन परिवार ले पूछव',
    'call_on': 'काल सुरू होइस', 'call_off': 'काल खतम होइस',
    'no_calls': 'अभी कोनो काल नइ जाँचे गे हे', 'no_calls_sub': 'काल आही त इहाँ चेतावनी दिखही',
    'retry': 'फेर कोसिस करव',
    'previous': 'पिछू के जाँच',
    'in_call': 'काल चलत हे', 'no_call': 'अभी कोनो काल नइ ए',
    'prot_on': 'सुरक्षा चालू हे',
    'helpline': '1930 मा काल करव',
  },
  en: {
    'advice_title': 'Stay calm. Do this now:',
    'pay1': 'Do not send money, hang up', 'pay2': 'Never share your OTP or PIN',
    'sus1': 'Do not rush, hang up', 'sus2': 'Ask your family first',
    'call_on': 'Call started', 'call_off': 'Call ended',
    'signal': 'In-call signal: {1} ({0})',
    'mic_has': 'Mic test ({0}): audio detected',
    'mic_silent': 'Mic test ({0}): no audio detected',
    'mic_bad': 'Mic test ({0}): microphone problem',
    'mic_done': 'Mic test finished. Play each recording: can you hear the CALLER?',
    'svc_on': 'Protection service connected', 'svc_off': 'Protection service stopped',
    'play': 'Play',
    'feed_stopped': 'Live feed stopped', 'feed_stopped_sub': 'Tap below to reconnect',
    'retry': 'Try again',
    'no_calls': 'No call checked yet', 'no_calls_sub': 'A warning will appear here when a call comes in',
    'enable_caption': 'Turn on Live Caption',
    'previous': 'Earlier checks',
    'in_call': 'Call in progress', 'no_call': 'No call right now',
    'prot_on': 'Protection is on', 'prot_off': 'Protection is off. Turn it on in Setup',
    'caption_wait': 'Waiting for Live Caption text…',
    'otp': 'An OTP arrived during the call. Do not share it with anyone.',
    'helpline': 'Call 1930', 'helpline_cap': 'Free cyber-fraud helpline',
  },
);

String liveT(String lang, String key, [List<String> args = const []]) {
  var s = liveStrings(lang, key);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', args[i]);
  }
  return s;
}
