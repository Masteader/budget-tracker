import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {describe, expect, it} from 'vitest';
import {parseRenderProps} from '../props';
import type {PropsClip, RenderProps} from '../props';
import {featureProps, renderReel, styleOf, visibleText} from './helpers';

const EN = 'illustrative prices';
const AR = 'أسعار توضيحية';
const FULL_LABEL = `${EN} / ${AR}`;

const SHA = '3'.repeat(64);

const basket = (start_ms: number, end_ms: number, regions = [{x: 0.05, y: 0.2, width: 0.9, height: 0.08}]): PropsClip => ({
	src: 'clips/smart_basket/clip_01.mp4',
	folder: 'smart_basket',
	sha256: SHA,
	start_ms,
	end_ms,
	mask_regions: regions,
});

const plain = (start_ms: number, end_ms: number): PropsClip => ({
	src: 'clips/payday_cycle/clip_01.mp4',
	folder: 'payday_cycle',
	sha256: SHA,
	start_ms,
	end_ms,
	mask_regions: [],
});

const props = (clips: PropsClip[], language: 'ar' | 'en' = 'ar', fps: 30 | 60 = 30): RenderProps =>
	featureProps({clips, language, fps, duration_ms: 6000, words: []});

const framesBetween = (fromMs: number, toMs: number, fps: number): number[] => {
	const from = Math.floor((fromMs * fps) / 1000);
	const to = Math.ceil((toMs * fps) / 1000);
	return Array.from({length: to - from}, (_, index) => from + index);
};

