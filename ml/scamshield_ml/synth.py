"""Deterministic synthetic messages for ScamShield training and evaluation."""

from __future__ import annotations

import argparse
import csv
import json
import random
from collections.abc import Iterable
from pathlib import Path

from scamshield_ml.data import COLUMNS, LANGUAGES, SCAM_TYPES, Row, validate_row
from scamshield_ml.prompt import build_prompt, target_for_row


# Each language has four message variants for every scam type, then four hard negatives.
_TEXT = {
    "en": {
        "OTP": [
            "{bank} support needs your OTP {otp}; reply with the code to keep access.",
            "Your {bank} account is locked. Send OTP {otp} to this agent to unlock it.",
            "Share verification code {otp} with our {bank} representative to stop a transfer.",
            "To cancel a suspicious login, send OTP {otp} to the security agent now.",
        ],
        "KYC": [
            "{bank} KYC expires today. Verify at {domain} to keep your account active.",
            "Update KYC now at {domain} or {bank} access will be blocked.",
            "Your {bank} account needs KYC. Submit details at {domain}.",
            "Final KYC reminder: confirm your {bank} profile at {domain} today.",
        ],
        "DIGITAL_ARREST": [
            "An officer says your ID is linked to a case. Stay on video and pay {amount} now.",
            "Police case notice: transfer {amount} for verification or face digital arrest.",
            "Your parcel case is under investigation. Do not disconnect; pay {amount}.",
            "A caller claiming to be an officer demands {amount} to clear your name.",
        ],
        "COURIER_CUSTOMS": [
            "Customs fee {amount} due for parcel {track}. Pay at {domain} to release it.",
            "Your delivery is held. Pay a customs charge of {amount} at {domain}.",
            "Courier notice: parcel {track} blocked until {amount} is paid online.",
            "Customs clearance failed. Submit payment at {domain} for your parcel.",
        ],
        "FAKE_QR": [
            "Scan this QR to receive {amount}; enter your UPI PIN to complete.",
            "Refund {amount} ready. Scan the QR and approve the collect request.",
            "To claim your prize, scan the QR and authorize the payment request.",
            "Scan to accept {amount}; the app will ask you to confirm with your PIN.",
        ],
        "LOAN_APP": [
            "Instant loan approved. Install {domain} and pay {amount} processing fee.",
            "Get a quick loan today; send {amount} upfront to unlock funds.",
            "Loan disbursal pending. Pay the verification fee of {amount} now.",
            "Your loan limit is ready. Install our app from {domain} and share contacts.",
        ],
        "INVESTMENT": [
            "Guaranteed daily returns! Invest {amount} through {domain} today.",
            "Double your money in a week. Join our investment group at {domain}.",
            "Exclusive shares offer: send {amount} now for a guaranteed profit.",
            "Risk-free crypto returns promised. Deposit at {domain} before midnight.",
        ],
        "JOB": [
            "You are selected for a remote job. Pay {amount} for registration at {domain}.",
            "Earn from home: submit ID and a {amount} training fee to start.",
            "Job offer confirmed. Buy the starter kit for {amount} using {domain}.",
            "Recruitment deposit {amount} required today to reserve your position.",
        ],
        "MISTAKEN_TRANSFER": [
            "I sent {amount} to you by mistake. Please return it to {upi} immediately.",
            "Wrong transfer of {amount}; send it back to this UPI handle: {upi}.",
            "Please refund {amount} now. I transferred it to your number accidentally.",
            "A payment of {amount} was sent in error. Return it to {upi} right away.",
        ],
        "OTHER": [
            "Your account is compromised. Install support app from {domain} now.",
            "Claim a free gift by sharing your bank details at {domain}.",
            "Urgent: pay {amount} to avoid account suspension. Visit {domain}.",
            "You won a reward. Send your details and a {amount} release fee.",
        ],
    },
    "hi": {
        "OTP": [
            "{bank} सहायता को आपका OTP {otp} चाहिए; खाता चालू रखने को कोड भेजें।",
            "आपका {bank} खाता बंद है। खोलने के लिए एजेंट को OTP {otp} दें।",
            "ट्रांसफर रोकने के लिए {otp} सत्यापन कोड {bank} प्रतिनिधि को भेजें।",
            "संदिग्ध लॉगिन रद्द करने के लिए सुरक्षा एजेंट को OTP {otp} भेजें।",
        ],
        "KYC": [
            "{bank} KYC आज समाप्त होगी। खाता चालू रखने के लिए {domain} पर अपडेट करें।",
            "अभी {domain} पर KYC करें वरना {bank} सेवा बंद होगी।",
            "आपके {bank} खाते के लिए KYC जरूरी है। {domain} पर जानकारी दें।",
            "अंतिम KYC सूचना: आज {domain} पर {bank} प्रोफाइल सत्यापित करें।",
        ],
        "DIGITAL_ARREST": [
            "एक अधिकारी कहता है कि ID केस से जुड़ी है। वीडियो पर रहें और {amount} दें।",
            "पुलिस केस सूचना: डिजिटल गिरफ्तारी से बचने के लिए {amount} भेजें।",
            "आपका पार्सल जांच में है। कॉल न काटें, {amount} जमा करें।",
            "अधिकारी बनकर कॉल करने वाला नाम साफ करने के लिए {amount} मांगता है।",
        ],
        "COURIER_CUSTOMS": [
            "पार्सल {track} का सीमा शुल्क {amount} बाकी है। छुड़ाने के लिए {domain} पर दें।",
            "डिलीवरी रुकी है। {domain} पर {amount} शुल्क जमा करें।",
            "कूरियर सूचना: {track} पार्सल {amount} भुगतान तक रुका है।",
            "कस्टम क्लियरेंस नहीं हुआ। पार्सल के लिए {domain} पर भुगतान करें।",
        ],
        "FAKE_QR": [
            "{amount} पाने के लिए QR स्कैन करें और UPI PIN डालें।",
            "आपका {amount} रिफंड तैयार है। QR स्कैन कर कलेक्ट अनुरोध मंजूर करें।",
            "इनाम पाने के लिए QR स्कैन करें और भुगतान अनुरोध स्वीकार करें।",
            "{amount} लेने के लिए स्कैन करें; PIN से भुगतान मंजूर करें।",
        ],
        "LOAN_APP": [
            "तुरंत लोन मंजूर। {domain} ऐप लें और {amount} प्रोसेसिंग फीस दें।",
            "जल्दी लोन पाएं; रकम जारी कराने को पहले {amount} भेजें।",
            "लोन भुगतान रुका है। {amount} सत्यापन शुल्क अभी दें।",
            "आपकी लोन सीमा तैयार है। {domain} से ऐप लें और संपर्क साझा करें।",
        ],
        "INVESTMENT": [
            "गारंटी रोज़ाना मुनाफा! आज {domain} पर {amount} निवेश करें।",
            "एक हफ्ते में पैसा दोगुना। {domain} निवेश समूह से जुड़ें।",
            "खास शेयर ऑफर: निश्चित लाभ के लिए {amount} अभी भेजें।",
            "बिना जोखिम क्रिप्टो लाभ। आधी रात से पहले {domain} पर जमा करें।",
        ],
        "JOB": [
            "घर से नौकरी के लिए चयन हुआ। {domain} पर {amount} पंजीकरण शुल्क दें।",
            "घर बैठे कमाएं: शुरू करने को ID और {amount} प्रशिक्षण शुल्क भेजें।",
            "नौकरी पक्की। {amount} की किट {domain} से खरीदें।",
            "पद रोकने के लिए आज {amount} भर्ती जमा जरूरी है।",
        ],
        "MISTAKEN_TRANSFER": [
            "गलती से {amount} आपको भेजे। कृपया {upi} पर तुरंत लौटाएं।",
            "{amount} गलत भेजे गए; इस UPI पर वापस भेजें: {upi}।",
            "कृपया {amount} अभी लौटाएं, पैसे गलती से आपके नंबर पर गए।",
            "{amount} का भुगतान भूल से हुआ। इसे {upi} पर वापस करें।",
        ],
        "OTHER": [
            "आपका खाता खतरे में है। अभी {domain} से सहायता ऐप लें।",
            "मुफ्त उपहार पाने को {domain} पर बैंक जानकारी साझा करें।",
            "तुरंत {amount} दें वरना खाता बंद होगा। {domain} खोलें।",
            "इनाम जीता है। जानकारी और {amount} रिलीज फीस भेजें।",
        ],
    },
    "hinglish": {
        "OTP": [
            "{bank} support ko aapka OTP {otp} chahiye; access ke liye code reply karein.",
            "Aapka {bank} account locked hai. Unlock karne ko agent ko OTP {otp} bhejein.",
            "Transfer rokne ke liye verification code {otp} {bank} representative ko share karein.",
            "Suspicious login cancel karne ko security agent ko OTP {otp} bhejein.",
        ],
        "KYC": [
            "{bank} KYC aaj expire hai. Account active rakhne ke liye {domain} par verify karein.",
            "Abhi {domain} par KYC update karein warna {bank} access block hoga.",
            "Aapke {bank} account ko KYC chahiye. {domain} par details bharein.",
            "Final KYC reminder: aaj {domain} par {bank} profile confirm karein.",
        ],
        "DIGITAL_ARREST": [
            "Officer bolta hai ID case se linked hai. Video par raho aur {amount} pay karo.",
            "Police case notice: digital arrest se bachne ke liye {amount} transfer karo.",
            "Aapka parcel investigation mein hai. Call mat kaato, {amount} do.",
            "Officer ban kar caller naam clear karne ke liye {amount} maangta hai.",
        ],
        "COURIER_CUSTOMS": [
            "Parcel {track} ka customs fee {amount} due hai. Release ke liye {domain} par pay karein.",
            "Delivery hold hai. {domain} par {amount} customs charge do.",
            "Courier update: {track} parcel {amount} payment tak blocked hai.",
            "Customs clearance fail. Parcel ke liye {domain} par payment submit karein.",
        ],
        "FAKE_QR": [
            "{amount} receive karne ke liye QR scan karo aur UPI PIN enter karo.",
            "{amount} refund ready hai. QR scan karke collect request approve karo.",
            "Prize claim karne ko QR scan karo aur payment request accept karo.",
            "{amount} lene ke liye scan karo; app mein PIN se approve karo.",
        ],
        "LOAN_APP": [
            "Instant loan approved. {domain} app install karo aur {amount} processing fee do.",
            "Quick loan pao; funds unlock karne ko pehle {amount} bhejo.",
            "Loan disbursal pending. {amount} verification fee abhi pay karo.",
            "Loan limit ready hai. {domain} se app lo aur contacts share karo.",
        ],
        "INVESTMENT": [
            "Guaranteed daily returns! Aaj {domain} par {amount} invest karo.",
            "Ek hafte mein paisa double. {domain} investment group join karo.",
            "Exclusive shares offer: guaranteed profit ke liye {amount} bhejo.",
            "Risk-free crypto returns. Midnight se pehle {domain} par deposit karo.",
        ],
        "JOB": [
            "Remote job ke liye select hue. {domain} par {amount} registration fee do.",
            "Ghar se kamao: start karne ko ID aur {amount} training fee bhejo.",
            "Job offer confirmed. {amount} ka starter kit {domain} se lo.",
            "Position reserve karne ko aaj {amount} recruitment deposit chahiye.",
        ],
        "MISTAKEN_TRANSFER": [
            "Galti se {amount} aapko bheje. Please {upi} par abhi return karo.",
            "{amount} wrong transfer hua; is UPI par wapas bhejo: {upi}.",
            "Please {amount} refund karo, transfer galti se aapke number par hua.",
            "{amount} payment mistake se gaya. Abhi {upi} par return karo.",
        ],
        "OTHER": [
            "Aapka account compromised hai. {domain} se support app install karo.",
            "Free gift claim karne ko {domain} par bank details share karo.",
            "Urgent: account suspend se bachne ko {amount} pay karo. {domain} visit karo.",
            "Reward jeeta hai. Details aur {amount} release fee bhejo.",
        ],
    },
}

