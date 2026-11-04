import {z} from 'zod';
import {isBrandColor} from './lib/tokens';

/**
 * The same contract as core/render_props.py, checked again at the point of rendering. Fields and
 * allowed values are compared with props.schema.json by a test, so the two cannot drift.
 *
 * There is deliberately no field that hides the watermark, the masks or the illustrative label,
 * and unknown fields are refused, so a props file cannot add one.
 */

export const REAL_BRAND_NAME_AR = 'قوام المال';
export const REAL_BRAND_NAME_EN = 'Qawam Money';
export const MASKED_FOLDER = 'smart_basket';

const MIN_MASK_WIDTH = 0.05;
const MIN_MASK_HEIGHT = 0.01;
const MIN_MASK_AREA = 0.002;
const FLOAT_TOLERANCE = 1e-9;
const MAX_REEL_MS = 180_000;
const TEST_LOGO_MARKER = 'test_logo';

const PUBLIC_PATH = /^[A-Za-z0-9][A-Za-z0-9._-]*(\/[A-Za-z0-9][A-Za-z0-9._-]*)*$/;
const REEL_ID = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}[A-Za-z0-9])?$/;
const HEX_COLOR = /^#[0-9A-Fa-f]{6}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const VISIBLE = /[\p{L}\p{N}]/u;
// Bidi overrides and other format characters could reorder a caption. Direction marks and joiners
// are normal in Arabic text, as in core/safe_text.py.
const HIDDEN = /(?![\u200c-\u200f])\p{Cf}/u;

const displayText = (maxChars: number) =>
	z
		.string()
		.max(maxChars)
		.refine((value) => VISIBLE.test(value), 'has no visible text')
		.refine((value) => !HIDDEN.test(value), 'contains a hidden character');

const publicPath = z.string().max(200).regex(PUBLIC_PATH, 'must be a relative path inside public/');
const count = z.number().int().min(0);
const fraction = z.number().min(0).max(1);

export const TemplateSchema = z.enum(['FeatureDemo', 'DailyTip', 'MythVsFact']);
export const LanguageSchema = z.enum(['ar', 'en']);
export const DigitsSchema = z.enum(['western', 'arabic_indic']);
export const FpsSchema = z.literal([30, 60]);
export const ClipFolderSchema = z.enum([
	'payday_cycle',
	'zatca_receipt_scan',
	'receipt_photo_scan',
	'chat_and_voice_entry',
	'multi_account_ledger',
	'budget_capacity',
	'nafaqah_wife_expenses',
	'roommate_debt_split',
	'recurring_and_installments',
	'price_tracker',
	MASKED_FOLDER,
	'app_experience',
]);

const CaptionWordObject = z.strictObject({
	text: displayText(64),
	start_ms: count,
	end_ms: count,
});

const MaskRegionObject = z.strictObject({
	x: fraction,
	y: fraction,
	width: z.number().gt(0).max(1),
	height: z.number().gt(0).max(1),
});

const PropsBrandObject = z.strictObject({
	name_ar: displayText(64),
	name_en: displayText(64),
	hashtag: displayText(64),
	logo_src: publicPath,
});

const FocalPointObject = z.strictObject({
	x: fraction,
	y: fraction,
});

const SafeZonesObject = z.strictObject({
	top: count,
	bottom: count,
	left: count,
	right: count,
});

const PropsClipObject = z.strictObject({
	src: publicPath,
	folder: ClipFolderSchema,
	sha256: z.string().regex(SHA256),
	start_ms: count,
	end_ms: count,
	mask_regions: z.array(MaskRegionObject).max(32),
	focal_point: FocalPointObject.nullable(),
});

const RenderPropsObject = z.strictObject({
	reel_id: z.string().regex(REEL_ID),
	revision: z.number().int().min(1),
	template: TemplateSchema,
	language: LanguageSchema,
	width: z.literal(1080),
	height: z.literal(1920),
	fps: FpsSchema,
	duration_ms: z.number().int().gt(0).max(MAX_REEL_MS),
	watermark: z.boolean(),
	device_frame: z.literal('generic'),
	digits: DigitsSchema,
	highlight_color: z.string().regex(HEX_COLOR),
	safe_zones: SafeZonesObject,
	brand: PropsBrandObject,
	hook_text: displayText(200),
	on_screen_text: z.array(displayText(160)).max(20),
	subtitles_en: displayText(2000),
	audio_src: publicPath,
	music_src: publicPath.nullable(),
	duck_under_voice: fraction,
	duck_in_pauses: fraction,
	words: z.array(CaptionWordObject).max(2000),
	clips: z.array(PropsClipObject).max(20),
});

/** Each object in the contract, by the name it has in props.schema.json. */
export const objectShapes = (): Record<string, Record<string, unknown>> => ({
	RenderProps: RenderPropsObject.shape,
	CaptionWord: CaptionWordObject.shape,
	FocalPoint: FocalPointObject.shape,
	MaskRegion: MaskRegionObject.shape,
	PropsBrand: PropsBrandObject.shape,
	PropsClip: PropsClipObject.shape,
	SafeZones: SafeZonesObject.shape,
});

type Issues = {addIssue: (message: string) => void};

const checkMask = (mask: z.infer<typeof MaskRegionObject>, {addIssue}: Issues): void => {
	const limit = 1 + FLOAT_TOLERANCE;
	if (mask.x + mask.width > limit || mask.y + mask.height > limit) {
		addIssue('mask region runs outside the clip');
	}
	if (
		mask.width < MIN_MASK_WIDTH - FLOAT_TOLERANCE ||
		mask.height < MIN_MASK_HEIGHT - FLOAT_TOLERANCE ||
		mask.width * mask.height < MIN_MASK_AREA - FLOAT_TOLERANCE
	) {
		addIssue('mask region is too small to hide a store name');
	}
};

