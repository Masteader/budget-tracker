import asyncio
import os
import re
import logging
from typing import Optional, List, Dict, Tuple
import litellm
from utils import litellm_model

_HISTORY_MAX_TURNS = 6
_HISTORY_MAX_CHARS = 2000


def _sanitize_history(history: Optional[List[Dict[str, str]]]) -> List[Dict[str, str]]:
    """
    Client-supplied history may only contribute 'user' and 'assistant' turns. Passing the
    client's `role` through verbatim let a caller inject extra 'system' messages and override
    the support prompt.
    """
    clean: List[Dict[str, str]] = []
    for h in (history or [])[-_HISTORY_MAX_TURNS:]:
        if not isinstance(h, dict):
            continue
        text = h.get("content") or h.get("text") or ""
        if not isinstance(text, str) or not text.strip():
            continue
        is_assistant = h.get("role") == "assistant" or h.get("isUser") is False
        clean.append({"role": "assistant" if is_assistant else "user", "content": text[:_HISTORY_MAX_CHARS]})
    return clean

logger = logging.getLogger(__name__)

SUPPORT_EMAIL = "fmscoinfo@fmsco.com.sa"

SUPPORT_SYSTEM_PROMPTS = {
    "ar": """You are the AI Support Assistant for the Budget Tracker mobile application for Saudi households.
You provide clear, friendly, and practical guidance in warm, professional Saudi Arabic.
App capabilities:
1. Receipt Scanner: Multi-page photos & Saudi ZATCA QR codes (TLV). Automatic OCR line-items.
2. Voice & Dialect: Saudi colloquial speech or text (e.g. 'قهوة 16 ريال وحلا 12') and affordability checks ('أقدر أشتري آيباد بـ 1200؟').
3. Salary Cycles: {payday_fact}
4. Recurring Bills & BNPL: {bills_fact}
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
3. Salary Cycles: {payday_fact}
4. Recurring Bills & BNPL: {bills_fact}
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
3. Salary Cycles: {payday_fact}
4. Recurring Bills & BNPL: {bills_fact}
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

# Facts that depend on the household are filled per request (product review 3.1 / "Stop doing":
# the prompts hard-coded a 27th payday and a 400 SAR Iqama fee, wrong for most households).
PAYDAY_FACTS = {
    "ar": {
        "generic": (
            "Each household chooses its own payday (any day of the month) in household settings. "
            "A cycle runs from one payday to the day before the next, with the "
            "household's carry-over rule and a daily burn-rate. Do not assume a payday day."
        ),
        "known": (
            "This household's payday is day {day} of each month; its cycle runs from day {day} to the "
            "day before the next payday, with the household's carry-over rule and a daily burn-rate. "
            "An admin can change it in household settings."
        ),
    },
    "en": {
        "generic": (
            "Each household chooses its own payday (any day of the month) in household settings. "
            "A cycle runs from one payday to the day before the next, with the "
            "household's carry-over rule and daily burn-rate pacing. Do not assume a payday day."
        ),
        "known": (
            "This household's payday is day {day} of each month; its cycle runs from day {day} to the "
            "day before the next payday, with the household's carry-over rule and daily burn-rate "
            "pacing. An admin can change it in household settings."
        ),
    },
    "ur": {
        "generic": (
            "ہر گھرانہ اپنی تنخواہ کا دن خود منتخب کرتا ہے (مہینے کا کوئی بھی دن)۔ سائیکل ایک تنخواہ "
            "کے دن سے اگلی تنخواہ سے ایک دن پہلے تک چلتا ہے۔ تنخواہ کا کوئی دن فرض نہ کریں۔"
        ),
        "known": (
            "اس گھرانے کی تنخواہ کا دن ہر ماہ کی {day} تاریخ ہے؛ سائیکل {day} تاریخ سے اگلی تنخواہ سے ایک دن پہلے "
            "تک چلتا ہے۔ ایڈمن اسے گھرانے کی سیٹنگز میں بدل سکتا ہے۔"
        ),
    },
}
BILLS_FACTS = {
    "ar": "Track the household's own recurring bills (rent, electricity, internet, phone, government fees) with "
          "1-tap payments, plus Tabby/Tamara installments. Amounts are whatever the household entered; never "
          "quote a fee amount.",
    "en": "Track the household's own recurring bills (rent, electricity, internet, phone, government fees) with "
          "1-tap payments, plus Tabby/Tamara installments. Amounts are whatever the household entered; never "
          "quote a fee amount.",
    "ur": "گھرانے کے اپنے بار بار آنے والے بل (کرایہ، بجلی، انٹرنیٹ، فون، سرکاری فیس) ایک ٹیپ ادائیگی کے ساتھ، اور "
          "Tabby/Tamara اقساط۔ رقم وہی ہے جو گھرانے نے درج کی؛ کوئی فیس کی رقم نہ بتائیں۔",
}
FALLBACK_PAYDAY = {
    "ar": " (يوم {day} من كل شهر)",
    "en": " (day {day} of each month)",
    "ur": " (ہر ماہ کی {day} تاریخ)",
}


def household_payday_day(household_id: Optional[str]) -> Optional[int]:
    """The household's payday (households.payday_day), or None without a household / on failure."""
    if not household_id:
        return None
    try:
        from supabase_client import get_household_payday

        return int(get_household_payday(household_id))
    except Exception as exc:
        logger.warning("Support chat: payday of the household unavailable (%s); answering generically.", exc)
        return None


def build_support_prompt(lang_key: str, payday_day: Optional[int]) -> str:
    facts = PAYDAY_FACTS[lang_key]
    payday_fact = facts["known"].format(day=payday_day) if payday_day else facts["generic"]
    return SUPPORT_SYSTEM_PROMPTS[lang_key].format(payday_fact=payday_fact, bills_fact=BILLS_FACTS[lang_key])


def general_fallback(lang_key: str, payday_day: Optional[int]) -> str:
    payday = FALLBACK_PAYDAY[lang_key].format(day=payday_day) if payday_day else ""
    return FALLBACK_MESSAGES[lang_key]["general"].format(payday=payday)


FALLBACK_MESSAGES = {
    "ar": {
        "escalation": "نعتذر عن هذه المشكلة! يمكنك التواصل مباشرة مع المطور عبر الزر أدناه وسيتم فتح بريدك الإلكتروني مع كافة تفاصيل المشكلة.",
        "general": "أهلاً بك في مركز المساعدة والدعم الذكي! يمكنك الاستفسار عن فواتيرك، دورة الرواتب{payday}، فواتير الأقساط، أو كيفية مسح الفواتير.",
    },
    "en": {
        "escalation": "We apologize for the inconvenience! You can contact the developer directly using the button below to send full diagnostic details.",
        "general": "Welcome to Budget Tracker Support! Feel free to ask about your bills, salary cycle{payday}, installment plans, or receipt scanning.",
    },
    "ur": {
        "escalation": "اس تکلیف کے لیے معذرت خواہ ہیں! آپ نیچے دیے گئے بٹن کے ذریعے ڈویلپر سے براہ راست رابطہ کر سکتے ہیں۔",
        "general": "بجٹ ٹریکر سپورٹ میں خوش آمدید! آپ اپنے بلوں، تنخواہ کے سائیکل{payday}، اقساط، یا رسید اسکین کرنے کے بارے میں دریافت کر سکتے ہیں۔",
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
    # The route verified the caller's membership before passing household_id.
    payday_day = await asyncio.to_thread(household_payday_day, household_id) if household_id else None

    if api_key or os.environ.get("LITELLM_MODEL"):
        try:
            model = litellm_model()
            messages = [{"role": "system", "content": build_support_prompt(lang_key, payday_day)}]
            messages.extend(_sanitize_history(history))
            messages.append({"role": "user", "content": message})

            # litellm.completion is synchronous network I/O: run it in a worker thread so a
            # multi-second LLM call does not stall every other request on the event loop.
            response = await asyncio.to_thread(
                litellm.completion,
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
            reply = general_fallback(lang_key, payday_day)

    return reply, escalate, summary
