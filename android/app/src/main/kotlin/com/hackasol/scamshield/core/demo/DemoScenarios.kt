package com.hackasol.scamshield.core.demo

import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.graph.FlagKind

/** TEXT runs the full pipeline; QR runs UpiQr (arg = the name the user was told); FAMILY runs Totp (arg = "match" | "mismatch"). */
enum class StepKind { TEXT, QR, FAMILY }

/**
 * One scripted event. [delayMs] is the pause BEFORE the step (UI pacing; also the simulated clock gap the graph sees).
 * [senderId]: SMS header, or the caller number for call sources (CAPTION/RECORDING).
 * Expectation: SAFE must stay SAFE; any other label means "at least this severe" (the SLM may be stricter than the rules).
 * [expectedFlags] is the exact set of context flags in the scenario's default graph mode.
 */
data class DemoStep(
    val delayMs: Long,
    val source: Source,
    val senderId: String,
    val text: String,
    val expectedLabel: Label,
    val expectedFlags: Set<FlagKind> = emptySet(),
    val kind: StepKind = StepKind.TEXT,
    val arg: String? = null,
)

data class DemoScenario(
    val id: String,
    val icon: String,
    val titleHi: String,
    val titleEn: String,
    val storyHi: String,
    val storyEn: String,
    val steps: List<DemoStep>,
    /** true = start from an empty graph (cold start); false = a warm graph with one benign seed message. */
    val coldStartDefault: Boolean = false,
) {
    fun toChannelMap(): Map<String, Any?> = mapOf(
        "id" to id, "icon" to icon, "titleHi" to titleHi, "titleEn" to titleEn,
        "storyHi" to storyHi, "storyEn" to storyEn, "steps" to steps.size, "coldStartDefault" to coldStartDefault,
    )
}

/** Synthetic scripts only: no real person, tenant, number or account. */
object DemoScenarios {
    /** Public RFC-style example secret, used for both "phones" of the demo family pair. Not a real pairing secret. */
    const val FAMILY_DEMO_SECRET = "JBSWY3DPEHPK3PXP"

    /** Ingested (age [SEED_AGE_MS]) into a warm graph so it is not empty; creates no order/credit/delivery event. */
    val WARM_SEED: List<Pair<String, String>> = listOf("VM-SBIINB" to "Welcome. Alerts are now active.")
    const val SEED_AGE_MS = 3L * 24 * 60 * 60 * 1000

    private const val FIRST = 600L
    private const val GAP = 2500L
    private const val CALL_GAP = 3000L

    private fun sms(sender: String, text: String, exp: Label, flags: Set<FlagKind> = emptySet(), delay: Long = GAP) =
        DemoStep(delay, Source.SMS, sender, text, exp, flags)

    private fun call(caller: String, text: String, exp: Label, flags: Set<FlagKind> = emptySet(), delay: Long = GAP) =
        DemoStep(delay, Source.CAPTION, caller, text, exp, flags)

    private const val BANK_CALL_TEXT = "Main bank se bol raha hoon, aapke account ki ek detail confirm karni hai"

