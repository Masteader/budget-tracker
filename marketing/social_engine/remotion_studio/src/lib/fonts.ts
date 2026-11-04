import type {RenderProps} from '../props';
import {ILLUSTRATIVE_AR, ILLUSTRATIVE_EN, LABELS, TEST_WATERMARK} from './strings';
import {localizeDigits} from './text';

/** Fonts come from public/fonts, never from a network or the system (spec Section 8.4, rule 8). */

const ARABIC_FAMILY = 'Cairo';
const LATIN_FAMILY = 'Outfit';

export const FONT_FACES = [
	{family: ARABIC_FAMILY, weight: '400', file: 'fonts/cairo/Cairo-Regular.ttf'},
	{family: ARABIC_FAMILY, weight: '600', file: 'fonts/cairo/Cairo-SemiBold.ttf'},
	{family: ARABIC_FAMILY, weight: '700', file: 'fonts/cairo/Cairo-Bold.ttf'},
	{family: LATIN_FAMILY, weight: '100 900', file: 'fonts/outfit/Outfit-Variable.ttf'},
] as const;

/**
 * Outfit first in every reel, because Cairo has Latin letters of its own and would take them. Outfit
 * has no Arabic, so Arabic letters land on Cairo. No generic family is named on purpose.
 */
export const fontStack = `${LATIN_FAMILY}, ${ARABIC_FAMILY}`;

export class FontLoadError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'FontLoadError';
	}
}

export class GlyphCoverageError extends FontLoadError {
	constructor(message: string) {
		super(message);
		this.name = 'GlyphCoverageError';
	}
}

type LoadedFace = object;

export type FontEnvironment = {
	createFace: (family: string, source: string, weight: string) => {load: () => Promise<LoadedFace>};
	addFace: (face: LoadedFace) => void;
	isAvailable: (cssFont: string, sample: string) => boolean;
	fileUrl: (file: string) => string;
	readFont: (file: string) => Promise<ArrayBuffer>;
};

const SAMPLE_ARABIC = 'قوام المال';
const SAMPLE_LATIN = 'Qawam Money';

const CMAP_FORMAT_SEGMENTS = 4;
const CMAP_FORMAT_GROUPS = 12;

const readSegments = (view: DataView, at: number, found: Set<number>): void => {
	const segments = view.getUint16(at + 6) / 2;
	const ends = at + 14;
	const starts = ends + segments * 2 + 2;
	const deltas = starts + segments * 2;
	const offsets = deltas + segments * 2;
	for (let segment = 0; segment < segments; segment++) {
		const end = view.getUint16(ends + segment * 2);
		const start = view.getUint16(starts + segment * 2);
		const delta = view.getUint16(deltas + segment * 2);
		const offsetAt = offsets + segment * 2;
		const offset = view.getUint16(offsetAt);
		for (let point = start; point <= end && point !== 0xffff; point++) {
			const glyph =
				offset === 0 ? (point + delta) & 0xffff : view.getUint16(offsetAt + offset + (point - start) * 2);
			if (glyph !== 0) {
				found.add(point);
			}
		}
	}
};

const readGroups = (view: DataView, at: number, found: Set<number>): void => {
	const groups = view.getUint32(at + 12);
	for (let group = 0; group < groups; group++) {
		const entry = at + 16 + group * 12;
		const start = view.getUint32(entry);
		const end = view.getUint32(entry + 4);
		for (let point = start; point <= end; point++) {
			found.add(point);
		}
	}
};

/** The characters a TrueType font really has, from its own table. */
export const parseCmap = (bytes: ArrayBuffer): Set<number> => {
	const view = new DataView(bytes);
	const tables = view.getUint16(4);
	let cmap = -1;
	for (let table = 0; table < tables; table++) {
		const record = 12 + table * 16;
		if (String.fromCharCode(...new Uint8Array(bytes, record, 4)) === 'cmap') {
			cmap = view.getUint32(record + 8);
		}
	}
	if (cmap < 0) {
		throw new FontLoadError('a font file has no character table');
	}
	const found = new Set<number>();
	const encodings = view.getUint16(cmap + 2);
	for (let encoding = 0; encoding < encodings; encoding++) {
		const at = cmap + view.getUint32(cmap + 4 + encoding * 8 + 4);
		const format = view.getUint16(at);
		if (format === CMAP_FORMAT_SEGMENTS) {
			readSegments(view, at, found);
		} else if (format === CMAP_FORMAT_GROUPS) {
			readGroups(view, at, found);
		}
	}
	return found;
};

// Spaces, direction marks and joiners draw nothing a reader would miss.
const DRAWS_NOTHING = /[\s\u00a0\u200c-\u200f]/u;

/** A character neither font has would come from a system font, or a blank box. That stops a render. */
export const assertGlyphCoverage = (texts: string[], coverages: Set<number>[]): void => {
	for (const text of texts) {
		for (const character of text) {
			const point = character.codePointAt(0) ?? 0;
			if (!DRAWS_NOTHING.test(character) && !coverages.some((coverage) => coverage.has(point))) {
				const hex = point.toString(16).toUpperCase().padStart(4, '0');
				throw new GlyphCoverageError(
					`U+${hex} (${character}) in "${text.slice(0, 60)}" is in no brand font, so it would come from a system font`,
				);
			}
		}
	}
};

/** Everything a reel can put on screen, as it will show. */
export const displayTexts = (
	props: Pick<RenderProps, 'hook_text' | 'on_screen_text' | 'subtitles_en' | 'words' | 'brand' | 'digits'>,
): string[] =>
	[
		props.hook_text,
		...props.on_screen_text,
		props.subtitles_en,
		...props.words.map((word) => word.text),
		props.brand.name_ar,
		props.brand.name_en,
		props.brand.hashtag,
		ILLUSTRATIVE_AR,
		ILLUSTRATIVE_EN,
		TEST_WATERMARK,
		...Object.values(LABELS).flatMap((name) => [name.ar, name.en]),
	].map((text) => localizeDigits(text, props.digits));

/**
 * Rejects if any font is missing or any text needs a character they lack, and the composition turns
 * that into a failed render, so a reel never goes out in a fallback font with broken Arabic joins.
 */
export const loadBrandFonts = async (environment: FontEnvironment, texts: string[]): Promise<void> => {
	await Promise.all(
		FONT_FACES.map(async ({family, weight, file}) => {
			const face = environment.createFace(family, `url("${environment.fileUrl(file)}")`, weight);
			try {
				environment.addFace(await face.load());
			} catch (error) {
				throw new FontLoadError(`${family} ${weight} did not load from ${file}: ${String(error)}`);
			}
		}),
	);
	if (!environment.isAvailable(`700 40px "${ARABIC_FAMILY}"`, SAMPLE_ARABIC)) {
		throw new FontLoadError(`${ARABIC_FAMILY} is not available for Arabic text`);
	}
	if (!environment.isAvailable(`700 40px "${LATIN_FAMILY}"`, SAMPLE_LATIN)) {
		throw new FontLoadError(`${LATIN_FAMILY} is not available for Latin text`);
	}
	const coverages = await Promise.all(
		FONT_FACES.map(async ({file}) => parseCmap(await environment.readFont(file))),
	);
	assertGlyphCoverage(texts, coverages);
};
