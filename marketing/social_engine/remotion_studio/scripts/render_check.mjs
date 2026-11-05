/**
 * The local render check (plan tasks F6 and F7). Everything is generated and rendered here, with
 * no call to any service. Output goes to out/, which git and the sync both leave alone.
 *
 *   npm run render:check
 *   node scripts/render_check.mjs --update-golden   writes golden/*.png for review by eye
 *   node scripts/render_check.mjs --only=masks,bad-props   runs part of it, to look into a failure
 */
import {bundle} from '@remotion/bundler';
import {ensureBrowser, openBrowser, renderFrames, renderMedia, renderStill, selectComposition} from '@remotion/renderer';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {PNG} from 'pngjs';

const ROOT = resolve(import.meta.dirname, '..');
const OUT = join(ROOT, 'out');
const PUBLIC = join(ROOT, 'public');
const GOLDEN = join(ROOT, 'golden');
const UPDATE_GOLDEN = process.argv.includes('--update-golden');
const ONLY = process.argv.find((argument) => argument.startsWith('--only='))?.slice('--only='.length).split(',');

const MAX_FILE_BYTES = 48 * 1024 * 1024;
const VIDEO_BITRATE = '8000k';
const AUDIO_BITRATE = '192k';
const SAMPLE_RATE = 48000;
const VOICE_SECONDS = 32;

const GOLDEN_SCALE = 0.5;
const GOLDEN_CHANNEL_TOLERANCE = 24;
const GOLDEN_MAX_DIFFERENT_PIXELS = 0.005;
const CHECK_SCALE = 0.5;
// The same as remotion.config.ts, which the CLI reads and this script does not.
const VIDEO_CACHE_BYTES = 1_500_000_000;

// Colours nothing else in a reel uses, so counting them finds the thing they mark.
const isSecretGreen = (r, g, b) => g > 170 && r < 90 && b < 90;
const isLabelAmber = (r, g, b) => Math.abs(r - 0xf5) < 16 && Math.abs(g - 0x9e) < 16 && Math.abs(b - 0x0b) < 24;
const isWatermarkCoral = (r, g, b) => Math.abs(r - 0xf4) < 16 && Math.abs(g - 0x3f) < 16 && Math.abs(b - 0x5e) < 16;
const isLabelInk = (r, g, b) => r < 70 && g < 50 && b < 60;
const MIN_LABEL_PIXELS = 1500;
const MIN_LABEL_INK_PIXELS = 300;
const MIN_WATERMARK_PIXELS = 5000;
const MIN_CONTROL_GREEN_PIXELS = 400;
const MAX_LEAKED_GREEN_PIXELS = 12;
// A sharp stripe under the mask's tint still jumps this much from one pixel to the next. The test
// watermark over a blurred mask does not, and a blur leaves nothing close.
const STRIPE_EDGE_JUMP = 60;
const MAX_MASK_EDGES = 40;
const MIN_CONTROL_EDGES = 400;
const MASK_DIFFERENCE = 40;
const MIN_MOVED_PIXELS = 0.004;

const MOTION_SHAPES = {portrait: null, landscape: {width: 1170, height: 540}, tall: {width: 400, height: 1400}};
const MOTION_FRAMES = [30, 31, 33, 40, 52, 75, 149];
const MOTION_SECONDS = 5;
const MOVING_STEP_SECONDS = 2;

const GOLDEN_FRAMES = [
	{name: 'hook_first_frame', sample: 'sample_feature_ar', frame: 0},
	{name: 'hook_impact', sample: 'sample_feature_ar', frame: 12},
	{name: 'hook_hero', sample: 'sample_feature_ar', frame: 60},
	{name: 'clip_wide', sample: 'sample_feature_ar', frame: 100},
	{name: 'clip_hard_words', sample: 'sample_feature_ar', frame: 200},
	{name: 'caption_brand_token', sample: 'sample_feature_ar', frame: null},
	{name: 'smart_basket_mask_label', sample: 'sample_feature_ar', frame: 600},
	{name: 'closing_brand', sample: 'sample_feature_ar', frame: 860},
	{name: 'tip_en', sample: 'sample_tip_en', frame: 240},
	{name: 'tip_recap_en', sample: 'sample_tip_en', frame: 830},
	{name: 'myth_ar', sample: 'sample_myth_ar', frame: 130},
	{name: 'fact_ar', sample: 'sample_myth_ar', frame: 400},
	{name: 'basket_en', sample: 'sample_basket_en', frame: 60},
];

const results = [];
const log = (message) => console.log(`[render-check] ${message}`);
const seconds = (since) => ((Date.now() - since) / 1000).toFixed(1);

