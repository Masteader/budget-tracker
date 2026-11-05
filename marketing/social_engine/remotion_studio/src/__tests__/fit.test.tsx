import {describe, expect, it} from 'vitest';
import {planHook} from '../components/HookTitle';
import {planCallout} from '../compositions/FeatureDemo';
import {planTipCard, planTipRecap} from '../compositions/DailyTip';
import {planComparison} from '../compositions/MythVsFact';
import {textTokens} from '../lib/captionGrouping';
import {findFitProblems, fitFlow, TextFitError} from '../lib/fit';
import {computeLayout} from '../lib/layout';
import {planLabel} from '../components/IllustrativePricesLabel';
import {planCaptions} from '../components/KineticCaptions';
import {estimateWidth, featureProps, renderReel, styleOf} from './helpers';

const NAMES = ['قوام المال', 'Qawam Money'];
const INSTAGRAM = {top: 220, bottom: 420, left: 60, right: 140};
const NARROW = {top: 220, bottom: 420, left: 0, right: 660};
const LONG_AR = 'خطط ميزانيتك '.repeat(12).trim().slice(0, 160);
const LONG_EN = 'Plan your whole budget '.repeat(7).trim().slice(0, 160);

const tokens = (text: string) => textTokens(text, NAMES);

describe('fitting text by measuring it', () => {
	const request = {
		language: 'en' as const,
		measure: estimateWidth,
		weight: 700,
		maxWidth: 500,
		maxHeight: 400,
		maxSize: 100,
		minSize: 20,
	};

	it('keeps the largest size that fits', () => {
		const plan = fitFlow({...request, tokens: tokens('Short')});
		expect(plan.fontSize).toBe(100);
		expect(plan.lineCount).toBe(1);
		expect(plan.fits).toBe(true);
	});

	it('counts the real lines, so the height it gives is the height drawn', () => {
		const one = fitFlow({...request, maxSize: 40, tokens: tokens('one two')});
		const many = fitFlow({...request, maxSize: 40, tokens: tokens('one two three four five six seven eight nine ten')});
		expect(one.lineCount).toBe(1);
		expect(many.lineCount).toBeGreaterThan(1);
		expect(many.height).toBeGreaterThan(one.height * many.lineCount * 0.9);
	});

	it('shrinks until the longest word fits the width', () => {
		const plan = fitFlow({...request, tokens: tokens('ا'.repeat(30))});
		expect(plan.width).toBeLessThanOrEqual(500);
		expect(plan.fits).toBe(true);
	});

	it('says so when nothing fits, instead of clipping', () => {
		const plan = fitFlow({...request, maxHeight: 30, tokens: tokens(LONG_EN)});
		expect(plan.fits).toBe(false);
		expect(plan.fontSize).toBe(20);
	});

	it('treats a number and its unit as one piece when it breaks lines', () => {
		const measure = (text: string, font: {size: number}) => text.length * font.size;
		const plan = fitFlow({...request, measure, maxWidth: 70, maxSize: 10, minSize: 10, tokens: tokens('500 SAR')});
		expect(plan.fits).toBe(true);
		expect(plan.lineCount).toBe(1);
	});
});

describe('a browser check catches what the measure missed', () => {
	const element = (offsetWidth: number, offsetHeight: number, maxWidth = 100, maxHeight = 100, words: number[] = []) => ({
		offsetWidth,
		offsetHeight,
		getAttribute: (name: string) =>
			({'data-fit-max-width': String(maxWidth), 'data-fit-max-height': String(maxHeight), 'data-fit-box': 'test'})[name] ?? null,
		querySelectorAll: () => words.map((width) => ({offsetWidth: width})),
	});

	it('passes a box within its limits', () => {
		expect(findFitProblems([element(100, 100, 100, 100, [90])])).toEqual([]);
	});

	it.each([
		['too tall', element(100, 140)],
		['too wide', element(160, 100)],
		['a word wider than its box', element(100, 100, 100, 100, [130])],
	])('flags %s', (_name, box) => {
		expect(findFitProblems([box])).toHaveLength(1);
	});
});

describe.each([
	['Instagram zones', INSTAGRAM],
	['a narrow zone', NARROW],
])('the hook, in %s', (_name, zones) => {
	const layout = computeLayout(zones);
	const hook = (text: string) => planHook(text, NAMES, 'ar', 'western', layout, estimateWidth);

	it.each([
		['a 24-character hook', 'Misunderstanding money?!'],
		['a short hook', 'راتبك وين يروح؟'],
		['a long hook', 'راتبك وين يروح كل شهر وأنت ما تدري وين راح؟'],
		['a 200-character hook', 'خطط ميزانيتك '.repeat(16).trim().slice(0, 200)],
		['one huge word', 'ا'.repeat(30)],
	])('%s stays on canvas in its hero phase', (_text, text) => {
		const plan = hook(text);
		expect(plan.hero.fits).toBe(true);
		expect(plan.heroTop).toBeGreaterThanOrEqual(layout.content.top);
		expect(plan.heroTop + plan.hero.height).toBeLessThanOrEqual(layout.captions.top);
		expect(plan.hero.width).toBeLessThanOrEqual(layout.content.width);
	});

	it('stays above the stage once compact, or leaves the screen', () => {
		for (const text of ['Misunderstanding money?!', 'راتبك وين يروح؟', 'خطط ميزانيتك '.repeat(16).trim().slice(0, 200)]) {
			const {compact, compactTop} = hook(text);
			if (compact) {
				expect(compact.fits).toBe(true);
				expect(compactTop + compact.height).toBeLessThanOrEqual(layout.top.top + layout.top.height);
				expect(compact.width).toBeLessThanOrEqual(layout.top.width);
			}
		}
	});

	it('leaves the label room under it, so the label cannot cover the accent word', () => {
		const {compact, compactTop} = hook('Misunderstanding money?!');
		expect(compact).not.toBeNull();
		expect(compactTop + (compact?.height ?? 0)).toBeLessThanOrEqual(layout.labelBand.top);
	});
});

