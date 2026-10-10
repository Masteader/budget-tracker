import os
import re
import logging
from typing import Optional, List, Dict, Tuple
import litellm

logger = logging.getLogger(__name__)

SUPPORT_EMAIL = "fmscoinfo@fmsco.com.sa"

SUPPORT_SYSTEM_PROMPTS = {
    "ar": """You are the AI Support Assistant for the Budget Tracker mobile application for Saudi households.
You provide clear, friendly, and practical guidance in warm, professional Saudi Arabic.
App capabilities:
1. Receipt Scanner: Multi-page photos & Saudi ZATCA QR codes (TLV). Automatic OCR line-items.
2. Voice & Dialect: Saudi colloquial speech or text (e.g. 'قهوة 16 ريال وحلا 12') and affordability checks ('أقدر أشتري آيباد بـ 1200؟').
3. Salary Cycles: 27th of Gregorian month payday, automatic carryovers, daily burn-rate.
4. Recurring Bills & BNPL: Track rent, SEC electricity, fiber, Iqama fees (400 SAR) with 1-tap payments, plus Tabby/Tamara installments.
5. 2D Attribution: Tracks who paid ('paid_by') vs who benefited ('beneficiary') with instant net settlements.
6. Privacy: Zero SMS interception, zero SMS permissions.

If the user reports a bug, app crash, unresolvable defect, or explicitly asks to contact the developer:
Set ESCALATE: TRUE and provide a one-line SUMMARY of their issue. Otherwise set ESCALATE: FALSE.
Format your output as:
[ESCALATE: TRUE|FALSE]
[SUMMARY: brief summary or NONE]
<Your helpful conversational reply to the user in Arabic>
""",
    "en": """You are the AI Support Assistant for the Budget Tracker mobile application for Saudi households.
You provide clear, friendly, and practical guidance in English.
App capabilities:
1. Receipt Scanner: Multi-page photos & Saudi ZATCA QR codes (TLV). Automatic OCR line-items.
2. Voice & Dialect: Natural language text/voice expense logging and affordability checks.
3. Salary Cycles: 27th of Gregorian month payday, automatic carryovers, daily burn-rate pacing.
4. Recurring Bills & BNPL: Track rent, SEC electricity, fiber, Iqama fees (400 SAR) with 1-tap payments, plus Tabby/Tamara installments.
5. 2D Attribution: Tracks who paid ('paid_by') vs who benefited ('beneficiary') with instant net settlements.
6. Privacy: Zero SMS interception, zero SMS permissions.

If the user reports a bug, app crash, unresolvable defect, or explicitly asks to contact the developer:
Set ESCALATE: TRUE and provide a one-line SUMMARY of their issue. Otherwise set ESCALATE: FALSE.
Format your output as:
[ESCALATE: TRUE|FALSE]
[SUMMARY: brief summary or NONE]
<Your helpful conversational reply to the user in English>
""",
    "ur": """You are the AI Support Assistant for the Budget Tracker mobile application for Saudi households.
You provide clear, friendly, and practical guidance in Urdu (اردو زبان میں واضح اور دوستانہ رہنمائی).
App capabilities:
1. Receipt Scanner: رسید اسکینر، تصاویر اور سعودی ZATCA QR کوڈز (TLV) خودکار OCR۔
2. Voice & Dialect: آواز یا ٹیکسٹ سے اخراجات کا فوری اندراج۔
3. Salary Cycles: تنخواہ کا سائیکل (ہر ماہ کی 27 تاریخ)، خودکار بچت اور روزانہ خرچ کی رفتار۔
4. Recurring Bills & BNPL: کرایہ، بجلی، فائبر، اقامہ فیس (400 ریال) اور Tabby/Tamara اقساط کا انتظام۔
5. 2D Attribution: کس نے ادا کیا اور کس کے لیے، خودکار حساب کتاب۔
6. Privacy: کوئی SMS مداخلت نہیں، مکمل پرائیویسی۔

If the user reports a bug, app crash, unresolvable defect, or explicitly asks to contact the developer:
Set ESCALATE: TRUE and provide a one-line SUMMARY of their issue. Otherwise set ESCALATE: FALSE.
Format your output as:
[ESCALATE: TRUE|FALSE]
[SUMMARY: brief summary or NONE]
<Your helpful conversational reply to the user in Urdu>
"""
}