_SAFE = {
    "en": [
        "{bank}: OTP {otp}. Do not share this code with anyone.",
        "Delivery update: parcel {track} is out for delivery. No payment is due.",
        "Your utility bill of {amount} is ready in the official app.",
        "Salary credit: {amount} deposited to account ending XXXXXX1234.",
    ],
    "hi": [
        "{bank}: OTP {otp}। इस कोड को किसी के साथ साझा न करें।",
        "डिलीवरी सूचना: पार्सल {track} आज पहुंचेगा। कोई भुगतान बाकी नहीं।",
        "आपका {amount} बिजली बिल आधिकारिक ऐप में उपलब्ध है।",
        "वेतन जमा: खाते XXXXXX1234 में {amount} जमा हुए।",
    ],
    "hinglish": [
        "{bank}: OTP {otp}. Is code ko kisi ke saath share na karein.",
        "Delivery update: parcel {track} aaj aa raha hai. Koi payment due nahi.",
        "Aapka {amount} utility bill official app mein ready hai.",
        "Salary credit: account XXXXXX1234 mein {amount} jama hue.",
    ],
}

_SLOTS = {
    "bank": ["Example Bank", "Demo Bank", "Sample Bank", "Test Bank"],
    "otp": ["123456", "654321", "246810", "135790"],
    "amount": ["₹500", "₹1,200", "₹2,500", "₹750"],
    "track": ["DEMO123", "TEST456", "SAMPLE789", "DEMO246"],
    "domain": [
        "example-bank-kyc.xyz",
        "example-parcel-check.test",
        "demo-loan-app.test",
        "sample-reward.test",
    ],
    "upi": [
        "demo.user@example",
        "sample.person@example",
        "test.receiver@example",
        "demo.payee@example",
    ],
}


