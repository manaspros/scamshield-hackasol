from datetime import date

from scamshield_ml.cluster import cluster_records


def test_T4_4_newCampaignAlerts():
    batch = []
    patterns = {
        "OTP": ["share otp", "send code", "verification code"],
        "KYC": ["kyc expires", "verify account", "update kyc"],
    }
    for scam_type, phrases in patterns.items():
        for i in range(6):
            batch.append(
                {
                    "scam_type": scam_type,
                    "triggers": [
                        phrases[i % len(phrases)],
                        f"common {scam_type.lower()}",
                    ],
                    "source": "synthetic",
                    "date": f"2026-11-{10 + i:02d}",
                }
            )
    for i in range(5):
        batch.append(
            {
                "scam_type": "OTHER",
                "triggers": [
                    "quantum parcel beacon",
                    "wallet resonance",
                    f"novel marker {i % 2}",
                ],
                "source": "export",
                "date": f"2026-11-{15 + i:02d}",
            }
        )

    summaries = cluster_records(batch, as_of=date(2026, 11, 23), min_recent_members=3)
    alerts = [item for item in summaries if item["is_new_campaign"]]

    assert alerts
    assert any(
        item["dominant_type"] == "OTHER" and item["size"] >= 3 for item in alerts
    )
    assert all(
        not item["is_new_campaign"]
        for item in summaries
        if item["dominant_type"] in patterns
    )
