package com.hackasol.scamshield.core.graph

/** One brand: normalized [id], every name/DLT header code it goes by, and its official web hosts. */
data class BrandInfo(
    val id: String,
    val aliases: List<String>,
    val domains: List<String>,
    val name: String = id.replaceFirstChar { it.uppercase() },
)

/**
 * Brand table shared by claim parsing (brand from text / DLT header) and link checks (official host, lookalike host).
 * [VERIFY] every alias and domain below is from memory; check against the DLT header registry and each brand's site.
 */
object Brands {
    private fun b(id: String, name: String, aliases: String, domains: String = "") =
        BrandInfo(id, (listOf(id) + aliases.split(' ').filter { it.isNotEmpty() }).distinct(), domains.split(' ').filter { it.isNotEmpty() }, name)

    val ALL: List<BrandInfo> = listOf(
        b("hdfcbank", "HDFC Bank", "hdfc hdfcbk", "hdfcbank.com hdfc.bank.in hdfcbank.net"),
        b("sbi", "SBI", "sbibnk sbiinb statebank sbibank", "onlinesbi.sbi sbi.co.in sbi.bank.in onlinesbi.com"),
        b("icicibank", "ICICI Bank", "icici icicib", "icicibank.com icici.bank.in"),
        b("axisbank", "Axis Bank", "axis axisbk", "axisbank.com axis.bank.in"),
        b("kotak", "Kotak", "kotakb kotakbank", "kotak.com kotak.bank.in"),
        b("pnb", "PNB", "pnbindia", "pnbindia.in pnb.bank.in"),
        b("bankofbaroda", "Bank of Baroda", "bob bobank baroda", "bankofbaroda.in bankofbaroda.com bob.bank.in"),
        b("canara", "Canara Bank", "canarabank", "canarabank.com canarabank.in"),
        b("unionbank", "Union Bank", "unionbankofindia", "unionbankofindia.co.in unionbank.bank.in"),
        b("yesbank", "Yes Bank", "yesbnk", "yesbank.in yesbank.bank.in"),
        b("indusind", "IndusInd Bank", "indusindbank", "indusind.com indusind.bank.in"),
        b("idfc", "IDFC First Bank", "idfcfirst idfcbank", "idfcfirstbank.com"),
        b("paytm", "Paytm", "paytmbank", "paytm.com paytmbank.com paytm.me"),
        b("phonepe", "PhonePe", "", "phonepe.com phon.pe"),
        b("googlepay", "Google Pay", "gpay", "pay.google.com"),
        b("bhim", "BHIM", "", "bhimupi.org.in npci.org.in"),
        b("amazon", "Amazon", "amazonpay amzn", "amazon.in amazon.com amzn.in amzn.to a.co amazonpay.in amazon.co.uk amazon.de amazon.ca amazon.com.au amazon.co.jp amazon.fr amazon.it amazon.es"),
        b("flipkart", "Flipkart", "fkrt", "flipkart.com fkrt.it"),
        b("myntra", "Myntra", "", "myntra.com myntr.it"),
        b("meesho", "Meesho", "", "meesho.com"),
        b("ajio", "Ajio", "", "ajio.com"),
        b("nykaa", "Nykaa", "", "nykaa.com"),
        b("swiggy", "Swiggy", "", "swiggy.com swiggy.in"),
        b("zomato", "Zomato", "", "zomato.com zoma.to"),
        b("blinkit", "Blinkit", "", "blinkit.com"),
        b("zepto", "Zepto", "", "zeptonow.com zepto.com"),
        b("bigbasket", "BigBasket", "", "bigbasket.com"),
        b("jio", "Jio", "reliancejio jiofiber", "jio.com"),
        b("airtel", "Airtel", "", "airtel.in airtel.com"),
        b("vi", "Vi", "vodafone", "myvi.in vodafone.in vodafone.com vodafoneidea.com"),
        b("bsnl", "BSNL", "", "bsnl.co.in"),
        b("irctc", "IRCTC", "", "irctc.co.in"),
        b("delhivery", "Delhivery", "delhvy", "delhivery.com"),
        b("bluedart", "Blue Dart", "bludrt", "bluedart.com"),
        b("dtdc", "DTDC", "", "dtdc.in dtdc.com"),
        b("ekart", "Ekart", "ekartlogistics", "ekartlogistics.com"),
        b("xpressbees", "Xpressbees", "", "xpressbees.com"),
        b("shadowfax", "Shadowfax", "", "shadowfax.in"),
        b("ecomexpress", "Ecom Express", "", "ecomexpress.in"),
        b("indiapost", "India Post", "", "indiapost.gov.in"),
        b("bescom", "BESCOM", "", "bescom.co.in bescom.org"),
        b("msedcl", "MSEDCL", "mahadiscom", "mahadiscom.in msedcl.in"),
        b("tatapower", "Tata Power", "", "tatapower.com tatapowerddl.com"),
        b("adanielectricity", "Adani Electricity", "adani", "adanielectricity.com"),
        b("bses", "BSES", "", "bsesdelhi.com"),
        b("tneb", "TNEB", "tangedco", "tnebltd.gov.in tangedco.gov.in"),
        b("uppcl", "UPPCL", "", "uppcl.org"),
        b("kseb", "KSEB", "", "kseb.in"),
        b("cesc", "CESC", "", "cesc.co.in"),
        b("torrentpower", "Torrent Power", "", "torrentpower.com"),
        b("echallan", "e-Challan", "parivahan", "echallan.parivahan.gov.in parivahan.gov.in"),
        b("incometax", "Income Tax Department", "", "incometax.gov.in incometaxindia.gov.in"),
        b("epfo", "EPFO", "", "epfindia.gov.in epfo.gov.in"),
        b("uidai", "UIDAI", "aadhaar", "uidai.gov.in"),
        b("lic", "LIC", "licindia", "licindia.in"),
        b("uber", "Uber", "", "uber.com"),
        b("ola", "Ola", "olacabs", "olacabs.com"),
    )

