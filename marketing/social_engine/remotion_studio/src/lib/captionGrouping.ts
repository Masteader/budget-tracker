import type {CaptionWord} from '../props';

/**
 * Groups timed words into caption pages. Written here because createTikTokStyleCaptions can split
 * the brand across two pages and has no limit on words per page, as captions.test.tsx shows.
 */

export type CaptionToken = {
	text: string;
	startMs: number;
	endMs: number;
	isBrand: boolean;
};

export type CaptionPage = {
	tokens: CaptionToken[];
	startMs: number;
	endMs: number;
};

const MAX_TOKENS_PER_PAGE = 4;
const MAX_CHARS_PER_PAGE = 30;
const PAUSE_BREAK_MS = 500;
const PAGE_HOLD_MS = 600;

const SENTENCE_END = /[.!?؟…۔]["'”»)]*$/u;
const EDGE_PUNCTUATION_START = /^[\p{P}\p{S}]+/u;
const EDGE_PUNCTUATION_END = /[\p{P}\p{S}]+$/u;
const ENGLISH_POSSESSIVE = /['’]s$/i;
const ARABIC_PROCLITICS = /^[وفبلك]{0,2}/u;

const normalize = (text: string): string =>
	text
		.normalize('NFC')
		.replace(/[\p{M}ـ\u200c-\u200f]/gu, '')
		.toLowerCase()
		.trim();

const bareWord = (text: string): string =>
	normalize(text)
		.replace(ENGLISH_POSSESSIVE, '')
		.replace(EDGE_PUNCTUATION_START, '')
		.replace(EDGE_PUNCTUATION_END, '');

const firstWordMatches = (word: string, nameWord: string): boolean =>
	word === nameWord ||
	(/\p{Script=Arabic}/u.test(nameWord) && word.replace(ARABIC_PROCLITICS, '') === nameWord);

const nameLengthAt = (words: CaptionWord[], start: number, names: string[][]): number => {
	for (const name of names) {
		const fits = start + name.length <= words.length;
		if (
			fits &&
			name.every((nameWord, offset) => {
				const word = bareWord(words[start + offset]?.text ?? '');
				return offset === 0 ? firstWordMatches(word, nameWord) : word === nameWord;
			})
		) {
			return name.length;
		}
	}
	return 0;
};

const isWholeName = (text: string, names: string[][]): boolean => {
	const parts = text.split(/\s+/).map(bareWord);
	return names.some(
		(name) =>
			name.length === parts.length && name.every((nameWord, index) => parts[index] === nameWord),
	);
};

/** The brand is one token, so قوام can never be on screen without المال (G18). */
export const mergeBrandTokens = (words: CaptionWord[], brandNames: string[]): CaptionToken[] => {
	const names = [...new Set(brandNames)]
		.map((name) => normalize(name).split(/\s+/))
		.filter((name) => name.length > 1)
		.sort((a, b) => b.length - a.length);
	const tokens: CaptionToken[] = [];
	for (let index = 0; index < words.length; index++) {
		const word = words[index];
		if (!word) {
			continue;
		}
		const length = nameLengthAt(words, index, names);
		if (length > 1) {
			const parts = words.slice(index, index + length);
			tokens.push({
				text: parts.map((part) => part.text.trim()).join(' '),
				startMs: word.start_ms,
				endMs: parts[parts.length - 1]?.end_ms ?? word.end_ms,
				isBrand: true,
			});
			index += length - 1;
		} else {
			tokens.push({
				text: word.text.trim(),
				startMs: word.start_ms,
				endMs: word.end_ms,
				isBrand: isWholeName(word.text, names),
			});
		}
	}
	return tokens;
};

const startsNewPage = (page: CaptionPage, token: CaptionToken): boolean => {
	const last = page.tokens[page.tokens.length - 1];
	if (!last) {
		return false;
	}
	const chars = [...page.tokens, token].map((item) => item.text).join(' ').length;
	return (
		page.tokens.length >= MAX_TOKENS_PER_PAGE ||
		chars > MAX_CHARS_PER_PAGE ||
		SENTENCE_END.test(last.text) ||
		token.startMs - last.endMs >= PAUSE_BREAK_MS
	);
};

export const groupIntoPages = (tokens: CaptionToken[]): CaptionPage[] => {
	const pages: CaptionPage[] = [];
	for (const token of tokens) {
		const page = pages[pages.length - 1];
		if (page && !startsNewPage(page, token)) {
			page.tokens.push(token);
			page.endMs = token.endMs;
		} else {
			pages.push({tokens: [token], startMs: token.startMs, endMs: token.endMs});
		}
	}
	return pages;
};

export const pageAt = (pages: CaptionPage[], ms: number): CaptionPage | null => {
	let shown: CaptionPage | null = null;
	for (const page of pages) {
		if (page.startMs <= ms) {
			shown = page;
		}
	}
	return shown && ms < shown.endMs + PAGE_HOLD_MS ? shown : null;
};

export const activeTokenIndex = (page: CaptionPage, ms: number): number => {
	let active = -1;
	page.tokens.forEach((token, index) => {
		if (token.startMs <= ms) {
			active = index;
		}
	});
	return active;
};
