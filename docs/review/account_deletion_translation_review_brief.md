# Translation review brief: account deletion

**What this is.** Qawam Money (قوام المال) is a household budgeting app for families and people sharing a home in Saudi Arabia. People track expenses, shared accounts and who owes whom. These strings are new: how someone deletes their account, what happens to their household, the emails we send about it, and some new settings and settlement wording.

**What we need.** Please read the Arabic and Urdu in `account_deletion_translation_review.csv` as a native speaker. Write any correction or comment in the `reviewer_notes` column. Don't edit the other columns, because the file is generated from the app's source and engineers apply your notes.

**Tone.** Plain, calm and respectful. This is about someone's money and a permanent deletion, so it must be exact and never alarming or salesy. Arabic should be clear modern Arabic that reads naturally in Saudi Arabia. The landing page strings (`web.landing.*`) are deliberately a little more conversational, so keep that voice there. Urdu should be everyday Urdu, with common English loanwords such as "اکاؤنٹ" kept where people really use them.

**Terms that must stay consistent everywhere.**

| Term | English | Arabic | Urdu |
|---|---|---|---|
| A person whose account was deleted | Deleted member | عضو محذوف | حذف شدہ رکن |
| The app's name | Qawam Money | قوام المال | قوام المال |

Tell us if you think one of these is wrong, and we'll change it everywhere at once.

**Words that must not change without engineering.** People type a word to confirm a deletion, and the server checks for these exact characters: `DELETE`, `حذف` and `حذف کریں`. The Urdu one uses the Urdu letters ک and ی. If you think a word should change, say so in your notes and we'll change it in the code first. Otherwise deletion stops working for those people.

**Don't change placeholders.** Anything in curly braces, such as `{date}` or `{email}`, is filled in by the app. Keep it exactly as written, with the same spelling in English letters. You can move it within the sentence.

**Good to know.**

- `where_it_appears` says whether the text is in the app, on the website or in an email. The `key` is our name for the string. It may hint at where the string is used, and you can ignore it otherwise.
- Keys ending in `.one`, `.two`, `.few`, `.many`, `.other` or `.zero` are plural forms of one sentence.
- Dates appear as `{date}`. In emails they are written like 2026-12-06.
- The Urdu column is blank for `web.landing.*`, because that page has no Urdu. Nothing is needed there.
- Line breaks inside a cell are intentional, so please keep them.
