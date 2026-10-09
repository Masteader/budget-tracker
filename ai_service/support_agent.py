import os
import re
from typing import Optional, List, Dict, Tuple

SUPPORT_EMAIL = "fmscoinfo@fmsco.com.sa"

SUPPORT_SYSTEM_PROMPT = """You are the AI Support Assistant for the Budget Tracker mobile application for Saudi households.
You provide clear, friendly, and practical guidance in Saudi Arabic or English.
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
<Your helpful conversational reply to the user>
"""

async def handle_support_query(
    message: str,
    household_id: Optional[str] = None,
    user_id: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
) -> Tuple[str, bool, Optional[str]]:
    # Escalation keyword heuristics
    bug_keywords = [
        "crash", "bug", "broken", "error", "defect", "developer",
        "contact developer", "خلل", "عطل", "مشكلة في النظام",
        "تواصل مع المطور", "المبرمج", "فشل"
    ]
    is_escalation_candidate = any(kw in message.lower() for kw in bug_keywords)

    api_key = os.environ.get("GOOGLE_API_KEY", "")
    reply = ""
    escalate = is_escalation_candidate
    summary = message[:100] if is_escalation_candidate else None

    if api_key:
        try:
            from google import genai
            client = genai.Client(api_key=api_key)
            prompt = f"{SUPPORT_SYSTEM_PROMPT}\n\nUser Question: {message}"
            res = client.models.generate_content(
                model="gemini-2.0-flash",
                contents=prompt,
            )
            raw_text = res.text or ""
            if "[ESCALATE: TRUE]" in raw_text:
                escalate = True
            m_sum = re.search(r"\[SUMMARY:\s*(.+?)\]", raw_text)
            if m_sum and m_sum.group(1).strip() != "NONE":
                summary = m_sum.group(1).strip()

            clean_reply = re.sub(r"\[ESCALATE:\s*(TRUE|FALSE)\]", "", raw_text)
            clean_reply = re.sub(r"\[SUMMARY:\s*.+?\]", "", clean_reply).strip()
            if clean_reply:
                reply = clean_reply
        except Exception:
            pass

    if not reply:
        if is_escalation_candidate:
            reply = "نعتذر عن هذه المشكلة! يمكنك التواصل مباشرة مع المطور عبر الزر أدناه وسيتم فتح بريدك الإلكتروني مع كافة تفاصيل المشكلة."
            escalate = True
            summary = message[:100]
        else:
            reply = (
                "أهلاً بك في تطبيق ميزانية الأسرة! يمكنك الاستفسار عن فواتيرك، "
                "دورة الرواتب (27 من كل شهر)، فواتير الأقساط، أو كيفية مسح الفواتير."
            )

    return reply, escalate, summary
