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



# Round-3 coverage gaps: appended (own rng, own ids) so the original rows stay byte-stable.
# gap -> lang -> 3 scam templates; _R3_SAFE: gap -> lang -> 2 hard-negative look-alikes.
_R3 = {
    "ELECTRICITY_BILL": {
        "en": [
            "Electricity power will be disconnected tonight 9:30 pm due to unpaid bill. Call officer {phone} now.",
            "Your last month bill is pending. Update at {domain} or supply is cut today.",
            "Power board notice: pay {amount} via this link {domain} to avoid disconnection.",
        ],
        "hi": [
            "बिजली बिल बकाया है, आज रात 9:30 बजे कनेक्शन कटेगा। अधिकारी {phone} को अभी कॉल करें।",
            "पिछले महीने का बिल बाकी है। {domain} पर अपडेट करें वरना आज बिजली कटेगी।",
            "बिजली बोर्ड सूचना: कनेक्शन कटने से बचने के लिए {domain} पर {amount} भरें।",
        ],
        "hinglish": [
            "Bijli bill pending hai, aaj raat 9:30 baje connection kat jayega. Officer {phone} ko abhi call karo.",
            "Pichle mahine ka bill baaki hai. {domain} par update karo warna aaj light cut hogi.",
            "Bijli board notice: disconnection se bachne ke liye {domain} par {amount} pay karo.",
        ],
    },
    "SIM_SWAP": {
        "en": [
            "Your SIM will be blocked in 24 hours. Complete telecom KYC at {domain} or call {phone}.",
            "SIM upgrade to 5G: reply with the code {otp} to activate the new SIM.",
            "Your number will be deactivated. Share the SIM swap code {otp} with our agent to keep it.",
        ],
        "hi": [
            "आपका सिम 24 घंटे में बंद होगा। {domain} पर टेलीकॉम KYC करें या {phone} पर कॉल करें।",
            "5G सिम अपग्रेड: नया सिम चालू करने के लिए कोड {otp} भेजें।",
            "आपका नंबर बंद होगा। चालू रखने के लिए सिम स्वैप कोड {otp} एजेंट को दें।",
        ],
        "hinglish": [
            "Aapka SIM 24 ghante mein block hoga. {domain} par telecom KYC karein ya {phone} par call karein.",
            "5G SIM upgrade: naya SIM activate karne ke liye code {otp} bhejein.",
            "Aapka number deactivate hoga. Rakhne ke liye SIM swap code {otp} agent ko do.",
        ],
    },
    "CUSTOMER_CARE": {
        "en": [
            "For your refund call customer care {phone} and install the support app from {domain}.",
            "Helpline agent: install the remote screen share app at {domain} to get your {amount} refund.",
            "Your order refund failed. Contact the toll free number {phone} found on {domain} now.",
        ],
        "hi": [
            "रिफंड के लिए कस्टमर केयर {phone} पर कॉल करें और {domain} से सपोर्ट ऐप लें।",
            "हेल्पलाइन एजेंट: {amount} रिफंड पाने के लिए {domain} से स्क्रीन शेयर ऐप इंस्टॉल करें।",
            "आपका रिफंड विफल रहा। अभी टोल फ्री नंबर {phone} पर संपर्क करें।",
        ],
        "hinglish": [
            "Refund ke liye customer care {phone} par call karein aur {domain} se support app lo.",
            "Helpline agent: {amount} refund ke liye {domain} se screen share app install karo.",
            "Aapka order refund fail hua. Abhi toll free number {phone} par contact karein.",
        ],
    },
    "UPI_COLLECT": {
        "en": [
            "A collect request of {amount} is pending. Enter your UPI PIN to receive the money.",
            "Approve the collect request from {upi} and enter your PIN to get {amount} cashback.",
            "To receive {amount} accept the UPI request and put your PIN to confirm.",
        ],
        "hi": [
            "{amount} का कलेक्ट अनुरोध बाकी है। पैसे पाने के लिए UPI PIN डालें।",
            "{upi} का कलेक्ट अनुरोध मंजूर करें और {amount} कैशबैक पाने को PIN डालें।",
            "{amount} पाने के लिए UPI अनुरोध स्वीकार करें और PIN से पुष्टि करें।",
        ],
        "hinglish": [
            "{amount} ki collect request pending hai. Paise receive karne ke liye UPI PIN enter karo.",
            "{upi} ki collect request approve karo aur {amount} cashback ke liye PIN daalo.",
            "{amount} lene ke liye UPI request accept karo aur PIN se confirm karo.",
        ],
    },
    "SEXTORTION": {
        "en": [
            "I recorded your video call. Pay {amount} or I will send it to all your contacts.",
            "We have your private photos. Transfer {amount} to {upi} or they go public.",
            "Your video is saved. Pay now to {upi} else it will be posted to your family.",
        ],
        "hi": [
            "तुम्हारी वीडियो कॉल रिकॉर्ड है। {amount} दो वरना सभी संपर्कों को भेज दूंगा।",
            "हमारे पास आपकी निजी फोटो हैं। {upi} पर {amount} भेजें वरना सार्वजनिक होंगी।",
            "आपका वीडियो सेव है। अभी {upi} पर पैसे भेजें वरना परिवार को भेजा जाएगा।",
        ],
        "hinglish": [
            "Tumhari video call record hai. {amount} do warna saare contacts ko bhej dunga.",
            "Hamare paas aapki private photos hain. {upi} par {amount} bhejo warna public hongi.",
            "Aapka video saved hai. Abhi {upi} par paise bhejo warna family ko post hoga.",
        ],
    },
    "LOTTERY": {
        "en": [
            "Congratulations! You won a KBC lottery of {amount}. Pay a release fee at {domain} to claim.",
            "Lucky draw winner! Your number won a prize. Send {amount} tax to claim it.",
            "You are selected for a free prize. Share details and pay {amount} processing at {domain}.",
        ],
        "hi": [
            "बधाई! आपने KBC लॉटरी जीती है। इनाम पाने के लिए {domain} पर {amount} रिलीज फीस दें।",
            "लकी ड्रॉ विजेता! आपके नंबर ने इनाम जीता। पाने के लिए {amount} टैक्स भेजें।",
            "आप मुफ्त इनाम के लिए चुने गए हैं। जानकारी दें और {domain} पर {amount} दें।",
        ],
        "hinglish": [
            "Congratulations! Aapne KBC lottery jeeti hai. Claim ke liye {domain} par {amount} release fee do.",
            "Lucky draw winner! Aapke number ne prize jeeta. Lene ke liye {amount} tax bhejo.",
            "Aap free prize ke liye select hue hain. Details do aur {domain} par {amount} pay karo.",
        ],
    },
    "FAMILY_EMERGENCY": {
        "en": [
            "Papa it's me, I am in an accident and in hospital. Send {amount} to {upi} urgently, don't tell mom.",
            "Mom I lost my phone, this is my new number {phone}. Need {amount} now, an emergency.",
            "Your brother is in trouble with the police. Send {amount} to {upi} immediately.",
        ],
        "hi": [
            "पापा मैं हूं, एक्सीडेंट हो गया है और अस्पताल में हूं। {upi} पर {amount} तुरंत भेजो, मम्मी को मत बताना।",
            "मम्मी मेरा फोन खो गया, यह मेरा नया नंबर {phone} है। अभी {amount} चाहिए, इमरजेंसी है।",
            "आपका भाई पुलिस के चक्कर में फंसा है। {upi} पर तुरंत {amount} भेजें।",
        ],
        "hinglish": [
            "Papa main hoon, accident ho gaya hai aur hospital mein hoon. {upi} par {amount} turant bhejo, mummy ko mat batana.",
            "Mummy mera phone kho gaya, ye mera naya number {phone} hai. Abhi {amount} chahiye, emergency hai.",
            "Aapka bhai police ke chakkar mein hai. {upi} par turant {amount} bhejo.",
        ],
    },
    "PHISHING_LINK": {
        "en": [
            "Your account is suspended. Verify now at {domain}/login to restore access.",
            "Package fee pending, confirm your card at bit.ly/example-pay within 1 hour.",
            "Security alert: unusual sign in. Re-enter your password at {domain} immediately.",
        ],
        "hi": [
            "आपका खाता निलंबित है। पहुंच बहाल करने के लिए {domain}/login पर सत्यापित करें।",
            "पैकेज शुल्क बाकी है, 1 घंटे में bit.ly/example-pay पर कार्ड की पुष्टि करें।",
            "सुरक्षा चेतावनी: असामान्य साइन इन। तुरंत {domain} पर पासवर्ड दोबारा डालें।",
        ],
        "hinglish": [
            "Aapka account suspend hai. Access wapas pane ke liye {domain}/login par verify karo.",
            "Package fee pending hai, 1 ghante mein bit.ly/example-pay par card confirm karo.",
            "Security alert: unusual sign in. Turant {domain} par password dobara daalo.",
        ],
    },
    "JOB": {
        "en": [
            "Part-time task job: like and review videos, earn {amount} daily. Join the group at {domain}.",
            "Complete 3 simple tasks, get paid. Deposit {amount} first to unlock the next task.",
            "Work from home like-review job. Message {phone} on chat; a {amount} fee is required.",
        ],
        "hi": [
            "पार्ट-टाइम टास्क जॉब: वीडियो लाइक और रिव्यू करें, रोज़ {amount} कमाएं। {domain} पर समूह जुड़ें।",
            "3 आसान टास्क पूरे करें, पैसे पाएं। अगला टास्क खोलने को पहले {amount} जमा करें।",
            "घर से लाइक-रिव्यू जॉब। चैट पर {phone} को मैसेज करें; {amount} शुल्क लगेगा।",
        ],
        "hinglish": [
            "Part-time task job: videos like aur review karo, roz {amount} kamao. {domain} par group join karo.",
            "3 simple tasks complete karo, paise pao. Agla task unlock karne ko pehle {amount} deposit karo.",
            "Ghar se like-review job. Chat par {phone} ko message karo; {amount} fee lagegi.",
        ],
    },
    "INVESTMENT": {
        "en": [
            "Join our VIP stock trading group at {domain}. Sure shot tips, guaranteed profit.",
            "Crypto trading signals: deposit {amount} and we guarantee 3x returns in a week.",
            "Our expert will trade for you. Fund the account at {domain} for assured daily returns.",
        ],
        "hi": [
            "{domain} पर हमारे VIP शेयर ट्रेडिंग ग्रुप से जुड़ें। पक्के टिप्स, गारंटीड मुनाफा।",
            "क्रिप्टो ट्रेडिंग सिग्नल: {amount} जमा करें, एक हफ्ते में 3 गुना की गारंटी।",
            "हमारा एक्सपर्ट आपके लिए ट्रेड करेगा। पक्के रोज़ मुनाफे को {domain} पर खाता भरें।",
        ],
        "hinglish": [
            "{domain} par hamare VIP stock trading group se judo. Sure shot tips, guaranteed profit.",
            "Crypto trading signals: {amount} deposit karo, ek hafte mein 3x returns ki guarantee.",
            "Hamara expert aapke liye trade karega. Pakke daily returns ke liye {domain} par account fund karo.",
        ],
    },
    "LOAN_APP": {
        "en": [
            "Repay the loan today or we will message all your contacts that you are a fraud.",
            "Instant loan app: a {amount} insurance fee is needed before disbursal. Pay at {domain}.",
            "Your overdue loan photo will be shared with your family and contacts unless you pay {amount}.",
        ],
        "hi": [
            "आज लोन चुकाएं वरना आपके सभी संपर्कों को बताएंगे कि आप धोखेबाज हैं।",
            "इंस्टेंट लोन ऐप: रकम जारी होने से पहले {amount} बीमा शुल्क दें। {domain} पर भरें।",
            "बकाया लोन के लिए {amount} न दिया तो आपकी फोटो परिवार और संपर्कों को भेजी जाएगी।",
        ],
        "hinglish": [
            "Aaj loan repay karo warna saare contacts ko bolenge ki aap fraud ho.",
            "Instant loan app: disbursal se pehle {amount} insurance fee do. {domain} par pay karo.",
            "Overdue loan ke {amount} nahi diye to aapki photo family aur contacts ko bheji jayegi.",
        ],
    },
    "COURIER_CUSTOMS": {
        "en": [
            "FedEx: parcel in your name contains illegal drugs. Call {phone} or the case goes to police.",
            "Your courier {track} was seized at customs. Pay {amount} clearance at {domain}.",
            "Parcel {track} flagged for banned items. Speak to the customs officer on {phone} now.",
        ],
        "hi": [
            "FedEx: आपके नाम के पार्सल में अवैध ड्रग्स मिले हैं। {phone} पर कॉल करें वरना केस पुलिस को जाएगा।",
            "आपका कूरियर {track} कस्टम में जब्त है। {domain} पर {amount} क्लियरेंस दें।",
            "पार्सल {track} में प्रतिबंधित सामान मिला। अभी {phone} पर कस्टम अधिकारी से बात करें।",
        ],
        "hinglish": [
            "FedEx: aapke naam ke parcel mein illegal drugs mile hain. {phone} par call karo warna case police ko jayega.",
            "Aapka courier {track} customs mein seize hai. {domain} par {amount} clearance do.",
            "Parcel {track} mein banned items mile. Abhi {phone} par customs officer se baat karo.",
        ],
    },
    "FAKE_QR": {
        "en": [
            "OLX buyer here: scan this QR to receive the {amount} payment for your item.",
            "I will pay you {amount} advance. Scan my QR code and enter your PIN to get it.",
            "Buyer paying for your listing. Scan the QR sent to you and approve to receive {amount}.",
        ],
        "hi": [
            "OLX खरीदार: आपके सामान के {amount} पाने के लिए यह QR स्कैन करें।",
            "मैं {amount} एडवांस दूंगा। मेरा QR स्कैन करें और पाने के लिए PIN डालें।",
            "आपकी लिस्टिंग का भुगतान हो रहा है। {amount} पाने को भेजा QR स्कैन कर मंजूर करें।",
        ],
        "hinglish": [
            "OLX buyer hoon: aapke item ke {amount} lene ke liye ye QR scan karo.",
            "Main {amount} advance dunga. Mera QR scan karo aur lene ke liye PIN daalo.",
            "Aapki listing ka payment ho raha hai. {amount} lene ko bheja QR scan karke approve karo.",
        ],
    },
}

