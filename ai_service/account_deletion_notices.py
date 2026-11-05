"""Emails about a scheduled account deletion, in Arabic, English and Urdu.

An account holder's email is in the language of their request. A household member's is in all
three (Arabic, then English, then Urdu): members have no stored language of their own.

The names are the ones public.list_account_deletion_notices_due returns. Plain text, no links: the
app is where a deletion is cancelled, and a link in a deletion email is what a phishing copy would
imitate.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional, Union

from mail_service import OutboundEmail
from utils import RIYADH_TZ

DEFAULT_LOCALE = "ar"

_TEMPLATES = {
    "holder_t7": {
        "en": (
            "Qawam Money: your account will be deleted on {date}",
            "Your Qawam Money account is scheduled for permanent deletion on {date}.\n\n"
            "Signing in does not cancel this. To keep your account, open the app, go to Settings and "
            "choose to cancel the deletion before that date.\n\n"
            "If you want a copy of your data, export it before then.\n\n"
            "If you did not ask for this, cancel it in the app and change your password.\n",
        ),
        "ar": (
            "قوام المال: سيُحذف حسابك بتاريخ {date}",
            "حسابك في قوام المال مجدول للحذف النهائي بتاريخ {date}.\n\n"
            "تسجيل الدخول وحده لا يلغي الحذف. إذا أردت الاحتفاظ بحسابك، افتح التطبيق وادخل الإعدادات "
            "واختر إلغاء الحذف قبل هذا التاريخ.\n\n"
            "إذا أردت نسخة من بياناتك، صدّرها قبل ذلك.\n\n"
            "إذا لم تطلب هذا، ألغِ الحذف من التطبيق وغيّر كلمة المرور.\n",
        ),
        "ur": (
            "قوام المال: آپ کا اکاؤنٹ {date} کو حذف ہو جائے گا",
            "قوام المال میں آپ کا اکاؤنٹ {date} کو مستقل طور پر حذف ہونا طے ہے۔\n\n"
            "صرف سائن ان کرنے سے حذف منسوخ نہیں ہوتا۔ اکاؤنٹ رکھنا ہو تو ایپ کھولیں، سیٹنگز میں جائیں اور "
            "اس تاریخ سے پہلے حذف منسوخ کریں۔\n\n"
            "اگر آپ کو اپنے ڈیٹا کی نقل چاہیے تو اس سے پہلے ایکسپورٹ کر لیں۔\n\n"
            "اگر آپ نے یہ درخواست نہیں کی تو ایپ سے حذف منسوخ کریں اور اپنا پاس ورڈ بدل لیں۔\n",
        ),
    },
    "holder_t1": {
        "en": (
            "Qawam Money: last reminder, your account will be deleted on {date}",
            "This is the last reminder. Your Qawam Money account will be permanently deleted on {date}.\n\n"
            "Signing in does not cancel this. To keep your account, open the app, go to Settings and "
            "choose to cancel the deletion now.\n\n"
            "If you want a copy of your data, export it today.\n",
        ),
        "ar": (
            "قوام المال: تذكير أخير، سيُحذف حسابك بتاريخ {date}",
            "هذا آخر تذكير. سيُحذف حسابك في قوام المال نهائياً بتاريخ {date}.\n\n"
            "تسجيل الدخول وحده لا يلغي الحذف. إذا أردت الاحتفاظ بحسابك، افتح التطبيق وادخل الإعدادات "
            "واختر إلغاء الحذف الآن.\n\n"
            "إذا أردت نسخة من بياناتك، صدّرها اليوم.\n",
        ),
        "ur": (
            "قوام المال: آخری یاد دہانی، آپ کا اکاؤنٹ {date} کو حذف ہو جائے گا",
            "یہ آخری یاد دہانی ہے۔ قوام المال میں آپ کا اکاؤنٹ {date} کو مستقل طور پر حذف ہو جائے گا۔\n\n"
            "صرف سائن ان کرنے سے حذف منسوخ نہیں ہوتا۔ اکاؤنٹ رکھنا ہو تو ایپ کھولیں، سیٹنگز میں جائیں اور "
            "ابھی حذف منسوخ کریں۔\n\n"
            "اگر آپ کو اپنے ڈیٹا کی نقل چاہیے تو آج ہی ایکسپورٹ کر لیں۔\n",
        ),
    },
    "holder_completion": {
        "en": (
            "Qawam Money: your account has been deleted",
            "Your Qawam Money account has been deleted, and you can no longer sign in with it.\n\n"
            "Entries you added to households that still exist stay there, shown as \"Deleted member\", "
            "with your notes and receipt images removed.\n",
        ),
        "ar": (
            "قوام المال: تم حذف حسابك",
            "تم حذف حسابك في قوام المال، ولم يعد بإمكانك تسجيل الدخول به.\n\n"
            "ما أضفته في المنازل التي ما زالت قائمة يبقى فيها باسم \"عضو محذوف\"، مع إزالة ملاحظاتك "
            "وصور فواتيرك.\n",
        ),
        "ur": (
            "قوام المال: آپ کا اکاؤنٹ حذف ہو گیا ہے",
            "قوام المال میں آپ کا اکاؤنٹ حذف ہو گیا ہے اور اب آپ اس سے سائن ان نہیں کر سکتے۔\n\n"
            "جو اندراجات آپ نے موجود گھرانوں میں کیے تھے وہ وہاں \"حذف شدہ رکن\" کے نام سے باقی رہیں گے، "
            "آپ کے نوٹس اور رسیدوں کی تصاویر ہٹا دی گئی ہیں۔\n",
        ),
    },
    "member_marked": {
        "en": (
            "Qawam Money: a household you belong to will be deleted on {date}",
            "A household you belong to in Qawam Money is scheduled for deletion on {date}, at the request "
            "of the person who manages it.\n\n"
            "On that date all its data is removed, including your accounts and entries in that household. "
            "Your own account stays, and you can still sign in.\n\n"
            "Export anything you want to keep before that date.\n",
        ),
        "ar": (
            "قوام المال: سيُحذف منزل أنت عضو فيه بتاريخ {date}",
            "منزل أنت عضو فيه في قوام المال مجدول للحذف بتاريخ {date}، بطلب من مديره.\n\n"
            "في ذلك التاريخ تُحذف كل بياناته، ومنها حساباتك ومصروفاتك المسجلة في هذا المنزل. "
            "حسابك أنت يبقى، وتستطيع تسجيل الدخول كالمعتاد.\n\n"
            "صدّر ما تريد الاحتفاظ به قبل هذا التاريخ.\n",
        ),
        "ur": (
            "قوام المال: جس گھرانے کے آپ رکن ہیں وہ {date} کو حذف ہو جائے گا",
            "قوام المال میں جس گھرانے کے آپ رکن ہیں اس کے منتظم کی درخواست پر وہ {date} کو حذف ہونا طے ہے۔\n\n"
            "اس تاریخ کو اس کا سارا ڈیٹا ہٹا دیا جائے گا، جس میں اس گھرانے میں آپ کے اکاؤنٹس اور اندراجات بھی شامل ہیں۔ "
            "آپ کا اپنا اکاؤنٹ برقرار رہے گا اور آپ سائن ان کر سکیں گے۔\n\n"
            "جو کچھ رکھنا چاہتے ہیں اسے اس تاریخ سے پہلے ایکسپورٹ کر لیں۔\n",
        ),
    },
    "member_t7": {
        "en": (
            "Qawam Money: reminder, a household you belong to will be deleted on {date}",
            "Reminder: a household you belong to in Qawam Money will be deleted on {date}.\n\n"
            "All its data will be removed, including your accounts and entries in that household. "
            "Your own account stays, and you can still sign in.\n\n"
            "Export anything you want to keep before that date.\n",
        ),
        "ar": (
            "قوام المال: تذكير، سيُحذف منزل أنت عضو فيه بتاريخ {date}",
            "تذكير: سيُحذف منزل أنت عضو فيه في قوام المال بتاريخ {date}.\n\n"
            "ستُحذف كل بياناته، ومنها حساباتك ومصروفاتك المسجلة في هذا المنزل. "
            "حسابك أنت يبقى، وتستطيع تسجيل الدخول كالمعتاد.\n\n"
            "صدّر ما تريد الاحتفاظ به قبل هذا التاريخ.\n",
        ),
        "ur": (
            "قوام المال: یاد دہانی، جس گھرانے کے آپ رکن ہیں وہ {date} کو حذف ہو جائے گا",
            "یاد دہانی: قوام المال میں جس گھرانے کے آپ رکن ہیں وہ {date} کو حذف ہو جائے گا۔\n\n"
            "اس کا سارا ڈیٹا ہٹا دیا جائے گا، جس میں اس گھرانے میں آپ کے اکاؤنٹس اور اندراجات بھی شامل ہیں۔ "
            "آپ کا اپنا اکاؤنٹ برقرار رہے گا اور آپ سائن ان کر سکیں گے۔\n\n"
            "جو کچھ رکھنا چاہتے ہیں اسے اس تاریخ سے پہلے ایکسپورٹ کر لیں۔\n",
        ),
    },
}

NOTICES = tuple(_TEMPLATES)

# Members have no stored language, and the request's locale is the requester's, so a member gets
# every language, Arabic first.
TRILINGUAL_NOTICES = ("member_marked", "member_t7")
TRILINGUAL_ORDER = ("ar", "en", "ur")
_SUBJECT_SEPARATOR = " / "
_BODY_SEPARATOR = "\n----------\n\n"


def _riyadh_date(value: Union[str, datetime, None]) -> str:
    if value is None:
        return ""
    parsed = value if isinstance(value, datetime) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(RIYADH_TZ).strftime("%Y-%m-%d")


def compose(notice: str, locale: Optional[str], scheduled_for: Union[str, datetime, None] = None) -> OutboundEmail:
    """The email for ``notice``. A holder's is in their locale, an unknown one getting Arabic. A
    member's is in Arabic, English and Urdu, in that order, whatever ``locale`` is. An unknown
    notice raises ValueError."""
    languages = _TEMPLATES.get(notice)
    if languages is None:
        raise ValueError("unknown account deletion notice")
    date = _riyadh_date(scheduled_for)
    if notice in TRILINGUAL_NOTICES:
        parts = [languages[lang] for lang in TRILINGUAL_ORDER]
        subject = _SUBJECT_SEPARATOR.join(s for s, _ in parts)
        body = _BODY_SEPARATOR.join(b for _, b in parts)
    else:
        subject, body = languages.get(locale or "", languages[DEFAULT_LOCALE])
    return OutboundEmail(subject=subject.replace("{date}", date), body=body.replace("{date}", date))