const pass = (name, detail) => {
	results.push({name, detail});
	log(`PASS ${name}: ${detail}`);
};

class CheckFailed extends Error {}

const require = (condition, message) => {
	if (!condition) {
		throw new CheckFailed(message);
	}
};

const loadSample = (name) => JSON.parse(readFileSync(join(ROOT, 'test_data', `${name}.json`), 'utf-8'));

const writeSilentWav = (path, durationSeconds) => {
	const channels = 2;
	const bytesPerSample = 2;
	const dataBytes = durationSeconds * SAMPLE_RATE * channels * bytesPerSample;
	const header = Buffer.alloc(44);
	header.write('RIFF', 0);
	header.writeUInt32LE(36 + dataBytes, 4);
	header.write('WAVEfmt ', 8);
	header.writeUInt32LE(16, 16);
	header.writeUInt16LE(1, 20);
	header.writeUInt16LE(channels, 22);
	header.writeUInt32LE(SAMPLE_RATE, 24);
	header.writeUInt32LE(SAMPLE_RATE * channels * bytesPerSample, 28);
	header.writeUInt16LE(channels * bytesPerSample, 32);
	header.writeUInt16LE(8 * bytesPerSample, 34);
	header.write('data', 36);
	header.writeUInt32LE(dataBytes, 40);
	writeFileSync(path, Buffer.concat([header, Buffer.alloc(dataBytes)]));
};

/** Reads top-level boxes, and walks to the track boxes, with no ffprobe. */
const readMp4 = (path) => {
	const data = readFileSync(path);
	const boxes = (from, to) => {
		const found = [];
		for (let at = from; at + 8 <= to; ) {
			let size = data.readUInt32BE(at);
			const type = data.toString('latin1', at + 4, at + 8);
			let header = 8;
			if (size === 1) {
				size = Number(data.readBigUInt64BE(at + 8));
				header = 16;
			} else if (size === 0) {
				size = to - at;
			}
			if (size < header) {
				break;
			}
			found.push({type, start: at + header, end: at + size});
			at += size;
		}
		return found;
	};
	const top = boxes(0, data.length);
	const order = top.map((box) => box.type);
	const moov = top.find((box) => box.type === 'moov');
	const tracks = [];
	for (const trak of moov ? boxes(moov.start, moov.end).filter((box) => box.type === 'trak') : []) {
		const children = boxes(trak.start, trak.end);
		const tkhd = children.find((box) => box.type === 'tkhd');
		const mdia = children.find((box) => box.type === 'mdia');
		const minf = mdia && boxes(mdia.start, mdia.end).find((box) => box.type === 'minf');
		const stbl = minf && boxes(minf.start, minf.end).find((box) => box.type === 'stbl');
		const stsd = stbl && boxes(stbl.start, stbl.end).find((box) => box.type === 'stsd');
		const version = tkhd ? data[tkhd.start] : 0;
		const sizeAt = tkhd ? tkhd.start + (version === 1 ? 88 : 76) : 0;
		tracks.push({
			codec: stsd ? data.toString('latin1', stsd.start + 12, stsd.start + 16) : null,
			width: tkhd ? data.readUInt32BE(sizeAt) / 65536 : 0,
			height: tkhd ? data.readUInt32BE(sizeAt + 4) / 65536 : 0,
			hasEditList: children.some((box) => box.type === 'edts'),
		});
	}
	return {
		order,
		moovFirst: order.indexOf('moov') >= 0 && order.indexOf('moov') < order.indexOf('mdat'),
		tracks,
	};
};

const countPixels = (png, test) => {
	let count = 0;
	for (let at = 0; at < png.data.length; at += 4) {
		if (test(png.data[at], png.data[at + 1], png.data[at + 2])) {
			count++;
		}
	}
	return count;
};

const readPng = (path) => PNG.sync.read(readFileSync(path));

const boxOf = (png, test) => {
	const box = {left: png.width, top: png.height, right: -1, bottom: -1, count: 0};
	for (let y = 0; y < png.height; y++) {
		for (let x = 0; x < png.width; x++) {
			const at = (y * png.width + x) * 4;
			if (test(png.data[at], png.data[at + 1], png.data[at + 2], x, y)) {
				box.left = Math.min(box.left, x);
				box.top = Math.min(box.top, y);
				box.right = Math.max(box.right, x);
				box.bottom = Math.max(box.bottom, y);
				box.count++;
			}
		}
	}
	return box;
};

const countIn = (png, box, test) => {
	let count = 0;
	for (let y = box.top; y <= box.bottom; y++) {
		for (let x = box.left; x <= box.right; x++) {
			const at = (y * png.width + x) * 4;
			if (test(png.data[at], png.data[at + 1], png.data[at + 2])) {
				count++;
			}
		}
	}
	return count;
};

