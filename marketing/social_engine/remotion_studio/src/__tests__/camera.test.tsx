import {describe, expect, it} from 'vitest';
import {planCallout} from '../compositions/FeatureDemo';
import {FeatureDemo} from '../compositions/FeatureDemo';
import {cameraPose} from '../lib/camera';
import {CANVAS_WIDTH, computeLayout} from '../lib/layout';
import {clipWindow} from '../lib/timeline';
import {parseRenderProps} from '../props';
import type {PropsClip} from '../props';
import {estimateWidth, featureProps, renderReel, styleOf} from './helpers';

const ZONES = {
	instagram: {top: 220, bottom: 420, left: 60, right: 140},
	tiktok: {top: 160, bottom: 480, left: 60, right: 160},
	youtube: {top: 140, bottom: 340, left: 60, right: 140},
	narrow: {top: 220, bottom: 420, left: 0, right: 660},
};
const SHA = '3'.repeat(64);

const clip = (focal_point: PropsClip['focal_point'], start_ms = 3000, end_ms = 15000): PropsClip => ({
	src: 'clips/payday_cycle/clip_01.mp4',
	folder: 'payday_cycle',
	sha256: SHA,
	start_ms,
	end_ms,
	mask_regions: [],
	focal_point,
});

const pose = (focal: PropsClip['focal_point'], frame: number, zones = ZONES.instagram) => {
	const reelClip = clip(focal);
	return cameraPose({
		clip: reelClip,
		clips: [reelClip],
		frame,
		fps: 30,
		layout: computeLayout(zones),
		motion: FeatureDemo,
	});
};

describe('the phone is the hero', () => {
	it('takes well over half the canvas width', () => {
		for (const zones of [ZONES.instagram, ZONES.tiktok, ZONES.youtube]) {
			expect(computeLayout(zones).device.width).toBeGreaterThanOrEqual(0.58 * CANVAS_WIDTH);
		}
	});

	it('stays inside the zones sideways at the narrowest accepted zone', () => {
		const layout = computeLayout(ZONES.narrow);
		expect(layout.device.left).toBeGreaterThanOrEqual(layout.content.left);
		expect(layout.device.left + layout.device.width).toBeLessThanOrEqual(layout.content.left + layout.content.width);
	});

	it('shows the app at about its real size or more when zoomed, so its text can be read', () => {
		const settled = pose({x: 0.5, y: 0.5}, 300);
		const shownWidth = computeLayout(ZONES.instagram).device.width * settled.deviceScale * settled.zoom;
		expect(shownWidth).toBeGreaterThanOrEqual(1080);
	});
});

describe('the camera zooms to the focal point from props', () => {
	it('opens wide with the whole phone clear of the captions, then pushes in', () => {
		const layout = computeLayout(ZONES.instagram);
		const wide = pose({x: 0.5, y: 0.5}, 92);
		expect(wide.zoom).toBeCloseTo(1, 1);
		expect(layout.device.top + wide.deviceScale * layout.device.height).toBeLessThanOrEqual(layout.view.top + layout.view.height + 1);
		const settled = pose({x: 0.5, y: 0.5}, 300);
		expect(settled.zoom).toBeGreaterThanOrEqual(1.45);
		expect(settled.pushed).toBe(1);
		// The whole move, from the phone in full view to the feature: well past a gentle drift.
		expect((settled.deviceScale * settled.zoom) / wide.deviceScale).toBeGreaterThanOrEqual(2.5);
	});

	it('keeps moving once settled', () => {
		expect(pose({x: 0.5, y: 0.5}, 400).zoom).toBeGreaterThan(pose({x: 0.5, y: 0.5}, 200).zoom);
	});

	it('pulls back before the clip ends', () => {
		expect(pose({x: 0.5, y: 0.5}, 449).pushed).toBeLessThan(0.1);
	});

	it.each([
		[0.2, 0.15],
		[0.5, 0.5],
		[0.8, 0.3],
		[0.35, 0.7],
		[0.5, 0.92],
	])('brings the point (%f, %f) to the clear part of the screen', (x, y) => {
		const layout = computeLayout(ZONES.instagram);
		const {focalCanvas} = pose({x, y}, 300);
		expect(focalCanvas.y).toBeGreaterThanOrEqual(layout.view.top);
		expect(focalCanvas.y).toBeLessThanOrEqual(layout.view.top + layout.view.height);
		expect(focalCanvas.x).toBeGreaterThanOrEqual(layout.content.left);
		expect(focalCanvas.x).toBeLessThanOrEqual(layout.content.left + layout.content.width);
	});

	it('moves differently for different focal points', () => {
		const one = pose({x: 0.2, y: 0.2}, 300);
		const two = pose({x: 0.8, y: 0.7}, 300);
		expect(one.translateX).not.toBe(two.translateX);
		expect(one.translateY).not.toBe(two.translateY);
	});

	it('has a default when props give no focal point', () => {
		const settled = pose(null, 300);
		expect(settled.zoom).toBeGreaterThanOrEqual(1.45);
		expect(settled.translateY).toContain('%');
	});

	it('uses the same pace at 60 fps', () => {
		const reelClip = clip({x: 0.5, y: 0.5});
		const at = (frame: number, fps: number) =>
			cameraPose({clip: reelClip, clips: [reelClip], frame, fps, layout: computeLayout(ZONES.instagram), motion: FeatureDemo});
		expect(at(600, 60).zoom).toBeCloseTo(at(300, 30).zoom, 3);
	});

	it('still zooms inside a very short clip', () => {
		const reelClip = clip({x: 0.5, y: 0.5}, 1000, 3000);
		const best = Math.max(
			...Array.from({length: 60}, (_, index) =>
				cameraPose({clip: reelClip, clips: [reelClip], frame: 30 + index, fps: 30, layout: computeLayout(ZONES.instagram), motion: FeatureDemo}).zoom,
			),
		);
		expect(best).toBeGreaterThanOrEqual(1.45);
	});
});

