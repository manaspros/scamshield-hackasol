package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.ContextRules
import com.hackasol.scamshield.core.graph.FlagKind

/** App language codes as stored under pref `lang_v1`. Anything else (including unset) is Hindi. */
fun normalizeLang(s: String?): String = when (val t = s?.trim()?.lowercase()) {
    "en", "hi", "hne" -> t
    else -> "hi"
}

/**
 * Native-side strings for alerts and the overlay (pure, no Android types). en is English only; hne reuses Hindi
 * where no Chhattisgarhi text is provided. The caller's own words (triggers, quote) are never translated here.
 */
object L10n {
    private fun pick(lang: String, en: String, hi: String, hne: String = hi): String = when (normalizeLang(lang)) {
        "en" -> en
        "hne" -> hne
        else -> hi
    }

    fun notifTitle(label: Label, lang: String): String? = when (label) {
        Label.SCAM -> pick(lang, "Scam warning", "स्कैम की चेतावनी (SCAM)")
        Label.SUSPICIOUS -> pick(lang, "Suspicious", "संदिग्ध (SUSPICIOUS)")
        Label.SAFE -> null
    }

    fun advice(label: Label, lang: String): String =
        if (label == Label.SCAM) pick(lang, "Do not share OTP/PIN/money", "OTP/PIN/पैसे न दें")
        else pick(lang, "Do not share personal information", "निजी जानकारी न दें")

    fun reportAction(lang: String): String = pick(lang, "Report", "रिपोर्ट करें (Report)")

    fun scamType(t: ScamType?, lang: String): String? = when (t) {
        ScamType.OTP -> pick(lang, "OTP scam", "OTP ठगी")
        ScamType.KYC -> pick(lang, "KYC scam", "KYC ठगी")
        ScamType.DIGITAL_ARREST -> pick(lang, "Digital arrest", "डिजिटल अरेस्ट")
        ScamType.COURIER_CUSTOMS -> pick(lang, "Courier/customs scam", "कूरियर/कस्टम्स ठगी")
        ScamType.FAKE_QR -> pick(lang, "Fake QR", "नकली QR")
        ScamType.LOAN_APP -> pick(lang, "Loan app scam", "लोन ऐप ठगी")
        ScamType.INVESTMENT -> pick(lang, "Investment scam", "निवेश ठगी")
        ScamType.JOB -> pick(lang, "Job scam", "नौकरी ठगी")
        ScamType.MISTAKEN_TRANSFER -> pick(lang, "Mistaken transfer scam", "गलत ट्रांसफर ठगी")
        ScamType.ELECTRICITY_BILL -> pick(lang, "Electricity bill scam", "बिजली बिल ठगी")
        ScamType.SIM_SWAP -> pick(lang, "SIM block scam", "सिम ब्लॉक ठगी")
        ScamType.CUSTOMER_CARE -> pick(lang, "Fake customer care", "नकली कस्टमर केयर")
        ScamType.UPI_COLLECT -> pick(lang, "UPI collect scam", "UPI कलेक्ट ठगी")
        ScamType.SEXTORTION -> pick(lang, "Sextortion", "वीडियो ब्लैकमेल")
        ScamType.LOTTERY -> pick(lang, "Lottery scam", "लॉटरी ठगी")
        ScamType.FAMILY_EMERGENCY -> pick(lang, "Family emergency scam", "परिवार इमरजेंसी ठगी")
        ScamType.PHISHING_LINK -> pick(lang, "Phishing link", "फ़र्ज़ी लिंक")
        ScamType.OTHER, null -> null
    }

    // ---- rule reasons (keyed by RuleScorer rule tag) ----

