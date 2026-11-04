import {createTikTokStyleCaptions} from '@remotion/captions';
import {readdirSync, readFileSync, statSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, it} from 'vitest';
import {KineticCaptions} from '../components/KineticCaptions';
import {
	activeTokenIndex,
	groupIntoPages,
	mergeBrandTokens,
	pageAt,
} from '../lib/captionGrouping';
import {localizeDigits, splitForIsolation} from '../lib/text';
import {colors} from '../lib/tokens';
import type {CaptionWord, Digits, Language} from '../props';

const REAL_AR = 'قوام المال';
const REAL_EN = 'Qawam Money';
const names = [REAL_AR, REAL_EN, 'علامة تجريبية', 'TEST BRAND'];

const timed = (texts: string[], stepMs = 400, gapMs = 0): CaptionWord[] =>
	texts.map((text, index) => ({
		text,
		start_ms: index * (stepMs + gapMs),
		end_ms: index * (stepMs + gapMs) + stepMs,
	}));

const render = (
	words: CaptionWord[],
	ms: number,
	{language = 'ar', digits = 'western'}: {language?: Language; digits?: Digits} = {},
) =>
	renderToStaticMarkup(
		<KineticCaptions
			words={words}
			brandNames={names}
			language={language}
			digits={digits}
			highlightColor={colors.roseGold}
			frame={Math.floor((ms * 30) / 1000)}
			fps={30}
		/>,
	);

const tokensIn = (markup: string): string[] =>
	[...markup.matchAll(/data-token="([^"]*)"/g)].map((match) => match[1] ?? '');

describe('brand name', () => {
	it.each([
		[['مع', 'قوام', 'المال'], ['مع', REAL_AR]],
		[['قوام', 'المال،', 'قريبًا'], [`${REAL_AR}،`, 'قريبًا']],
		[['with', 'Qawam', 'Money'], ['with', REAL_EN]],
		[['Qawam', 'Money,', 'coming'], [`${REAL_EN},`, 'coming']],
		[['qawam', 'money'], ['qawam money']],
		[['بقوام', 'المال'], ['بقوام المال']],
		[['علامة', 'تجريبية'], ['علامة تجريبية']],
		[[REAL_AR], [REAL_AR]],
	])('%j merges into one token', (texts, expected) => {
		expect(mergeBrandTokens(timed(texts), names).map((token) => token.text)).toEqual(expected);
	});

	it('takes its timing from all the words it merged', () => {
		const [token] = mergeBrandTokens(timed(['قوام', 'المال']), names);
		expect(token).toMatchObject({startMs: 0, endMs: 800, isBrand: true});
	});

	it('leaves other words alone', () => {
		const tokens = mergeBrandTokens(timed(['قوام', 'الجسم']), names);
		expect(tokens.map((token) => token.text)).toEqual(['قوام', 'الجسم']);
		expect(tokens.some((token) => token.isBrand)).toBe(false);
	});

	it('stays on one page wherever the page limit falls', () => {
		for (let before = 0; before < 8; before++) {
			const filler = Array.from({length: before}, (_, index) => `كلمة${index}`);
			const tokens = mergeBrandTokens(timed([...filler, 'قوام', 'المال', 'بعدها']), names);
			const pages = groupIntoPages(tokens);
			const holding = pages.filter((page) =>
				page.tokens.some((token) => token.text.includes('قوام')),
			);
			expect(holding).toHaveLength(1);
			expect(holding[0]?.tokens.some((token) => token.text === REAL_AR)).toBe(true);
		}
	});

	it('cannot wrap across lines, and highlights as one element', () => {
		const markup = render(timed(['مع', 'قوام', 'المال', 'قريب']), 500);
		expect(tokensIn(markup)).toContain(REAL_AR);
		const brand = /<span[^>]*data-token="قوام المال"[^>]*>/.exec(markup)?.[0] ?? '';
		expect(brand).toContain('white-space:nowrap');
		expect(brand).toContain('display:inline-block');
		expect(brand).toContain('data-active="true"');
		expect(markup).not.toContain('data-token="قوام"');
	});

	it('is never on screen alone at any moment of the reel', () => {
		const words = timed(['خطط', 'ميزانيتك', 'مع', 'قوام', 'المال', 'قريبًا', 'جدًا']);
		for (let ms = 0; ms < 3000; ms += 33) {
			const tokens = tokensIn(render(words, ms));
			expect(tokens).not.toContain('قوام');
			expect(tokens).not.toContain('المال');
		}
	});
});

