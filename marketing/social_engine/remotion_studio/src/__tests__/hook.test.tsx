import {describe, expect, it} from 'vitest';
import {heroEndMs} from '../lib/timeline';
import {featureProps, mythProps, renderReel, styleOf, tipProps} from './helpers';

const HOOK = 'راتبك وين يروح كل شهر؟';
const WORDS = HOOK.split(' ');

const hookWords = (markup: string) =>
	[...markup.matchAll(/<span[^>]*data-hook-word="([^"]*)"[^>]*>/g)].map((match) => ({
		text: match[1],
		element: match[0],
	}));

const opacityOf = (element: string) => Number(/opacity:([\d.]+)/.exec(element)?.[1] ?? '1');

describe('the hook grabs from the first frame', () => {
	it('already shows something on frame 0, not an empty screen', () => {
		const [first] = hookWords(renderReel(featureProps(), 0));
		expect(first?.text).toBe(WORDS[0]);
		expect(opacityOf(first?.element ?? '')).toBeGreaterThan(0.5);
	});

	it('has every word fully on screen within half a second', () => {
		const words = hookWords(renderReel(featureProps(), 15));
		expect(words.map((word) => word.text)).toEqual(WORDS);
		for (const word of words) {
			expect(opacityOf(word.element)).toBe(1);
		}
	});

	it('flashes and bursts on entry, then settles', () => {
		const props = featureProps();
		expect(renderReel(props, 0)).toContain('data-hook-flash');
		expect(renderReel(props, 14)).toContain('data-hook-burst');
		expect(renderReel(props, 60)).not.toContain('data-hook-flash');
		expect(renderReel(props, 60)).not.toContain('data-hook-burst');
	});

	it('lands words with a large spring, so each one hits', () => {
		const scale = (frame: number) => {
			const [first] = hookWords(renderReel(featureProps(), frame));
			return Number(/scale\(([\d.]+)\)/.exec(first?.element ?? '')?.[1]);
		};
		expect(scale(0)).toBeGreaterThan(1.15);
		expect(scale(40)).toBeCloseTo(1, 1);
	});

	it('uses a big type size in the hero phase', () => {
		const size = (hook_text: string) =>
			Number.parseFloat(
				styleOf(renderReel(featureProps({hook_text}), 30), 'data-hook-title')['font-size'] ?? '0',
			);
		expect(size(HOOK)).toBeGreaterThanOrEqual(110);
		expect(size(`${HOOK} ${HOOK} ${HOOK} ${HOOK}`)).toBeLessThan(size(HOOK));
		expect(size('ا'.repeat(40) + ' ' + 'ب'.repeat(40) + ' ' + HOOK.repeat(5))).toBeGreaterThanOrEqual(56);
	});

	it('marks the last word with a sweeping rose gold pill that mirrors by language', () => {
		const arabic = renderReel(featureProps({language: 'ar'}), 40);
		expect(arabic).toContain('data-hook-accent="شهر؟"');
		expect(styleOf(arabic, 'data-accent-pill')['transform-origin']).toContain('right');
		const english = renderReel(
			featureProps({language: 'en', hook_text: 'Where does your salary go?'}),
			40,
		);
		expect(english).toContain('data-hook-accent="go?"');
		expect(styleOf(english, 'data-accent-pill')['transform-origin']).toContain('left');
	});

	it('moves from the hero position up to the top zone when the stage takes over', () => {
		const props = featureProps();
		const title = (frame: number) => styleOf(renderReel(props, frame), 'data-hook-title').transform ?? '';
		const move = (transform: string) => Number(/translateY\((-?[\d.]+)px\)/.exec(transform)?.[1]);
		const scale = (transform: string) => Number(/scale\(([\d.]+)\)/.exec(transform)?.[1]);
		expect(move(title(45))).toBeGreaterThan(100);
		expect(move(title(200))).toBeCloseTo(0, 0);
		expect(scale(title(200))).toBeLessThan(scale(title(45)));
	});

	it('leaves the screen to a clip that starts at once, so nothing covers it', () => {
		const source = featureProps();
		const first = source.clips[0];
		expect(first).toBeDefined();
		const props = featureProps({
			clips: first ? [{...first, start_ms: 0}] : [],
		});
		expect(heroEndMs(props)).toBe(0);
		const transform = styleOf(renderReel(props, 0), 'data-hook-title').transform ?? '';
		expect(Number(/translateY\((-?[\d.]+)px\)/.exec(transform)?.[1])).toBeCloseTo(0, 0);
		expect(renderReel(props, 0)).toContain('data-device-frame');
	});

	it('does not repeat the hook in the captions while it fills the screen', () => {
		const markup = renderReel(featureProps(), 20);
		expect(markup).not.toContain('data-token="راتبك"');
		expect(renderReel(featureProps(), 65)).toContain('data-token="علامة تجريبية"');
	});

	it('keeps every caption when the speech does not open with the hook', () => {
		const markup = renderReel(featureProps({hook_text: 'كم باقي من راتبك؟'}), 20);
		expect(markup).toContain('data-token="راتبك"');
	});

	it('keeps every caption when a clip cuts the hero short before the hook is spoken', () => {
		const source = featureProps();
		const clip = source.clips[0];
		const props = featureProps({clips: clip ? [{...clip, start_ms: 0}] : []});
		expect(renderReel(props, 20)).toContain('data-token="راتبك"');
	});

	it('shrinks a long hook further, so three lines still fit the top zone', () => {
		const scale = (hook_text: string) =>
			Number(
				/scale\(([\d.]+)\)/.exec(
					styleOf(renderReel(tipProps({hook_text}), 170), 'data-hook-title').transform ?? '',
				)?.[1],
			);
		const short = scale('راتبك وين يروح؟');
		const long = scale('راتبك وين يروح كل شهر وأنت ما تدري وين راح؟');
		expect(short).toBeLessThanOrEqual(0.5);
		expect(long).toBeLessThan(short);
		expect(long).toBeGreaterThan(0.25);
	});

	it('holds the hero for three seconds at most, and within the reel', () => {
		expect(heroEndMs(tipProps())).toBe(3000);
		expect(heroEndMs(tipProps({duration_ms: 2000}))).toBeLessThanOrEqual(2000);
	});

	it('runs on all three templates', () => {
		for (const props of [featureProps(), tipProps(), mythProps()]) {
			expect(hookWords(renderReel(props, 30)).length).toBe(WORDS.length);
		}
	});

	it('keeps the same pace at 60 fps', () => {
		const props = featureProps({fps: 60});
		const words = hookWords(renderReel(props, 30));
		expect(words.length).toBe(WORDS.length);
		for (const word of words) {
			expect(opacityOf(word.element)).toBe(1);
		}
	});
});

