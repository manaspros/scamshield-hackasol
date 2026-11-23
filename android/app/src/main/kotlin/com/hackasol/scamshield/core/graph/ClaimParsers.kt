package com.hackasol.scamshield.core.graph

import com.hackasol.scamshield.core.UnicodeRegex

/** What a message asserts. Raw text is never kept; only these extracted values. */
data class Claims(
    val brand: String?,              // canonical brand id (Brands.canonical); text brand, else DLT header brand
    val amountRupees: Double?,
    val upiIds: List<String>,
    val links: List<String>,
    val numbers: List<String>,       // 10-digit Indian mobile numbers found in the text
    val claimsBill: Boolean,
    val claimsOrder: Boolean,
    val claimsPayment: Boolean,
) {
    val claimsAnyEvent: Boolean get() = claimsBill || claimsOrder || claimsPayment
}

object ClaimParsers {
    private const val BRAND_SUFFIXES = "bank|courier|express|logistics"
    private val BRAND_STOPWORDS = setOf(
        "the", "your", "my", "our", "this", "that", "any", "a", "an", "of", "with", "from", "by", "to", "in",
        "for", "and", "or", "you", "we", "net", "mobile", "online", "state",
    )

    private val SUFFIX_BRAND = UnicodeRegex.of("([\\p{L}][\\p{L}0-9]{1,20})\\s?($BRAND_SUFFIXES)\\b")

    // Amounts: ₹ / Rs / INR / रु prefix, or a rupee word after; k / hazaar / lakh / crore multipliers (Devanagari digits normalised first).
    private const val NUM = "([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
    // Hindi thousand/crore are spelled with a nukta either composed (U+095B, U+095C) or as base + U+093C.
    private const val WORD_MULT = "hazaar|hazar|hajar|हज़ार|हज़ार|हजार|lakhs?|lacs?|लाख|crores?|करोड़|करोड़|करोड"
    private const val MULT = "(?:\\s*(k(?![\\p{L}0-9])|$WORD_MULT))?"
    private val AMOUNT_PREFIX = UnicodeRegex.of("(?:₹|\\brs\\.?|\\binr\\b|रुपये|रुपए|रु\\.?)\\s*$NUM$MULT")
    private val AMOUNT_SUFFIX = UnicodeRegex.of("$NUM$MULT\\s*(?:रुपये|रुपए|रुपया|rupees|rupee|rupaye|rupay)")
    private val AMOUNT_WORD = UnicodeRegex.of("$NUM\\s*($WORD_MULT)")
    // shortcut: no domain-suffix list for UPI handles; the lookahead only rejects emails like a@b.com. Upgrade if real handles false-match.
    private val UPI = UnicodeRegex.of("(?<![\\w.@-])[a-z0-9._-]{2,}@[a-z][a-z0-9]+(?![a-z0-9]|\\.[a-z])")
    // shortcut: bare hosts need a common TLD (avoids "Dear customer.Your" -> host); a link on a rare TLD without a scheme is missed. Upgrade with a real TLD list.
    private val LINK = UnicodeRegex.of(
        "(?<![@\\w.-])(?:(?:https?://|www\\.)\\S+|(?:[a-z0-9-]+\\.)+" +
            "(?:com|in|co|net|org|xyz|top|info|link|ly|me|cc|app|site|online|vip|club|live|shop|icu|click|page)\\b(?:/\\S*)?)",
    )
    private val PHONE = UnicodeRegex.of("(?<!\\d)(?:\\+?91[\\s-]?|0)?([6-9]\\d{9})(?!\\d)")

    // Claims: what a message asserts (English, Hindi, Hinglish).
    private val BILL = UnicodeRegex.of("\\b(?:bill|invoice|statement|due date|overdue|bakaya)\\b|बिल|बकाया")
    // "in order to" / "order of" are English, not an order.
    private val ORDER = UnicodeRegex.of("(?<!\\bin )\\border\\b(?!\\s+of\\b)|\\b(?:parcel|shipment|package|courier)\\b|ऑर्डर|पार्सल")
    private val PAYMENT = UnicodeRegex.of("\\b(?:debited|payment|paid|refund|transaction)\\b|\\bpaisa\\s+bhej|भुगतान")

    // Events: what a genuine notification reports (only recorded from DLT-header senders).
    private val EV_ORDER = UnicodeRegex.of(
        "(?<!\\bin )\\border\\b.{0,40}\\b(?:placed|confirmed|shipped|dispatched)\\b|" +
            "(?<!\\bin )\\border\\b.{0,20}\\b(?:confirm|place)\\s+ho\\s+(?:gaya|gayi)\\b|ऑर्डर.{0,40}(?:कन्फर्म|कंफर्म|कन्फ़र्म|प्लेस)",
    )
    private val EV_BILL = UnicodeRegex.of(
        "\\b(?:bill|invoice)\\b.{0,40}\\b(?:generated|due|ready|payable|baaki|bakaya|baki)\\b|\\bdue date\\b|बिल.{0,40}बकाया",
    )
    private val EV_CREDIT = UnicodeRegex.of("\\bcredited\\b|\\bcredit of\\b|\\bjama\\s+(?:ho|hue|kiye|kar)|\\bcredit\\s+ho\\s+gaye|जमा")
    private val EV_DEBIT = UnicodeRegex.of(
        "\\bdebited\\b|\\bdebit of\\b|\\bspent\\b|\\bcharged\\b|\\bdeducted\\b|\\bwithdrawn\\b|\\bkat\\s+(?:gaye|gaya|gayi)\\b|\\bkate\\s+(?:gaye|hain|hai)\\b|\\bpaise\\s+kate\\b|कट गए|कटे|डेबिट(?!\\s*कार्ड)",
    )
    private val EV_REFUND = UnicodeRegex.of("\\brefund\\b.{0,40}\\b(?:processed|initiated|credited|issued)\\b|रिफंड")
    // [VERIFY] delivery phrasing varies by courier.
    private val EV_OFD = UnicodeRegex.of("out for delivery|will be delivered today|arriving today|aaj delivery|डिलीवरी के लिए|आज डिलीवरी")