/** Sharp lines inside a box, by how much green jumps from each pixel to the one below it. */
const edgesIn = (png, box) => {
	let edges = 0;
	for (let y = box.top; y < box.bottom; y++) {
		for (let x = box.left; x <= box.right; x++) {
			const at = (y * png.width + x) * 4;
			if (Math.abs(png.data[at + 1] - png.data[at + png.width * 4 + 1]) > STRIPE_EDGE_JUMP) {
				edges++;
			}
		}
	}
	return edges;
};

const shrink = (box, by) => ({
	left: box.left + by,
	top: box.top + by,
	right: box.right - by,
	bottom: box.bottom - by,
});

const compositionFor = (serveUrl, inputProps) =>
	selectComposition({serveUrl, id: inputProps.template, inputProps, logLevel: 'error'});

const prepareInputs = async () => {
	mkdirSync(join(PUBLIC, 'audio'), {recursive: true});
	writeSilentWav(join(PUBLIC, 'audio', 'voice.wav'), VOICE_SECONDS);

	const clip = join(OUT, 'placeholder', 'clip.mp4');
	const clipFor = (shape) => join(OUT, 'placeholder', `clip_${shape}.mp4`);
	if (!existsSync(clip) || Object.keys(MOTION_SHAPES).some((shape) => !existsSync(clipFor(shape)))) {
		const since = Date.now();
		const serveUrl = await bundle({
			entryPoint: join(ROOT, 'test_data', 'placeholder', 'entry.tsx'),
			publicDir: PUBLIC,
		});
		const composition = await selectComposition({serveUrl, id: 'PlaceholderClip', logLevel: 'error'});
		const common = {serveUrl, codec: 'h264', crf: 18, pixelFormat: 'yuv420p', overwrite: true, logLevel: 'error'};
		await renderMedia({...common, composition, outputLocation: clip});
		for (const [shape, size] of Object.entries(MOTION_SHAPES)) {
			await renderMedia({
				...common,
				composition: {...composition, ...size},
				frameRange: [0, MOTION_SECONDS * 30],
				outputLocation: clipFor(shape),
			});
		}
		log(`generated the placeholder clips in ${seconds(since)} s`);
	}
	for (const folder of ['payday_cycle', 'smart_basket']) {
		mkdirSync(join(PUBLIC, 'clips', folder), {recursive: true});
		copyFileSync(clip, join(PUBLIC, 'clips', folder, 'clip_01.mp4'));
		for (const shape of Object.keys(MOTION_SHAPES)) {
			copyFileSync(clipFor(shape), join(PUBLIC, 'clips', folder, `clip_${shape}.mp4`));
		}
	}
};

const checkFullRender = async (serveUrl) => {
	const inputProps = loadSample('sample_feature_ar');
	const composition = await compositionFor(serveUrl, inputProps);
	const outputLocation = join(OUT, 'render_check_feature_ar.mp4');
	const since = Date.now();
	await renderMedia({
		composition,
		serveUrl,
		inputProps,
		codec: 'h264',
		audioCodec: 'aac',
		audioBitrate: AUDIO_BITRATE,
		videoBitrate: VIDEO_BITRATE,
		sampleRate: SAMPLE_RATE,
		pixelFormat: 'yuv420p',
		imageFormat: 'jpeg',
		enforceAudioTrack: true,
		offthreadVideoCacheSizeInBytes: VIDEO_CACHE_BYTES,
		outputLocation,
		overwrite: true,
		logLevel: 'error',
	});
	const renderSeconds = seconds(since);
	const size = statSync(outputLocation).size;
	const mp4 = readMp4(outputLocation);
	const video = mp4.tracks.find((track) => track.codec === 'avc1');
	const audio = mp4.tracks.find((track) => track.codec === 'mp4a');
	require(video, `no H.264 video track, found ${JSON.stringify(mp4.tracks)}`);
	require(audio, `no AAC audio track, found ${JSON.stringify(mp4.tracks)}`);
	require(video.width === 1080 && video.height === 1920, `size is ${video.width}x${video.height}`);
	require(size < MAX_FILE_BYTES, `the file is ${size} bytes, over the 48 MB limit`);
	pass(
		'full render',
		`${outputLocation}, 1080x1920 H.264 with AAC, ${(size / 1024 / 1024).toFixed(1)} MB, ` +
			`${composition.durationInFrames} frames in ${renderSeconds} s, moov first: ${mp4.moovFirst}, ` +
			`edit list: ${video.hasEditList}`,
	);
	return outputLocation;
};