    private val RULE_EN = mapOf(
        "otp_share" to "Asks you to share an OTP/code",
        "otp" to "Mentions OTP",
        "pin" to "Asks for PIN/CVV",
        "digital_arrest" to "'Digital arrest' is always a scam",
        "authority" to "Claims to be police/CBI/customs",
        "arrest" to "Threatens arrest or legal case",
        "parcel" to "Parcel/courier story",
        "contraband" to "Claims illegal items in your name",
        "secrecy" to "Tells you to keep it secret",
        "stay_on_call" to "Tells you not to disconnect",
        "money_transfer" to "Asks you to move money",
        "remote_app" to "Asks for screen-sharing app",
        "kyc" to "KYC claim",
        "account_block" to "Threatens account/SIM block",
        "prize" to "Prize/lottery claim",
        "prize_fee" to "Asks a fee to release a prize",
        "bank_claim" to "Claims to call from a bank",
        "app_install" to "Asks to install app/click link",
        "loan" to "Unsolicited loan offer",
        "video_stay" to "Tells you to stay on video",
        "urgency" to "Creates urgency",
        "elec_cut" to "Threatens electricity disconnection",
        "sim_kyc" to "Threatens SIM block or telecom KYC",
        "care_refund" to "Refund via customer-care number or app",
        "upi_collect" to "Asks for PIN to receive money",
        "qr_receive" to "Asks you to scan a QR to receive money",
        "job_task" to "Task or part-time job earning claim",
        "invest_scam" to "Guaranteed-return investment pitch",
        "join_group" to "Asks you to join a group",
        "sextortion" to "Threatens to share a private video",
        "blackmail_pay" to "Demands money or it shares your content",
        "loan_threat" to "Loan recovery threat to your contacts",
        "loan_fee" to "Asks a fee before a loan",
        "courier_hold" to "Claims your parcel is held with illegal items",
        "lottery_claim" to "Lottery or KBC winner claim",
        "family_emerg" to "Relative-in-emergency money request",
        "new_number" to "Says it is a new number or lost phone",
        "fee_ask" to "Asks a registration or processing fee",
        "call_ask" to "Asks you to call a number",
        "url_short" to "Shortened link hides the real site",
        "url_ip" to "Link goes to a raw IP address",
        "url_punycode" to "Link uses look-alike characters",
        "url_tld" to "Link on a risky domain ending",
        "url_lookalike" to "Link looks like a bank or service site",
    )

    private val RULE_HI = mapOf(
        "otp_share" to "OTP/कोड बताने को कहता है",
        "otp" to "OTP का ज़िक्र",
        "pin" to "PIN/CVV माँगता है",
        "digital_arrest" to "'डिजिटल अरेस्ट' हमेशा ठगी होती है",
        "authority" to "पुलिस/CBI/कस्टम्स होने का दावा",
        "arrest" to "गिरफ्तारी या कानूनी केस की धमकी",
        "parcel" to "पार्सल/कूरियर की कहानी",
        "contraband" to "आपके नाम पर गैरकानूनी सामान का दावा",
        "secrecy" to "बात छुपाने को कहता है",
        "stay_on_call" to "कॉल न काटने को कहता है",
        "money_transfer" to "पैसे भेजने को कहता है",
        "remote_app" to "स्क्रीन-शेयरिंग ऐप माँगता है",
        "kyc" to "KYC का दावा",
        "account_block" to "खाता/सिम बंद करने की धमकी",
        "prize" to "इनाम/लॉटरी का दावा",
        "prize_fee" to "इनाम पाने के लिए फीस माँगता है",
        "bank_claim" to "बैंक से कॉल होने का दावा",
        "app_install" to "ऐप इंस्टॉल/लिंक पर क्लिक करने को कहता है",
        "loan" to "बिना माँगे लोन का ऑफर",
        "video_stay" to "वीडियो कॉल पर बने रहने को कहता है",
        "urgency" to "जल्दबाज़ी करवाता है",
        "elec_cut" to "बिजली कटने की धमकी",
        "sim_kyc" to "सिम बंद या टेलीकॉम KYC की धमकी",
        "care_refund" to "कस्टमर केयर नंबर या ऐप से रिफंड का दावा",
        "upi_collect" to "पैसे पाने के लिए PIN माँगता है",
        "qr_receive" to "पैसे पाने के लिए QR स्कैन करने को कहता है",
        "job_task" to "टास्क या पार्ट-टाइम जॉब से कमाई का दावा",
        "invest_scam" to "पक्के मुनाफे वाला निवेश ऑफर",
        "join_group" to "ग्रुप में जुड़ने को कहता है",
        "sextortion" to "निजी वीडियो फैलाने की धमकी",
        "blackmail_pay" to "पैसे न देने पर सामग्री फैलाने की धमकी",
        "loan_threat" to "आपके कॉन्टैक्ट्स को लोन वसूली की धमकी",
        "loan_fee" to "लोन से पहले फीस माँगता है",
        "courier_hold" to "पार्सल में गैरकानूनी सामान का दावा",
        "lottery_claim" to "लॉटरी या KBC जीतने का दावा",
        "family_emerg" to "रिश्तेदार की इमरजेंसी बताकर पैसे माँगता है",
        "new_number" to "नया नंबर या फोन खराब होने का दावा",
        "fee_ask" to "रजिस्ट्रेशन या प्रोसेसिंग फीस माँगता है",
        "call_ask" to "किसी नंबर पर कॉल करने को कहता है",
        "url_short" to "छोटा लिंक असली साइट छुपाता है",
        "url_ip" to "लिंक सीधे IP पते पर जाता है",
        "url_punycode" to "लिंक में नकली जैसे दिखने वाले अक्षर हैं",
        "url_tld" to "लिंक जोखिम भरे डोमेन पर है",
        "url_lookalike" to "लिंक बैंक या सर्विस साइट जैसा दिखता है",
    )