_R3_SAFE = {
    "ELECTRICITY_BILL": {
        "en": [
            "Your electricity bill of {amount} is due on the 15th. Pay in the official app or at the counter.",
            "Power board: bill generated for {amount}. Last date is next week; no action needed today.",
        ],
        "hi": [
            "आपका {amount} का बिजली बिल 15 तारीख को देय है। आधिकारिक ऐप या काउंटर पर भरें।",
            "बिजली बोर्ड: {amount} का बिल बना है। अंतिम तिथि अगले हफ्ते है; आज कुछ करना नहीं।",
        ],
        "hinglish": [
            "Aapka {amount} ka bijli bill 15 tarikh ko due hai. Official app ya counter par bharein.",
            "Bijli board: {amount} ka bill bana hai. Last date agle hafte hai; aaj kuch karna nahi.",
        ],
    },
    "SIM_SWAP": {
        "en": [
            "Your recharge of {amount} is successful. Plan valid for 28 days. Thank you.",
            "Telecom: your plan expires in 3 days. Recharge in the official app whenever you wish.",
        ],
        "hi": [
            "आपका {amount} का रिचार्ज सफल रहा। प्लान 28 दिन वैध है। धन्यवाद।",
            "टेलीकॉम: आपका प्लान 3 दिन में खत्म होगा। जब चाहें आधिकारिक ऐप में रिचार्ज करें।",
        ],
        "hinglish": [
            "Aapka {amount} ka recharge successful raha. Plan 28 din valid hai. Dhanyavaad.",
            "Telecom: aapka plan 3 din mein expire hoga. Jab chahein official app mein recharge karein.",
        ],
    },
    "CUSTOMER_CARE": {
        "en": [
            "Your support ticket 4821 is received. We will reply within 2 working days. No action needed.",
            "Customer care: your complaint is registered. Track it in the official app.",
        ],
        "hi": [
            "आपका सपोर्ट टिकट 4821 मिल गया है। हम 2 कार्य दिवस में उत्तर देंगे। कुछ करना नहीं।",
            "कस्टमर केयर: आपकी शिकायत दर्ज हो गई है। आधिकारिक ऐप में ट्रैक करें।",
        ],
        "hinglish": [
            "Aapka support ticket 4821 mil gaya hai. Hum 2 working days mein reply karenge. Kuch karna nahi.",
            "Customer care: aapki complaint register ho gayi hai. Official app mein track karein.",
        ],
    },
    "UPI_COLLECT": {
        "en": [
            "Rs 500 credited to your account via UPI from {upi}. No action needed.",
            "{bank}: {amount} received in your account by UPI. Balance updated.",
        ],
        "hi": [
            "{upi} से UPI द्वारा आपके खाते में Rs 500 जमा हुए। कुछ करना नहीं है।",
            "{bank}: UPI से आपके खाते में {amount} प्राप्त हुए। बैलेंस अपडेट हो गया।",
        ],
        "hinglish": [
            "{upi} se UPI dwara aapke account mein Rs 500 credit hue. Kuch karna nahi hai.",
            "{bank}: UPI se aapke account mein {amount} mile. Balance update ho gaya.",
        ],
    },
    "SEXTORTION": {
        "en": [
            "Hi, family video call at 8 pm tonight? Everyone will join.",
            "Sharing the trip photos from the weekend. Let me know which ones you like.",
        ],
        "hi": [
            "नमस्ते, आज रात 8 बजे परिवार की वीडियो कॉल करें? सब जुड़ेंगे।",
            "सप्ताहांत की ट्रिप की फोटो भेज रहा हूं। बताना कौन सी पसंद आईं।",
        ],
        "hinglish": [
            "Hi, aaj raat 8 baje family video call karein? Sab join honge.",
            "Weekend ki trip ki photos bhej raha hoon. Batana kaun si pasand aayi.",
        ],
    },
    "LOTTERY": {
        "en": [
            "Society raffle draw is on Sunday at the club. Entry is free for residents, nothing to pay.",
            "Your store loyalty points are now {amount} off your next bill, applied automatically.",
        ],
        "hi": [
            "सोसाइटी रैफल ड्रॉ रविवार को क्लब में है। निवासियों के लिए प्रवेश मुफ्त है, कुछ देना नहीं।",
            "आपके स्टोर लॉयल्टी पॉइंट अगले बिल पर {amount} छूट के रूप में अपने आप लगेंगे।",
        ],
        "hinglish": [
            "Society raffle draw Sunday ko club mein hai. Residents ke liye entry free hai, kuch pay nahi karna.",
            "Aapke store loyalty points agle bill par {amount} off ke roop mein automatically lagenge.",
        ],
    },
    "FAMILY_EMERGENCY": {
        "en": [
            "Mom, I reached the hostel safely. Will call after dinner.",
            "Papa, the exam went well. Coming home on Friday, no need to send anything.",
        ],
        "hi": [
            "मम्मी, मैं हॉस्टल सही से पहुंच गया। खाने के बाद कॉल करूंगा।",
            "पापा, परीक्षा अच्छी रही। शुक्रवार को घर आ रहा हूं, कुछ भेजने की जरूरत नहीं।",
        ],
        "hinglish": [
            "Mummy, main hostel safely pahunch gaya. Dinner ke baad call karunga.",
            "Papa, exam achha gaya. Friday ko ghar aa raha hoon, kuch bhejne ki zarurat nahi.",
        ],
    },
    "PHISHING_LINK": {
        "en": [
            "Your statement is ready. Log in at onlinesbi.sbi to view it. We never ask for your password.",
            "Official update: manage your account only on onlinesbi.sbi or the bank app.",
        ],
        "hi": [
            "आपका स्टेटमेंट तैयार है। देखने के लिए onlinesbi.sbi पर लॉगिन करें। हम पासवर्ड कभी नहीं मांगते।",
            "आधिकारिक सूचना: खाता केवल onlinesbi.sbi या बैंक ऐप पर संभालें।",
        ],
        "hinglish": [
            "Aapka statement ready hai. Dekhne ke liye onlinesbi.sbi par login karein. Hum password kabhi nahi maangte.",
            "Official update: account sirf onlinesbi.sbi ya bank app par manage karein.",
        ],
    },
    "JOB": {
        "en": [
            "Interview letter: your interview is on Monday 11 am at our office. Carry your resume. No fee.",
            "HR: thank you for applying. Your interview is scheduled for Tuesday. No payment is required.",
        ],
        "hi": [
            "साक्षात्कार पत्र: आपका इंटरव्यू सोमवार 11 बजे हमारे कार्यालय में है। रिज्यूमे लाएं। कोई शुल्क नहीं।",
            "HR: आवेदन के लिए धन्यवाद। आपका इंटरव्यू मंगलवार को है। कोई भुगतान नहीं।",
        ],
        "hinglish": [
            "Interview letter: aapka interview Monday 11 baje hamare office mein hai. Resume layein. Koi fee nahi.",
            "HR: apply karne ke liye dhanyavaad. Aapka interview Tuesday ko hai. Koi payment nahi.",
        ],
    },
    "INVESTMENT": {
        "en": [
            "Your SIP of {amount} was debited today. Mutual fund returns are market linked and not guaranteed.",
            "Fund statement for the month is ready in the official app. No action needed.",
        ],
        "hi": [
            "आपकी {amount} की SIP आज कटी। म्यूचुअल फंड रिटर्न बाजार आधारित हैं, गारंटीड नहीं।",
            "इस महीने का फंड स्टेटमेंट आधिकारिक ऐप में तैयार है। कुछ करना नहीं।",
        ],
        "hinglish": [
            "Aapki {amount} ki SIP aaj debit hui. Mutual fund returns market linked hain, guaranteed nahi.",
            "Is mahine ka fund statement official app mein ready hai. Kuch karna nahi.",
        ],
    },
    "LOAN_APP": {
        "en": [
            "{bank}: your EMI of {amount} is due on the 5th. Autopay is active, no action needed.",
            "Loan statement ready. Your next instalment is {amount}. Pay at the branch or official app.",
        ],
        "hi": [
            "{bank}: आपकी {amount} की EMI 5 तारीख को देय है। ऑटोपे चालू है, कुछ करना नहीं।",
            "लोन स्टेटमेंट तैयार है। अगली किस्त {amount} है। शाखा या आधिकारिक ऐप में भरें।",
        ],
        "hinglish": [
            "{bank}: aapki {amount} ki EMI 5 tarikh ko due hai. Autopay active hai, kuch karna nahi.",
            "Loan statement ready hai. Agli kist {amount} hai. Branch ya official app mein bharein.",
        ],
    },
    "COURIER_CUSTOMS": {
        "en": [
            "Courier update: parcel {track} is out for delivery today. No payment is due.",
            "Your order {track} has been dispatched and will arrive on Friday. Pay nothing on delivery.",
        ],
        "hi": [
            "कूरियर सूचना: पार्सल {track} आज डिलीवरी के लिए निकला है। कोई भुगतान बाकी नहीं।",
            "आपका ऑर्डर {track} भेज दिया गया है, शुक्रवार तक पहुंचेगा। डिलीवरी पर कुछ न दें।",
        ],
        "hinglish": [
            "Courier update: parcel {track} aaj out for delivery hai. Koi payment due nahi.",
            "Aapka order {track} dispatch ho gaya hai, Friday tak aayega. Delivery par kuch pay na karein.",
        ],
    },
    "FAKE_QR": {
        "en": [
            "Payment of {amount} received at Example Store via QR. No action needed.",
            "UPI QR payment of {amount} successful. Thank you for shopping.",
        ],
        "hi": [
            "Example Store पर QR से {amount} का भुगतान मिला। कुछ करना नहीं।",
            "UPI QR से {amount} का भुगतान सफल रहा। खरीदारी के लिए धन्यवाद।",
        ],
        "hinglish": [
            "Example Store par QR se {amount} ka payment mila. Kuch karna nahi.",
            "UPI QR se {amount} ka payment successful raha. Shopping ke liye dhanyavaad.",
        ],
    },
}


def generate_rows(seed: int = 0) -> list[Row]:
    """Generate stable unique template rows in deterministic shuffled order."""
    rng = random.Random(seed)
    rows: list[Row] = []
    for lang in sorted(LANGUAGES):
        for scam_type in sorted(_TEXT[lang]):
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
    # Round-3 pass uses its own rng so the draws above (and their splits) stay stable.
    rng = random.Random(seed + 3)
    slots_r3 = {**_SLOTS, "phone": ["98XXXXXX10", "97XXXXXX20", "99XXXXXX30"]}
    for lang in sorted(LANGUAGES):
        for gap in _R3:
            for kind, table in (("SCAM", _R3), ("SAFE", _R3_SAFE)):
                for index, template in enumerate(table[gap][lang]):
                    slots = {key: rng.choice(values) for key, values in slots_r3.items()}
                    stem = f"{lang}_{gap.lower()}_r3" if kind == "SCAM" else f"{lang}_safe_r3_{gap.lower()}"
                    rows.append(
                        validate_row(
                            {
                                "text": template.format(**slots),
                                "label": kind,
                                "lang": lang,
                                "scam_type": gap if kind == "SCAM" else "",
                                "template_id": f"{stem}_{index + 1:02d}",
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
