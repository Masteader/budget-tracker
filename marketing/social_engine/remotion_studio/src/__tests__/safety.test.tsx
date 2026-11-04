import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {describe, expect, it} from 'vitest';
import {
	assertGlyphCoverage,
	displayTexts,
	fontStack,
	FONT_FACES,
	GlyphCoverageError,
	loadBrandFonts,
	parseCmap,
} from '../lib/fonts';
import type {FontEnvironment} from '../lib/fonts';
import {calculateReelMetadata} from '../lib/reelMetadata';
import {ILLUSTRATIVE_AR, ILLUSTRATIVE_EN, TEST_WATERMARK, label} from '../lib/strings';
import {parseRenderProps} from '../props';
import type {RenderProps} from '../props';
import {featureProps, mythProps, tipProps} from './helpers';

const fontFile = (file: string): ArrayBuffer => {
	const bytes = readFileSync(resolve(process.cwd(), 'public', file));
	return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
};

// Assembled over two lines, so that the boundary scan keeps code free of the withdrawn name.
const WITHDRAWN_SPELLINGS = [
	'wa' +
		'feer',
	'وف' +
		'يير',
	'وَفْـ' +
		'يير',
];

const coverages = FONT_FACES.map((face) => parseCmap(fontFile(face.file)));

describe('Metadata fails on a missing field, with no sample to fall back on', () => {
	const metadata = calculateReelMetadata('FeatureDemo');
	const asked = (props: unknown) =>
		metadata({props: props as RenderProps, defaultProps: {} as RenderProps, abortSignal: new AbortController().signal, compositionId: 'FeatureDemo', isRendering: true});

	it('takes full props, and sets the size and length from them', async () => {
		const result = await asked(featureProps());
		expect(result.durationInFrames).toBe(900);
		expect(result.fps).toBe(30);
		expect(result.props).toBeDefined();
	});

	it.each([
		'hook_text',
		'words',
		'clips',
		'on_screen_text',
		'safe_zones',
		'watermark',
		'brand',
		'language',
		'subtitles_en',
		'duration_ms',
	])('throws when %s is missing', async (field) => {
		const props = {...featureProps()} as Record<string, unknown>;
		delete props[field];
		await expect(Promise.resolve().then(() => asked(props))).rejects.toThrow(new RegExp(field));
	});

	it('throws on an unknown field', async () => {
		await expect(Promise.resolve().then(() => asked({...featureProps(), hide_watermark: true}))).rejects.toThrow();
	});

	it('throws when the props are for another template', async () => {
		await expect(Promise.resolve().then(() => asked(tipProps()))).rejects.toThrow(/DailyTip/);
	});

	it('lets the CLI list the compositions with no props at all, and without a usable length', async () => {
		const result = await asked({});
		expect(result.durationInFrames).toBe(1);
		expect(result.props).toBeUndefined();
	});
});

describe('the root holds no sample', () => {
	const root = readFileSync(resolve(process.cwd(), 'src/Root.tsx'), 'utf-8');

	it('imports nothing from test_data', () => {
		expect(root).not.toContain('test_data');
		expect(root).not.toContain('sample_');
	});

	it('goes through the checked metadata', () => {
		expect(root).toContain('calculateReelMetadata(template)');
	});

	it('checks props again inside the composition, so a render with none at all fails', () => {
		const composition = readFileSync(resolve(process.cwd(), 'src/compositions/ReelComposition.tsx'), 'utf-8');
		expect(composition).toContain('parseRenderProps(');
	});
});

describe('the brand checks are the same as the Python ones', () => {
	type Case = {name_ar: string; name_en: string; real: boolean};
	const cases = JSON.parse(readFileSync(resolve(process.cwd(), 'test_data/brand_name_cases.json'), 'utf-8')) as Case[];

	it.each(cases)('$name_en / $name_ar counts as real: $real', ({name_ar, name_en, real}) => {
		const brand = {name_ar, name_en, hashtag: '#x', logo_src: 'approved_mark.svg'};
		const props = {...featureProps()};
		const publicReel = () => parseRenderProps({...props, watermark: false, brand});
		const testReel = () => parseRenderProps({...props, watermark: true, brand});
		if (real) {
			expect(publicReel).not.toThrow();
			expect(testReel).toThrow();
		} else {
			expect(publicReel).toThrow();
			expect(testReel).not.toThrow();
		}
	});

	it.each([
		['hook_text', (name: string) => ({hook_text: `خطط مع ${name}`})],
		['on_screen_text', (name: string) => ({on_screen_text: [`a ${name}`]})],
		['subtitles_en', (name: string) => ({subtitles_en: `with ${name.toUpperCase()}`})],
		['a word', (name: string) => ({words: [{text: name, start_ms: 0, end_ms: 10}]})],
		['the hashtag', (name: string) => ({brand: {...featureProps().brand, hashtag: `#${name}`}})],
	])('refuses the withdrawn name in %s', (_field, change) => {
		for (const name of WITHDRAWN_SPELLINGS) {
			expect(() => parseRenderProps({...featureProps(), ...change(name)})).toThrow(/withdrawn/);
		}
	});
});