    val ruleIds: Set<String> get() = RULE_EN.keys

    /** Unknown rule ids fall back to the id itself, as RuleScorer always did. */
    fun ruleReason(id: String, lang: String): String =
        (if (normalizeLang(lang) == "en") RULE_EN[id] else RULE_HI[id]) ?: id

    fun noPhrases(lang: String): String = pick(lang, "No scam phrases found", "कोई स्कैम वाक्य नहीं मिला")

    // ---- context flag texts ----

    private val LINK_HOST = Regex("^Link goes to (.*), not a \\.bank\\.in or \\.gov\\.in site\\.$")
    private val LOOKALIKE = Regex("^Link goes to (.*), which imitates (.*) but is not its official site\\.$")
    private val NO_BILL_BRAND = Regex("^No bill or order from (.*) on record, but this message claims one\\.$")

    /**
     * [flag].reason is the English text produced by the rules (it may carry a brand, a host or a cold-start note).
     * en returns it untouched; hi/hne return a Hindi sentence for the kind, keeping the brand/host when present.
     */
    fun flagReason(flag: ContextFlag, lang: String): String {
        if (normalizeLang(lang) == "en") return flag.reason
        val r = flag.reason
        return when (flag.kind) {
            FlagKind.NO_MATCHING_EVENT -> NO_BILL_BRAND.find(r)?.let {
                "${it.groupValues[1]} का कोई बिल या ऑर्डर रिकॉर्ड में नहीं है, लेकिन यह संदेश उसका दावा करता है।"
            } ?: "रिकॉर्ड नहीं मिला, इसलिए इस बिल, ऑर्डर या भुगतान की पुष्टि नहीं हो सकती।"
            FlagKind.NON_DLT_SENDER -> "यह संदेश सामान्य नंबर से आया है, पंजीकृत सेंडर हेडर से नहीं।"
            FlagKind.LINK_NOT_ALLOWLISTED -> LINK_HOST.find(r)?.let {
                "लिंक ${it.groupValues[1]} पर जाता है, किसी .bank.in या .gov.in साइट पर नहीं।"
            } ?: r
            FlagKind.FAKE_CREDIT ->
                if (r == ContextRules.SPOOFED_CREDIT_RETURN_TEXT)
                    "पहले आया \"पैसे जमा हुए\" SMS आम मोबाइल नंबर से था, आपके बैंक से नहीं। कोई पैसा नहीं आया। कुछ भी वापस न भेजें।"
                else if (r == ContextRules.MISTAKEN_A_COLD_TEXT)
                    "ScamShield इंस्टॉल होने के बाद कोई क्रेडिट अलर्ट दर्ज नहीं है। कुछ भी लौटाने से पहले अपना बैंक ऐप देखें।"
                else if (r.startsWith(ContextRules.MISTAKEN_A_AMOUNT_TEXT))
                    "क्रेडिट आया, लेकिन ₹${r.removePrefix(ContextRules.MISTAKEN_A_AMOUNT_TEXT).substringBefore('.')} का नहीं। यह SMS आपके बैंक से नहीं है।"
                else "कोई पैसा नहीं आया। यह SMS आपके बैंक से नहीं है।"
            FlagKind.RETURN_VIA_BANK_ONLY ->
                "यह पैसा चोरी का हो सकता है। खुद लौटाने पर आपका खाता फ्रीज़ हो सकता है। उनसे अपने बैंक के ज़रिए रिवर्सल माँगने को कहें; अपने बैंक / 1930 से संपर्क करें।"
            FlagKind.NON_1600_BANK_CALL -> "बैंक 1600 वाले नंबरों से कॉल करते हैं। यह कॉल सामान्य मोबाइल नंबर से है।"
            FlagKind.UNVERIFIED_DELIVERY -> "इस कूरियर का कोई 'डिलीवरी के लिए निकला' संदेश रिकॉर्ड में नहीं है, लेकिन कॉल डिलीवरी के बारे में है।"
            FlagKind.LOOKALIKE_LINK -> LOOKALIKE.find(r)?.let {
                "लिंक ${it.groupValues[1]} पर जाता है, जो ${it.groupValues[2]} जैसा दिखता है पर उसकी असली साइट नहीं है।"
            } ?: "लिंक किसी जानी-मानी कंपनी जैसा दिखता है पर उसकी असली साइट नहीं है।"
            FlagKind.NEW_UPI_PAY -> "यह ऐसे UPI आईडी पर पैसे भेजने को कहता है जो इस फ़ोन पर पहले कभी नहीं दिखी।"
            FlagKind.DEBIT_SCARE ->
                if (r == ContextRules.DEBIT_SCARE_COLD_TEXT) "ScamShield इंस्टॉल होने के बाद का कोई रिकॉर्ड नहीं है, इसलिए इस डेबिट की पुष्टि नहीं हो सकती।"
                else "आपके बैंक का कोई डेबिट अलर्ट दर्ज नहीं है। इस संदेश के नंबरों पर कॉल न करें; अपना बैंक ऐप देखें।"
            FlagKind.REPORTED_ENTITY -> "आपने इस सेंडर, नंबर या UPI आईडी को पहले ठगी बताया था।"
            FlagKind.SPOOFED_BANK_SMS ->
                "यह बैंक अलर्ट जैसा दिखता है, लेकिन आम मोबाइल नंबर से आया है। बैंक अलर्ट सिर्फ़ पंजीकृत सेंडर आईडी (जैसे AX-HDFCBK) से भेजते हैं। अपना बैंक ऐप देखें; यह पैसा असली नहीं हो सकता।"
        }
    }