    val ALL: List<DemoScenario> = listOf(
        DemoScenario(
            "mistaken_a", "sms",
            "गलती से भेजे पैसे: नकली क्रेडिट SMS", "Mistaken transfer: fake credit SMS",
            "आम नंबर से SMS आता है कि ₹5,000 जमा हुए। फिर उसी का कॉल: 'गलती से भेज दिए, वापस कर दो'। बैंक का कोई असली क्रेडिट अलर्ट नहीं मिला, इसलिए चेतावनी।",
            "A normal-number SMS claims Rs 5,000 arrived, then the same person calls: 'sent by mistake, send it back'. " +
                "The graph holds no real credit alert, so the request is flagged.",
            listOf(
                sms("9800000010", "आपके खाते में ₹5,000 जमा हुए। कृपया अपना बैलेंस देखें।", Label.SAFE, setOf(FlagKind.NON_DLT_SENDER), FIRST),
                call("9800000010", "Maine galti se aapko 5000 bhej diye, please wapas kar do", Label.SUSPICIOUS, setOf(FlagKind.FAKE_CREDIT)),
            ),
        ),
        DemoScenario(
            "mistaken_b", "sms",
            "गलती से भेजे पैसे: असली क्रेडिट, खतरनाक वापसी", "Mistaken transfer: real credit, risky return",
            "बैंक का असली क्रेडिट SMS आया, फिर कॉल: 'गलती से भेजा, इस UPI पर वापस भेजो'। खुद लौटाने से खाता फ्रीज़ हो सकता है; बैंक से रिवर्सल कराएं।",
            "A real bank credit SMS did arrive, then a caller says 'sent by mistake, return it to this UPI'. " +
                "Returning it yourself can get your account frozen: ask for a reversal through the bank.",
            listOf(
                sms("VM-SBIINB", "Rs 5000.00 credited to A/c XXXX on 23Nov. Avl Bal Rs 17430.00", Label.SAFE, emptySet(), FIRST),
                call("9800000011", "Galti se bheja, is UPI pe wapas bhejo refund.help@ybl", Label.SUSPICIOUS,
                    setOf(FlagKind.RETURN_VIA_BANK_ONLY)),
            ),
        ),
        DemoScenario(
            "debit_scare", "call",
            "डेबिट का डर, फिर बैंक का कॉल", "Debit scare, then a 'bank' call",
            "आम नंबर से SMS: 'आपके खाते से ₹9,999 कटे, नहीं किया तो कॉल करें'। फिर कॉल करने वाला OTP मांगता है।",
            "A normal-number SMS says Rs 9,999 was debited, 'call to cancel'. The caller then asks for the OTP.",
            listOf(
                sms("9800000020", "Your a/c debited Rs 9,999. If not you, call 98XXXXXX10 to cancel", Label.SUSPICIOUS,
                    setOf(FlagKind.NO_MATCHING_EVENT, FlagKind.NON_DLT_SENDER), FIRST),
                call("9800000030", "Main bank se bol raha hoon, OTP batao cancel karne ke liye", Label.SCAM, setOf(FlagKind.NON_1600_BANK_CALL)),
            ),
        ),
        DemoScenario(
            "bank_call_number", "call",
            "बैंक कॉल: आम नंबर बनाम 1600", "Bank call: normal number vs 1600 series",
            "एक ही बात दो कॉल में। बैंक 1600 वाले नंबर से कॉल करते हैं; आम मोबाइल नंबर से बैंक का दावा संदिग्ध है।",
            "The same words in two calls. Banks call from 1600 numbers; the same claim from a normal mobile number is suspicious.",
            listOf(
                call("9800000040", BANK_CALL_TEXT, Label.SUSPICIOUS, setOf(FlagKind.NON_1600_BANK_CALL), FIRST),
                call("1600123456", BANK_CALL_TEXT, Label.SAFE),
            ),
        ),
        DemoScenario(
            "delivery_genuine", "local_shipping",
            "असली डिलीवरी कॉल", "Genuine delivery call",
            "ऑर्डर और 'आउट फॉर डिलीवरी' SMS कूरियर के हेडर से आए। फिर डिलीवरी एजेंट का कॉल आम नंबर से: कोई चेतावनी नहीं।",
            "Order and out-for-delivery SMS arrived from the courier's header. The agent's call from a normal number is not flagged.",
            listOf(
                sms("VM-DELHVY", "Your Delhivery order has been shipped. Track it in the app.", Label.SAFE, emptySet(), FIRST),
                sms("VM-DELHVY", "Your Delhivery parcel is out for delivery today.", Label.SAFE),
                call("9800000050", "Hello, Delhivery se bol raha hoon, parcel aapke gate par hai, please nikal aaiye", Label.SAFE),
            ),
        ),
        DemoScenario(
            "delivery_customs", "local_shipping",
            "कस्टम्स फीस का नकली SMS", "Fake customs-fee SMS",
            "'पार्सल कस्टम्स में रुका है, ₹49 फीस दें' और एक लिंक। आपने कोई ऑर्डर नहीं किया, नंबर आम है, लिंक अनजान है।",
            "'Parcel held at customs, pay Rs 49 fee' with a link. No order on record, a normal number and an unknown link.",
            listOf(
                sms("9800000060", "Parcel held at customs, pay ₹49 fee: http://dlv-fee.example/pay", Label.SUSPICIOUS,
                    setOf(FlagKind.NO_MATCHING_EVENT, FlagKind.NON_DLT_SENDER, FlagKind.LINK_NOT_ALLOWLISTED), FIRST),
            ),
        ),
        DemoScenario(
            "digital_arrest", "gavel",
            "डिजिटल अरेस्ट कॉल (रिकॉर्डिंग)", "Digital arrest call (recording)",
            "रिकॉर्ड की गई कॉल के बयान एक-एक करके जांचे जाते हैं; जोखिम हर बयान के साथ बढ़ता है।",
            "Statements of a recorded call are checked one by one through the recording pipeline; risk rises with each statement.",
            listOf(
                DemoStep(FIRST, Source.RECORDING, "", "Namaste, main Mumbai se Inspector Verma bol raha hoon.", Label.SAFE),
                DemoStep(CALL_GAP, Source.RECORDING, "", "Aapke naam par ek parcel pakda gaya hai jisme drugs mile hain.", Label.SUSPICIOUS,
                    setOf(FlagKind.UNVERIFIED_DELIVERY)),
                DemoStep(CALL_GAP, Source.RECORDING, "", "Aapke khilaf FIR darj hui hai aur warrant jaari hua hai.", Label.SUSPICIOUS),
                DemoStep(CALL_GAP, Source.RECORDING, "", "Aap abhi digital arrest mein hain, call mat kaatna.", Label.SCAM),
                DemoStep(CALL_GAP, Source.RECORDING, "", "Kisi ko mat batana aur safe account mein paisa transfer karo.", Label.SCAM),
            ),
        ),
        DemoScenario(
            "kyc_link", "link",
            "KYC लिंक: नकली बनाम असली", "KYC link: fake vs genuine",
            "आम नंबर से KYC का लिंक अनजान साइट पर जाता है। बैंक के हेडर से आया संदेश .bank.in लिंक पर जाता है: कोई चेतावनी नहीं।",
            "A KYC SMS from a normal number links to an unknown site. A message from the bank's header links to a .bank.in site: not flagged.",
            listOf(
                sms("9800000070", "Dear customer, your KYC has expired. Update immediately: http://kyc-update.example/verify", Label.SUSPICIOUS,
                    setOf(FlagKind.NON_DLT_SENDER, FlagKind.LINK_NOT_ALLOWLISTED), FIRST),
                sms("VM-EXMPLB", "Dear customer, your debit card renewal is complete. Details: https://netbanking.examplebank.bank.in/card", Label.SAFE),
            ),
        ),
        DemoScenario(
            "genuine_otp", "verified",
            "असली बैंक OTP बनाम OTP मांगना", "Genuine bank OTP vs OTP ask",
            "बैंक के हेडर से 'OTP किसी को न बताएं' वाला SMS सुरक्षित है। कॉल पर OTP मांगना ठगी है।",
            "A bank-header SMS saying 'do not share' is safe. A caller asking you to read the OTP out is a scam.",
            listOf(
                sms("VM-SBIINB", "Your OTP is 48XXXX. Do not share it with anyone.", Label.SAFE, emptySet(), FIRST),
                call("9800000080", "Sir aapke phone pe ek OTP aaya hoga, woh jaldi bata dijiye", Label.SCAM),
            ),
        ),
        DemoScenario(
            "fake_qr", "qr_code",
            "नकली QR: नाम नहीं मिलता", "Fake QR: name does not match",
            "QR में दुकान 'Priya Stores' है पर आपको 'Sharma Kirana' बताया गया था। नाम मिलने पर वही QR ठीक है।",
            "The QR pays 'Priya Stores' but you were told 'Sharma Kirana'. The same QR with a matching name is fine.",
            listOf(
                DemoStep(FIRST, Source.PASTE, "", "upi://pay?pa=priya.stores@ybl&pn=Priya%20Stores&am=499", Label.SCAM,
                    kind = StepKind.QR, arg = "Sharma Kirana"),
                DemoStep(GAP, Source.PASTE, "", "upi://pay?pa=priya.stores@ybl&pn=Priya%20Stores&am=499", Label.SAFE,
                    kind = StepKind.QR, arg = "Priya Stores"),
            ),
        ),
        DemoScenario(
            "family_code", "family_restroom",
            "परिवार कोड", "Family code",
            "जोड़ी बनाए दो फोन एक ही 6 अंकों का कोड दिखाते हैं। असली रिश्तेदार का कोड मिलता है, नकली का नहीं।",
            "Two paired phones show the same 6-digit code. The real relative's code matches, an impostor's does not.",
            listOf(
                DemoStep(FIRST, Source.CAPTION, "9800000090", "Papa, naye number se bol raha hoon, mera family code {code} hai.",
                    Label.SAFE, kind = StepKind.FAMILY, arg = "match"),
                DemoStep(GAP, Source.CAPTION, "9800000091", "Papa, accident ho gaya, mera family code {code} hai, turant paise bhejo.",
                    Label.SUSPICIOUS, kind = StepKind.FAMILY, arg = "mismatch"),
            ),
        ),
    )

    fun byId(id: String): DemoScenario? = ALL.firstOrNull { it.id == id }
}