describe('a compact hook is big enough to read', () => {
	it('keeps a normal hook at a real headline size', () => {
		const plan = planHook('راتبك وين يروح كل شهر؟', NAMES, 'ar', 'western', computeLayout(INSTAGRAM), estimateWidth);
		expect(plan.compact?.fontSize).toBeGreaterThanOrEqual(48);
	});

	it('leaves the screen rather than shrink past reading', () => {
		const huge = 'خطط ميزانيتك '.repeat(16).trim().slice(0, 200);
		const plan = planHook(huge, NAMES, 'ar', 'western', computeLayout(NARROW), estimateWidth);
		expect(plan.compact).toBeNull();
	});

	it('takes no compact form from a too-long hook on the real frame', () => {
		const huge = 'خطط ميزانيتك '.repeat(16).trim().slice(0, 200);
		const markup = renderReel(featureProps({hook_text: huge, safe_zones: NARROW}), 500);
		expect(markup).not.toContain('data-hook-compact');
		expect(markup).not.toContain('data-hook-title');
	});
});

describe.each([
	['Instagram zones', INSTAGRAM],
	['a narrow zone', NARROW],
])('on-screen text, in %s', (_name, zones) => {
	const layout = computeLayout(zones);

	it.each([
		['Arabic', LONG_AR],
		['English', LONG_EN],
	])('three 160-character %s cards fit the stage, one at a time', (_language, text) => {
		const plan = planTipCard(text, NAMES, 'ar', 'western', layout, estimateWidth);
		expect(plan.fits).toBe(true);
		expect(plan.height).toBeLessThanOrEqual(layout.stage.height);
	});

	it.each([
		['Arabic', LONG_AR],
		['English', LONG_EN],
	])('three 160-character %s cards fit the stage in the recap', (_language, text) => {
		const plan = planTipRecap([text, text, text], NAMES, 'ar', 'western', layout, estimateWidth);
		expect(plan.fits).toBe(true);
		expect(plan.rowsHeight).toBeLessThanOrEqual(plan.maxRowsHeight);
	});

	it('fits a long myth and a long fact on the stage', () => {
		const plan = planComparison([LONG_AR, LONG_AR], NAMES, 'ar', 'western', layout, estimateWidth);
		expect(plan.fits).toBe(true);
		expect(plan.settledHeight).toBeLessThanOrEqual(layout.stage.height);
	});

	it('keeps a long callout out of the captions', () => {
		const plan = planCallout(LONG_AR, NAMES, 'ar', 'western', layout, estimateWidth);
		expect(plan.fits).toBe(true);
		expect(plan.top + plan.height).toBeLessThanOrEqual(layout.captions.top);
	});

	it('fits the longest possible word and the label', () => {
		const caption = planCaptions(tokens('الاستراتيجياتوالاستثماراتوالميزانيات'), 'ar', 'western', layout, estimateWidth, true);
		expect(caption.fits).toBe(true);
		const label = planLabel(layout.content.width, estimateWidth);
		expect(label.fits).toBe(true);
		expect(label.width).toBeLessThanOrEqual(layout.content.width);
	});
});

describe('a text that cannot fit fails the render', () => {
	it('throws for a hook whose one word is wider than the zone at the smallest size', () => {
		expect(() => planHook('ا'.repeat(120), NAMES, 'ar', 'western', computeLayout(NARROW), estimateWidth)).toThrow(TextFitError);
	});

	it('throws for on-screen text too long for its box', () => {
		const measure = (text: string, font: {size: number}) => text.length * font.size * 5;
		expect(() => planCallout(LONG_AR, NAMES, 'ar', 'western', computeLayout(NARROW), measure)).toThrow(TextFitError);
	});
});

describe('the label fits the zone it is given', () => {
	it('shows on one line where there is room', () => {
		const plan = planLabel(880, estimateWidth);
		expect(plan.stacked).toBe(false);
	});

	it('stacks its two languages at the narrowest accepted zone, with nothing cropped', () => {
		const plan = planLabel(420, estimateWidth);
		expect(plan.width).toBeLessThanOrEqual(420);
		const markup = renderReel(featureProps({safe_zones: NARROW}), 500);
		expect(styleOf(markup, 'data-illustrative-label')['white-space']).toBeUndefined();
	});
});
