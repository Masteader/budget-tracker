import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, it} from 'vitest';
import {DeviceFrame} from '../components/DeviceFrame';
import type {TemplateDefinition} from '../compositions/media';
import {ReelShell} from '../compositions/ReelShell';
import {TEMPLATES} from '../compositions/templates';
import {FontLoadError, FONT_FACES, loadBrandFonts} from '../lib/fonts';
import type {FontEnvironment} from '../lib/fonts';
import {computeLayout} from '../lib/layout';
import {durationInFrames, englishLineAt, musicVolumeAt} from '../lib/timeline';
import {parseRenderProps} from '../props';
import type {RenderProps} from '../props';
import {
	fakeMedia,
	featureProps,
	framesOf,
	mythProps,
	realBrand,
	renderReel,
	styleOf,
	tipProps,
	visibleText,
} from './helpers';

const WATERMARK = 'TEST, not for posting';
const ZONES = {
	instagram: {top: 220, bottom: 420, left: 60, right: 140},
	tiktok: {top: 160, bottom: 480, left: 60, right: 160},
	youtube: {top: 140, bottom: 340, left: 60, right: 140},
	fixture: {top: 220, bottom: 380, left: 60, right: 140},
};

const allTemplates: [string, (overrides?: Partial<RenderProps>) => RenderProps][] = [
	['FeatureDemo', featureProps],
	['DailyTip', tipProps],
	['MythVsFact', mythProps],
];