/** Renders every frame of a sample, and returns the path for each frame number. */
const framesOf = async (serveUrl, sampleName) => {
	const inputProps = loadSample(sampleName);
	const composition = await compositionFor(serveUrl, inputProps);
	const outputDir = join(OUT, 'frames', sampleName);
	rmSync(outputDir, {recursive: true, force: true});
	mkdirSync(outputDir, {recursive: true});
	await renderFrames({
		composition,
		serveUrl,
		inputProps,
		outputDir,
		imageFormat: 'png',
		scale: CHECK_SCALE,
		offthreadVideoCacheSizeInBytes: VIDEO_CACHE_BYTES,
		onStart: () => undefined,
		onFrameUpdate: () => undefined,
		logLevel: 'error',
	});
	const names = readdirSync(outputDir).filter((name) => name.endsWith('.png')).sort();
	require(names.length === composition.durationInFrames, `${sampleName}: got ${names.length} frames`);
	return {inputProps, paths: names.map((name) => join(outputDir, name))};
};

const clipFrames = (clip, fps) => ({
	from: Math.floor((clip.start_ms * fps) / 1000),
	to: Math.ceil((clip.end_ms * fps) / 1000),
});

const checkSafetyOnEveryFrame = async (serveUrl) => {
	for (const sampleName of ['sample_basket_ar', 'sample_basket_en']) {
		const {inputProps, paths} = await framesOf(serveUrl, sampleName);
		const {from, to} = clipFrames(inputProps.clips[0], inputProps.fps);
		paths.forEach((path, frame) => {
			const png = readPng(path);
			const coral = countPixels(png, isWatermarkCoral);
			require(coral >= MIN_WATERMARK_PIXELS, `${sampleName} frame ${frame}: watermark missing (${coral})`);
			const amber = countPixels(png, isLabelAmber);
			const green = countPixels(png, isSecretGreen);
			if (frame >= from && frame < to) {
				require(amber >= MIN_LABEL_PIXELS, `${sampleName} frame ${frame}: label missing (${amber})`);
				// A pill with its words gone would still count as amber.
				const ink = countIn(png, boxOf(png, isLabelAmber), isLabelInk);
				require(ink >= MIN_LABEL_INK_PIXELS, `${sampleName} frame ${frame}: the label has no readable text (${ink})`);
				require(green <= MAX_LEAKED_GREEN_PIXELS, `${sampleName} frame ${frame}: mask leaks (${green})`);
			} else {
				require(amber < MIN_LABEL_PIXELS / 10, `${sampleName} frame ${frame}: label outside the clip (${amber})`);
			}
		});
		pass('smart_basket frames', `${sampleName}: watermark, mask and label right on all ${paths.length} frames`);
	}

	// The same clip outside smart_basket has no mask, so this shows the pixel test can really see it.
	const {inputProps, paths} = await framesOf(serveUrl, 'sample_control_ar');
	const {from, to} = clipFrames(inputProps.clips[0], inputProps.fps);
	const png = readPng(paths[Math.floor((from + to) / 2)]);
	const green = countPixels(png, isSecretGreen);
	require(green >= MIN_CONTROL_GREEN_PIXELS, `control: sharp stripes not seen (${green})`);
	const amber = countPixels(png, isLabelAmber);
	require(amber < MIN_LABEL_PIXELS / 10, `control: a label appeared on a plain clip (${amber})`);
	pass('mask control', `an unmasked clip shows ${green} secret pixels, so the zero above means something`);
};

// Opening a browser for each of hundreds of stills would take most of the check's time.
let sharedBrowser = null;

const stillOf = async (serveUrl, inputProps, frame, name, scale = 1) => {
	sharedBrowser ??= await openBrowser('chrome', {logLevel: 'error'});
	const composition = await selectComposition({serveUrl, id: inputProps.template, inputProps, logLevel: 'error', puppeteerInstance: sharedBrowser});
	const output = join(OUT, 'stills', `${name}.png`);
	mkdirSync(join(OUT, 'stills'), {recursive: true});
	await renderStill({composition, serveUrl, inputProps, output, frame, imageFormat: 'png', scale, overwrite: true, logLevel: 'error', offthreadVideoCacheSizeInBytes: VIDEO_CACHE_BYTES, puppeteerInstance: sharedBrowser});
	return output;
};

/**
 * The same camera over the same clip, with and without masks, on the frames where it moves most, at
 * three recording shapes and in both directions. Where the green is in the plain frame says where
 * the secret really is on that frame, so this shows the mask is on it, is still blurred, and has
 * not drifted, through zoom and tilt.
 */
