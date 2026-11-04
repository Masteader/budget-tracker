import type {CaptionWord, PropsClip, RenderProps} from '../props';

/** Pure time arithmetic. Every frame's picture is decided here, so tests can walk each frame. */

const HOOK_HERO_MS = 3000;
const DUCK_RAMP_MS = 250;
const ENGLISH_LINE_CHARS = 56;

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

const chunkSubtitle = (text: string): string[] => {
	const chunks: string[] = [];
	for (const sentence of text.match(/[^.!?]+[.!?]*/g) ?? []) {
		let line = '';
		for (const word of sentence.trim().split(/\s+/)) {
			if (line && line.length + word.length + 1 > ENGLISH_LINE_CHARS) {
				chunks.push(line);
				line = word;
			} else {
				line = line ? `${line} ${word}` : word;
			}
		}
		if (line) {
			chunks.push(line);
		}
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
): string | null => {
	const start = words[0]?.start_ms ?? 0;
	const end = words[words.length - 1]?.end_ms ?? durationMs;
	if (ms < start || ms >= end || end <= start) {
		return null;
	}
	const chunks = chunkSubtitle(subtitles);
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
