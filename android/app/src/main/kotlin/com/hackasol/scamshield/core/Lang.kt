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
    )

    val ruleIds: Set<String> get() = RULE_EN.keys

    /** Unknown rule ids fall back to the id itself, as RuleScorer always did. */
    fun ruleReason(id: String, lang: String): String =
        (if (normalizeLang(lang) == "en") RULE_EN[id] else RULE_HI[id]) ?: id

    fun noPhrases(lang: String): String = pick(lang, "No scam phrases found", "कोई स्कैम वाक्य नहीं मिला")

    // ---- context flag texts ----

    private val LINK_HOST = Regex("^Link goes to (.*), not a \\.bank\\.in or \\.gov\\.in site\\.$")
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
                if (r == ContextRules.MISTAKEN_A_COLD_TEXT)
                    "ScamShield इंस्टॉल होने के बाद कोई क्रेडिट अलर्ट दर्ज नहीं है। कुछ भी लौटाने से पहले अपना बैंक ऐप देखें।"
                else "कोई पैसा नहीं आया। यह SMS आपके बैंक से नहीं है।"
            FlagKind.RETURN_VIA_BANK_ONLY ->
                "यह पैसा चोरी का हो सकता है। खुद लौटाने पर आपका खाता फ्रीज़ हो सकता है। उनसे अपने बैंक के ज़रिए रिवर्सल माँगने को कहें; अपने बैंक / 1930 से संपर्क करें।"
            FlagKind.NON_1600_BANK_CALL -> "बैंक 1600 वाले नंबरों से कॉल करते हैं। यह कॉल सामान्य मोबाइल नंबर से है।"
            FlagKind.UNVERIFIED_DELIVERY -> "इस कूरियर का कोई 'डिलीवरी के लिए निकला' संदेश रिकॉर्ड में नहीं है, लेकिन कॉल डिलीवरी के बारे में है।"
        }
    }

    // ---- overlay ----

    /** Collapsed title keeps its English wording in every language (hi/hne look unchanged); only the label name is shown as-is. */
    fun overlayTitle(label: Label, pct: Int, lang: String): String =
        pick(lang, "This statement is ${label.name} · $pct%", "This statement is ${label.name} · $pct%")

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

    fun captionTitle(lang: String) = pick(lang, "🛡️ Turn on Live Caption for protection", "🛡️ Turn on Live Caption for protection")
    fun captionLine(lang: String) =
        pick(lang, "ScamShield reads call captions to warn you about scams", "कॉल सुरक्षा के लिए Live Caption चालू करें")
    fun captionHint(lang: String) =
        pick(lang, "Tap below, then press the captions button in the volume panel.", "Tap below, then press the captions button in the volume panel.")
    fun openVolumePanel(lang: String) = pick(lang, "Open volume panel", "Open volume panel")
}
