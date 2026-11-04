import {describe, expect, it} from 'vitest';
import {factRevealFrame, tipBeats} from '../lib/timeline';
import {durationInFrames} from '../lib/timeline';
import {mythProps, renderReel, tipProps} from './helpers';

const speech = (seconds: number, brandAtSeconds?: number) => {
	const words = [];
	for (let at = 0; at < seconds * 1000; at += 400) {
		words.push({text: `كلمة${at}`, start_ms: at, end_ms: at + 380});
	}
	if (brandAtSeconds !== undefined) {
		const index = Math.round((brandAtSeconds * 1000) / 400);
		words.splice(
			index,
			2,
			{text: 'قوام', start_ms: index * 400, end_ms: index * 400 + 380},
			{text: 'المال', start_ms: (index + 1) * 400, end_ms: (index + 1) * 400 + 380},
		);
	}
	return words;
};

const NAMES = ['قوام المال', 'Qawam Money'];

describe('Template B follows the length of the script', () => {
	it('spreads the cards over the speech, for a 30 s reel and for a 9 s one', () => {
		for (const seconds of [9, 30, 45]) {
			const beats = tipBeats({
				stageStartFrame: 90,
				durationInFrames: seconds * 30,
				fps: 30,
				words: speech(seconds - 1),
				brandNames: NAMES,
				cardCount: 3,
			});
			expect(beats.cardAt).toHaveLength(3);
			expect(beats.cardAt[0]).toBe(90);
			const spans = [beats.cardAt[1]! - beats.cardAt[0]!, beats.cardAt[2]! - beats.cardAt[1]!, beats.outroAt - beats.cardAt[2]!];
			expect(Math.max(...spans) - Math.min(...spans)).toBeLessThanOrEqual(1);
			expect(beats.outroAt).toBeGreaterThan(0.6 * seconds * 30);
		}
	});

	it('does not leave the third card landing at 7 s of a 30 s reel', () => {
		const beats = tipBeats({stageStartFrame: 90, durationInFrames: 900, fps: 30, words: speech(29), brandNames: NAMES, cardCount: 3});
		expect(beats.cardAt[2]! / 30).toBeGreaterThan(12);
	});

	it('starts the outro when the script names the brand', () => {
		const beats = tipBeats({stageStartFrame: 90, durationInFrames: 900, fps: 30, words: speech(29, 24), brandNames: NAMES, cardCount: 3});
		expect(Math.abs(beats.outroAt / 30 - 24)).toBeLessThan(0.1);
	});

	it('ignores a brand named early, because the outro ends the reel', () => {
		const beats = tipBeats({stageStartFrame: 90, durationInFrames: 900, fps: 30, words: speech(29, 5), brandNames: NAMES, cardCount: 3});
		expect(beats.outroAt / 30).toBeGreaterThan(18);
	});

	it('copes with no speech and no cards', () => {
		const none = tipBeats({stageStartFrame: 90, durationInFrames: 180, fps: 30, words: [], brandNames: NAMES, cardCount: 3});
		expect(none.outroAt).toBeGreaterThan(90);
		expect(none.outroAt).toBeLessThan(180);
		expect(tipBeats({stageStartFrame: 90, durationInFrames: 180, fps: 30, words: [], brandNames: NAMES, cardCount: 0}).cardAt).toEqual([]);
	});
});

describe('Template B shows one card at a time, then how the brand helps', () => {
	const words = speech(29, 24);
	const props = tipProps({duration_ms: 30000, words});
	const card = (frame: number) => [...renderReel(props, frame).matchAll(/data-tip-card="(\d)"/g)].map((match) => match[1]);

	it('shows each card in its own turn', () => {
		const beats = tipBeats({stageStartFrame: 90, durationInFrames: 900, fps: 30, words, brandNames: NAMES, cardCount: 3});
		expect(card(beats.cardAt[0]! + 45)).toEqual(['0']);
		expect(card(beats.cardAt[1]! + 45)).toEqual(['1']);
		expect(card(beats.cardAt[2]! + 45)).toEqual(['2']);
	});

	it('ends on a recap with the brand and a visual, not only caption text', () => {
		const markup = renderReel(props, 800);
		expect(card(800)).toEqual(['0', '1', '2']);
		expect(markup).toContain('data-brand-lockup');
		expect(markup).toContain('data-budget-ring');
		expect(markup).toContain('data-logo-src="test_logo.svg"');
	});

	it('changes the stage in every second of the reel, with no frozen stretch', () => {
		const stage = (frame: number) => /data-layer="stage".*data-layer="clip"/s.exec(renderReel(props, frame))?.[0];
		for (let frame = 90; frame + 30 < durationInFrames(props); frame += 30) {
			expect(stage(frame), `frame ${frame}`).not.toBe(stage(frame + 30));
		}
	});
});

describe('Template C is a fast, visual contrast', () => {
	it('reveals the fact early, for every length', () => {
		for (const seconds of [6, 15, 25, 30]) {
			const at = factRevealFrame(90, seconds * 30, 30);
			expect(at).toBeGreaterThan(90);
			expect((at - 90) / 30).toBeLessThanOrEqual(3.5);
			expect((at - 90) / (seconds * 30 - 90)).toBeLessThanOrEqual(0.3);
		}
	});

	const props = mythProps({duration_ms: 20000});
	const reveal = factRevealFrame(90, 600, 30);

	it('draws a visual of the mess before the reveal, and of the order after it', () => {
		const before = renderReel(props, reveal - 5);
		expect(before.match(/data-note-piece="/g)?.length).toBeGreaterThanOrEqual(6);
		expect(before).toContain('data-myth-stamp');
		const after = renderReel(props, reveal + 90);
		expect(after.match(/data-note-piece="/g)?.length).toBeGreaterThanOrEqual(6);
		expect(after).toContain('data-fact-tick');
	});

	it('moves the pieces into order, from different places', () => {
		const pieces = (frame: number) =>
			[...renderReel(props, frame).matchAll(/data-note-piece="\d+"[^>]*transform:([^;"]+)/g)].map((match) => match[1]);
		const messy = pieces(reveal - 5);
		const tidy = pieces(reveal + 90);
		expect(messy).not.toEqual(tidy);
		expect(new Set(tidy.map((value) => /rotate\((-?[\d.]+)deg\)/.exec(value ?? '')?.[1])).size).toBe(1);
		expect(Math.abs(Number(/rotate\((-?[\d.]+)deg\)/.exec(tidy[0] ?? '')?.[1]))).toBeLessThan(0.5);
	});

	it('crosses out the myth once the fact is in', () => {
		expect(renderReel(props, reveal - 5)).not.toContain('data-myth-strike');
		expect(renderReel(props, reveal + 60)).toContain('data-myth-strike');
	});

	it('shows the brand after the reveal', () => {
		expect(renderReel(props, 590)).toContain('data-brand-lockup');
	});

	it('changes the stage in every second of the reel', () => {
		const stage = (frame: number) => /data-layer="stage".*data-layer="clip"/s.exec(renderReel(props, frame))?.[0];
		for (let frame = 90; frame + 30 < 600; frame += 30) {
			expect(stage(frame), `frame ${frame}`).not.toBe(stage(frame + 30));
		}
	});
});