    /** Aliases too ordinary as English words to spot a brand in free text; they still resolve DLT headers. */
    private val TEXT_STOP = setOf("vi", "axis", "ola", "bob", "lic", "baroda", "adani", "aadhaar")

    private val byId: Map<String, BrandInfo> = ALL.associateBy { it.id }
    private val aliasToId: Map<String, String> = ALL.flatMap { br -> br.aliases.map { it to br.id } }.toMap()

    /** Word-boundary match over every text-safe alias, longest first. */
    val TEXT_REGEX: Regex = com.hackasol.scamshield.core.UnicodeRegex.of(
        "\\b(" + aliasToId.keys.filter { it !in TEXT_STOP }.sortedByDescending { it.length }.joinToString("|") + ")\\b",
    )

    fun normalize(s: String): String = s.lowercase().filter { it.isLetterOrDigit() }

    /** Alias -> brand id; unknown -> the normalized input. */
    fun canonical(s: String): String = normalize(s).let { aliasToId[it] ?: it }

    fun isKnown(s: String): Boolean = aliasToId.containsKey(normalize(s))

    fun byId(id: String): BrandInfo? = byId[id]

    fun isOfficialHost(host: String): Boolean {
        val h = host.lowercase().trimEnd('.')
        return ALL.any { br -> br.domains.any { h == it || h.endsWith(".$it") } }
    }

    private val LEET = mapOf('0' to 'o', '1' to 'l', '3' to 'e', '4' to 'a', '5' to 's', '7' to 't', '@' to 'a')

    private fun deleet(s: String): String =
        s.lowercase().map { LEET[it] ?: it }.filter { it.isLetter() }.joinToString("")

    private fun lev1(a: String, b: String): Boolean {
        if (a == b) return true
        if (kotlin.math.abs(a.length - b.length) > 1) return false
        var i = 0
        while (i < a.length && i < b.length && a[i] == b[i]) i++
        return when {
            a.length == b.length -> a.substring(i + 1) == b.substring(i + 1)
            a.length > b.length -> a.substring(i + 1) == b.substring(i)
            else -> a.substring(i) == b.substring(i + 1)
        }
    }

    private val TWO_PART_SUFFIXES = setOf("co.in", "org.in", "gov.in", "net.in", "co.uk", "com.au")

    /**
     * Id of the brand whose name [host] imitates without being official, else null. Each host label (and each pair of
     * adjacent labels, for "amazon-in.xyz" style hosts) is de-leeted and compared with every alias: aliases of 5+ chars
     * match by containment, 7+ chars also by one edit, 4-char aliases only exactly (short or ordinary words such as
     * canada/kodak/tomato must not match). 3-char aliases match only a whole '-'-delimited segment of the registrable
     * label. Hosts under .gov.in / .bank.in are registry-controlled, never lookalikes.
     */
    fun lookalikeOf(host: String): String? {
        val h = host.lowercase().trimEnd('.')
        if (h.isEmpty() || isOfficialHost(h) || h.endsWith(".gov.in") || h.endsWith(".bank.in")) return null
        val labels = h.split('.').filter { it.isNotEmpty() }
        val cands = (labels + labels.zipWithNext { a, c -> a + c }).map { deleet(it) }.filter { it.length >= 4 }.distinct()
        // Registrable label = the one left of the public suffix: "bob.github.io" -> "github", "sbi-yono.xyz" -> "sbi-yono".
        val twoPart = labels.size >= 3 && labels.takeLast(2).joinToString(".") in TWO_PART_SUFFIXES
        val registrable = labels.getOrNull(labels.size - if (twoPart) 3 else 2) ?: labels.firstOrNull().orEmpty()
        val segs = registrable.split('-').map { deleet(it) }.toSet()
        for (br in ALL) for (a in br.aliases) {
            if (a.length == 3) { if (a in segs) return br.id; continue }
            if (a.length < 4) continue
            if (cands.any { c -> if (a.length >= 5) c.contains(a) || (a.length >= 7 && lev1(c, a)) else c == a }) return br.id
        }
        return null
    }
}