const checkMasksThroughMotion = async (serveUrl) => {
	const base = loadSample('sample_basket_ar');
	const clip = {...base.clips[0], start_ms: 1000, end_ms: 1000 + MOTION_SECONDS * 800, focal_point: {x: 0.5, y: 0.3}};
	const since = Date.now();
	let frames = 0;
	let worstLeak = 0;
	let worstEdges = 0;
	const mostControlEdges = {};
	for (const shape of Object.keys(MOTION_SHAPES)) {
		mostControlEdges[shape] = 0;
		for (const language of ['ar', 'en']) {
			const masked = {
				...base,
				reel_id: 'MOTION',
				language,
				duration_ms: 6000,
				clips: [{...clip, src: `clips/smart_basket/clip_${shape}.mp4`}],
			};
			const plain = {
				...masked,
				clips: [{...clip, src: `clips/payday_cycle/clip_${shape}.mp4`, folder: 'payday_cycle', mask_regions: []}],
			};
			for (const frame of MOTION_FRAMES) {
				const where = `${shape} ${language} frame ${frame}`;
				const maskedPng = readPng(await stillOf(serveUrl, masked, frame, 'motion_masked'));
				const plainPng = readPng(await stillOf(serveUrl, plain, frame, 'motion_plain'));
				const green = boxOf(plainPng, isSecretGreen);
				require(green.count >= MIN_CONTROL_GREEN_PIXELS, `${where}: the secret is not on screen in the plain frame (${green.count})`);
				const leak = countPixels(maskedPng, isSecretGreen);
				worstLeak = Math.max(worstLeak, leak);
				require(leak <= MAX_LEAKED_GREEN_PIXELS, `${where}: the mask leaks (${leak})`);

				const inside = shrink(green, 1);
				const edges = edgesIn(maskedPng, inside);
				mostControlEdges[shape] = Math.max(mostControlEdges[shape], edgesIn(plainPng, inside));
				worstEdges = Math.max(worstEdges, edges);
				require(edges <= MAX_MASK_EDGES, `${where}: sharp lines come through the mask (${edges})`);

				const label = boxOf(maskedPng, isLabelAmber);
				const changed = boxOf(maskedPng, (r, g, b, x, y) => {
					if (y >= label.top - 12 && y <= label.bottom + 12) {
						return false;
					}
					const at = (y * plainPng.width + x) * 4;
					return (
						Math.abs(r - plainPng.data[at]) > MASK_DIFFERENCE ||
						Math.abs(g - plainPng.data[at + 1]) > MASK_DIFFERENCE ||
						Math.abs(b - plainPng.data[at + 2]) > MASK_DIFFERENCE
					);
				});
				// The sample mask runs 5% to 95% across and 20% to 28% down, around green from 10% to 90%
				// and 21% to 27%. So it should cover the green, and stop close to these margins. The edge
				// of the phone can cut the green short, so the room allowed is more than the margin.
				const greenWidth = green.right - green.left;
				const greenHeight = green.bottom - green.top;
				const roomX = greenWidth * 0.1 + 8;
				const roomY = greenHeight * 0.5 + 8;
				require(
					changed.left <= green.left + 4 && changed.right >= green.right - 4 && changed.top <= green.top + 4 && changed.bottom >= green.bottom - 4,
					`${where}: the mask does not cover the secret: mask ${JSON.stringify(changed)}, secret ${JSON.stringify(green)}`,
				);
				require(
					changed.left >= green.left - roomX && changed.right <= green.right + roomX && changed.top >= green.top - roomY && changed.bottom <= green.bottom + roomY,
					`${where}: the mask has drifted from the secret: mask ${JSON.stringify(changed)}, secret ${JSON.stringify(green)}`,
				);
				frames++;
			}
		}
		// A far-off secret is too small to have lines, so what counts is that the zoom brings them out.
		require(mostControlEdges[shape] >= MIN_CONTROL_EDGES, `${shape}: no sharp lines to hide in any plain frame`);
	}
	pass(
		'masks through motion',
		`${frames} frames: at most ${worstLeak} green pixels and ${worstEdges} sharp edges through a mask, against up to ` +
			`${JSON.stringify(mostControlEdges)} sharp edges with none, and each mask on its secret, in ${seconds(since)} s`,
	);
};