describe('Arabic shaping survives the hook animation', () => {
	it('animates whole words only, each its own inline-block', () => {
		for (let frame = 0; frame < 120; frame += 3) {
			const markup = renderReel(featureProps(), frame);
			for (const word of hookWords(markup)) {
				expect(word.element).toContain('display:inline-block');
				expect(word.element).toContain('white-space:nowrap');
			}
		}
	});

	it('never uses letter-spacing, in any template, on any frame', () => {
		for (const props of [featureProps(), tipProps(), mythProps()]) {
			for (let frame = 0; frame < 180; frame += 7) {
				expect(renderReel(props, frame)).not.toContain('letter-spacing');
			}
		}
	});

	it('uses dir="rtl" with no reversal', () => {
		const markup = renderReel(featureProps(), 40);
		expect(/<[a-z]+[^>]*data-hook-title[^>]*>/.exec(markup)?.[0]).toContain('dir="rtl"');
		expect(hookWords(markup).map((word) => word.text)).toEqual(WORDS);
	});

	it('keeps the brand as one word in the hook', () => {
		const props = featureProps({hook_text: 'خطط مع قوام المال اليوم'});
		const words = hookWords(renderReel(props, 40)).map((word) => word.text);
		expect(words).toEqual(['خطط', 'مع', 'قوام المال', 'اليوم']);
	});

	it('wraps Latin and digits in <bdi> in the hook', () => {
		const markup = renderReel(featureProps({hook_text: 'راتبك 2500 Budget وين؟'}), 40);
		expect(markup).toContain('<bdi>2500</bdi>');
		expect(markup).toContain('<bdi>Budget</bdi>');
	});

	it('keeps text in the top zone from ever reaching past the reel width', () => {
		const style = styleOf(renderReel(featureProps(), 40), 'data-hook-title');
		expect(style['flex-wrap']).toBe('wrap');
	});
});
