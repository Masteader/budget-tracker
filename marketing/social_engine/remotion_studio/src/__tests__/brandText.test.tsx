import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, it} from 'vitest';
import {Isolated} from '../components/Isolated';
import {groupIntoPages, mergeBrandTokens, textTokens} from '../lib/captionGrouping';
import {baseLanguage, groupWordRuns, splitForIsolation} from '../lib/text';
import {englishLineAt} from '../lib/timeline';
import {durationInFrames} from '../lib/timeline';
import {featureProps, mythProps, realBrand, renderReel, tipProps} from './helpers';

const REAL_AR = 'قوام المال';
const REAL_EN = 'Qawam Money';
const BRAND = [REAL_AR, REAL_EN];

const isolated = (text: string, language: 'ar' | 'en') =>
	splitForIsolation(text, language)
		.filter((run) => run.isolate)
		.map((run) => run.text);

describe('word order inside a line of the other direction', () => {
	it.each([
		['جرّب Qawam Money الآن', ['Qawam Money']],
		['ادفع بـ Apple Pay اليوم', ['Apple Pay']],
		['الراتب 500 SAR فقط', ['500 SAR']],
		['ادفع Apple Pay, Google Pay اليوم', ['Apple Pay, Google Pay']],
		['من 5 إلى 10 أيام', ['5', '10']],
	])('%s keeps its Latin phrase in one isolate', (text, expected) => {
		expect(isolated(text, 'ar')).toEqual(expected);
	});

	it('keeps the punctuation at the end of a phrase outside the isolate', () => {
		expect(splitForIsolation('Qawam Money،', 'ar')).toEqual([
			{text: 'Qawam Money', isolate: true},
			{text: '،', isolate: false},
		]);
		expect(isolated('Qawam Money.', 'ar')).toEqual(['Qawam Money']);
	});

	it('isolates the whole brand as one, once it is a merged token', () => {
		const [token] = mergeBrandTokens(
			[
				{text: 'Qawam', start_ms: 0, end_ms: 1},
				{text: 'Money', start_ms: 1, end_ms: 2},
			],
			BRAND,
		);
		expect(isolated(token?.text ?? '', 'ar')).toEqual(['Qawam Money']);
	});

	it('draws Qawam before Money in one <bdi>, in an Arabic reel', () => {
		const markup = renderToStaticMarkup(<Isolated text={REAL_EN} language="ar" digits="western" />);
		expect(markup).toBe('<bdi>Qawam Money</bdi>');
	});

	it('keeps Arabic words joined inside an English line', () => {
		expect(isolated(`Track it in ${REAL_AR} every day`, 'en')).toEqual([REAL_AR]);
	});

	it('takes the direction of a line from most of its letters, not from one foreign word', () => {
		expect(baseLanguage(`Track it in ${REAL_AR} every day`, 'ar')).toBe('en');
		expect(baseLanguage('جرّب Qawam Money الآن ووفر كل شهر', 'en')).toBe('ar');
		expect(baseLanguage('Know your payday cycle', 'ar')).toBe('en');
		expect(baseLanguage('500', 'ar')).toBe('ar');
		expect(baseLanguage('500', 'en')).toBe('en');
	});

	it.each([
		['hook', (language: 'ar' | 'en') => tipProps({language, hook_text: 'خطتك مع Qawam Money'}), 30],
		[
			'caption',
			(language: 'ar' | 'en') =>
				tipProps({
					language,
					words: [
						{text: 'جرب', start_ms: 3200, end_ms: 3400},
						{text: 'Qawam', start_ms: 3400, end_ms: 3600},
						{text: 'Money', start_ms: 3600, end_ms: 3800},
					],
				}),
			110,
		],
		['card', (language: 'ar' | 'en') => tipProps({language, on_screen_text: ['جرّب Qawam Money الآن ووفر', 'b1', 'c1']}), 100],
		['recap', (language: 'ar' | 'en') => tipProps({language, on_screen_text: ['جرّب Qawam Money الآن ووفر', 'b1', 'c1']}), 175],
		['myth', (language: 'ar' | 'en') => mythProps({language, on_screen_text: ['جرّب Qawam Money الآن ووفر', 'ثانيا']}), 100],
		['callout', (language: 'ar' | 'en') => featureProps({language, on_screen_text: ['جرّب Qawam Money الآن ووفر']}), 150],
	] as const)('the %s draws the Latin name whole and in order in an Arabic reel', (_name, make, frame) => {
		const markup = renderReel(make('ar'), frame);
		expect(markup).toContain('<bdi>Qawam Money</bdi>');
		expect(markup).not.toContain('<bdi>Qawam</bdi>');
		expect(markup).not.toContain('<bdi>Money</bdi>');
	});

	it('lets an English card with an Arabic name read left to right in an Arabic reel', () => {
		const line = `Track it in ${REAL_AR} every day`;
		const markup = renderReel(tipProps({language: 'ar', on_screen_text: [line, 'b1', 'c1']}), 100);
		const card = /<div[^>]*data-flow-text="ltr"[^>]*>(.*?)<\/div>/s.exec(markup);
		expect(card?.[0]).toBeTruthy();
		const words = [...(card?.[1] ?? '').matchAll(/data-flow-word="([^"]*)"/g)].map((match) => match[1]);
		expect(words).toEqual(['Track', 'it', 'in', REAL_AR, 'every', 'day']);
	});
});