describe('the masks move with the clip', () => {
	const basket: PropsClip = {
		...clip({x: 0.5, y: 0.6}),
		src: 'clips/smart_basket/clip_01.mp4',
		folder: 'smart_basket',
		mask_regions: [{x: 0.05, y: 0.2, width: 0.9, height: 0.08}],
	};
	const props = featureProps({clips: [basket], words: []});

	it('puts the sharp clip and its masks in the one box the camera moves', () => {
		for (const frame of [90, 120, 200, 300, 449]) {
			const markup = renderReel(props, frame);
			const box = /<div[^>]*data-clip-box.*$/s.exec(markup)?.[0] ?? '';
			expect(box.indexOf('data-clip-media')).toBeGreaterThanOrEqual(0);
			expect(box.indexOf('data-clip-masks')).toBeGreaterThan(box.indexOf('data-clip-media'));
			expect(styleOf(markup, 'data-clip-box').transform).toContain('scale(');
			expect(styleOf(markup, 'data-mask-region').left).toBe('5%');
			expect(styleOf(markup, 'data-mask-region').top).toBe('20%');
		}
	});

	it('zooms the box to the settled zoom in the real markup', () => {
		const transform = styleOf(renderReel(props, 300), 'data-clip-box').transform ?? '';
		expect(Number(/scale\(([\d.]+)\)/.exec(transform)?.[1])).toBeGreaterThanOrEqual(1.45);
		expect(styleOf(renderReel(props, 300), 'data-clip-box')['transform-origin']).toBe('0 0');
	});

	it('draws nothing that masks do not move with', () => {
		const markup = renderReel(props, 300);
		const outside = markup.slice(0, markup.indexOf('data-clip-box'));
		expect(outside).not.toContain('data-clip-media');
	});
});

describe('overlays stay off the important area', () => {
	const REACH = 150; // how far around the focal point counts as the feature

	it.each(Object.entries(ZONES))('in %s the focal point is clear of every overlay on every frame', (_name, zones) => {
		const layout = computeLayout(zones);
		const reelClip = clip({x: 0.5, y: 0.45});
		const {from, to} = clipWindow(reelClip, 30);
		for (let frame = from; frame < to; frame++) {
			const camera = cameraPose({clip: reelClip, clips: [reelClip], frame, fps: 30, layout, motion: FeatureDemo});
			expect(camera.focalCanvas.y, `frame ${frame}`).toBeGreaterThanOrEqual(layout.labelBand.top + layout.labelBand.height);
			expect(camera.focalCanvas.y, `frame ${frame}`).toBeLessThanOrEqual(layout.captions.top);
		}
	});

	it('puts a callout under the feature once the camera has settled, even a long one', () => {
		const layout = computeLayout(ZONES.instagram);
		const {focalCanvas} = pose({x: 0.5, y: 0.45}, 300);
		const plan = planCallout('خطط ميزانيتك '.repeat(12).trim().slice(0, 160), ['قوام المال'], 'ar', 'western', layout, estimateWidth);
		expect(focalCanvas.y + REACH).toBeLessThanOrEqual(plan.top);
		expect(plan.top + plan.height).toBeLessThanOrEqual(layout.captions.top);
	});

	it('holds a callout back until the camera has settled, so it never slides over the feature', () => {
		const props = featureProps({words: []});
		expect(renderReel(props, 95)).not.toContain('data-callout');
		expect(renderReel(props, 300)).toContain('data-callout');
	});

	it('moves a callout above a feature that rests low in the clip, so it never covers it', () => {
		const low = clip({x: 0.5, y: 0.95});
		const props = featureProps({clips: [low], words: [], on_screen_text: ['قصير']});
		const layout = computeLayout(props.safe_zones);
		const camera = cameraPose({clip: low, clips: [low], frame: 300, fps: 30, layout, motion: FeatureDemo});
		const top = Number.parseFloat(styleOf(renderReel(props, 300), 'data-callout').top ?? 'NaN');
		expect(top).toBeLessThan(camera.focalCanvas.y - 150);
	});

	it('keeps the label out of the phone', () => {
		const layout = computeLayout(ZONES.instagram);
		expect(layout.labelBand.top + layout.labelBand.height).toBeLessThanOrEqual(layout.device.top);
	});

	it('keeps the label out of the phone at the narrowest zone too', () => {
		const layout = computeLayout(ZONES.narrow);
		expect(layout.labelBand.top + layout.labelBand.height).toBeLessThanOrEqual(layout.device.top);
	});
});

describe('the focal point in the contract', () => {
	const base = () => featureProps();

	it.each([
		['x past the clip', {x: 1.5, y: 0.5}],
		['a negative y', {x: 0.5, y: -0.1}],
		['an unknown field', {x: 0.5, y: 0.5, zoom: 9}],
		['a string', '50%'],
	])('refuses %s', (_name, focal_point) => {
		const props = base();
		const clips = props.clips.map((item) => ({...item, focal_point}));
		expect(() => parseRenderProps({...props, clips})).toThrow();
	});

	it('takes null, which means the default', () => {
		const props = base();
		const clips = props.clips.map((item) => ({...item, focal_point: null}));
		expect(() => parseRenderProps({...props, clips})).not.toThrow();
	});

	it('refuses a clip that leaves it out, as any other field', () => {
		const props = base();
		const clips = props.clips.map((item) => {
			const partial: Partial<PropsClip> = {...item};
			delete partial.focal_point;
			return partial;
		});
		expect(() => parseRenderProps({...props, clips})).toThrow();
	});
});