    private val BANK_TALK = UnicodeRegex.of("\\b(?:bank|rbi|kyc|credit card|debit card|loan|account|a/c|atm)\\b|बैंक|खाता")
    private val PAY_ASK = UnicodeRegex.of("\\b(?:pay|send|transfer|return|refund)\\b|bhej|wapas|chuka|भेज|वापस")
    private val ACT_ASK = UnicodeRegex.of("\\b(?:call|contact|click|reply|cancel|block|dispute|helpline|customer care)\\b|call karo|कॉल")

    fun normalizeBrand(s: String): String = s.lowercase().filter { it.isLetterOrDigit() }

    /** Same brand when both resolve to one canonical id; two unknown names may still match by 4+ char prefix (header vs full name). */
    fun sameBrand(a: String, b: String): Boolean {
        val ca = Brands.canonical(a)
        val cb = Brands.canonical(b)
        if (ca == cb) return true
        if (Brands.isKnown(a) || Brands.isKnown(b)) return false
        return minOf(ca.length, cb.length) >= 4 && (ca.startsWith(cb) || cb.startsWith(ca))
    }

    fun senderBrand(sender: String): String? =
        if (ClaimVsContext.isDltHeader(sender)) Brands.canonical(sender.trim().split('-')[1]) else null

    fun brandFromText(text: String): String? {
        SUFFIX_BRAND.findAll(text).forEach { m ->
            val word = m.groupValues[1].lowercase()
            if (word !in BRAND_STOPWORDS) return Brands.canonical(word + m.groupValues[2])
        }
        return Brands.TEXT_REGEX.find(text)?.let { Brands.canonical(it.groupValues[1]) }
    }

    private fun devanagariDigitsToAscii(s: String): String =
        if (s.none { it in '०'..'९' }) s else s.map { if (it in '०'..'९') '0' + (it - '०') else it }.joinToString("")

    private fun multiplier(m: String): Double = when {
        m.isEmpty() -> 1.0
        m.equals("k", ignoreCase = true) -> 1e3
        m.startsWith("lakh", ignoreCase = true) || m.startsWith("lac", ignoreCase = true) || m == "लाख" -> 1e5
        m.startsWith("crore", ignoreCase = true) || m.startsWith("करो") -> 1e7
        else -> 1e3   // hazaar / hazar / hajar / हज़ार
    }

    fun amountRupees(text: String): Double? {
        val t = devanagariDigitsToAscii(text)
        val m = AMOUNT_PREFIX.find(t) ?: AMOUNT_SUFFIX.find(t) ?: AMOUNT_WORD.find(t) ?: return null
        val n = m.groupValues[1].replace(",", "").toDoubleOrNull() ?: return null
        return n * multiplier(m.groupValues.getOrElse(2) { "" })
    }

    fun upiIds(text: String): List<String> = UPI.findAll(text).map { it.value.lowercase() }.distinct().toList()

    fun links(text: String): List<String> =
        LINK.findAll(text).map { it.value.trimEnd('.', ',', ')', ';', '!', '?') }.distinct().toList()

    fun numbers(text: String): List<String> = PHONE.findAll(text).map { it.groupValues[1] }.distinct().toList()

    /** Host of a link; takes the part after any `user@` so `https://bank.in@evil.example` yields `evil.example`. */
    fun host(link: String): String =
        link.substringAfter("://").substringBefore('/').substringBefore('?').substringBefore('#')
            .substringAfterLast('@').substringBefore(':').trimEnd('.').lowercase()

    fun mentionsBank(text: String): Boolean = BANK_TALK.containsMatchIn(text)

    /** Money said to have left the account (debited / spent / kat gaye ...). */
    fun mentionsDebit(text: String): Boolean = EV_DEBIT.containsMatchIn(text)

    fun asksPay(text: String): Boolean = PAY_ASK.containsMatchIn(text)

    /** Asks the reader to call, click, reply, cancel, block or dispute. */
    fun asksAction(text: String): Boolean = ACT_ASK.containsMatchIn(text)

    /** Key for a sender in trust/report lookups: a phone-number sender is its 10-digit national form, anything else is trimmed. */
    fun senderKey(sender: String): String = sender.trim().let { s -> numbers(s).firstOrNull() ?: s }

    fun eventTypes(text: String): Set<EventType> {
        val out = mutableSetOf<EventType>()
        if (EV_ORDER.containsMatchIn(text)) out += EventType.ORDER
        if (EV_BILL.containsMatchIn(text)) out += EventType.BILL
        if (EV_CREDIT.containsMatchIn(text)) out += EventType.CREDIT
        if (EV_DEBIT.containsMatchIn(text)) out += EventType.DEBIT
        if (EV_REFUND.containsMatchIn(text)) out += EventType.REFUND
        if (EV_OFD.containsMatchIn(text)) out += EventType.OUT_FOR_DELIVERY
        return out
    }

    fun parse(text: String, sender: String = ""): Claims = Claims(
        brand = brandFromText(text) ?: senderBrand(sender),
        amountRupees = amountRupees(text),
        upiIds = upiIds(text),
        links = links(text),
        numbers = numbers(text),
        claimsBill = BILL.containsMatchIn(text),
        claimsOrder = ORDER.containsMatchIn(text),
        claimsPayment = PAYMENT.containsMatchIn(text),
    )
}
