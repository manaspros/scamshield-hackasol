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

    // Fee-for-prize: a prize/lottery word and a fee/pay word within ~12 words, either order. No "you won" alone (too chatty).
    private val PRIZE_W = "(?:lottery|lucky draw|\\bprize\\b|you(?:'ve| have) won|aapne jeeta|इनाम|लॉटरी|जीत|\\bkbc\\b|crorepati|jackpot|केबीसी|करोड़पति)"
    private val FEE_W = "(?:\\b(?:fees?|charges?|tax|pay|deposit|jama|gst)\\b|शुल्क|भुगतान|फीस|टैक्स|जमा)"

    // URL heuristics stay generic; brand-vs-link matching lives in the KB layer. Official suffixes are skipped.
    private const val URL_HOST = "(?:https?://|www\\.)(?![^\\s/?#]*\\.(?:gov\\.in|nic\\.in|bank\\.in|sbi)(?:[:/?#\\s]|\\z))[^\\s/?#]*"
    private const val RISKY_TLD = "xyz|top|click|live|buzz|icu|ru|tk|cc|ml|ga|cf|gq|cyou|sbs|cfd|vip|work|rest|monster|loan|win|bid"

    private val rules = listOf(
        Rule("otp_share", 0.90, "(otp|ओटीपी|o\\.t\\.p|verification code|code|कोड)\\W+(?:\\w+\\W+){0,5}$SHARE|\\b(?:share|tell|read out)\\W+(?:\\w+\\W+){0,3}(?:otp|ओटीपी|verification code)"),
        Rule("otp", 0.50, "\\botp\\b|ओटीपी|one[- ]time password"),
        Rule("pin", 0.75, "upi pin|atm pin|mpin|cvv|पिन (नंबर|बताओ|बताइए)|pin (batao|bataiye|daalo|dalo|enter)"),
        Rule("digital_arrest", 0.92, "digital arrest|डिजिटल अरेस्ट|डिजिटल गिरफ्तारी"),
        Rule("authority", 0.45, "\\b(cbi|ncb|crime branch|cyber cell|customs|narcotics|income tax department|trai)\\b|सीबीआई|कस्टम(?!र)|क्राइम ब्रांच|पुलिस स्टेशन|police officer|customs officer|mumbai police|delhi police|पुलिस (?:अधिकारी|वाले)|कस्टम (?:अधिकारी|विभाग)|नारकोटिक्स"),
        Rule("arrest", 0.55, "\\barrest\\b|warrant|गिरफ्तार|वारंट|\\bfir\\b|case (darj|register)|money laundering|मनी लॉन्ड्रिंग"),
        Rule("parcel", 0.30, "\\bparcel\\b|\\bcourier\\b|fedex|पार्सल|कूरियर"),
        Rule("contraband", 0.55, "\\bdrugs\\b|ड्रग्स|narcotics? (?:found|items)|illegal (items|passport)|fake passport|नशीली|मादक"),
        Rule("secrecy", 0.75, "kisi ko (mat|na|nahi) (batana|bataye|bataiye|batayein)|don'?t tell anyone|do not tell anyone|किसी को (मत|न|नहीं) बता"),
        Rule("stay_on_call", 0.70, "(call|phone) (mat|na) (kaato|kaatna|katna|cut karna|cut)|don'?t (disconnect|hang up|cut the call)|फ़?फोन मत काट|कॉल मत काट"),
        Rule("money_transfer", 0.70, "safe account|secure account|rbi account|verification (amount|fee|charge)|(paise|amount|money) (transfer|bhej)|transfer (karo|kar do|kijiye|karein)|पैसे (भेज|ट्रांसफर)|refundable"),
        Rule("remote_app", 0.85, "anydesk|any desk|teamviewer|team viewer|quick ?support|rustdesk|screen ?share|स्क्रीन शेयर"),
        Rule("kyc", 0.40, "\\bkyc\\b|केवाईसी"),
        Rule("account_block", 0.55, "(account|khata|card|sim) (block|band|suspend|freeze|deactivate)|खाता (बंद|ब्लॉक)|सिम (बंद|ब्लॉक)"),
        Rule("prize", 0.50, "lottery|lucky draw|\\bprize\\b|you have won|aapne jeeta|इनाम|लॉटरी|\\bkbc\\b"),
        Rule("prize_fee", 0.80, "$PRIZE_W\\W+(?:\\w+\\W+){0,12}$FEE_W|$FEE_W\\W+(?:\\w+\\W+){0,12}$PRIZE_W"),
        Rule("bank_claim", 0.30, "(bank|sbi|hdfc|icici|axis|rbi|paytm|phonepe) (se|from) (bol|baat|speaking|calling)|बैंक से बोल"),
        Rule("app_install", 0.55, "\\.apk\\b|app (download|install) (karo|kijiye|karein)|link (par|pe) click|लिंक पर क्लिक"),
        // "processing fee" counts as loan evidence only next to loan wording, so a lottery fee is not typed LOAN_APP.
        Rule("loan", 0.40, "instant loan|pre-?approved loan|\\bloan\\b.{0,80}processing fee|processing fee.{0,80}\\bloan\\b|लोन (मंजूर|अप्रूव)"),
        Rule("video_stay", 0.60, "video call (pe|par) (raho|rahiye|rahna)|camera (on|chalu) (rakho|rakhiye)"),
        Rule("elec_cut", 0.65, "(?:bijli|electricity|power|बिजली)\\W.{0,60}?(?:\\bkat\\w*|\\bkaat\\w*|disconnected|cut off|will be cut|काट\\S*|कट\\s|बंद|band (?:ho|kar))"),
        Rule("sim_kyc", 0.60, "\\bsim\\b.{0,50}?(?:block|\\bband\\b|\\bbandh\\b|deactivat|suspend|disconnect|expire|swap|\\bkyc\\b|केवाईसी)|सिम.{0,40}?(?:बंद|बन्द|ब्लॉक|केवाईसी)|mobile number.{0,40}?(?:block|\\bband\\b|deactivat|disconnect)|मोबाइल नंबर.{0,30}?(?:बंद|ब्लॉक)"),
        Rule("care_refund", 0.65, "(?:refund|रिफंड|paise wapas|पैसे वापस).{0,70}?(?:customer care|helpline|toll ?free|support number|download|install|anydesk|teamviewer|डाउनलोड|इंस्टॉल|कस्टमर केयर|हेल्पलाइन)|(?:customer care|helpline|support) (?:number|no\\b).{0,60}?(?:refund|रिफंड)|(?:download|install|डाउनलोड).{0,40}?(?:refund|रिफंड)"),
        Rule("upi_collect", 0.75, "(?:enter|daalo|dalo|dal do|put|डालें|डालो|दर्ज|डाल)\\W.{0,20}?(?:pin|पिन).{0,50}?(?:receive|recieve|credit|refund|milega|milenge|प्राप्त|पाने|मिलेगा|मिलेंगे)|(?:receive|recieve|paane|पाने|मिलेंगे).{0,50}?(?:enter|daal\\w*|put|डाल\\w*).{0,20}?(?:pin|पिन)|(?:receive|recieve|paane|पाने|मिलेंगे).{0,50}?(?:pin|पिन).{0,15}?(?:डाल|दर्ज|daal|dalo|enter)|collect request.{0,60}?(?:approve|accept|pin|enter)|(?:approve|accept).{0,25}?collect request|पिन.{0,30}?(?:पैसे मिल|पाने|रिसीव)"),
        Rule("qr_receive", 0.75, "(?:scan|स्कैन).{0,30}?(?:qr|क्यूआर|क्यू आर).{0,50}?(?:receive|recieve|get|payment|refund|paise|money|पैसे|रिफंड|पाएं|पाने|मिलेंगे)|(?:receive|get|पाने).{0,30}?(?:payment|money|paise|पैसे).{0,30}?(?:scan|qr|स्कैन|क्यूआर)|(?:army|military|crpf|cisf|fauj|soldier|फौजी|सेना).{0,80}?(?:qr|scan|advance|क्यूआर|स्कैन)|(?:olx|quikr).{0,80}?(?:qr|scan|advance|token|क्यूआर|स्कैन)"),
        Rule("job_task", 0.65, "\\btasks?\\b.{0,60}?(?:earn|commission|daily|income|kamao|कमाएं|कमाओ)|(?:like|review|rating|subscribe|rate|लाइक|रिव्यू).{0,40}?(?:earn|income|kamao|kamai|commission|per (?:video|task|review)|कमाएं|कमाओ|कमाई)|(?:part[- ]?time|work from home|wfh|ghar baithe|घर बैठे).{0,60}?(?:earn|income|salary|kamao|kamai|daily|per day|roz|कमाएं|कमाओ|रोज)|(?:earn|kamao|कमाएं|कमाओ)\\W.{0,25}?(?:daily|per day|roz|रोज|प्रतिदिन)|prepaid task|telegram.{0,50}?(?:task|job|earn)|(?:task|job).{0,50}?telegram|टेलीग्राम.{0,40}?(?:टास्क|जॉब|कमा)"),
        Rule("invest_scam", 0.65, "guaranteed (?:returns?|profits?|income)|(?:double|doubl\\w+|dugna|2x|दोगुना|दुगना).{0,25}?(?:money|paise|amount|rupees|पैसे|रुपये)|\\d+\\s?%\\s*(?:daily|weekly|per (?:day|week)|roz)|(?:daily|weekly|roz|रोज)\\W.{0,15}?\\d+\\s?(?:%|percent|प्रतिशत)|\\d+\\s?(?:प्रतिशत|percent).{0,20}?(?:मुनाफा|return|profit)|vip (?:group|tips|signals?|channel)|ipo allot\\w*.{0,50}?(?:group|vip|guarantee|profit|apply)|(?:stock|trading|crypto|forex|bitcoin|share market|शेयर|ट्रेडिंग).{0,60}?(?:whatsapp|telegram|vip|guarantee|\\bgroup\\b|ग्रुप|गारंटी|मुनाफा)|invest\\w*.{0,50}?(?:guarantee|\\bgroup\\b|return per|मुनाफा|ग्रुप)|निवेश.{0,40}?(?:मुनाफा|ग्रुप|गारंटी)|मुनाफा.{0,40}?गारंटी"),
        Rule("join_group", 0.35, "\\bjoin\\b.{0,30}?(?:group|channel|telegram|whatsapp)|(?:group|channel|ग्रुप).{0,20}?(?:join|जुड़)|ग्रुप में (?:जुड़|ऐड)"),
        Rule("sextortion", 0.70, "(?:nude|naked|obscene|nangi|nanga|अश्लील|न्यूड|आपत्तिजनक).{0,40}?(?:video|vedio|photo|pic|clip|वीडियो|फोटो)|(?:video|vedio|photo|pics?|clips?|वीडियो|फोटो).{0,30}?(?:nude|naked|obscene|अश्लील|न्यूड|आपत्तिजनक)|viral\\s?(?:kar|kardunga|kar dunga|kar denge|ho jayega|hoga)|वायरल\\s?(?:कर|हो)|(?:video call|वीडियो कॉल).{0,60}?(?:record|रिकॉर्ड)|record\\w*.{0,30}?video call|(?:video|वीडियो).{0,30}?(?:viral|वायरल).{0,40}?(?:contacts?|friends|family|relatives|sabko|कॉन्टैक्ट|दोस्तों|रिश्तेदारों)"),
        Rule("blackmail_pay", 0.55, "(?:pay|paise|rs\\.?|₹|\\d{3,}|पैसे|रुपये).{0,60}?(?:or else|otherwise|nahi to|nahi toh|warna|वरना|नहीं तो).{0,50}?(?:viral|share|send|post|leak|expose|upload|वायरल|शेयर|भेज)|(?:viral|share|leak|expose|वायरल).{0,40}?(?:unless|if you (?:don'?t|do not)) pay"),
        Rule("loan_threat", 0.75, "(?:loan|लोन|recovery).{0,80}?(?:contacts?|phonebook|gallery|photos?|relatives|family|कॉन्टैक्ट).{0,60}?(?:share|send|message|call|viral|inform|bhej|वायरल|भेज)|(?:morph\\w*|edited).{0,30}?(?:photo|pic).{0,60}?(?:contacts|relatives|friends|family)|(?:repay|payback|wapas|loan|लोन).{0,40}?(?:or|nahi to|warna|वरना).{0,40}?(?:contacts|relatives|viral|police|legal|case)|(?:loan|लोन).{0,60}?(?:overdue|pending|बकाया).{0,60}?(?:legal|police|case|contacts|notice|कानूनी)"),
        Rule("loan_fee", 0.60, "(?:loan|लोन).{0,90}?(?:fee|charges?|insurance|फीस|शुल्क).{0,60}?(?:pay|send|deposit|transfer|bhej|jama|भेज|जमा|पहले)|(?:pay|send|deposit|bhej|jama|भेज|जमा).{0,40}?(?:fee|charges?|फीस).{0,90}?(?:loan|लोन)"),
        Rule("courier_hold", 0.50, "(?:parcel|courier|package|पार्सल|कूरियर).{0,80}?(?:aadhaar|aadhar|आधार|passport|पासपोर्ट|sim cards?|customs|कस्टम(?!र)|mumbai|मुंबई|narcotic|नारकोटिक).{0,60}?(?:seiz|held|stopp|detain|\\brok\\w*|pakd\\w*|found|caught|जब्त|रोक|पकड़|मिल)"),
        Rule("lottery_claim", 0.55, "kaun banega|कौन बनेगा|\\bkbc\\b|केबीसी|lucky (?:draw|winner|customer|number)|jackpot|(?:won|jeeta|jeete|जीता|जीती|जीते).{0,30}?(?:rs\\.?|₹|lakh|crore|लाख|करोड़)|(?:lakh|crore|लाख|करोड़).{0,30}?(?:won|jeeta|prize|lottery|inaam|इनाम|लॉटरी)|winner of"),
        Rule("family_emerg", 0.75, "(?:papa|mummy|mom|dad|bhaiya|bhai|didi|beta|uncle|mama|chacha|पापा|मम्मी|माँ|भैया|दीदी|अंकल|मामा|चाचा).{0,60}?(?:hospital|haspital|accident|police|arrest|emergency|अस्पताल|एक्सीडेंट|पुलिस|इमरजेंसी|गिरफ्तार).{0,80}?(?:paise|money|pay|transfer|bhej\\w*|send|urgent|rupee|rs\\.?|₹|पैसे|रुपये|भेज\\w*)|(?:aapka|your|आपका|आपकी) (?:beta|son|bhai|daughter|beti|husband|pati|बेटा|बेटी|भाई|पति).{0,60}?(?:accident|arrest|hospital|police|custody|गिरफ्तार|एक्सीडेंट|अस्पताल|पुलिस).{0,80}?(?:paise|money|pay|bail|settle|bhej|transfer|पैसे|जमानत|भेज)"),
        Rule("new_number", 0.45, "(?:mera|my) (?:old )?(?:phone|mobile|number) (?:kharab|toot|gum|lost|broken|damaged|changed|band)|(?:naye|naya|new) number (?:se|hai|from|is my|par|save)|this is my new number|ye mera (?:naya|new) number|मेरा फोन (?:खराब|टूट|खो)|नए नंबर से|नया नंबर"),
        Rule("fee_ask", 0.30, "(?:registration|joining|processing|activation|security|insurance|release|clearance|claim)\\W+(?:fee|fees|charges?|deposit|amount)|(?:रजिस्ट्रेशन|प्रोसेसिंग|जॉइनिंग)\\s*(?:फीस|शुल्क)"),
        Rule("call_ask", 0.35, "\\b(?:call|contact|dial|whatsapp)\\s+(?:us\\s+)?(?:this|the|our|immediately|now|officer|helpline|customer care|support)\\b|\\bcall\\s+(?:on|at)\\s+\\+?\\d|(?:officer|adhikari|helpline|customer care)\\s+(?:ko|se)\\s+(?:call|baat|sampark)|इस नंबर (?:पर|पे)|is number (?:pe|par)|(?:call|कॉल)\\s+(?:karo|kijiye|karein|करें|करो|कीजिए)|संपर्क करें|अधिकारी से (?:बात|संपर्क)"),
        Rule("url_short", 0.45, "\\b(?:bit\\.ly|tinyurl\\.com|cutt\\.ly|rb\\.gy|is\\.gd|t\\.ly|ow\\.ly|shorturl\\.at|tiny\\.cc|rebrand\\.ly|s\\.id|v\\.gd)/"),
        Rule("url_ip", 0.65, "https?://\\d{1,3}(?:\\.\\d{1,3}){3}"),
        Rule("url_punycode", 0.65, "https?://[^\\s/?#]*xn--|\\bxn--[a-z0-9-]+\\.[a-z]"),
        Rule("url_tld", 0.45, "(?:https?://|www\\.)[^\\s/?#]*\\.(?:$RISKY_TLD)(?=[:/?#\\s.,;!]|\\z)|\\b[a-z0-9-]{3,}\\.(?:$RISKY_TLD)/"),
        Rule("url_lookalike", 0.60, "$URL_HOST(?:kyc|refund|verify|verification|(?:sbi|hdfc|icici|axis|pnb|kotak|paytm|phonepe|upi|irctc|uidai|aadhaar|incometax|epfo|jio|airtel|bsnl|bijli)[a-z0-9]*-|-(?:update|secure|login|claim|reward|support|care|helpdesk))"),
        Rule("urgency", 0.20, "\\b(turant|abhi ke abhi|immediately|urgent|right now)\\b|within \\d+ (minutes|hours)|तुरंत|अभी के अभी"),
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

    /** [lang] only picks the language of the human-readable reason; matching and scoring are unchanged. */
    fun score(text: String, lang: String = "en"): RuleResult {
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
        val reason = if (top.isEmpty()) L10n.noPhrases(lang)
        else top.take(2).joinToString("; ") { L10n.ruleReason(it.first.tag, lang) }
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
        "courier_hold" in t || "parcel" in t && ("authority" in t || "contraband" in t || "arrest" in t) -> ScamType.COURIER_CUSTOMS
        "sextortion" in t -> ScamType.SEXTORTION
        "family_emerg" in t -> ScamType.FAMILY_EMERGENCY
        "sim_kyc" in t && "arrest" !in t && "contraband" !in t -> ScamType.SIM_SWAP
        "elec_cut" in t -> ScamType.ELECTRICITY_BILL
        "upi_collect" in t -> ScamType.UPI_COLLECT
        "care_refund" in t -> ScamType.CUSTOMER_CARE
        "qr_receive" in t -> ScamType.FAKE_QR
        "loan_threat" in t || "loan_fee" in t -> ScamType.LOAN_APP
        "arrest" in t || "authority" in t || "contraband" in t -> ScamType.DIGITAL_ARREST
        "otp_share" in t || "pin" in t -> ScamType.OTP
        "job_task" in t -> ScamType.JOB
        "invest_scam" in t -> ScamType.INVESTMENT
        "url_lookalike" in t || "url_ip" in t || "url_punycode" in t -> ScamType.PHISHING_LINK
        "kyc" in t -> ScamType.KYC            // KYC wording beats an incidental bare OTP mention; a real OTP ask is otp_share above
        "otp" in t -> ScamType.OTP
        "account_block" in t || "bank_claim" in t -> ScamType.KYC
        "prize_fee" in t || "prize" in t || "lottery_claim" in t -> ScamType.LOTTERY
        "loan" in t -> ScamType.LOAN_APP
        "parcel" in t -> ScamType.COURIER_CUSTOMS
        t.any { it.startsWith("url_") } -> ScamType.PHISHING_LINK
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