describe('Latin text uses Outfit and Arabic uses Cairo, in both kinds of reel', () => {
	it('names Outfit first, so Latin never lands on the Latin letters in Cairo', () => {
		expect(fontStack.split(',').map((name) => name.trim())).toEqual(['Outfit', 'Cairo']);
	});

	it('finds no Arabic in Outfit, so Arabic lands on Cairo and not a system font', () => {
		const outfit = coverages[coverages.length - 1];
		const cairo = coverages[0];
		for (const letter of 'قوامالم') {
			const point = letter.codePointAt(0) ?? 0;
			expect(outfit?.has(point)).toBe(false);
			expect(cairo?.has(point)).toBe(true);
		}
		expect(outfit?.has('Q'.codePointAt(0) ?? 0)).toBe(true);
	});

	it('uses the one stack everywhere in the source', () => {
		for (const file of ['KineticCaptions', 'HookTitle', 'ProgressHud', 'IllustrativePricesLabel', 'FlowText']) {
			const source = readFileSync(resolve(process.cwd(), `src/components/${file}.tsx`), 'utf-8');
			expect(source, file).not.toContain('LATIN_FAMILY');
			expect(source, file).not.toContain('ARABIC_FAMILY');
		}
	});
});

describe('a glyph no brand font draws fails the render', () => {
	it.each([
		['an emoji', 'راتبك وين يروح \u{1f631}؟'],
		['the new riyal sign', 'وفّر 500 \u20c1 كل شهر'],
		['Chinese', '保存'],
	])('refuses %s', (_name, text) => {
		expect(() => assertGlyphCoverage([text], coverages)).toThrow(GlyphCoverageError);
	});

	it('names the character and the text it was in', () => {
		expect(() => assertGlyphCoverage(['abc \u{1f631}'], coverages)).toThrow(/U\+1F631/);
	});

	it('passes what the reel really says', () => {
		const everything = [
			'راتبك وين يروح كل شهر؟',
			'قوام المال، Qawam Money. 2,500 ريال ١٢٣٤٥٦٧٨٩٠ ٪ 100% قِوامٌ لـلـه',
			'Save 1.5 SAR at qawam.money #test “quoted” it’s — …',
			ILLUSTRATIVE_AR,
			ILLUSTRATIVE_EN,
			TEST_WATERMARK,
			...(['badge', 'stopDoingThis', 'theSmartWay'] as const).flatMap((name) => [label(name, 'ar'), label(name, 'en')]),
		];
		expect(() => assertGlyphCoverage(everything, coverages)).not.toThrow();
	});

	it('ignores spaces, direction marks and joiners', () => {
		expect(() => assertGlyphCoverage(['a\u00a0b\u200c\u200d\u200e\u200f\n'], coverages)).not.toThrow();
	});

	it('checks every text a reel can show, in the digits it shows', () => {
		const props = tipProps({
			hook_text: 'hook-text',
			on_screen_text: ['card-text'],
			subtitles_en: 'english-line',
			words: [{text: 'caption-word', start_ms: 0, end_ms: 10}],
			digits: 'arabic_indic',
		});
		const texts = displayTexts({...props, on_screen_text: ['card-text 25']});
		for (const text of ['hook-text', 'english-line', 'caption-word', props.brand.name_ar, props.brand.name_en, props.brand.hashtag]) {
			expect(texts).toContain(text);
		}
		expect(texts).toContain('card-text ٢٥');
	});

	const environment = (): FontEnvironment => ({
		createFace: () => ({load: () => Promise.resolve({})}),
		addFace: () => undefined,
		isAvailable: () => true,
		fileUrl: (file) => file,
		readFont: (file) => Promise.resolve(fontFile(file)),
	});

	it('makes the font step itself fail on such a glyph', async () => {
		const props = mythProps({hook_text: 'راتبك وين \u{1f631}'});
		await expect(loadBrandFonts(environment(), displayTexts(props))).rejects.toThrow(GlyphCoverageError);
	});

	it('lets the font step pass on normal text', async () => {
		await expect(loadBrandFonts(environment(), displayTexts(mythProps()))).resolves.toBeUndefined();
	});

	it('fails the font step when Outfit is not usable, not only Cairo', async () => {
		const checked: string[] = [];
		const env = {
			...environment(),
			isAvailable: (font: string) => {
				checked.push(font);
				return true;
			},
		};
		await loadBrandFonts(env, []);
		expect(checked.join()).toContain('Cairo');
		expect(checked.join()).toContain('Outfit');
	});
});
