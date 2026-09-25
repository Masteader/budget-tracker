import time
import json
from send_simulated_sms import send_sms

transactions = [
    {
        "category_expected": "OPEX-HEALTH",
        "label": "Health",
        "merchant": "Al Dawaa Pharmacy",
        "amount": 142.30,
        "sms": "شراء عبر نقاط البيع\nبطاقة مدى: **8821\nمبلغ: 142.30 رس\nلدى: صيدلية الدواء Al Dawaa Pharmacy\nفي: 2026-09-25 19:22\nالرصيد: 3,222.20 رس",
        "sender": "AlRajhi"
    },
    {
        "category_expected": "OPEX-GROCERY",
        "label": "Groceries",
        "merchant": "Danube Supermarket",
        "amount": 315.75,
        "sms": "شراء عبر نقاط البيع\nبطاقة مدى: **8821\nمبلغ: 315.75 رس\nلدى: أسواق الدانوب DANUBE\nفي: 2026-09-25 19:23\nالرصيد: 2,906.45 رس",
        "sender": "AlRajhi"
    },
    {
        "category_expected": "OPEX-ENTERTAINMENT",
        "label": "Entertainment",
        "merchant": "MUVI Cinemas",
        "amount": 120.00,
        "sms": "شراء عبر الإنترنت\nبطاقة مدى: **8821\nمبلغ: 120.00 رس\nلدى: MUVI CINEMAS\nفي: 2026-09-25 19:24\nالرصيد: 2,786.45 رس",
        "sender": "AlRajhi"
    }
]

def main():
    results = []
    for t in transactions:
        print("\n" + "="*60)
        print(f"--> Sending {t['label']} Transaction ({t['merchant']} - SAR {t['amount']})")
        res = send_sms(t["sms"], sender=t["sender"])
        results.append(res)
        time.sleep(1)

    print("\n" + "="*60)
    print("ALL 3 TRANSACTIONS SIMULATED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
