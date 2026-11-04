import type {Language} from '../props';

/** Fonts come from public/fonts, never from a network or the system (spec Section 8.4, rule 8). */

export const ARABIC_FAMILY = 'Cairo';
export const LATIN_FAMILY = 'Outfit';

export const FONT_FACES = [
	{family: ARABIC_FAMILY, weight: '400', file: 'fonts/cairo/Cairo-Regular.ttf'},
	{family: ARABIC_FAMILY, weight: '600', file: 'fonts/cairo/Cairo-SemiBold.ttf'},
	{family: ARABIC_FAMILY, weight: '700', file: 'fonts/cairo/Cairo-Bold.ttf'},
	{family: LATIN_FAMILY, weight: '100 900', file: 'fonts/outfit/Outfit-Variable.ttf'},
] as const;

/** Each family carries the other for mixed text. No generic family is named on purpose. */
export const fontStack = (language: Language): string =>
	language === 'ar'
		? `${ARABIC_FAMILY}, ${LATIN_FAMILY}`
		: `${LATIN_FAMILY}, ${ARABIC_FAMILY}`;

export class FontLoadError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'FontLoadError';
	}
}

type LoadedFace = object;

export type FontEnvironment = {
	createFace: (family: string, source: string, weight: string) => {load: () => Promise<LoadedFace>};
	addFace: (face: LoadedFace) => void;
	isAvailable: (cssFont: string, sample: string) => boolean;
	fileUrl: (file: string) => string;
};

const SAMPLE_ARABIC = 'قوام المال';

/**
 * Rejects if any font is missing, and the composition turns that into a failed render, so a reel
 * never goes out in a fallback font with broken Arabic joins.
 */
export const loadBrandFonts = async (environment: FontEnvironment): Promise<void> => {
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
};
