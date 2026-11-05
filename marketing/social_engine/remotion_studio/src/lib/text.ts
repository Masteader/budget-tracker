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

const wordsIn = (text: string, script: RegExp): number =>
	text.split(/\s+/).filter((word) => script.test(word)).length;

/**
 * The language a line reads in. It stays the reel's unless the other language clearly has the line,
 * by more than two words to one, so a sentence with the Latin brand name in it stays Arabic.
 */
export const baseLanguage = (text: string, reelLanguage: Language): Language => {
	const arabic = wordsIn(text, /\p{Script=Arabic}/u);
	const latin = wordsIn(text, /\p{Script=Latin}/u);
	if (reelLanguage === 'ar') {
		return latin > 2 * arabic ? 'en' : 'ar';
	}
	return arabic > 2 * latin ? 'ar' : 'en';
};

const isForeignWord = (text: string, language: Language): boolean =>
	language === 'ar' ? !hasArabic(text) && /[\p{Script=Latin}\p{Nd}]/u.test(text) : hasArabic(text);

const NUMBER = /^[#+\-(]?\p{Nd}[\p{Nd}.,:/٫٬-]*[%٪]?$/u;
const CURRENCY = /^(?:SAR|SR|USD|AED|ريال|ر\.س)$/iu;
const CLOSES_A_SENTENCE = /[.!?؟…۔]$/u;

/** A number is never left apart from its unit, in either order, on a line or a caption page. */
export const keepsWithNext = (text: string, next: string | undefined): boolean => {
	if (next === undefined) {
		return false;
	}
	return (
		(NUMBER.test(text) && !CLOSES_A_SENTENCE.test(text)) ||
		(CURRENCY.test(text) && NUMBER.test(next))
	);
};

/** Items in order, in pieces that no line break or page break may cut. */
export const groupAtoms = <T,>(items: T[], textOf: (item: T) => string): T[][] => {
	const atoms: T[][] = [];
	let joinNext = false;
	items.forEach((item, index) => {
		const last = atoms[atoms.length - 1];
		if (joinNext && last) {
			last.push(item);
		} else {
			atoms.push([item]);
		}
		const next = items[index + 1];
		joinNext = keepsWithNext(textOf(item), next === undefined ? undefined : textOf(next));
	});
	return atoms;
};

export type WordRun<T> = {direction: 'ltr' | 'rtl' | null; atoms: T[][]};

/**
 * Words are items in a flex row, and the row runs in the line's direction. Two English words side by
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
	let pending: T[][] = [];
	const flush = () => {
		if (pending.flat().length > 1) {
			runs.push({direction: foreign, atoms: pending});
		} else if (pending.length > 0) {
			runs.push({direction: null, atoms: pending});
		}
		pending = [];
	};
	for (const atom of groupAtoms(items, textOf)) {
		if (atom.every((item) => isForeignWord(textOf(item), language))) {
			pending.push(atom);
		} else {
			flush();
			runs.push({direction: null, atoms: [atom]});
		}
	}
	flush();
	return runs;
};

export type TextRun = {text: string; isolate: boolean};

// A Latin phrase or number in an Arabic line, with its inner punctuation. Words next to each other
// stay in one run: a <bdi> for each would draw them in Arabic order, as "Money Qawam". Punctuation at
// the end stays outside, so it lands on the correct side of the isolated run.
const LATIN_WORD = String.raw`[#@+\-]?[\p{Script=Latin}\p{Nd}]+(?:[.,:'’/\-][\p{Script=Latin}\p{Nd}]+)*[%٪]?`;
const LATIN_OR_NUMBER = new RegExp(String.raw`${LATIN_WORD}(?:[,;:&+]?\s+${LATIN_WORD})*`, 'gu');
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