    // ---- overlay ----

    /** Verdict title with the confidence (Demo/debug only; the in-call chip and card never show a percentage). hi/hne are Devanagari. */
    fun overlayTitle(label: Label, pct: Int, lang: String): String =
        pick(lang, "This statement is ${label.name} · $pct%", "यह बात ${labelWord(label, lang)} · $pct%")

    // ---- R3 alert surfaces: chip, card, spoken line, notification channels ----

    /** The one-word verdict shown next to the icon (colour is never the only cue). */
    fun labelWord(label: Label, lang: String): String = when (label) {
        Label.SCAM -> pick(lang, "Scam", "ठगी")
        Label.SUSPICIOUS -> pick(lang, "Careful", "सावधान")
        Label.SAFE -> pick(lang, "Safe", "सुरक्षित")
    }

    fun labelIcon(label: Label): String = when (label) { Label.SCAM -> "⛔"; Label.SUSPICIOUS -> "⚠"; Label.SAFE -> "✓" }

    /** Chip text: icon + word. */
    fun chipText(label: Label, lang: String): String = "${labelIcon(label)} ${labelWord(label, lang)}"

    fun chipDescription(label: Label, lang: String): String = when (label) {
        Label.SCAM -> pick(lang, "ScamShield warning: scam. Tap for details.", "ScamShield चेतावनी: ठगी। जानकारी के लिए छुएँ।")
        else -> pick(lang, "ScamShield warning: be careful. Tap for details.", "ScamShield चेतावनी: सावधान। जानकारी के लिए छुएँ।")
    }