describe('pages', () => {
	const words = (count: number) => Array.from({length: count}, (_, index) => `كلمة${index}`);

	it('keeps every word whole and in spoken order, with no reversal', () => {
		const texts = ['راتبك', 'وين', 'يروح', 'كل', 'شهر؟', 'خطط', 'ميزانيتك'];
		const pages = groupIntoPages(mergeBrandTokens(timed(texts), names));
		expect(pages.flatMap((page) => page.tokens.map((token) => token.text))).toEqual(texts);
	});

	it('limits a page by words and by characters, so it fits two lines', () => {
		for (const page of groupIntoPages(mergeBrandTokens(timed(words(40)), names))) {
			expect(page.tokens.length).toBeLessThanOrEqual(4);
			expect(page.tokens.map((token) => token.text).join(' ').length).toBeLessThanOrEqual(30);
		}
	});

	it('breaks at the end of a sentence and on a pause', () => {
		const sentence = groupIntoPages(mergeBrandTokens(timed(['وين', 'شهر؟', 'خطط']), names));
		expect(sentence.map((page) => page.tokens.length)).toEqual([2, 1]);
		const pause = groupIntoPages(mergeBrandTokens(timed(['وين', 'يروح'], 300, 800), names));
		expect(pause.map((page) => page.tokens.length)).toEqual([1, 1]);
	});

	it('keeps a word longer than the limit whole, on its own page', () => {
		const long = 'ا'.repeat(40);
		const pages = groupIntoPages(mergeBrandTokens(timed(['قبل', long, 'بعد']), names));
		expect(pages.map((page) => page.tokens.map((token) => token.text))).toEqual([
			['قبل'],
			[long],
			['بعد'],
		]);
	});

	it('shows nothing before the first word or long after a page ends', () => {
		const pages = groupIntoPages(mergeBrandTokens(timed(['وين'], 300, 0), names));
		const late = groupIntoPages(
			mergeBrandTokens([{text: 'وين', start_ms: 1000, end_ms: 1300}], names),
		);
		expect(pageAt(late, 999)).toBeNull();
		expect(pageAt(late, 1000)).not.toBeNull();
		expect(pageAt(pages, 5000)).toBeNull();
	});

	it('marks the word being spoken', () => {
		const [page] = groupIntoPages(mergeBrandTokens(timed(['وين', 'يروح', 'كل']), names));
		expect(page).toBeDefined();
		if (page) {
			expect(activeTokenIndex(page, 0)).toBe(0);
			expect(activeTokenIndex(page, 450)).toBe(1);
			expect(activeTokenIndex(page, 800)).toBe(2);
		}
	});

	it('copes with no words at all', () => {
		expect(groupIntoPages([])).toEqual([]);
		expect(render([], 0)).not.toContain('data-token');
	});
});

describe('the createTikTokStyleCaptions helper, tried on Arabic (spec Section 8.4, rule 9)', () => {
	const asHelperInput = (texts: string[], stepMs: number) =>
		texts.map((text, index) => ({
			text: index === 0 ? text : ` ${text}`,
			startMs: index * stepMs,
			endMs: index * stepMs + stepMs,
			timestampMs: null,
			confidence: null,
		}));

	it('keeps Arabic words whole and in order, so shaping alone is not the issue', () => {
		const {pages} = createTikTokStyleCaptions({
			captions: asHelperInput(['راتبك', 'وين', 'يروح'], 300),
			combineTokensWithinMilliseconds: 10_000,
		});
		expect(pages[0]?.tokens.map((token) => token.text.trim())).toEqual(['راتبك', 'وين', 'يروح']);
	});

	it('can split the brand across two pages, which G18 forbids, so the engine does not use it', () => {
		const {pages} = createTikTokStyleCaptions({
			captions: asHelperInput(['مع', 'قوام', 'المال'], 400),
			combineTokensWithinMilliseconds: 500,
		});
		const first = pages[0]?.tokens.map((token) => token.text.trim()) ?? [];
		expect(first.includes('قوام') && !first.includes('المال')).toBe(true);
	});

	it('has no limit on words per page, so fast speech overflows the caption zone', () => {
		const {pages} = createTikTokStyleCaptions({
			captions: asHelperInput(words(14), 50),
			combineTokensWithinMilliseconds: 1000,
		});
		expect(pages[0]?.tokens.length).toBeGreaterThan(4);
		function words(count: number) {
			return Array.from({length: count}, (_, index) => `كلمة${index}`);
		}
	});
});