const checkPropsFailTheRender = async (serveUrl) => {
	const sample = loadSample('sample_myth_ar');
	const output = join(OUT, 'bad_props.png');
	const tryRender = async (inputProps, id = 'MythVsFact') => {
		rmSync(output, {force: true});
		try {
			const composition = await selectComposition({serveUrl, id, inputProps, logLevel: 'error'});
			await renderStill({composition, serveUrl, inputProps, output, frame: 0, overwrite: true, logLevel: 'error'});
			return null;
		} catch (error) {
			return String(error);
		}
	};
	const without = (field) => Object.fromEntries(Object.entries(sample).filter(([name]) => name !== field));
	const fields = ['hook_text', 'words', 'clips', 'on_screen_text', 'safe_zones', 'watermark', 'brand', 'language'];
	for (const field of fields) {
		const failure = await tryRender(without(field));
		require(failure !== null, `a render with no ${field} went ahead`);
		require(failure.includes(field), `a render with no ${field} failed for another reason: ${failure.slice(0, 300)}`);
		require(!existsSync(output), `a frame was written with no ${field}`);
	}
	const cases = [
		['no props at all', {}],
		['an unknown field', {...sample, hide_watermark: true}],
		['props for another template', sample, 'DailyTip'],
		['a logo from the web', {...sample, brand: {...sample.brand, logo_src: 'https://example.invalid/a.svg'}}],
		['a path out of public', {...sample, audio_src: '../secret.wav'}],
		['a glyph no brand font has', {...sample, hook_text: `${sample.hook_text} \u{1F631}`}],
	];
	for (const [name, props, id] of cases) {
		const failure = await tryRender(props, id);
		require(failure !== null, `a render with ${name} went ahead`);
		require(!existsSync(output), `a frame was written with ${name}`);
	}
	pass('bad props', `${fields.length} missing fields and ${cases.length} other bad inputs each fail the render and write no frame`);
};

/** The browser's own check on every fitted text, with the longest text the contract allows. */
const checkLongestTextFits = async (serveUrl) => {
	const longAr = 'خطط ميزانيتك '.repeat(16).trim().slice(0, 160);
	const longEn = 'Plan your whole budget '.repeat(8).trim().slice(0, 160);
	const hook = 'خطط ميزانيتك '.repeat(18).trim().slice(0, 200);
	const zones = {
		accepted: {top: 220, bottom: 420, left: 60, right: 140},
		narrow: {top: 220, bottom: 420, left: 0, right: 660},
	};
	const longWord = {text: 'الاستراتيجياتوالاستثماراتوالميزانيات', start_ms: 3200, end_ms: 8900};
	const sampleFor = (name, on_screen_text, language) => ({
		...loadSample(name),
		reel_id: 'FIT',
		language,
		duration_ms: 9000,
		hook_text: hook,
		on_screen_text,
		words: [longWord],
		subtitles_en: longEn,
	});
	let count = 0;
	for (const [zoneName, safe_zones] of Object.entries(zones)) {
		for (const language of ['ar', 'en']) {
			const long = language === 'ar' ? longAr : longEn;
			const reels = [
				[sampleFor('sample_tip_en', [long, long, long], language), [40, 100, 130, 230, 260]],
				[sampleFor('sample_myth_ar', [long, long], language), [40, 100, 150, 260]],
				[{...sampleFor('sample_basket_ar', [long], language), clips: [{...loadSample('sample_basket_ar').clips[0], start_ms: 3000, end_ms: 8000}]}, [40, 92, 200]],
			];
			for (const [reel, frames] of reels) {
				for (const frame of frames) {
					await stillOf(serveUrl, {...reel, safe_zones}, frame, `fit_${zoneName}`, CHECK_SCALE);
					count++;
				}
			}
		}
	}
	pass('longest text', `${count} frames with the longest text the contract allows, in two zones, with no overflow in the browser`);
};

/** No template may stop moving. Each sample's stage changes between any two frames two seconds apart. */
const checkKeepsMoving = async (serveUrl) => {
	const details = [];
	for (const name of ['sample_feature_ar', 'sample_tip_en', 'sample_myth_ar']) {
		const inputProps = loadSample(name);
		const total = Math.ceil((inputProps.duration_ms * inputProps.fps) / 1000);
		const step = MOVING_STEP_SECONDS * inputProps.fps;
		let previous = null;
		let least = 1;
		for (let frame = 90; frame < total; frame += step) {
			const png = readPng(await stillOf(serveUrl, inputProps, frame, 'moving', GOLDEN_SCALE));
			if (previous) {
				const share = differentPixels(png, previous);
				least = Math.min(least, share);
				require(share >= MIN_MOVED_PIXELS, `${name}: only ${(share * 100).toFixed(2)}% of pixels change by frame ${frame}`);
			}
			previous = png;
		}
		details.push(`${name} at least ${(least * 100).toFixed(1)}%`);
	}
	pass('keeps moving', `pixels changed over every ${MOVING_STEP_SECONDS} s: ${details.join(', ')}`);
};

const checkDeterminism = async (serveUrl) => {
	const inputProps = loadSample('sample_basket_ar');
	const hash = async () => createHash('sha256').update(readFileSync(await stillOf(serveUrl, inputProps, 40, 'determinism'))).digest('hex');
	const first = await hash();
	require(first === (await hash()), 'the same frame came out different twice');
	pass('determinism', 'the same frame renders to the same bytes');
};

