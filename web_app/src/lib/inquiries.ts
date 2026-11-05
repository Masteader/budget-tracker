// Client for the backend inquiry endpoint (POST /public/inquiries), which emails VIP
// early-access, support and account deletion requests to the developer. Success is reported only
// when the server answers 2xx: the email provider accepted the message or, for a lead or a
// deletion request, the row is stored ("captured"). submitDeletionRequest tells those two apart.

export type InquiryType = 'vip_early_access' | 'support' | 'contact' | 'account_deletion';

export interface InquiryPayload {
  type: InquiryType;
  email: string;
  name?: string;
  message?: string;
  locale?: string;
  source: 'web' | 'landing';
  /** Honeypot: must stay empty for real visitors. */
  company_website?: string;
}

export type InquiryOutcome = 'sent' | 'invalid' | 'rate_limited' | 'unavailable' | 'network';

export type InquiryFailure = Exclude<InquiryOutcome, 'sent'>;

export type DeletionRequestResult =
  | { outcome: 'sent' | 'captured'; reference: string | null }
  | { outcome: InquiryFailure };

const DEFAULT_API_BASE_URL = 'https://budget.fmsco.com.sa';

/** Public contact address shown on the page (also the mailbox the inquiries are sent from). */
export const CONTACT_EMAIL = 'fmscoinfo@fmsco.com.sa';

/**
 * VITE_API_BASE_URL selects the backend. Unset → the production API; an empty string →
 * same origin (used when the build is served by the FastAPI service itself).
 */
export function inquiryEndpoint(): string {
  const configured = import.meta.env.VITE_API_BASE_URL as string | undefined;
  const base = (configured ?? DEFAULT_API_BASE_URL).trim().replace(/\/+$/, '');
  return `${base}/public/inquiries`;
}

async function postInquiry(payload: InquiryPayload, fetchImpl: typeof fetch): Promise<Response | null> {
  try {
    return await fetchImpl(inquiryEndpoint(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(payload),
      credentials: 'omit',
    });
  } catch {
    return null;
  }
}

function failureOf(response: Response | null): InquiryFailure {
  if (!response) return 'network';
  if (response.status === 422) return 'invalid';
  if (response.status === 429) return 'rate_limited';
  return 'unavailable';
}

export async function submitInquiry(
  payload: InquiryPayload,
  fetchImpl: typeof fetch = fetch,
): Promise<InquiryOutcome> {
  const response = await postInquiry(payload, fetchImpl);
  return response?.ok ? 'sent' : failureOf(response);
}

/** The page must say which one happened: "captured" means stored, with the developer not told yet. */
export async function submitDeletionRequest(
  payload: Omit<InquiryPayload, 'type'>,
  fetchImpl: typeof fetch = fetch,
): Promise<DeletionRequestResult> {
  const response = await postInquiry({ ...payload, type: 'account_deletion' }, fetchImpl);
  if (!response?.ok) return { outcome: failureOf(response) };
  const body = (await response.json().catch(() => null)) as { status?: unknown; reference?: unknown } | null;
  return {
    outcome: body?.status === 'captured' ? 'captured' : 'sent',
    reference: typeof body?.reference === 'string' ? body.reference : null,
  };
}
