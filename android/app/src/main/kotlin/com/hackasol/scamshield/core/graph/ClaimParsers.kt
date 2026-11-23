package com.hackasol.scamshield.core.graph

import com.hackasol.scamshield.core.UnicodeRegex

/** What a message asserts. Raw text is never kept; only these extracted values. */
data class Claims(
    val brand: String?,              // normalized (lowercase letters/digits); text brand, else DLT header brand
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
    val KNOWN_BRANDS = listOf(
        "amazon", "flipkart", "myntra", "meesho", "swiggy", "zomato", "paytm", "phonepe", "delhivery",
        "bluedart", "dtdc", "ekart", "indiapost",
    )

    private val SUFFIX_BRAND = UnicodeRegex.of("([\\p{L}][\\p{L}0-9]{1,20})\\s?($BRAND_SUFFIXES)\\b")
    private val KNOWN_BRAND = UnicodeRegex.of("\\b(${KNOWN_BRANDS.joinToString("|")})\\b")
    private val AMOUNT_PREFIX = UnicodeRegex.of("(?:₹|\\brs\\.?|\\binr)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)")
    private val AMOUNT_SUFFIX = UnicodeRegex.of("([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\s*(?:रुपये|रुपए|rupees)")
    // shortcut: no domain-suffix list for UPI handles; the lookahead only rejects emails like a@b.com. Upgrade if real handles false-match.
    private val UPI = UnicodeRegex.of("(?<![\\w.@-])[a-z0-9._-]{2,}@[a-z][a-z0-9]+(?![a-z0-9]|\\.[a-z])")
    // shortcut: bare hosts need a common TLD (avoids "Dear customer.Your" -> host); a link on a rare TLD without a scheme is missed. Upgrade with a real TLD list.
    private val LINK = UnicodeRegex.of(
        "(?<![@\\w.-])(?:(?:https?://|www\\.)\\S+|(?:[a-z0-9-]+\\.)+" +
            "(?:com|in|co|net|org|xyz|top|info|link|ly|me|cc|app|site|online|vip|club|live|shop|icu|click|page)\\b(?:/\\S*)?)",
    )
    private val PHONE = UnicodeRegex.of("(?<!\\d)(?:\\+?91[\\s-]?|0)?([6-9]\\d{9})(?!\\d)")

    // Claims: what a message asserts.
    private val BILL = UnicodeRegex.of("\\b(?:bill|invoice|statement|due date|overdue)\\b|बिल")
    private val ORDER = UnicodeRegex.of("\\b(?:order|parcel|shipment|package|courier)\\b|ऑर्डर|पार्सल")
    private val PAYMENT = UnicodeRegex.of("\\b(?:debited|payment|paid|refund|transaction)\\b|भुगतान")

    // Events: what a genuine notification reports (only recorded from DLT-header senders).
    private val EV_ORDER = UnicodeRegex.of("\\border\\b.{0,40}\\b(?:placed|confirmed|shipped|dispatched)\\b")
    private val EV_BILL = UnicodeRegex.of("\\b(?:bill|invoice)\\b.{0,40}\\b(?:generated|due|ready|payable)\\b|\\bdue date\\b")
    private val EV_CREDIT = UnicodeRegex.of("\\bcredited\\b|\\bcredit of\\b|जमा")
    // [VERIFY] delivery phrasing varies by courier.
    private val EV_OFD = UnicodeRegex.of("out for delivery|will be delivered today|arriving today|डिलीवरी के लिए")

    private val BANK_TALK = UnicodeRegex.of("\\b(?:bank|rbi|kyc|credit card|debit card|loan|account|a/c|atm)\\b|बैंक|खाता")

    fun normalizeBrand(s: String): String = s.lowercase().filter { it.isLetterOrDigit() }

    // shortcut: equal-or-prefix match (min 3 chars) bridges 6-char DLT headers and full names; "EXMPBK" vs "examplebank" will not match. Upgrade with an alias table.
    fun sameBrand(a: String, b: String): Boolean =
        a == b || (minOf(a.length, b.length) >= 3 && (a.startsWith(b) || b.startsWith(a)))

    fun senderBrand(sender: String): String? =
        if (ClaimVsContext.isDltHeader(sender)) normalizeBrand(sender.trim().split('-')[1]) else null

    fun brandFromText(text: String): String? {
        SUFFIX_BRAND.findAll(text).forEach { m ->
            val word = m.groupValues[1].lowercase()
            if (word !in BRAND_STOPWORDS) return normalizeBrand(word + m.groupValues[2])
        }
        return KNOWN_BRAND.find(text)?.let { normalizeBrand(it.groupValues[1]) }
    }

    fun amountRupees(text: String): Double? =
        (AMOUNT_PREFIX.find(text) ?: AMOUNT_SUFFIX.find(text))?.groupValues?.get(1)?.replace(",", "")?.toDoubleOrNull()

    fun upiIds(text: String): List<String> = UPI.findAll(text).map { it.value.lowercase() }.distinct().toList()

    fun links(text: String): List<String> =
        LINK.findAll(text).map { it.value.trimEnd('.', ',', ')', ';', '!', '?') }.distinct().toList()

    fun numbers(text: String): List<String> = PHONE.findAll(text).map { it.groupValues[1] }.distinct().toList()

    /** Host of a link; takes the part after any `user@` so `https://bank.in@evil.example` yields `evil.example`. */
    fun host(link: String): String =
        link.substringAfter("://").substringBefore('/').substringBefore('?').substringBefore('#')
            .substringAfterLast('@').substringBefore(':').trimEnd('.').lowercase()

    fun mentionsBank(text: String): Boolean = BANK_TALK.containsMatchIn(text)

    fun eventTypes(text: String): Set<EventType> {
        val out = mutableSetOf<EventType>()
        if (EV_ORDER.containsMatchIn(text)) out += EventType.ORDER
        if (EV_BILL.containsMatchIn(text)) out += EventType.BILL
        if (EV_CREDIT.containsMatchIn(text)) out += EventType.CREDIT
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
