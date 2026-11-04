import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {describe, expect, it} from 'vitest';
import {
	ClipFolderSchema,
	DigitsSchema,
	FpsSchema,
	LanguageSchema,
	RenderPropsSchema,
	TemplateSchema,
	objectShapes,
	parseRenderProps,
} from '../props';

type JsonSchemaObject = {
	properties: Record<string, {enum?: unknown[]; const?: unknown; [key: string]: unknown}>;
	required?: string[];
	additionalProperties?: boolean;
};
type JsonSchema = JsonSchemaObject & {$defs: Record<string, JsonSchemaObject>};

const readJson = (relative: string): unknown =>
	JSON.parse(readFileSync(resolve(process.cwd(), relative), 'utf-8'));

const jsonSchema = readJson('props.schema.json') as JsonSchema;
const fixture = readJson('fixtures/props_valid.json') as Record<string, unknown>;

describe('the Zod schema matches the frozen contract', () => {
	it('accepts the synced fixture', () => {
		expect(() => parseRenderProps(fixture)).not.toThrow();
	});

	it('has the same fields as props.schema.json at every level', () => {
		const objects: Record<string, JsonSchemaObject> = {
			RenderProps: jsonSchema,
			...jsonSchema.$defs,
		};
		const shapes = objectShapes();
		expect(Object.keys(shapes).sort()).toEqual(Object.keys(objects).sort());
		for (const [name, object] of Object.entries(objects)) {
			expect(Object.keys(shapes[name] ?? {}).sort(), name).toEqual(
				Object.keys(object.properties).sort(),
			);
			expect(object.required?.slice().sort(), name).toEqual(
				Object.keys(object.properties).sort(),
			);
			expect(object.additionalProperties, name).toBe(false);
		}
	});

	it('has the same allowed values as props.schema.json', () => {
		const top = jsonSchema.properties;
		expect(TemplateSchema.options).toEqual(top.template?.enum);
		expect(LanguageSchema.options).toEqual(top.language?.enum);
		expect(DigitsSchema.options).toEqual(top.digits?.enum);
		expect([...FpsSchema.values]).toEqual(top.fps?.enum);
		expect(ClipFolderSchema.options).toEqual(
			jsonSchema.$defs.PropsClip?.properties.folder?.enum,
		);
		expect(top.device_frame?.const).toBe('generic');
		expect(top.width?.const).toBe(1080);
		expect(top.height?.const).toBe(1920);
	});
});

describe('the Zod schema refuses what the contract refuses', () => {
	const valid = () => structuredClone(fixture) as Record<string, any>;

	it.each([
		['an unknown top-level field', (p: any) => void (p.no_watermark = true)],
		['an unknown clip field', (p: any) => void (p.clips[1].hide_label = true)],
		['an unknown mask field', (p: any) => void (p.clips[1].mask_regions[0].off = true)],
		['a missing watermark', (p: any) => void delete p.watermark],
		['a watermark that is not a boolean', (p: any) => void (p.watermark = 0)],
		['a phone device frame', (p: any) => void (p.device_frame = 'iphone')],
		['a Smart Basket clip with no masks', (p: any) => void (p.clips[1].mask_regions = [])],
		[
			'masks on a clip from another folder',
			(p: any) =>
				void (p.clips[0].mask_regions = [{x: 0, y: 0, width: 0.5, height: 0.1}]),
		],
		[
			'a mask too small to hide a name',
			(p: any) =>
				void (p.clips[1].mask_regions = [{x: 0, y: 0, width: 0.05, height: 0.01}]),
		],
		[
			'a mask running outside the clip',
			(p: any) =>
				void (p.clips[1].mask_regions = [{x: 0.9, y: 0, width: 0.5, height: 0.1}]),
		],
		['a clip outside its folder', (p: any) => void (p.clips[0].src = 'clips/smart_basket/a.mp4')],
		['a clip that ends before it starts', (p: any) => void (p.clips[0].end_ms = 1)],
		['a clip past the end of the reel', (p: any) => void (p.clips[1].end_ms = 99999)],
		['words out of order', (p: any) => void (p.words[1].start_ms = 0, p.words[0].start_ms = 100)],
		['a word past the end of the reel', (p: any) => void (p.words[5].end_ms = 99999)],
		['a FeatureDemo with no clip', (p: any) => void (p.clips = [])],
		['a colour that is not hex', (p: any) => void (p.highlight_color = 'rose')],
		['a colour outside the brand', (p: any) => void (p.highlight_color = '#' + 'C9933B')],
		['a path that leaves public/', (p: any) => void (p.audio_src = '../secret.wav')],
		['a test reel with the real name', (p: any) => void (p.brand.name_en = 'Qawam Money', p.brand.name_ar = 'قوام المال')],
		['a public reel with the test brand', (p: any) => void (p.watermark = false)],
		[
			'a public reel with the test logo',
			(p: any) =>
				void ((p.watermark = false),
				(p.brand.name_en = 'Qawam Money'),
				(p.brand.name_ar = 'قوام المال')),
		],
	])('%s', (_name, mutate) => {
		const props = valid();
		mutate(props);
		expect(() => RenderPropsSchema.parse(props)).toThrow();
	});
});
