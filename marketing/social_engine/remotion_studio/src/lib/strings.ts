import type {Language} from '../props';

/** The only fixed wording on screen. Everything else in a reel comes from props. */

export const TEST_WATERMARK = 'TEST, not for posting';

/** Spec Section 8.3 and D30, word for word, in both languages in every reel. */
export const ILLUSTRATIVE_EN = 'illustrative prices';
export const ILLUSTRATIVE_AR = 'أسعار توضيحية';

const LABELS = {
	badge: {ar: 'ذكاء مالي', en: 'Money smarts'},
	stopDoingThis: {ar: 'لا تسوّي كذا', en: 'Stop doing this'},
	theSmartWay: {ar: 'الطريقة الذكية', en: 'The smart way'},
} as const;

export const label = (name: keyof typeof LABELS, language: Language): string =>
	LABELS[name][language];
