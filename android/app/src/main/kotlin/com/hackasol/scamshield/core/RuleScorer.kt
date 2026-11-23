package com.hackasol.scamshield.core

/**
 * Deterministic scam-phrase scorer (English, Hindi/Devanagari, Hinglish).
 * Instant, explainable, and the fallback when the LLM is unavailable.
 * Score = noisy-OR of matched rule weights: 1 - Π(1 - w).
 */
object RuleScorer {

    private class Rule(val tag: String, val weight: Double, pattern: String) {
        // Case-insensitive + Unicode-aware word boundaries on both Android and the JVM (see UnicodeRegex).
        val regex = UnicodeRegex.of(pattern)
    }

    private val SHARE = "(batao|bataiye|bataye|bata do|bata dijiye|share|bhejo|bhej do|tell|send|read out|bol do|बताइए|बताओ|बता दो|बता दीजिए|भेजो|भेज दो)"

    private val rules = listOf(
        Rule("otp_share", 0.90, "(otp|ओटीपी|o\\.t\\.p|verification code|code|कोड)\\W+(?:\\w+\\W+){0,5}$SHARE|\\b(?:share|tell|read out)\\W+(?:\\w+\\W+){0,3}(?:otp|ओटीपी|verification code)"),
        Rule("otp", 0.50, "\\botp\\b|ओटीपी|one[- ]time password"),
        Rule("pin", 0.75, "upi pin|atm pin|mpin|cvv|पिन (नंबर|बताओ|बताइए)|pin (batao|bataiye|daalo|dalo|enter)"),
        Rule("digital_arrest", 0.92, "digital arrest|डिजिटल अरेस्ट|डिजिटल गिरफ्तारी"),
        Rule("authority", 0.45, "\\b(cbi|ncb|crime branch|cyber cell|customs|narcotics|income tax department|trai)\\b|सीबीआई|कस्टम|क्राइम ब्रांच|पुलिस स्टेशन"),
        Rule("arrest", 0.55, "\\barrest\\b|warrant|गिरफ्तार|वारंट|\\bfir\\b|case (darj|register)|money laundering|मनी लॉन्ड्रिंग"),
        Rule("parcel", 0.30, "\\bparcel\\b|\\bcourier\\b|fedex|पार्सल|कूरियर"),
        Rule("contraband", 0.55, "\\bdrugs\\b|ड्रग्स|illegal (items|passport)|fake passport"),
        Rule("secrecy", 0.75, "kisi ko (mat|na|nahi) (batana|bataye|bataiye|batayein)|don'?t tell anyone|do not tell anyone|किसी को (मत|न|नहीं) बता"),
        Rule("stay_on_call", 0.70, "(call|phone) (mat|na) (kaato|kaatna|katna|cut karna|cut)|don'?t (disconnect|hang up|cut the call)|फ़?फोन मत काट|कॉल मत काट"),
        Rule("money_transfer", 0.70, "safe account|secure account|rbi account|verification (amount|fee|charge)|(paise|amount|money) (transfer|bhej)|transfer (karo|kar do|kijiye|karein)|पैसे (भेज|ट्रांसफर)|refundable"),
        Rule("remote_app", 0.85, "anydesk|any desk|teamviewer|team viewer|quick ?support|rustdesk|screen ?share|स्क्रीन शेयर"),
        Rule("kyc", 0.40, "\\bkyc\\b|केवाईसी"),
        Rule("account_block", 0.55, "(account|khata|card|sim) (block|band|suspend|freeze|deactivate)|खाता (बंद|ब्लॉक)|सिम (बंद|ब्लॉक)"),
        Rule("prize", 0.50, "lottery|lucky draw|\\bprize\\b|you have won|aapne jeeta|इनाम|लॉटरी|\\bkbc\\b"),
        Rule("bank_claim", 0.30, "(bank|sbi|hdfc|icici|axis|rbi|paytm|phonepe) (se|from) (bol|baat|speaking|calling)|बैंक से बोल"),
        Rule("app_install", 0.55, "\\.apk\\b|app (download|install) (karo|kijiye|karein)|link (par|pe) click|लिंक पर क्लिक"),
        Rule("loan", 0.40, "instant loan|pre-?approved loan|processing fee|लोन (मंजूर|अप्रूव)"),
        Rule("video_stay", 0.60, "video call (pe|par) (raho|rahiye|rahna)|camera (on|chalu) (rakho|rakhiye)"),
        Rule("urgency", 0.20, "\\b(turant|abhi ke abhi|immediately|urgent|right now)\\b|within \\d+ (minutes|hours)|तुरंत|अभी के अभी"),
    )

    private val reasons = mapOf(
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
        "bank_claim" to "Claims to call from a bank",
        "app_install" to "Asks to install app/click link",
        "loan" to "Unsolicited loan offer",
        "video_stay" to "Tells you to stay on video",
        "urgency" to "Creates urgency",
    )