describe('the full name never breaks across a line or a page (G18)', () => {
	const words = [{text: 'x', start_ms: 0, end_ms: 10000}];
	const chunksOf = (subtitle: string, names?: string[]) => {
		const seen = new Set<string>();
		for (let ms = 0; ms < 10000; ms += 50) {
			seen.add(englishLineAt(subtitle, words, ms, 10000, names) ?? '');
		}
		return [...seen];
	};

	it('never ends an English chunk on Qawam, wherever the limit falls', () => {
		for (let padding = 0; padding < 60; padding++) {
			const subtitle = `${'word '.repeat(padding)}plan it all in Qawam Money and stop guessing today.`;
			for (const line of chunksOf(subtitle)) {
				expect(line).not.toMatch(/Qawam$/);
				expect(line).not.toMatch(/^Money/);
			}
		}
	});

	it('does the same for the Arabic name and the test brand in an English subtitle', () => {
		for (let padding = 0; padding < 60; padding++) {
			const arabic = `${'word '.repeat(padding)}plan it with ${REAL_AR} today`;
			for (const line of chunksOf(arabic)) {
				expect(line.endsWith('قوام')).toBe(false);
			}
			const test = `${'word '.repeat(padding)}plan it with TEST BRAND today`;
			for (const line of chunksOf(test, ['TEST BRAND'])) {
				expect(line).not.toMatch(/TEST$/);
			}
		}
	});

	it('keeps a decimal and a domain whole in a chunk', () => {
		expect(chunksOf('Save 1.5 SAR at qawam.money today')).toContain('Save 1.5 SAR at qawam.money today');
	});

	it('never splits a number from its unit', () => {
		for (let padding = 0; padding < 60; padding++) {
			const subtitle = `${'word '.repeat(padding)}you save 1.5 SAR and then 2,500 SAR today.`;
			for (const line of chunksOf(subtitle)) {
				expect(line).not.toMatch(/(?:1\.5|2,500)$/);
				expect(line).not.toMatch(/^SAR/);
			}
		}
	});

	it('never leaves a word or two alone at the end of a sentence', () => {
		const lines = chunksOf('Every riyal has its place, and every expense is written down.');
		expect(lines.filter(Boolean).every((line) => line.length >= 18)).toBe(true);
		expect(lines.filter(Boolean).join(' ')).toBe('Every riyal has its place, and every expense is written down.');
	});

	it('still breaks after a sentence that ends in a number', () => {
		const lines = chunksOf('You spend 500. Then you stop.');
		expect(lines).toContain('You spend 500.');
		expect(lines).toContain('Then you stop.');
	});

	it('keeps a number and its unit on one caption page, wherever the page limit falls', () => {
		for (let before = 0; before < 8; before++) {
			const filler = Array.from({length: before}, (_, index) => `كلمة${index}`);
			const texts = [...filler, '2,500', 'ريال', 'بعدها'];
			const timed = texts.map((text, index) => ({text, start_ms: index * 300, end_ms: index * 300 + 300}));
			const pages = groupIntoPages(mergeBrandTokens(timed, BRAND));
			const holding = pages.find((page) => page.tokens.some((token) => token.text === '2,500'));
			expect(holding?.tokens.map((token) => token.text)).toContain('ريال');
		}
	});

	it('keeps a number with its unit over a pause in the speech', () => {
		const timed = [
			{text: '500', start_ms: 0, end_ms: 200},
			{text: 'ريال', start_ms: 900, end_ms: 1200},
		];
		expect(groupIntoPages(mergeBrandTokens(timed, BRAND))).toHaveLength(1);
	});

	it('keeps a number and its unit together in one row', () => {
		const runs = groupWordRuns(['ادفع', '2,500', 'ريال', 'اليوم'], (word) => word, 'ar');
		expect(runs.flatMap((run) => run.atoms)).toEqual([['ادفع'], ['2,500', 'ريال'], ['اليوم']]);
		const latin = groupWordRuns(['ادفع', '500', 'SAR', 'اليوم'], (word) => word, 'ar');
		expect(latin.find((run) => run.direction === 'ltr')?.atoms).toEqual([['500', 'SAR']]);
	});

	it('finds the name inside on-screen text, with its proclitic and punctuation', () => {
		const tokens = textTokens(`خطط ميزانيتك بقوام المال، كل شهر`, BRAND);
		expect(tokens.map((token) => token.text)).toEqual(['خطط', 'ميزانيتك', 'بقوام المال،', 'كل', 'شهر']);
		expect(tokens[2]?.isBrand).toBe(true);
	});

	const longLine = `خطط ميزانيتك الشهرية كلها بسهولة وراحة مع ${REAL_AR} وخلك مرتاح`;
	const brandWord = /<span[^>]*data-flow-word="قوام المال"[^>]*>/;

	it.each([
		['a tip card', () => tipProps({on_screen_text: [longLine, 'ثانيا', 'ثالثا']}), 100],
		['the recap', () => tipProps({on_screen_text: [longLine, 'ثانيا', 'ثالثا']}), 175],
		['a myth card', () => mythProps({on_screen_text: [longLine, 'ثانيا']}), 100],
		['a fact card', () => mythProps({on_screen_text: ['ثانيا', longLine]}), 170],
		['a callout', () => featureProps({on_screen_text: [longLine]}), 150],
	] as const)('%s holds the Arabic name in one unbreakable word', (_name, make, frame) => {
		const element = brandWord.exec(renderReel(make(), frame))?.[0] ?? '';
		expect(element).toContain('white-space:nowrap');
		expect(element).toContain('display:inline-block');
	});

	it('holds the English name the same way in an English reel', () => {
		const markup = renderReel(
			tipProps({language: 'en', on_screen_text: [`Plan the whole month with ${REAL_EN} and relax`, 'b1', 'c1']}),
			100,
		);
		const element = /<span[^>]*data-flow-word="Qawam Money"[^>]*>/.exec(markup)?.[0] ?? '';
		expect(element).toContain('white-space:nowrap');
	});

	it('keeps the brand tag and the lockup in their full form', () => {
		const props = tipProps({watermark: false, brand: realBrand, language: 'ar'});
		const markup = renderReel(props, durationInFrames(props) - 1);
		expect(markup).toContain(`<bdi>${REAL_AR}</bdi>`);
		expect(markup).toContain(`<bdi>${REAL_EN}</bdi>`);
	});
});
