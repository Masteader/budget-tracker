"""HTML pages the API serves itself.

- ``/``: the ``web_app`` production build committed in ``static/index.html`` (the only landing
  page). If that build is missing (a broken deploy), a tiny inline page is served instead so the
  domain still says what it is and how to reach us.
- ``/auth/confirm`` and ``/auth/callback``: the page Supabase email-confirmation links open.
"""

from pathlib import Path

STATIC_INDEX = Path(__file__).resolve().parent / "static" / "index.html"

CONTACT_EMAIL = "fmscoinfo@fmsco.com.sa"

# Shown only when static/index.html is missing. No external resources, no claims.
FALLBACK_LANDING_HTML = f"""<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Budget Tracker • ميزانية الأسرة</title>
  <style>
    body{{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
      padding:24px;box-sizing:border-box;background:#f4fafb;color:#0c2530;
      font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;line-height:1.7;text-align:center}}
    main{{max-width:520px}}
    h1{{font-size:1.6rem;margin:0 0 .5rem}}
    p{{margin:.25rem 0}}
    a{{color:#006575}}
    @media (prefers-color-scheme: dark){{body{{background:#0b1528;color:#e8f4f6}} a{{color:#6fe3ef}}}}
  </style>
</head>
<body>
  <main>
    <h1>Budget Tracker • ميزانية الأسرة</h1>
    <p>اعرف كم باقي لك لين الراتب، وسجّل مصروفك بالكلام أو بتصوير الفاتورة.</p>
    <p lang="en" dir="ltr">Household budgeting by salary cycle for Saudi families and shared homes.</p>
    <p>للتواصل · Contact: <a href="mailto:{CONTACT_EMAIL}">{CONTACT_EMAIL}</a></p>
  </main>
</body>
</html>"""

AUTH_CONFIRM_HTML = f"""<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>تأكيد البريد الإلكتروني | Budget Tracker</title>
  <style>
    *{{box-sizing:border-box;margin:0;padding:0}}
    body{{background:#080709;color:#F0EDE8;font-family:'Cairo',system-ui,Tahoma,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px}}
    .card{{background:#121117;border:1px solid rgba(255,255,255,0.08);border-radius:24px;padding:56px 32px;max-width:480px;width:100%;text-align:center}}
    .ring{{width:72px;height:72px;border-radius:50%;background:rgba(52,211,153,0.12);border:2px solid #34D399;display:flex;align-items:center;justify-content:center;font-size:32px;margin:0 auto 28px}}
    h1{{font-size:24px;font-weight:900;margin-bottom:12px;color:#fff}}
    p{{font-size:15px;color:#B5AFA8;line-height:1.75;margin-bottom:32px}}
    .btn{{display:inline-flex;align-items:center;gap:8px;background:#C2783C;color:#fff;font-size:15px;font-weight:700;padding:14px 32px;border-radius:12px;text-decoration:none}}
    .btn:hover,.btn:focus-visible{{background:#A8652F}}
    .sub{{margin-top:24px;font-size:13px;color:#9E9790}}
    .sub a{{color:#E09A5C;text-decoration:none}}
  </style>
</head>
<body>
  <div class="card">
    <div class="ring" aria-hidden="true">✓</div>
    <h1 id="title">تم تأكيد البريد الإلكتروني بنجاح</h1>
    <p id="desc">حسابك مفعّل وجاهز. ارجع للتطبيق وسجّل دخولك.</p>
    <a id="action-btn" href="budgettracker://login" class="btn">فتح التطبيق</a>
    <div class="sub">مشكلة؟ تواصل معنا على <a href="mailto:{CONTACT_EMAIL}">{CONTACT_EMAIL}</a></div>
  </div>
  <script>
    (function() {{
      try {{
        var hash = window.location.hash || '';
        var search = window.location.search || '';
        var isRecovery = hash.indexOf('type=recovery') !== -1 || search.indexOf('type=recovery') !== -1;
        if (isRecovery) {{
          document.title = 'إعادة تعيين كلمة المرور | Budget Tracker';
          var h1 = document.getElementById('title');
          var desc = document.getElementById('desc');
          var btn = document.getElementById('action-btn');
          if (h1) h1.textContent = 'استعادة كلمة المرور';
          if (desc) desc.textContent = 'تم التحقق من رابط الاستعادة. اضغط على الزر أدناه لفتح التطبيق وتعيين كلمة المرور الجديدة.';
          if (btn) {{
            btn.textContent = 'فتح التطبيق لتعيين كلمة المرور';
            btn.href = 'budgettracker://reset-password' + (hash || search);
            window.location.href = btn.href;
          }}
        }}
      }} catch (_) {{}}
    }})();
  </script>
</body>
</html>"""


def get_landing_page_html() -> str:
    """The committed web_app build, or the inline fallback when the build is missing."""
    try:
        return STATIC_INDEX.read_text(encoding="utf-8")
    except FileNotFoundError:
        return FALLBACK_LANDING_HTML


def get_auth_confirm_html() -> str:
    return AUTH_CONFIRM_HTML


def get_auth_confirmed_html() -> str:
    return AUTH_CONFIRM_HTML