    /** Card headline for a caption verdict (signals use [signalTitle]). */
    fun cardTitle(label: Label, lang: String): String = when (label) {
        Label.SCAM -> pick(lang, "This may be a scam", "ठगी हो सकती है")
        Label.SUSPICIOUS -> pick(lang, "Be careful", "सावधान रहें")
        Label.SAFE -> pick(lang, "Normal conversation", "सामान्य बातचीत")
    }

    /** The one plain line of why/what to do on a caption card. No engine, no percentage, no quote. */
    fun cardWhy(label: Label, lang: String): String =
        if (label == Label.SCAM) pick(lang, "Do not share OTP, PIN or money.", "OTP, PIN या पैसे न दें।")
        else pick(lang, "Do not share personal information.", "निजी जानकारी न दें।")

    /** The ONE line read aloud for an in-call SCAM card: the signal's advice, or the generic scam line. */
    fun ttsLine(signalKind: String?, lang: String): String =
        if (signalKind != null) signalAdvice(signalKind, lang)
        else pick(lang, "Warning. This may be a scam. Do not share OTP or money.", "सावधान। यह ठगी हो सकती है। OTP या पैसे न दें।")

    /** BCP-47 tag for the platform TextToSpeech; hne has no voice, so it speaks Hindi. */
    fun ttsLanguageTag(lang: String): String = if (normalizeLang(lang) == "en") "en-IN" else "hi-IN"

    fun detailsAction(lang: String): String = pick(lang, "Details", "विवरण देखें")

    fun channelName(headsUp: Boolean, lang: String): String =
        if (headsUp) pick(lang, "Scam alerts", "स्कैम अलर्ट")
        else pick(lang, "Suspicious messages (silent)", "संदिग्ध संदेश (बिना आवाज़)")

    /** Secondary line under the title: Hindi in hi/hne, English advice in en. */
    fun overlayLine(label: Label, lang: String): String = when (label) {
        Label.SCAM -> pick(lang, "This may be a scam — do not share OTP / PIN / money", "यह धोखाधड़ी हो सकती है — OTP / PIN / पैसे न दें")
        Label.SUSPICIOUS -> pick(lang, "Be careful — do not share any personal information", "सावधान रहें — कोई निजी जानकारी न दें")
        Label.SAFE -> pick(lang, "Normal conversation", "सामान्य बातचीत")
    }

    fun why(lang: String) = pick(lang, "Why: ", "क्यों: ")
    fun heard(lang: String) = pick(lang, "Heard: ", "सुना: ")
    fun engine(lang: String) = pick(lang, "Engine: ", "इंजन: ")
    fun overallCall(label: Label, riskPct: Int, lang: String) =
        pick(lang, "Overall call: ${label.name} risk $riskPct%", "कुल कॉल: ${label.name} जोखिम $riskPct%")
    fun call1930(lang: String) = pick(lang, "Call 1930", "1930 पर कॉल करें")
    fun dismiss(lang: String) = pick(lang, "Dismiss", "बंद करें")

    // Payment-moment guard (hne first draft: [VERIFY] with a native speaker).
    fun payGuardTitle(lang: String) = pick(lang, "Stop.", "रुकिए।", "रुकव।")
    fun payGuardText(lang: String) = pick(lang,
        "Receiving money never needs your PIN. Ask family first",
        "पैसे लेने के लिए PIN कभी नहीं लगता। पहले परिवार से पूछें",
        "पइसा लेबर बर PIN कभु नइ लगय। पहिली परिवार ले पूछव")
    fun callFamily(lang: String) = pick(lang, "Call family", "परिवार को फ़ोन करें", "परिवार ला फ़ोन करव")
    fun payGuardChannel(lang: String) = pick(lang, "Payment safety", "भुगतान सुरक्षा", "भुगतान सुरक्षा")