    const val SCAM_AT = 0.75
    const val SUSPICIOUS_AT = 0.40

    /** "do not share / never share / साझा न करें": a warning, not a request. Removed before the OTP rules run. */
    private val NO_SHARE = UnicodeRegex.of("(?:do not|don'?t|never|not to)\\s+(?:share|disclose)|\\bshare\\s+(?:na|nahi|mat)\\s+kar\\w*|\\b(?:na|nahi|mat)\\s+bata\\w*|(?:साझा|शेयर)\\s+(?:न|ना|नहीं|मत)\\s+कर\\S*")

    /**
     * Every digit (ASCII and Devanagari) and UPI-like id never leaves the scorer: triggers reach the log and evidence ZIP.
     * All digits, not only 4+ runs, so separator-split values ("482-913", "482 913") cannot leak.
     */
    private val SENSITIVE = Regex("[\\w.\\-]{2,}(?=@[A-Za-z])|\\p{Nd}+")

    private const val MAX_TRIGGER = 40

    private fun mask(s: String) = SENSITIVE.replace(s, "•••")

    /** Mask, then cap at [MAX_TRIGGER] chars (ellipsis included) so a trigger never carries a long span of the message. */
    private fun maskSensitive(s: String): String =
        mask(s).let { if (it.length > MAX_TRIGGER) it.take(MAX_TRIGGER - 1) + "…" else it }

    private fun matches(text: String): List<Pair<Rule, String>> {
        val noShare = NO_SHARE.replace(text, " ")
        val notice = noShare != text
        val matched = mutableListOf<Pair<Rule, String>>()
        for (r in rules) {
            val isOtp = r.tag == "otp_share" || r.tag == "otp"
            // A do-not-share notice with no ask is a genuine OTP delivery: the bare "otp" mention is cancelled too.
            if (r.tag == "otp" && notice && matched.none { it.first.tag == "otp_share" }) continue
            val m = r.regex.find(if (isOtp) noShare else text) ?: continue
            matched += r to maskSensitive(m.value.trim())
        }
        return matched
    }

    fun score(text: String): RuleResult {
        val matched = matches(text)
        var keep = 1.0
        for ((r, _) in matched) keep *= (1 - r.weight)
        val score = 1 - keep
        val label = when {
            score >= SCAM_AT -> Label.SCAM
            score >= SUSPICIOUS_AT -> Label.SUSPICIOUS
            else -> Label.SAFE
        }
        val top = matched.sortedByDescending { it.first.weight }
        val reason = if (top.isEmpty()) "No scam phrases found"
        else top.take(2).joinToString("; ") { reasons[it.first.tag] ?: it.first.tag }
        return RuleResult(score, label, top.map { it.second }.distinct(), reason)
    }

    /**
     * Rule-derived scam type for rules-only mode. Null when the rules label the text SAFE;
     * OTHER when it is SCAM/SUSPICIOUS but no rule tag maps to a specific type.
     * shortcut: re-runs the regexes (score + tags), fine for short statements; cache if it gets hot.
     */
    fun scamType(text: String): ScamType? {
        if (score(text).label == Label.SAFE) return null
        val tags = matches(text).map { it.first.tag }.toSet()
        return typeFromTags(tags)
    }

    private fun typeFromTags(t: Set<String>): ScamType = when {
        "digital_arrest" in t -> ScamType.DIGITAL_ARREST
        "parcel" in t && ("authority" in t || "contraband" in t || "arrest" in t) -> ScamType.COURIER_CUSTOMS
        "arrest" in t || "authority" in t || "contraband" in t -> ScamType.DIGITAL_ARREST
        "otp_share" in t || "otp" in t || "pin" in t -> ScamType.OTP
        "kyc" in t || "account_block" in t || "bank_claim" in t -> ScamType.KYC
        "loan" in t -> ScamType.LOAN_APP
        "parcel" in t -> ScamType.COURIER_CUSTOMS
        else -> ScamType.OTHER
    }

    /** How much the rule evidence supports a given label (0..1). */
    fun support(r: RuleResult, label: Label): Double = when (label) {
        Label.SCAM -> r.score
        Label.SUSPICIOUS -> (1 - kotlin.math.abs(r.score - 0.55) / 0.55).coerceIn(0.0, 1.0)
        Label.SAFE -> 1 - r.score
    }

    /** Confidence when only rules are available. */
    fun confidence(r: RuleResult): Double = when (r.label) {
        Label.SCAM -> r.score
        Label.SUSPICIOUS -> 0.5 + 0.3 * (r.score - SUSPICIOUS_AT) / (SCAM_AT - SUSPICIOUS_AT)
        Label.SAFE -> (1 - r.score).coerceAtLeast(0.6)
    }.coerceIn(0.0, 1.0)
}