describe('templates accept valid props', () => {
	it.each(allTemplates)('%s renders at the first and last frame', (_name, make) => {
		const props = make();
		const last = durationInFrames(props) - 1;
		expect(renderReel(props, 0).length).toBeGreaterThan(100);
		expect(renderReel(props, last).length).toBeGreaterThan(100);
	});

	it('DailyTip and MythVsFact run with no clip, FeatureDemo does not', () => {
		expect(tipProps().clips).toEqual([]);
		expect(mythProps().clips).toEqual([]);
		expect(() => featureProps({clips: []})).toThrow();
	});

	it('DailyTip shows three fast cards, numbered in reel order', () => {
		const markup = renderReel(tipProps(), durationInFrames(tipProps()) - 1);
		expect(markup.match(/data-tip-card="/g)).toHaveLength(3);
		const text = visibleText(markup);
		expect(text).toContain('Know your payday cycle');
		expect(text).toContain('Check before you spend');
	});

	it('DailyTip never shows more than three cards', () => {
		const props = tipProps({on_screen_text: ['a1', 'b2', 'c3', 'd4', 'e5']});
		expect(renderReel(props, durationInFrames(props) - 1).match(/data-tip-card="/g)).toHaveLength(3);
	});

	it('DailyTip with no text still renders', () => {
		const props = tipProps({on_screen_text: []});
		expect(renderReel(props, 100)).not.toContain('data-tip-card');
	});

	it.each([
		['ar', 'لا تسوّي كذا', 'الطريقة الذكية'],
		['en', 'Stop doing this', 'The smart way'],
	] as const)('MythVsFact in %s shows the wrong way, then the smart way', (language, stop, smart) => {
		const props = mythProps({language});
		const early = visibleText(renderReel(props, 100));
		expect(early).toContain(stop);
		expect(early).toContain('Keeping it all in your head');
		expect(early).not.toContain(smart);
		const late = visibleText(renderReel(props, durationInFrames(props) - 1));
		expect(late).toContain(stop);
		expect(late).toContain(smart);
		expect(late).toContain('A clear budget by category');
	});

	it('FeatureDemo shows on-screen text as a callout', () => {
		expect(visibleText(renderReel(featureProps(), 150))).toContain('Where does your salary go?');
		expect(visibleText(renderReel(featureProps(), 880))).toContain('Plan by category');
	});

	it.each([
		['DailyTip', tipProps, 'Know your payday cycle'],
		['MythVsFact', mythProps, 'A clear budget by category'],
	] as const)('%s lets a whole English line read left to right in an Arabic reel', (_name, make, line) => {
		const props = make({language: 'ar'});
		const markup = renderReel(props, durationInFrames(props) - 1);
		const flow = new RegExp(`<div[^>]*data-flow-text="ltr"[^>]*>(?:(?!data-flow-text).)*${line.split(' ')[0]}`, 's');
		expect(markup).toMatch(flow);
		expect(visibleText(markup)).toContain(line);
		expect(markup).not.toContain(`<bdi>${line.split(' ')[0]}</bdi>`);
	});

	it('every template follows the digits setting on screen', () => {
		const texts = {on_screen_text: ['Save 2500 first'], hook_text: 'راتبك 2500 وين؟'};
		const eastern = renderReel(tipProps({...texts, digits: 'arabic_indic'}), 170);
		expect(eastern).toContain('٢٥٠٠');
		expect(eastern).not.toContain('2500');
		expect(renderReel(tipProps({...texts, digits: 'western'}), 170)).toContain('2500');
	});
});

describe('the test watermark', () => {
	it.each(allTemplates)('%s shows it on every frame of a test reel', (_name, make) => {
		const props = make();
		for (const frame of framesOf(props).filter((f) => f % 7 === 0 || f < 5)) {
			const markup = renderReel(props, frame);
			expect(markup, `frame ${frame}`).toContain('data-watermark="test"');
			expect(visibleText(markup)).toContain(WATERMARK);
		}
		expect(renderReel(props, durationInFrames(props) - 1)).toContain('data-watermark="test"');
	});

	it.each(['ar', 'en'] as const)('holds on all frames of a short %s reel with nothing skipped', (language) => {
		const props = tipProps({language, duration_ms: 2000});
		for (const frame of framesOf(props)) {
			expect(renderReel(props, frame)).toContain('data-watermark="test"');
		}
	});

	it('is the same on every frame, so no animation can hide it', () => {
		const props = tipProps();
		const element = (frame: number) =>
			/<div[^>]*data-watermark="test".*$/s.exec(renderReel(props, frame))?.[0];
		expect(element(0)).toBeTruthy();
		expect(element(1)).toBe(element(0));
		expect(element(100)).toBe(element(0));
	});

	it('is absent only when props say so, which needs the real brand', () => {
		const props = featureProps({watermark: false, brand: realBrand});
		const markup = renderReel(props, 100);
		expect(markup).not.toContain('data-watermark');
		expect(visibleText(markup)).not.toContain(WATERMARK);
	});

	it('cannot be dropped through props', () => {
		const source = featureProps();
		expect(() => parseRenderProps({...source, watermark: 'false'})).toThrow();
		expect(() => parseRenderProps({...source, watermark: false})).toThrow();
		expect(() => parseRenderProps({...source, hide_watermark: true})).toThrow();
	});
});

describe('a template cannot get above the safety layers', () => {
	const hostile: TemplateDefinition = {
		tilt: {fromDeg: 0, toDeg: 0},
		zoom: {from: 1, to: 1},
		renderStage: () => (
			<div data-hostile="stage" style={{position: 'fixed', inset: 0, zIndex: 999999, background: 'black'}} />
		),
		renderForeground: () => (
			<div data-hostile="foreground" style={{position: 'fixed', inset: 0, zIndex: 999999, background: 'black'}} />
		),
	};
	const shell = (props: RenderProps, frame: number) =>
		renderToStaticMarkup(
			<ReelShell
				props={props}
				template={hostile}
				media={fakeMedia}
				frame={frame}
				fps={props.fps}
				durationInFrames={durationInFrames(props)}
			/>,
		);

	it('still draws the watermark, and after everything the template drew', () => {
		const markup = shell(featureProps(), 100);
		expect(markup).toContain('data-watermark="test"');
		expect(markup.indexOf('data-hostile="stage"')).toBeLessThan(markup.indexOf('data-watermark'));
		expect(markup.indexOf('data-hostile="foreground"')).toBeLessThan(markup.indexOf('data-watermark'));
	});

	it('keeps what a template draws inside isolated layers below the safety layers', () => {
		const markup = shell(featureProps(), 500);
		for (const layer of ['stage', 'foreground']) {
			const style = styleOf(markup, `data-layer="${layer}"`);
			expect(style.isolation, layer).toBe('isolate');
			expect(style.overflow, layer).toBe('hidden');
			expect(Number(style['z-index']), layer).toBeLessThan(
				Number(styleOf(markup, 'data-layer="watermark"')['z-index']),
			);
			expect(Number(style['z-index']), layer).toBeLessThan(
				Number(styleOf(markup, 'data-layer="label"')['z-index']),
			);
		}
	});

	it('draws clips above the stage, and the masks with them', () => {
		const markup = shell(featureProps(), 500);
		expect(Number(styleOf(markup, 'data-layer="stage"')['z-index'])).toBeLessThan(
			Number(styleOf(markup, 'data-layer="clip"')['z-index']),
		);
	});

	it('ranks the watermark above every other layer in the reel', () => {
		const markup = renderReel(featureProps(), 500);
		const ranks = [...markup.matchAll(/data-layer="(\w+)"[^>]*?z-index:(\d+)/g)].map(
			(match) => [match[1], Number(match[2])] as const,
		);
		expect(ranks.length).toBeGreaterThan(5);
		const top = Math.max(...ranks.map(([, rank]) => rank));
		expect(ranks.filter(([, rank]) => rank === top).map(([name]) => name)).toEqual(['watermark']);
	});

	it('every shipped template goes through the shell, with no switch for safety layers', () => {
		for (const definition of Object.values(TEMPLATES)) {
			expect(Object.keys(definition).sort()).toEqual(
				expect.not.arrayContaining(['watermark', 'mask', 'masks', 'label']),
			);
		}
	});
});

describe('progress and tilt mirror by language', () => {
	it.each([
		['ar', 'right'],
		['en', 'left'],
	] as const)('the %s progress bar fills from the %s', (language, side) => {
		const props = featureProps({language});
		const style = styleOf(renderReel(props, 100), 'data-progress-fill');
		expect(style['transform-origin']).toContain(side);
	});

	it('runs from empty on the first frame to full on the last', () => {
		const props = featureProps();
		expect(styleOf(renderReel(props, 0), 'data-progress-fill').transform).toBe('scaleX(0)');
		expect(
			styleOf(renderReel(props, durationInFrames(props) - 1), 'data-progress-fill').transform,
		).toBe('scaleX(1)');
	});

	it('tilts the device the opposite way between Arabic and English', () => {
		const tilt = (language: 'ar' | 'en') => {
			const transform = styleOf(
				renderReel(featureProps({language}), 200),
				'data-device-frame',
			).transform;
			return Number(/rotateY\((-?[\d.]+)deg\)/.exec(transform ?? '')?.[1]);
		};
		expect(tilt('ar')).not.toBe(0);
		expect(tilt('en')).toBeCloseTo(-tilt('ar'));
	});

	it('zooms in over the clip', () => {
		const scale = (frame: number) =>
			Number(
				/scale\(([\d.]+)\)/.exec(
					styleOf(renderReel(featureProps(), frame), 'data-device-frame').transform ?? '',
				)?.[1],
			);
		expect(scale(420)).toBeGreaterThan(scale(120));
	});

	it('sets the reel direction from the language', () => {
		expect(renderReel(featureProps({language: 'ar'}), 100)).toMatch(/data-reel="[^"]*"[^>]*dir="rtl"|dir="rtl"[^>]*data-reel/);
		expect(renderReel(featureProps({language: 'en'}), 100)).toMatch(/data-reel="[^"]*"[^>]*dir="ltr"|dir="ltr"[^>]*data-reel/);
	});
});

describe('the device frame is generic only (D31)', () => {
	it('draws a generic frame around the clip', () => {
		const markup = renderReel(featureProps(), 200);
		expect(markup).toContain('data-device-frame="generic"');
		expect(markup).not.toMatch(/iphone|ipad|apple|notch|island|samsung|pixel-/i);
	});

	it('refuses anything else, in props and in the component', () => {
		expect(() => parseRenderProps({...featureProps(), device_frame: 'iphone'})).toThrow();
		expect(() =>
			renderToStaticMarkup(
				<DeviceFrame kind={'iphone' as 'generic'} language="ar" width={10} height={20} left={0} top={0} tiltDeg={0} scale={1} offsetY={0}>
					<div />
				</DeviceFrame>,
			),
		).toThrow();
	});

	it('shows no device when no clip is on screen', () => {
		expect(renderReel(featureProps(), 10)).not.toContain('data-device-frame');
		expect(renderReel(tipProps(), 100)).not.toContain('data-device-frame');
	});
});

describe('no logo is baked in', () => {
	it('draws the logo from props and nothing else', () => {
		const test = renderReel(featureProps(), 100);
		expect(test.match(/data-logo-src="/g)).toHaveLength(1);
		expect(test).toContain('data-logo-src="test_logo.svg"');
		const real = renderReel(featureProps({watermark: false, brand: realBrand}), 100);
		expect(real).toContain('data-logo-src="approved_mark.svg"');
		expect(real).not.toContain('test_logo');
	});
});

describe('brand tag', () => {
	it('puts the language of the reel first, and keeps the full names', () => {
		const brand = realBrand;
		const arabic = visibleText(
			renderReel(featureProps({watermark: false, brand, language: 'ar'}), 100),
		);
		expect(arabic).toContain('قوام المال Qawam Money');
		const english = visibleText(
			renderReel(featureProps({watermark: false, brand, language: 'en'}), 100),
		);
		expect(english).toContain('Qawam Money قوام المال');
	});

	it('uses the test brand on a test reel', () => {
		const text = visibleText(renderReel(featureProps(), 100));
		expect(text).toContain('علامة تجريبية TEST BRAND');
		expect(text).not.toContain('Qawam');
		expect(text).toContain('#test');
	});

	it('cannot wrap', () => {
		expect(styleOf(renderReel(featureProps(), 100), 'data-brand-tag')['white-space']).toBe('nowrap');
	});
});

describe('safe zones come from props', () => {
	const box = (markup: string, zone: string) => {
		const style = styleOf(markup, `data-zone="${zone}"`);
		const top = Number.parseFloat(style.top ?? 'NaN');
		const left = Number.parseFloat(style.left ?? 'NaN');
		return {
			top,
			left,
			bottom: top + Number.parseFloat(style.height ?? 'NaN'),
			right: left + Number.parseFloat(style.width ?? 'NaN'),
		};
	};

	it.each(Object.entries(ZONES))('%s: every zone stays inside and none overlap', (_name, zones) => {
		const markup = renderReel(featureProps({safe_zones: zones}), 200);
		const names = ['top', 'captions', 'hud'];
		for (const name of names) {
			const rect = box(markup, name);
			expect(rect.top, name).toBeGreaterThanOrEqual(zones.top);
			expect(rect.left, name).toBeGreaterThanOrEqual(zones.left);
			expect(rect.right, name).toBeLessThanOrEqual(1080 - zones.right);
			expect(rect.bottom, name).toBeLessThanOrEqual(1920 - zones.bottom);
		}
		expect(box(markup, 'top').bottom).toBeLessThanOrEqual(box(markup, 'captions').top);
		expect(box(markup, 'captions').bottom).toBeLessThanOrEqual(box(markup, 'hud').top);
	});

	it('moves when the zones move', () => {
		const one = renderReel(featureProps({safe_zones: ZONES.instagram}), 200);
		const two = renderReel(featureProps({safe_zones: ZONES.tiktok}), 200);
		expect(box(one, 'hud').bottom).not.toBe(box(two, 'hud').bottom);
		expect(box(one, 'hud').bottom).toBe(1920 - ZONES.instagram.bottom);
		expect(box(two, 'hud').bottom).toBe(1920 - ZONES.tiktok.bottom);
	});

	it('uses the physical left and right, because platform buttons do not mirror', () => {
		const zones = {top: 200, bottom: 400, left: 30, right: 200};
		for (const language of ['ar', 'en'] as const) {
			const rect = box(renderReel(featureProps({language, safe_zones: zones}), 200), 'hud');
			expect(rect.left).toBe(30);
			expect(rect.right).toBe(880);
		}
	});

	it('refuses zones that leave too little room, with a clear message', () => {
		expect(() => computeLayout({top: 900, bottom: 900, left: 0, right: 0})).toThrow(/safe zones/);
		expect(() => computeLayout({top: 0, bottom: 0, left: 500, right: 500})).toThrow(/safe zones/);
	});
});

describe('a missing font fails the render', () => {
	const environment = (fail: (file: string) => boolean, available = true) => {
		const added: unknown[] = [];
		const value: FontEnvironment = {
			createFace: (_family, source) => ({
				load: () =>
					fail(source) ? Promise.reject(new Error('404')) : Promise.resolve({source}),
			}),
			addFace: (face) => added.push(face),
			isAvailable: () => available,
			fileUrl: (file) => `/public/${file}`,
			readFont: (file) => {
				const bytes = readFileSync(resolve(process.cwd(), 'public', file));
				return Promise.resolve(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
			},
		};
		return {value, added};
	};

	it('loads every face when all exist', async () => {
		const {value, added} = environment(() => false);
		await loadBrandFonts(value, []);
		expect(added).toHaveLength(FONT_FACES.length);
	});

	it('includes Cairo for Arabic and Outfit for Latin', () => {
		const families = new Set(FONT_FACES.map((face) => face.family));
		expect(families).toEqual(new Set(['Cairo', 'Outfit']));
	});

	it.each(['Cairo-Bold', 'Cairo-Regular', 'Outfit-Variable'])('rejects when %s is missing', async (file) => {
		const {value} = environment((source) => source.includes(file));
		await expect(loadBrandFonts(value, [])).rejects.toThrow(FontLoadError);
	});

	it('rejects when the browser says Cairo is not usable', async () => {
		const {value} = environment(() => false, false);
		await expect(loadBrandFonts(value, [])).rejects.toThrow(FontLoadError);
	});
});

describe('the English line', () => {
	it('shows in an Arabic reel', () => {
		expect(visibleText(renderReel(featureProps(), 20))).toContain('Where does your salary go');
	});

	it('is left out of an English reel, where the captions are already English', () => {
		const props = featureProps({language: 'en'});
		expect(renderReel(props, 20)).not.toContain('data-english-line');
	});

	it('walks through a long subtitle in chunks, in order, with no word cut', () => {
		const text = 'Where does your salary go every month? Most people never check. Plan it by category and see it clearly.';
		const words = [{text: 'x1', start_ms: 0, end_ms: 100}, {text: 'x2', start_ms: 9000, end_ms: 9900}];
		const seen: string[] = [];
		for (let ms = 0; ms < 10000; ms += 100) {
			const line = englishLineAt(text, words, ms, 10000);
			if (line && seen[seen.length - 1] !== line) {
				seen.push(line);
			}
		}
		expect(seen.length).toBeGreaterThan(1);
		expect(seen.join(' ')).toBe(text);
		for (const line of seen) {
			expect(line.length).toBeLessThanOrEqual(60);
		}
	});

	it('shows nothing before speech starts or after it ends', () => {
		const words = [{text: 'x', start_ms: 2000, end_ms: 3000}];
		expect(englishLineAt('Hello there', words, 1000, 10000)).toBeNull();
		expect(englishLineAt('Hello there', words, 2500, 10000)).toBe('Hello there');
		expect(englishLineAt('Hello there', words, 9000, 10000)).toBeNull();
	});
});

describe('music ducking', () => {
	const words = [
		{text: 'a', start_ms: 1000, end_ms: 2000},
		{text: 'b', start_ms: 5000, end_ms: 6000},
	];
	it('is the under-voice level while speaking and the pause level between', () => {
		expect(musicVolumeAt(1500, words, 0.12, 0.25)).toBeCloseTo(0.12);
		expect(musicVolumeAt(3500, words, 0.12, 0.25)).toBeCloseTo(0.25);
		expect(musicVolumeAt(0, [], 0.12, 0.25)).toBeCloseTo(0.25);
	});
	it('ramps rather than jumps', () => {
		const volume = musicVolumeAt(2100, words, 0.12, 0.25);
		expect(volume).toBeGreaterThan(0.12);
		expect(volume).toBeLessThan(0.25);
	});
});