const brandTokenFrame = (sample) => {
	const index = sample.words.findIndex((word) => word.text.startsWith('قوام'));
	require(index >= 0, 'the sample has no brand name');
	return Math.ceil(((sample.words[index].start_ms + 80) * sample.fps) / 1000);
};

const differentPixels = (actual, expected) => {
	if (actual.width !== expected.width || actual.height !== expected.height) {
		return 1;
	}
	let different = 0;
	for (let at = 0; at < actual.data.length; at += 4) {
		if (
			Math.abs(actual.data[at] - expected.data[at]) > GOLDEN_CHANNEL_TOLERANCE ||
			Math.abs(actual.data[at + 1] - expected.data[at + 1]) > GOLDEN_CHANNEL_TOLERANCE ||
			Math.abs(actual.data[at + 2] - expected.data[at + 2]) > GOLDEN_CHANNEL_TOLERANCE
		) {
			different++;
		}
	}
	return different / (actual.width * actual.height);
};

const checkGoldenFrames = async (serveUrl) => {
	const actualDir = join(OUT, 'golden_actual');
	mkdirSync(actualDir, {recursive: true});
	mkdirSync(GOLDEN, {recursive: true});
	for (const {name, sample: sampleName, frame} of GOLDEN_FRAMES) {
		const inputProps = loadSample(sampleName);
		const composition = await compositionFor(serveUrl, inputProps);
		const output = join(actualDir, `${name}.png`);
		await renderStill({
			composition,
			serveUrl,
			inputProps,
			output,
			frame: frame ?? brandTokenFrame(inputProps),
			imageFormat: 'png',
			scale: GOLDEN_SCALE,
			offthreadVideoCacheSizeInBytes: VIDEO_CACHE_BYTES,
			overwrite: true,
			logLevel: 'error',
		});
		const reference = join(GOLDEN, `${name}.png`);
		if (UPDATE_GOLDEN) {
			copyFileSync(output, reference);
			continue;
		}
		require(existsSync(reference), `golden/${name}.png is missing. Run with --update-golden, then check it by eye`);
		const share = differentPixels(readPng(output), readPng(reference));
		require(
			share <= GOLDEN_MAX_DIFFERENT_PIXELS,
			`${name} differs from its golden frame on ${(share * 100).toFixed(2)}% of pixels. See ${output}`,
		);
	}
	pass(
		'golden frames',
		UPDATE_GOLDEN
			? `wrote ${GOLDEN_FRAMES.length} frames, pending the owner's eye (LIVE-5)`
			: `${GOLDEN_FRAMES.length} frames match, pending the owner's eye (LIVE-5)`,
	);
};

const checkMissingFontFails = async () => {
	const publicDir = join(OUT, 'public_without_cairo');
	rmSync(publicDir, {recursive: true, force: true});
	cpSync(PUBLIC, publicDir, {recursive: true});
	rmSync(join(publicDir, 'fonts', 'cairo'), {recursive: true, force: true});
	const serveUrl = await bundle({entryPoint: join(ROOT, 'src', 'index.ts'), publicDir});
	const inputProps = loadSample('sample_myth_ar');
	const composition = await compositionFor(serveUrl, inputProps);
	const output = join(OUT, 'must_not_exist.png');
	rmSync(output, {force: true});
	let failure = null;
	try {
		await renderStill({composition, serveUrl, inputProps, output, frame: 60, overwrite: true, logLevel: 'error'});
	} catch (error) {
		failure = String(error);
	}
	require(failure !== null, 'the render went ahead without the Arabic font');
	require(/Cairo/.test(failure), `the render failed for another reason: ${failure.slice(0, 300)}`);
	require(!existsSync(output), 'a frame was written without the Arabic font');
	rmSync(publicDir, {recursive: true, force: true});
	pass('missing Arabic font', 'the render fails and writes no frame');
};

const runBundledFfmpeg = (args) => {
	const command = ['npx', 'remotion', 'ffmpeg', ...args].join(' ');
	const result = spawnSync(command, {cwd: ROOT, shell: true, encoding: 'utf-8'});
	require(result.status === 0, `bundled FFmpeg refused: ${command}\n${(result.stderr ?? '').slice(-800)}`);
};