    // ---- live in-call signals (overlay bubble); kinds are InCallSignals.KIND_* ----

    /** Bubble headline for a signal kind. */
    fun signalTitle(kind: String, lang: String): String = when (kind) {
        InCallSignals.KIND_REMOTE_APP -> pick(lang, "Remote-access app opened during a call", "कॉल के दौरान रिमोट-एक्सेस ऐप खुला")
        InCallSignals.KIND_SCREEN_SHARE -> pick(lang, "Screen sharing during a call", "कॉल के दौरान स्क्रीन शेयरिंग")
        InCallSignals.KIND_OTP -> pick(lang, "OTP arrived during a call", "कॉल के दौरान OTP आया")
        InCallSignals.KIND_APP_INSTALLED -> pick(lang, "App installed during a call", "कॉल के दौरान ऐप इंस्टॉल हुआ")
        InCallSignals.KIND_PAYMENT_APP -> pick(lang, "Payment app opened during a call", "कॉल के दौरान पेमेंट ऐप खुला")
        else -> pick(lang, "Warning sign during a call", "कॉल के दौरान चेतावनी का संकेत")
    }

    /** What happened. [trigger] is the app name (never an OTP value: that line is the same for every OTP). */
    fun signalLine(kind: String, trigger: String, lang: String): String = when (kind) {
        InCallSignals.KIND_REMOTE_APP -> pick(lang, "$trigger is open", "$trigger खुला है")
        InCallSignals.KIND_SCREEN_SHARE -> pick(lang, "Your screen is being shared or recorded", "आपकी स्क्रीन शेयर या रिकॉर्ड हो रही है")
        InCallSignals.KIND_OTP -> pick(lang, "An OTP message just arrived", "अभी एक OTP संदेश आया")
        InCallSignals.KIND_APP_INSTALLED -> pick(lang, "$trigger was just installed", "$trigger अभी इंस्टॉल हुआ")
        InCallSignals.KIND_PAYMENT_APP -> pick(lang, "$trigger is open", "$trigger खुला है")
        else -> pick(lang, "Something unusual happened", "कुछ असामान्य हुआ")
    }

    /** What to do now. */
    fun signalAdvice(kind: String, lang: String): String = when (kind) {
        InCallSignals.KIND_REMOTE_APP, InCallSignals.KIND_SCREEN_SHARE ->
            pick(lang, "Hang up. Never let a caller see or control your screen.", "कॉल काट दें। किसी को अपनी स्क्रीन देखने या चलाने न दें।")
        InCallSignals.KIND_OTP ->
            pick(lang, "Do not read it out to anyone. No bank asks for an OTP on a call.", "इसे किसी को न बताएँ। कोई बैंक कॉल पर OTP नहीं माँगता।")
        InCallSignals.KIND_APP_INSTALLED ->
            pick(lang, "Hang up and uninstall it. Callers trick people into installing spy apps.", "कॉल काट दें और इसे हटा दें। ठग स्पाई ऐप इंस्टॉल करवाते हैं।")
        InCallSignals.KIND_PAYMENT_APP ->
            pick(lang, "Do not pay or 'verify' because a caller says so.", "कॉल करने वाले के कहने पर पैसे न भेजें, 'वेरिफाई' न करें।")
        else -> pick(lang, "Be careful and hang up if unsure.", "सावधान रहें, शक हो तो कॉल काट दें।")
    }

    fun captionTitle(lang: String) = pick(lang, "🛡️ Turn on Live Caption for protection", "🛡️ Turn on Live Caption for protection")
    fun captionLine(lang: String) =
        pick(lang, "ScamShield reads call captions to warn you about scams", "कॉल सुरक्षा के लिए Live Caption चालू करें")
    fun captionHint(lang: String) =
        pick(lang, "Tap below, then press the captions button in the volume panel.", "Tap below, then press the captions button in the volume panel.")
    fun openVolumePanel(lang: String) = pick(lang, "Open volume panel", "Open volume panel")
}