FALLBACK_MESSAGES = {
    "ar": {
        "escalation": "نعتذر عن هذه المشكلة! يمكنك التواصل مباشرة مع المطور عبر الزر أدناه وسيتم فتح بريدك الإلكتروني مع كافة تفاصيل المشكلة.",
        "general": "أهلاً بك في مركز المساعدة والدعم الذكي! يمكنك الاستفسار عن فواتيرك، دورة الرواتب (27 من كل شهر)، فواتير الأقساط، أو كيفية مسح الفواتير.",
    },
    "en": {
        "escalation": "We apologize for the inconvenience! You can contact the developer directly using the button below to send full diagnostic details.",
        "general": "Welcome to Budget Tracker Support! Feel free to ask about your bills, salary cycle (27th of each month), installment plans, or receipt scanning.",
    },
    "ur": {
        "escalation": "اس تکلیف کے لیے معذرت خواہ ہیں! آپ نیچے دیے گئے بٹن کے ذریعے ڈویلپر سے براہ راست رابطہ کر سکتے ہیں۔",
        "general": "بجٹ ٹریکر سپورٹ میں خوش آمدید! آپ اپنے بلوں، تنخواہ کے سائیکل (ہر ماہ کی 27 تاریخ)، اقساط، یا رسید اسکین کرنے کے بارے میں دریافت کر سکتے ہیں۔",
    }
}


async def handle_support_query(
    message: str,
    household_id: Optional[str] = None,
    user_id: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
    language: Optional[str] = "ar",
) -> Tuple[str, bool, Optional[str]]:
    lang_key = (language or "ar").lower()
    if lang_key not in SUPPORT_SYSTEM_PROMPTS:
        lang_key = "ar"

    # Escalation keyword heuristics
    bug_keywords = [
        "crash", "bug", "broken", "error", "defect", "developer",
        "contact developer", "خلل", "عطل", "مشكلة في النظام",
        "تواصل مع المطور", "المبرمج", "فشل", "خرابی", "مسئلہ", "ڈویلپر"
    ]
    is_escalation_candidate = any(kw in message.lower() for kw in bug_keywords)

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY", "")
    if api_key and not os.environ.get("GEMINI_API_KEY"):
        os.environ["GEMINI_API_KEY"] = api_key

    reply = ""
    escalate = is_escalation_candidate
    summary = message[:100] if is_escalation_candidate else None

    if api_key or os.environ.get("LITELLM_MODEL"):
        try:
            model = os.environ.get("LITELLM_MODEL", "gemini/gemini-2.0-flash")
            messages = [{"role": "system", "content": SUPPORT_SYSTEM_PROMPTS[lang_key]}]

            # Add context history if present
            if history:
                for h in history[-6:]:  # Keep last 6 exchanges for context
                    role = h.get("role") or ("user" if h.get("isUser") is True else "assistant")
                    text = h.get("content") or h.get("text") or ""
                    if text:
                        messages.append({"role": role, "content": text})

            messages.append({"role": "user", "content": message})

            response = litellm.completion(
                model=model,
                messages=messages,
                temperature=0.3,
            )

            raw_text = response.choices[0].message.content or ""
            if "[ESCALATE: TRUE]" in raw_text:
                escalate = True
            m_sum = re.search(r"\[SUMMARY:\s*(.+?)\]", raw_text)
            if m_sum and m_sum.group(1).strip() != "NONE":
                summary = m_sum.group(1).strip()

            clean_reply = re.sub(r"\[ESCALATE:\s*(TRUE|FALSE)\]", "", raw_text)
            clean_reply = re.sub(r"\[SUMMARY:\s*.+?\]", "", clean_reply).strip()
            if clean_reply:
                reply = clean_reply
        except Exception as exc:
            logger.error("LiteLLM support query failed: %s", exc, exc_info=True)

    if not reply:
        fallbacks = FALLBACK_MESSAGES.get(lang_key, FALLBACK_MESSAGES["ar"])
        if is_escalation_candidate:
            reply = fallbacks["escalation"]
            escalate = True
            summary = message[:100]
        else:
            reply = fallbacks["general"]

    return reply, escalate, summary
