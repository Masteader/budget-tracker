import type {CaptionWord, PropsClip, RenderProps} from '../props';
import {REAL_BRAND_NAME_AR, REAL_BRAND_NAME_EN} from '../props';
import {mergeBrandTokens, textTokens} from './captionGrouping';
import {groupAtoms} from './text';

/** Pure time arithmetic. Every frame's picture is decided here, so tests can walk each frame. */

const HOOK_HERO_MS = 3000;
const DUCK_RAMP_MS = 250;
const ENGLISH_LINE_CHARS = 56;
const ENGLISH_ORPHAN_CHARS = 18;

export const msToFrame = (ms: number, fps: number): number => Math.floor((ms * fps) / 1000);

export const durationInFrames = (props: Pick<RenderProps, 'duration_ms' | 'fps'>): number =>
	Math.max(1, Math.ceil((props.duration_ms * props.fps) / 1000));

export type FrameWindow = {from: number; to: number};

/** `to` is exclusive and rounded up, so a clip is never cut a frame short of its masks. */
export const clipWindow = (clip: PropsClip, fps: number): FrameWindow => ({
	from: msToFrame(clip.start_ms, fps),
	to: Math.ceil((clip.end_ms * fps) / 1000),
});

/** The one clip on screen at this frame. When clips overlap, the one that started last. */
export const shownClip = (clips: PropsClip[], frame: number, fps: number): PropsClip | null => {
	let shown: PropsClip | null = null;
	for (const clip of clips) {
		const {from, to} = clipWindow(clip, fps);
		if (frame >= from && frame < to && (!shown || clip.start_ms >= shown.start_ms)) {
			shown = clip;
		}
	}
	return shown;
};

/** Where the run of back-to-back clips holding this one began, so the phone enters only once. */
export const clipRunStartMs = (clips: PropsClip[], clip: PropsClip): number => {
	let start = clip.start_ms;
	for (let moved = true; moved; ) {
		moved = false;
		for (const other of clips) {
			if (other.start_ms < start && other.end_ms >= start) {
				start = other.start_ms;
				moved = true;
			}
		}
	}
	return start;
};

/** The hook has the screen alone until the first clip or three seconds, whichever comes first. */
export const heroEndMs = (props: Pick<RenderProps, 'clips' | 'duration_ms'>): number =>
	Math.min(HOOK_HERO_MS, props.duration_ms, ...props.clips.map((clip) => clip.start_ms));

const plainWord = (text: string): string =>
	text.normalize('NFC').replace(/[\p{P}\p{S}]/gu, '').toLowerCase();

/**
 * The hook is on screen in huge type while it is being spoken, so captions repeating it would only
 * compete with it. Captions take over from the first word after the hook. If the speech does not
 * open with the hook, or runs on past the hero phase, every word stays.
 */
export const wordsAfterHook = (
	words: CaptionWord[],
	hookText: string,
	heroEnd: number,
): CaptionWord[] => {
	const hook = hookText.trim().split(/\s+/).map(plainWord);
	const opensWithHook = hook.every((word, index) => plainWord(words[index]?.text ?? '') === word);
	const last = words[hook.length - 1];
	return opensWithHook && last && last.start_ms < heroEnd ? words.slice(hook.length) : words;
};

// A sentence ends at this mark only where a space or the end follows, so 1.5 and qawam.money hold.
const SENTENCES = /\S(?:.*?[.!?]+(?=\s|$)|.*$)/gsu;

const joined = (pieces: string[]): string => pieces.join(' ');

const chunkSubtitle = (text: string, brandNames: string[]): string[] => {
	const chunks: string[] = [];
	for (const sentence of text.match(SENTENCES) ?? []) {
		const lines: string[][] = [[]];
		const atoms = groupAtoms(textTokens(sentence, brandNames), (token) => token.text);
		for (const atom of atoms) {
			const piece = joined(atom.map((token) => token.text));
			const line = lines[lines.length - 1] as string[];
			if (line.length > 0 && joined(line).length + piece.length + 1 > ENGLISH_LINE_CHARS) {
				lines.push([piece]);
			} else {
				line.push(piece);
			}
		}
		// A sentence's last word or two would flash up alone, so the line before lends it some.
		const last = lines[lines.length - 1] as string[];
		const before = lines[lines.length - 2];
		while (before && before.length > 1 && joined(last).length < ENGLISH_ORPHAN_CHARS) {
			last.unshift(before.pop() as string);
		}
		chunks.push(...lines.filter((line) => line.length > 0).map(joined));
	}
	return chunks;
};

