// Client for the backend inquiry endpoint (POST /public/inquiries), which emails VIP
// early-access and support requests to the developer. Success is reported only when the
// server answers 2xx, i.e. after the email provider accepted the message.

export type InquiryType = 'vip_early_access' | 'support' | 'contact';

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

const DEFAULT_API_BASE_URL = 'https://budget.fmsco.com.sa';

/**
 * VITE_API_BASE_URL selects the backend. Unset → the production API; an empty string →
 * same origin (used when the build is served by the FastAPI service itself).
 */
export function inquiryEndpoint(): string {
  const configured = import.meta.env.VITE_API_BASE_URL as string | undefined;
  const base = (configured ?? DEFAULT_API_BASE_URL).trim().replace(/\/+$/, '');
  return `${base}/public/inquiries`;
}

export async function submitInquiry(
  payload: InquiryPayload,
  fetchImpl: typeof fetch = fetch,
): Promise<InquiryOutcome> {
  let response: Response;
  try {
    response = await fetchImpl(inquiryEndpoint(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(payload),
      credentials: 'omit',
    });
  } catch {
    return 'network';
  }
  if (response.ok) return 'sent';
  if (response.status === 422) return 'invalid';
  if (response.status === 429) return 'rate_limited';
  return 'unavailable';
}
