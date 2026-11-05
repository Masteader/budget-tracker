/**
 * The account deletion page's own logic, kept free of React so it can be run and tested alone
 * (ai_service/tests/test_account_deletion_web_logic.py runs this file with Node).
 */

/**
 * The words the server accepts, before folding. request_account_deletion folds both sides with
 * public.account_deletion_fold_confirmation (supabase/migrations/20261105000800_*), and
 * foldConfirmation below is the same five steps, so the page never accepts what the server
 * refuses, or the reverse.
 */
export const ACCEPTED_CONFIRMATION_WORDS = ['delete', 'حذف', 'حذف کریں'] as const;

// 2. Dropped: zero-width space, non-joiner and joiner, bidi embeddings and isolates, BOM.
const REMOVED = /[\u200B-\u200D\u202A-\u202E\u2066-\u2069\uFEFF]/g;
// 3. A space: PostgreSQL's \s (tab, newline, vertical tab, form feed, carriage return, space),
// then the Unicode spaces and the two direction marks. JavaScript's \s is wider, so it is not used.
const SPACES = /[\t\n\v\f\r \u0085\u00A0\u1680\u2000-\u200A\u200E\u200F\u2028\u2029\u202F\u205F\u3000]/g;
// 4. Urdu letters as an Arabic keyboard types them.
const LETTERS: Record<string, string> = {
  'ک': 'ك', // keheh -> kaf
  'ی': 'ي', // Farsi yeh -> yeh
  'ں': 'ن', // noon ghunna -> noon
  'ى': 'ي', // alef maksura -> yeh
};

/** account_deletion_fold_confirmation, step for step. */
export function foldConfirmation(value: string): string {
  return value
    .normalize('NFC') // 1
    .replace(REMOVED, '') // 2
    .replace(SPACES, ' ') // 3
    .replace(/[کیںى]/g, (letter) => LETTERS[letter]) // 4
    .replace(/ {2,}/g, ' ') // 5: one space, trimmed, lowercased
    .replace(/^ +| +$/g, '')
    .toLowerCase();
}

const ACCEPTED = new Set(ACCEPTED_CONFIRMATION_WORDS.map(foldConfirmation));

/** Whether the server will accept this typed word. */
export function isAcceptedConfirmation(value: string): boolean {
  const folded = foldConfirmation(value);
  return folded !== '' && ACCEPTED.has(folded);
}

export type DeletionStatusName = 'none' | 'scheduled' | 'processing' | 'failed';

/**
 * What the signed-in page shows for the status the server returned. can_cancel is the
 * server's word on whether anything was deleted yet: while it is true, Cancel is offered,
 * whatever the status.
 */
export type DeletionView =
  | 'schedule' // no deletion: the form to request one
  | 'pending' // scheduled, with its date and Cancel
  | 'starting' // processing, nothing deleted yet: Cancel
  | 'stopped' // failed before deleting anything: Cancel
  | 'inProgress' // processing, data already being deleted: no Cancel
  | 'stoppedPartway'; // failed after deleting some data: no Cancel

export function deletionView(deletion: { status: DeletionStatusName; can_cancel: boolean }): DeletionView {
  if (deletion.status === 'none') return 'schedule';
  if (deletion.can_cancel) {
    if (deletion.status === 'failed') return 'stopped';
    if (deletion.status === 'processing') return 'starting';
    return 'pending';
  }
  return deletion.status === 'failed' ? 'stoppedPartway' : 'inProgress';
}

export type CancellableView = Extract<DeletionView, 'pending' | 'starting' | 'stopped'>;

/** Whether the view offers the Cancel button. */
export function offersCancel(view: DeletionView): view is CancellableView {
  return view === 'pending' || view === 'starting' || view === 'stopped';
}