describe('Arabic rendering rules', () => {
	const words = timed(['راتبك', 'وين', 'يروح', 'شهر؟', 'خطط', 'ميزانيتك']);

	it('uses dir="rtl" on a wrapping flex row for Arabic, and ltr for English', () => {
		const arabic = render(words, 100);
		expect(arabic).toMatch(/dir="rtl"/);
		expect(arabic).toContain('flex-wrap:wrap');
		expect(arabic).toContain('display:flex');
		expect(render(timed(['Where', 'does']), 100, {language: 'en'})).toMatch(/dir="ltr"/);
	});

	it('keeps DOM order equal to spoken order, because the browser does the mirroring', () => {
		expect(tokensIn(render(timed(['راتبك', 'وين', 'يروح']), 100))).toEqual([
			'راتبك',
			'وين',
			'يروح',
		]);
	});

	it('makes each word exactly one inline-block, with no element inside a word', () => {
		for (let ms = 0; ms < 2400; ms += 100) {
			const markup = render(words, ms);
			const elements = markup.match(/<span[^>]*data-token="[^"]*"[^>]*>/g) ?? [];
			for (const element of elements) {
				expect(element).toContain('display:inline-block');
			}
			for (const match of markup.matchAll(/<span[^>]*data-token="([^"]*)"[^>]*>(.*?)<\/span>/g)) {
				expect(match[2]).toBe(match[1]);
			}
		}
	});

	it('never uses letter-spacing', () => {
		for (let ms = 0; ms < 2400; ms += 100) {
			expect(render(words, ms)).not.toContain('letter-spacing');
		}
	});

	it('animates only with transform, opacity and glow, and keeps one font and weight', () => {
		const seen = new Set<string>();
		for (let ms = 0; ms < 2400; ms += 33) {
			for (const element of render(words, ms).match(/<span[^>]*data-token="[^"]*"[^>]*>/g) ?? []) {
				seen.add(/font-weight:(\d+)/.exec(element)?.[1] ?? 'inherited');
				seen.add(/font-family:([^;"]+)/.exec(element)?.[1] ?? 'inherited');
			}
		}
		expect(seen).toEqual(new Set(['inherited']));
	});

	it('gives the active word the highlight colour, whole, and leaves the rest near-white', () => {
		const markup = render(timed(['راتبك', 'وين', 'يروح']), 500);
		const element = (token: string) =>
			new RegExp(`<span[^>]*data-token="${token}"[^>]*>`).exec(markup)?.[0] ?? '';
		expect(element('وين')).toContain('data-active="true"');
		expect(element('وين')).toContain('color:#E598B0');
		expect(element('راتبك')).toContain('color:#FDF8FA');
		expect(element('يروح')).toContain('color:#FDF8FA');
	});

	it('wraps Latin and digits in <bdi> inside an Arabic line, outside the Arabic letters', () => {
		const markup = render(timed(['ميزانية', 'Budget', '2,500', 'ريال']), 100);
		expect(markup).toContain('<bdi>Budget</bdi>');
		expect(markup).toContain('<bdi>2,500</bdi>');
		expect(markup).not.toContain('<bdi>ميزانية</bdi>');
	});

	it('wraps an Arabic word in <bdi> inside an English line', () => {
		expect(render(timed(['with', 'قوام', 'المال']), 100, {language: 'en'})).toContain(
			`<bdi>${REAL_AR}</bdi>`,
		);
	});

	it('keeps English words next to each other in reading order inside an Arabic line', () => {
		const markup = render(timed(['ميزانية', 'Budget', 'Plan', '2,500']), 100);
		const group = /<span[^>]*data-direction-run="ltr"[^>]*>.*?<\/span><\/span>/.exec(markup)?.[0] ?? '';
		expect(group).toContain('dir="ltr"');
		expect(tokensIn(group)).toEqual(['Budget', 'Plan', '2,500']);
		expect(tokensIn(markup)).toEqual(['ميزانية', 'Budget', 'Plan', '2,500']);
	});

	it('keeps Arabic words next to each other in reading order inside an English line', () => {
		const markup = render(timed(['say', 'مرحبا', 'بكم', 'now']), 100, {language: 'en'});
		expect(markup).toContain('data-direction-run="rtl"');
		expect(tokensIn(markup)).toEqual(['say', 'مرحبا', 'بكم', 'now']);
	});

	it('needs no extra group for a single foreign word', () => {
		expect(render(timed(['ميزانية', 'Budget', 'ريال']), 100)).not.toContain('data-direction-run');
	});

	it.each([
		['100%', [{text: '100%', isolate: true}]],
		['#test', [{text: '#test', isolate: true}]],
		['2,500.', [{text: '2,500', isolate: true}, {text: '.', isolate: false}]],
		['(Budget)', [{text: '(', isolate: false}, {text: 'Budget', isolate: true}, {text: ')', isolate: false}]],
		['قبل', [{text: 'قبل', isolate: false}]],
		['ريال100', [{text: 'ريال', isolate: false}, {text: '100', isolate: true}]],
		['١٠٠٪', [{text: '١٠٠٪', isolate: true}]],
	])('isolates %s so punctuation stays on the right side', (token, runs) => {
		expect(splitForIsolation(token, 'ar')).toEqual(runs);
	});

	it('never isolates inside a run of Arabic letters, even with marks and joiners', () => {
		for (const word of ['قُوام', 'مَالٌ', 'لـلـه', 'اللّٰه']) {
			expect(splitForIsolation(word, 'ar')).toEqual([{text: word, isolate: false}]);
		}
	});
});

describe('digits follow config', () => {
	it('converts in both directions', () => {
		expect(localizeDigits('2,500 ريال', 'arabic_indic')).toBe('٢,٥٠٠ ريال');
		expect(localizeDigits('٢٥٠٠ ريال', 'western')).toBe('2500 ريال');
		expect(localizeDigits('۲۵۰۰', 'western')).toBe('2500');
		expect(localizeDigits('no digits', 'western')).toBe('no digits');
	});

	it('applies to captions', () => {
		const words = timed(['ادفع', '2500', 'ريال']);
		expect(render(words, 100, {digits: 'arabic_indic'})).toContain('<bdi>٢٥٠٠</bdi>');
		expect(render(words, 100, {digits: 'western'})).toContain('<bdi>2500</bdi>');
	});
});

describe('the source itself', () => {
	const walk = (folder: string): string[] =>
		readdirSync(folder).flatMap((name) => {
			const path = join(folder, name);
			return statSync(path).isDirectory() ? walk(path) : [path];
		});
	const sources = walk(resolve(process.cwd(), 'src')).filter(
		(path) => !path.includes('__tests__') && /\.tsx?$/.test(path),
	);

	it('finds the source', () => {
		expect(sources.length).toBeGreaterThan(3);
	});

	it.each([
		['letter-spacing', /letterSpacing|letter-spacing/],
		['array reversal', /\.reverse\(|\.toReversed\(/],
		['splitting text into letters', /\.split\((?:''|"")\)|Array\.from\(\s*(?:word|text|token)|\[\.\.\.(?:word|text|token)/],
		['a network address', /https?:\/\//],
	])('contains no %s', (_name, pattern) => {
		for (const path of sources) {
			expect(pattern.test(readFileSync(path, 'utf-8')), path).toBe(false);
		}
	});
});