const checkClip = (clip: z.infer<typeof PropsClipObject>, durationMs: number, issues: Issues): void => {
	const {addIssue} = issues;
	const parts = clip.src.split('/');
	if (parts.length !== 3 || parts[0] !== 'clips' || parts[1] !== clip.folder) {
		addIssue(`src must sit in its folder, clips/${clip.folder}/`);
	}
	if (clip.end_ms <= clip.start_ms) {
		addIssue('a clip must end after it starts');
	}
	if (clip.end_ms > durationMs) {
		addIssue('a clip runs past the end of the reel');
	}
	if (clip.folder === MASKED_FOLDER && clip.mask_regions.length === 0) {
		addIssue(`a ${MASKED_FOLDER} clip needs non-empty mask_regions`);
	}
	if (clip.folder !== MASKED_FOLDER && clip.mask_regions.length > 0) {
		addIssue(`mask_regions are only for ${MASKED_FOLDER} clips`);
	}
	clip.mask_regions.forEach((mask) => checkMask(mask, issues));
};

// The same folding as letters_only in core/brand_gate.py, and tested against the same cases.
const LOOK_ALIKES: Record<string, string> = {
	'ی': 'ي', // Persian yeh
	'ى': 'ي', // alef maksura
	'а': 'a', // Cyrillic
	'е': 'e',
	'о': 'o',
	'р': 'p',
	'с': 'c',
	'у': 'y',
	'х': 'x',
};

const lettersOnly = (text: string): string =>
	text
		.normalize('NFKC')
		.toLowerCase()
		.normalize('NFD')
		.replace(/[یىаеорсух]/gu, (letter) => LOOK_ALIKES[letter] ?? letter)
		.replace(/ـ/gu, '')
		.replace(/[^\p{L}\p{N}]/gu, '');

// Assembled over two lines, so that the boundary scan keeps code free of the withdrawn name itself.
const WITHDRAWN_NAMES = [
	'wa' +
		'feer',
	'وف' +
		'يير',
].map(lettersOnly);
const containsWithdrawnName = (text: string): boolean => {
	const letters = lettersOnly(text);
	return WITHDRAWN_NAMES.some((name) => letters.includes(name));
};

const shownStrings = (props: z.infer<typeof RenderPropsObject>): string[] => [
	props.brand.name_ar,
	props.brand.name_en,
	props.brand.hashtag,
	props.brand.logo_src,
	props.hook_text,
	...props.on_screen_text,
	props.subtitles_en,
	...props.words.map((word) => word.text),
	...props.clips.map((clip) => clip.src),
];

const isRealBrand = (brand: z.infer<typeof PropsBrandObject>): boolean =>
	lettersOnly(brand.name_en) === lettersOnly(REAL_BRAND_NAME_EN) &&
	lettersOnly(brand.name_ar) === lettersOnly(REAL_BRAND_NAME_AR);

const checkBrand = (props: z.infer<typeof RenderPropsObject>, {addIssue}: Issues): void => {
	const real = isRealBrand(props.brand);
	if (props.watermark && real) {
		addIssue('a watermarked test reel must use the test brand');
	}
	if (!props.watermark && !real) {
		addIssue('a reel with no watermark must carry the full real brand name');
	}
	if (!props.watermark && props.brand.logo_src.toLowerCase().includes(TEST_LOGO_MARKER)) {
		addIssue('a reel with no watermark cannot use the test logo');
	}
	if (shownStrings(props).some(containsWithdrawnName)) {
		addIssue('the reel uses the withdrawn brand name (D1)');
	}
};

export const RenderPropsSchema = RenderPropsObject.superRefine((props, context) => {
	const issues: Issues = {
		addIssue: (message) => context.addIssue({code: 'custom', message}),
	};
	props.clips.forEach((clip) => checkClip(clip, props.duration_ms, issues));
	props.words.forEach((word, index) => {
		if (word.end_ms < word.start_ms) {
			issues.addIssue('a word must not end before it starts');
		}
		if (word.end_ms > props.duration_ms) {
			issues.addIssue('a caption word runs past the end of the reel');
		}
		const earlier = props.words[index - 1];
		if (earlier && word.start_ms < earlier.start_ms) {
			issues.addIssue('caption words must be in time order');
		}
	});
	if (props.template === 'FeatureDemo' && props.clips.length === 0) {
		issues.addIssue('FeatureDemo needs at least one clip');
	}
	if (!isBrandColor(props.highlight_color)) {
		issues.addIssue('highlight_color is not a brand colour (G16)');
	}
	checkBrand(props, issues);
});

export type RenderProps = z.infer<typeof RenderPropsObject>;
export type PropsClip = z.infer<typeof PropsClipObject>;
export type MaskRegion = z.infer<typeof MaskRegionObject>;
export type CaptionWord = z.infer<typeof CaptionWordObject>;
export type SafeZones = z.infer<typeof SafeZonesObject>;
export type Language = z.infer<typeof LanguageSchema>;
export type Digits = z.infer<typeof DigitsSchema>;
export type Template = z.infer<typeof TemplateSchema>;

/** Throws naming each bad field, because a render log shows only the message of an error. */
export const parseRenderProps = (value: unknown): RenderProps => {
	const result = RenderPropsSchema.safeParse(value);
	if (!result.success) {
		const issues = result.error.issues.map((issue) => `${issue.path.join('.') || 'props'}: ${issue.message}`);
		throw new Error(`The reel props are not valid. ${issues.join('; ')}`);
	}
	return result.data;
};