/** Plan task F7: trim, metadata strip and +faststart remux through the FFmpeg Remotion ships. */
const checkBundledFfmpeg = (input) => {
	const relative = (name) => `out/${name}`;
	const source = relative('render_check_feature_ar.mp4');
	require(existsSync(input), 'the full render is missing');
	const before = readMp4(input);

	const trimmed = relative('ffmpeg_trim.mp4');
	runBundledFfmpeg(['-y', '-loglevel', 'error', '-ss', '1', '-t', '3', '-i', source, '-c', 'copy', trimmed]);
	require(statSync(join(ROOT, trimmed)).size > 0, 'the trim wrote nothing');
	const trimResult = readMp4(join(ROOT, trimmed));

	const stripped = relative('ffmpeg_strip.mp4');
	runBundledFfmpeg(['-y', '-loglevel', 'error', '-i', source, '-map_metadata', '-1', '-c', 'copy', stripped]);
	require(statSync(join(ROOT, stripped)).size > 0, 'the strip wrote nothing');

	const faststart = relative('ffmpeg_faststart.mp4');
	runBundledFfmpeg(['-y', '-loglevel', 'error', '-i', source, '-c', 'copy', '-movflags', '+faststart', faststart]);
	const faststartResult = readMp4(join(ROOT, faststart));
	require(faststartResult.moovFirst, `+faststart did not move moov first: ${faststartResult.order}`);

	// What the conform step needs (spec Section 8.6): moov first and no edit lists. Remotion's own
	// output has edit lists, and +faststart alone keeps them, so -use_editlist 0 is what removes them.
	const conformed = relative('ffmpeg_conform.mp4');
	runBundledFfmpeg(['-y', '-loglevel', 'error', '-i', source, '-map_metadata', '-1', '-c', 'copy', '-use_editlist', '0', '-movflags', '+faststart', conformed]);
	const conformedResult = readMp4(join(ROOT, conformed));
	require(conformedResult.moovFirst, 'the conform step did not put moov first');
	require(conformedResult.tracks.length === 2, 'the conform step lost a track');
	require(!conformedResult.tracks.some((track) => track.hasEditList), 'the conform step left an edit list');
	pass(
		'bundled FFmpeg',
		`trim, metadata strip, +faststart and -use_editlist 0 all ran. Remotion's own output: moov first ${before.moovFirst}, ` +
			`edit list ${before.tracks.some((track) => track.hasEditList)}. After the conform: moov first ${conformedResult.moovFirst}, edit list false. ` +
			`Edit list after a plain trim: ${trimResult.tracks.some((track) => track.hasEditList)}`,
	);
};

/**
 * Batch G runs `remotion render <template> <file>` with no entry point, so the real CLI has to find
 * the entry point by itself and list each template as a composition under that exact name.
 */
const checkCliFindsEachTemplate = () => {
	const command = 'npx --no remotion compositions --quiet';
	const result = spawnSync(command, {cwd: ROOT, shell: true, encoding: 'utf-8'});
	require(result.status === 0, `${command} failed: ${(result.stderr ?? '').slice(-800)}`);
	const schema = JSON.parse(readFileSync(join(ROOT, 'props.schema.json'), 'utf-8'));
	const expected = [...schema.properties.template.enum].sort();
	// After a fresh install the CLI first prints a line about caching its bundle. The IDs come last.
	const found = result.stdout.trim().split(/\r?\n/).at(-1).trim().split(/\s+/).sort();
	require(found.join() === expected.join(), `the CLI lists ${found}, and the schema lists ${expected}`);
	pass('composition IDs', `the CLI found the entry point by itself and lists ${found.join(', ')}`);
};

const main = async () => {
	mkdirSync(OUT, {recursive: true});
	await ensureBrowser();
	await prepareInputs();
	const since = Date.now();
	const serveUrl = await bundle({entryPoint: join(ROOT, 'src', 'index.ts'), publicDir: PUBLIC});
	log(`bundled in ${seconds(since)} s`);

	const checks = {
		cli: checkCliFindsEachTemplate,
		'full-render': async () => checkBundledFfmpeg(await checkFullRender(serveUrl)),
		safety: () => checkSafetyOnEveryFrame(serveUrl),
		masks: () => checkMasksThroughMotion(serveUrl),
		'bad-props': () => checkPropsFailTheRender(serveUrl),
		'longest-text': () => checkLongestTextFits(serveUrl),
		moving: () => checkKeepsMoving(serveUrl),
		determinism: () => checkDeterminism(serveUrl),
		golden: () => checkGoldenFrames(serveUrl),
		'missing-font': checkMissingFontFails,
	};
	for (const [name, check] of Object.entries(checks)) {
		if (!ONLY || ONLY.includes(name)) {
			await check();
		}
	}
	await sharedBrowser?.close({silent: true});
	log(`all ${results.length} checks passed`);
};

main().then(() => process.exit(0)).catch((error) => {
	console.error(`[render-check] FAILED: ${error instanceof CheckFailed ? error.message : error?.stack ?? error}`);
	process.exit(1);
});