describe.each(['ar', 'en'] as const)('a smart_basket clip in a %s reel', (language) => {
	it.each([30, 60] as const)('shows every mask and the full label on every frame at %i fps', (fps) => {
		const regions = [
			{x: 0.05, y: 0.2, width: 0.9, height: 0.08},
			{x: 0.1, y: 0.5, width: 0.5, height: 0.05},
		];
		const reel = props([basket(1000, 3000, regions)], language, fps);
		for (const frame of framesBetween(1000, 3000, fps)) {
			const markup = renderReel(reel, frame);
			expect(markup, `frame ${frame}`).toContain('data-clip-media="clips/smart_basket/clip_01.mp4"');
			expect(markup.match(/data-mask-region="/g), `frame ${frame}`).toHaveLength(2);
			const text = visibleText(markup);
			expect(text, `frame ${frame}`).toContain(EN);
			expect(text, `frame ${frame}`).toContain(AR);
			expect(text, `frame ${frame}`).toContain(FULL_LABEL);
		}
	});

	it('shows neither before the clip or after it', () => {
		const reel = props([basket(1000, 3000)], language);
		for (const frame of [0, 10, 29, 90, 100, 179]) {
			const markup = renderReel(reel, frame);
			expect(markup, `frame ${frame}`).not.toContain('data-clip-media');
			expect(markup, `frame ${frame}`).not.toContain('data-mask-region');
			expect(visibleText(markup), `frame ${frame}`).not.toContain(EN);
		}
	});

	it('shows neither for a clip from another folder', () => {
		const reel = props([plain(1000, 3000)], language);
		for (const frame of framesBetween(1000, 3000, 30)) {
			const markup = renderReel(reel, frame);
			expect(markup).toContain('data-clip-media');
			expect(markup).not.toContain('data-mask-region');
			expect(markup).not.toContain('data-illustrative-label');
			expect(visibleText(markup)).not.toContain(AR);
		}
	});

	it('moves to the label straight after a plain clip, with no frame between', () => {
		const reel = props([plain(0, 2000), basket(2000, 4000)], language);
		expect(renderReel(reel, 59)).not.toContain('data-illustrative-label');
		expect(renderReel(reel, 60)).toContain('data-illustrative-label');
		expect(renderReel(reel, 119)).toContain('data-illustrative-label');
		expect(renderReel(reel, 120)).not.toContain('data-illustrative-label');
	});
});

describe('the masks sit on top of the clip', () => {
	const markup = renderReel(props([basket(1000, 3000)]), 50);

	it('comes after the sharp clip in the same box, so it paints over it and moves with it', () => {
		const box = /<div[^>]*data-clip-box.*$/s.exec(markup)?.[0] ?? '';
		const media = box.indexOf('data-clip-media');
		const masks = box.indexOf('data-clip-masks');
		expect(media).toBeGreaterThanOrEqual(0);
		expect(masks).toBeGreaterThan(media);
		expect(box.indexOf('data-mask-region')).toBeGreaterThan(media);
		expect(styleOf(markup, 'data-clip-masks').position).toBe('absolute');
		expect(styleOf(markup, 'data-clip-masks').inset).toBe('0');
		expect(Number(styleOf(markup, 'data-clip-masks')['z-index'])).toBeGreaterThan(0);
	});

	it('is placed by the fractions in props', () => {
		const style = styleOf(markup, 'data-mask-region');
		expect(style.left).toBe('5%');
		expect(style.top).toBe('20%');
		expect(style.width).toBe('90%');
		expect(style.height).toBe('8%');
	});

	it('blurs a copy of the clip, over an opaque base, so nothing sharp can show through', () => {
		const style = styleOf(markup, 'data-mask-region');
		expect(style.overflow).toBe('hidden');
		expect(style.background).toMatch(/#1E0B12/i);
		const blur = /filter:blur\((\d+)px\)/.exec(markup);
		expect(Number(blur?.[1])).toBeGreaterThanOrEqual(16);
	});

	it('sizes the sharp clip by its own width and height, so fractions land true at any shape', () => {
		const box = styleOf(markup, 'data-clip-box');
		expect(box.position).toBe('relative');
		expect(box.width).toBe('100%');
		expect(box.height).toBeUndefined();
	});

	it('draws no second clip outside the masks', () => {
		const region = /data-mask-region.*$/s.exec(markup)?.[0] ?? '';
		const total = markup.match(/data-clip-media="/g)?.length;
		const insideMask = region.match(/data-clip-media="/g)?.length;
		expect(total).toBe((insideMask ?? 0) + 1);
	});
});

describe('the label', () => {
	const reel = props([basket(1000, 3000)]);

	it('isolates each language', () => {
		const markup = renderReel(reel, 50);
		expect(markup).toContain(`<bdi>${EN}</bdi>`);
		expect(markup).toContain(`<bdi>${AR}</bdi>`);
	});

	it('has no animation, so its first frame is as readable as its last', () => {
		const label = (frame: number) =>
			/<div[^>]*data-illustrative-label.*?<\/div>/s.exec(renderReel(reel, frame))?.[0];
		expect(label(30)).toBeTruthy();
		expect(label(31)).toBe(label(30));
		expect(label(89)).toBe(label(30));
		expect(label(30)).not.toContain('opacity');
		expect(label(30)).not.toContain('transform');
	});

	it('sits above the clip and captions, inside the safe area', () => {
		const markup = renderReel(reel, 50);
		const rank = (name: string) => Number(styleOf(markup, `data-layer="${name}"`)['z-index']);
		expect(rank('label')).toBeGreaterThan(rank('clip'));
		expect(rank('label')).toBeGreaterThan(rank('captions'));
		const style = styleOf(markup, 'data-illustrative-label');
		const zones = reel.safe_zones;
		expect(Number.parseFloat(style.top ?? '0')).toBeGreaterThanOrEqual(zones.top);
		expect(Number.parseFloat(style.left ?? '0')).toBeGreaterThanOrEqual(zones.left);
	});

	it('follows the clip that is really on screen when clips overlap', () => {
		const overlap = props([plain(1000, 3000), basket(2000, 4000)]);
		expect(renderReel(overlap, 45)).not.toContain('data-illustrative-label');
		expect(renderReel(overlap, 75)).toContain('data-illustrative-label');
		const other = props([basket(1000, 3000), plain(2000, 4000)]);
		expect(renderReel(other, 45)).toContain('data-illustrative-label');
		expect(renderReel(other, 75)).not.toContain('data-illustrative-label');
		expect(renderReel(other, 75)).not.toContain('data-mask-region');
	});
});

describe('props offer no way to remove them', () => {
	const source = (): RenderProps => props([basket(1000, 3000)]);

	it('has no field for it in the frozen contract', () => {
		const schema = JSON.parse(readFileSync(resolve(process.cwd(), 'props.schema.json'), 'utf-8'));
		const fieldNames = (node: unknown): string[] => {
			if (typeof node !== 'object' || node === null) {
				return [];
			}
			const {properties} = node as {properties?: Record<string, unknown>};
			return [
				...Object.keys(properties ?? {}),
				...Object.values(node).flatMap((child) => fieldNames(child)),
			];
		};
		const names = fieldNames(schema);
		expect(names).toContain('mask_regions');
		for (const name of names) {
			expect(name).not.toMatch(/illustrative|label|hide|show|disable|enabled|no_mask/i);
		}
	});

	it.each([
		['show_label', false],
		['illustrative_label', false],
		['hide_label', true],
		['mask_enabled', false],
	])('refuses a top-level %s', (field, value) => {
		expect(() => parseRenderProps({...source(), [field]: value})).toThrow();
	});

	it('refuses the same on the clip', () => {
		const reel = source();
		const clip = reel.clips[0];
		expect(() =>
			parseRenderProps({...reel, clips: [{...clip, show_label: false}]}),
		).toThrow();
	});

	it('refuses a Smart Basket clip with its masks taken away', () => {
		const reel = source();
		const clip = reel.clips[0];
		expect(() => parseRenderProps({...reel, clips: [{...clip, mask_regions: []}]})).toThrow();
	});

	it('refuses a basket clip dressed up as another folder', () => {
		const reel = source();
		const clip = reel.clips[0];
		expect(() =>
			parseRenderProps({...reel, clips: [{...clip, folder: 'payday_cycle'}]}),
		).toThrow();
	});
});