def generate_rows(seed: int = 0) -> list[Row]:
    """Generate stable unique template rows in deterministic shuffled order."""
    rng = random.Random(seed)
    rows: list[Row] = []
    for lang in sorted(LANGUAGES):
        for scam_type in sorted(SCAM_TYPES):
            for index, template in enumerate(_TEXT[lang][scam_type]):
                slots = {key: rng.choice(values) for key, values in _SLOTS.items()}
                rows.append(
                    validate_row(
                        {
                            "text": template.format(**slots),
                            "label": "SCAM",
                            "lang": lang,
                            "scam_type": scam_type,
                            "template_id": f"{lang}_{scam_type.lower()}_{index + 1:02d}",
                            "source": "synthetic",
                        }
                    )
                )
        for index, template in enumerate(_SAFE[lang]):
            slots = {key: rng.choice(values) for key, values in _SLOTS.items()}
            rows.append(
                validate_row(
                    {
                        "text": template.format(**slots),
                        "label": "SAFE",
                        "lang": lang,
                        "scam_type": "",
                        "template_id": f"{lang}_safe_{index + 1:02d}",
                        "source": "synthetic",
                    }
                )
            )
    return rows


def sft_pairs(rows: Iterable[Row]) -> list[dict[str, str]]:
    return [
        {"prompt": build_prompt(row["text"]), "target": target_for_row(row)}
        for row in rows
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--sft", type=Path)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()
    rows = generate_rows(args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    if args.sft:
        args.sft.parent.mkdir(parents=True, exist_ok=True)
        with args.sft.open("w", encoding="utf-8") as file:
            for pair in sft_pairs(rows):
                file.write(json.dumps(pair, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
