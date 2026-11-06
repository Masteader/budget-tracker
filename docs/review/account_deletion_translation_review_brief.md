# Translation review brief: account deletion

**What this is.** Qawam Money (قوام المال) is a household budgeting app for families and people sharing a home in Saudi Arabia. People track expenses, shared accounts and who owes whom. These strings are new: how someone deletes their account, what happens to their household, the emails we send about it, and some new settings and settlement wording.

**What we need.** Please read the Arabic and Urdu in `account_deletion_translation_review.csv` as a native speaker. Write any correction or comment in the `reviewer_notes` column. Don't edit the other columns, because the file is generated from the app's source and engineers apply your notes.

**Tone.** Plain, calm and respectful. This is about someone's money and a permanent deletion, so it must be exact and never alarming or salesy. Arabic should be clear modern Arabic that reads naturally in Saudi Arabia. The landing page strings (`web.landing.*`) are deliberately a little more conversational, so keep that voice there. Urdu should be everyday Urdu, with common English loanwords such as "اکاؤنٹ" kept where people really use them.

**Terms that must stay consistent everywhere.**

| Term | English | Arabic | Urdu |
|---|---|---|---|
| A person whose account was deleted | Deleted member | عضو محذوف | حذف شدہ رکن |
| The app's name | Qawam Money | قوام المال | قوام المال |
| What the husband owes his wife for shared expenses she paid (family mode) | still owed to her | مستحق لها | واجب الادا |
| She releases him from what remains | waived by her | أبرأت منه (إبراء) | معاف کر دیا (ابراء) |

Tell us if you think one of these is wrong, and we'll change it everywhere at once.

**Words that must not change without engineering.** People type a word to confirm a deletion, and the server checks for these words: `DELETE`, `حذف` and `حذف کریں`. The Urdu one uses the Urdu letters ک and ی; the server also accepts it typed on an Arabic keyboard (ك, ي, ن), and with any kind of space between the words. If you think a word should change, say so in your notes and we'll change it in the code first. Otherwise deletion stops working for those people.

**Don't change placeholders.** Anything in curly braces, such as `{date}` or `{email}`, is filled in by the app. Keep it exactly as written, with the same spelling in English letters. You can move it within the sentence.

**Good to know.**

- `where_it_appears` says whether the text is in the app, on the website or in an email. The `key` is our name for the string. It may hint at where the string is used, and you can ignore it otherwise.
- Keys ending in `.one`, `.two`, `.few`, `.many`, `.other` or `.zero` are plural forms of one sentence.
- Dates appear as `{date}`. In emails they are written like 2026-12-06.
- The emails to other members of a household (`email.member_*`), and the one to a husband whose wife is deleting her account while he still owes her (`email.creditor_owed`), go out in all three languages in one email: Arabic, then English, then Urdu, because we don't know which language each person reads. The subjects are joined with " / ". So each language's text has to make sense on its own.
- `{amount}` is a SAR amount written like 1,234.50. The `fmd_*` app strings are about that same debt after her account is gone: the household keeps one record with no name, which the husband or an admin closes as paid or as waived by her.
- The Urdu column is blank for `web.landing.*`, because that page has no Urdu. Nothing is needed there.
- Line breaks inside a cell are intentional, so please keep them.