/**
 * subtitles_en is one string for the whole reel, with no timings of its own, so chunks are shared
 * out over the time that speech runs, in proportion to their length.
 */
export const englishLineAt = (
	subtitles: string,
	words: CaptionWord[],
	ms: number,
	durationMs: number,
	brandNames: string[] = [],
): string | null => {
	const start = words[0]?.start_ms ?? 0;
	const end = words[words.length - 1]?.end_ms ?? durationMs;
	if (ms < start || ms >= end || end <= start) {
		return null;
	}
	const chunks = chunkSubtitle(subtitles, [...brandNames, REAL_BRAND_NAME_AR, REAL_BRAND_NAME_EN]);
	const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
	const position = ((ms - start) / (end - start)) * total;
	let passed = 0;
	for (const chunk of chunks) {
		passed += chunk.length;
		if (position < passed) {
			return chunk;
		}
	}
	return chunks[chunks.length - 1] ?? null;
};

/** Which of `count` items is up, sharing the time from `fromMs` to `toMs` evenly. */
export const itemIndexAt = (count: number, ms: number, fromMs: number, toMs: number): number => {
	if (count <= 0 || ms < fromMs || toMs <= fromMs) {
		return -1;
	}
	return Math.min(count - 1, Math.floor(((ms - fromMs) / (toMs - fromMs)) * count));
};

const SPOKEN_END_SHARE = 0.8;
const OUTRO_EARLIEST_SHARE = 0.6;

/** When the speech says the brand for the last time, in frames, or null. */
const brandMentionFrame = (words: CaptionWord[], brandNames: string[], fps: number): number | null => {
	const mention = mergeBrandTokens(words, brandNames).filter((token) => token.isBrand).pop();
	return mention ? msToFrame(mention.startMs, fps) : null;
};

export type TipBeats = {cardAt: number[]; outroAt: number};

/**
 * Template B follows the script: the cards share the speech evenly, up to the moment the script
 * turns to the brand, which opens the outro. A script that does not name the brand late in the reel
 * gets its outro at a fixed share of what is left.
 */
export const tipBeats = ({
	stageStartFrame,
	durationInFrames: total,
	fps,
	words,
	brandNames,
	cardCount,
}: {
	stageStartFrame: number;
	durationInFrames: number;
	fps: number;
	words: CaptionWord[];
	brandNames: string[];
	cardCount: number;
}): TipBeats => {
	const stageLength = Math.max(1, total - stageStartFrame);
	const mention = brandMentionFrame(words, brandNames, fps);
	const earliest = stageStartFrame + stageLength * OUTRO_EARLIEST_SHARE;
	const outroAt = Math.round(
		mention !== null && mention >= earliest && mention < total
			? mention
			: stageStartFrame + stageLength * SPOKEN_END_SHARE,
	);
	const span = (outroAt - stageStartFrame) / Math.max(1, cardCount);
	return {
		cardAt: Array.from({length: cardCount}, (_, index) => stageStartFrame + Math.round(index * span)),
		outroAt,
	};
};

const MYTH_MAX_SECONDS = 3.2;
const MYTH_MAX_SHARE = 0.28;

/** Template C does not hold the wrong way for long: the fact lands within about three seconds. */
export const factRevealFrame = (stageStartFrame: number, total: number, fps: number): number =>
	stageStartFrame +
	Math.max(
		1,
		Math.round(Math.min(MYTH_MAX_SECONDS * fps, (total - stageStartFrame) * MYTH_MAX_SHARE)),
	);

/** True once every clip has ended. */
export const afterLastClip = (clips: PropsClip[], frame: number, fps: number): boolean =>
	clips.length > 0 && clips.every((clip) => frame >= clipWindow(clip, fps).to);

/** Music sits lower under the voice and rises in pauses, with a short ramp (spec Section 8.6). */
export const musicVolumeAt = (
	ms: number,
	words: CaptionWord[],
	underVoice: number,
	inPauses: number,
): number => {
	let nearest = Number.POSITIVE_INFINITY;
	for (const word of words) {
		const distance = ms < word.start_ms ? word.start_ms - ms : ms > word.end_ms ? ms - word.end_ms : 0;
		nearest = Math.min(nearest, distance);
	}
	const amount = Math.min(1, nearest / DUCK_RAMP_MS);
	return underVoice + (inPauses - underVoice) * amount;
};
