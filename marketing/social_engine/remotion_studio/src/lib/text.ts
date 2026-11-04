import type {Digits, Language} from '../props';

/**
 * Text helpers. Nothing here cuts a word into letters: Arabic letters change shape with their
 * neighbours, so the smallest piece that is ever animated or wrapped is a whole word.
 */

const WESTERN = '0123456789';
const ARABIC_INDIC = '٠١٢٣٤٥٦٧٨٩';
const EXTENDED_ARABIC_INDIC = '۰۱۲۳۴۵۶۷۸۹';

export const localizeDigits = (text: string, digits: Digits): string =>
	text.replace(/\p{Nd}/gu, (digit) => {
		const value = [WESTERN, ARABIC_INDIC, EXTENDED_ARABIC_INDIC]
			.map((set) => set.indexOf(digit))
			.find((index) => index >= 0);
		if (value === undefined) {
			return digit;
		}
		return (digits === 'western' ? WESTERN : ARABIC_INDIC)[value] ?? digit;
	});

export const hasArabic = (text: string): boolean => /\p{Script=Arabic}/u.test(text);

const isForeignWord = (text: string, language: Language): boolean =>
	language === 'ar' ? !hasArabic(text) && /[\p{Script=Latin}\p{Nd}]/u.test(text) : hasArabic(text);

export type WordRun<T> = {direction: 'ltr' | 'rtl' | null; items: T[]};

/**
 * Words are items in a flex row, and the row runs in the reel's direction. Two English words side by
 * side in an Arabic row would then read backwards, so a run of two or more goes in its own row with
 * its own direction. The same holds for Arabic words in an English row.
 */
export const groupWordRuns = <T,>(
	items: T[],
	textOf: (item: T) => string,
	language: Language,
): WordRun<T>[] => {
	const runs: WordRun<T>[] = [];
	const foreign = language === 'ar' ? 'ltr' : 'rtl';
	let pending: T[] = [];
	const flush = () => {
		if (pending.length > 1) {
			runs.push({direction: foreign, items: pending});
		} else if (pending.length === 1) {
			runs.push({direction: null, items: pending});
		}
		pending = [];
	};
	for (const item of items) {
		if (isForeignWord(textOf(item), language)) {
			pending.push(item);
		} else {
			flush();
			runs.push({direction: null, items: [item]});
		}
	}
	flush();
	return runs;
};

export type TextRun = {text: string; isolate: boolean};

// Latin words and numbers in an Arabic line, with their own inner punctuation. Punctuation at the
// end stays outside, so it lands on the correct side of the isolated run.
const LATIN_OR_NUMBER =
	/[#@+-]?[\p{Script=Latin}\p{Nd}]+(?:[.,:'’/-][\p{Script=Latin}\p{Nd}]+)*[%٪]?/gu;
// Arabic in an English line, joined across spaces so the brand name stays one isolate.
const ARABIC_RUN =
	/\p{Script=Arabic}[\p{Script=Arabic}\p{M}ـ\u200c\u200d]*(?:\s+\p{Script=Arabic}[\p{Script=Arabic}\p{M}ـ\u200c\u200d]*)*/gu;

/** The parts of a text that need a <bdi> around them in a line of this language. */
export const splitForIsolation = (text: string, language: Language): TextRun[] => {
	const pattern = language === 'ar' ? LATIN_OR_NUMBER : ARABIC_RUN;
	const runs: TextRun[] = [];
	let position = 0;
	for (const match of text.matchAll(pattern)) {
		if (match.index > position) {
			runs.push({text: text.slice(position, match.index), isolate: false});
		}
		runs.push({text: match[0], isolate: true});
		position = match.index + match[0].length;
	}
	if (position < text.length) {
		runs.push({text: text.slice(position), isolate: false});
	}
	return runs;
};
