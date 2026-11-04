/**
 * The local render check (plan tasks F6 and F7). Everything is generated and rendered here, with
 * no call to any service. Output goes to out/, which git and the sync both leave alone.
 *
 *   npm run render:check
 *   node scripts/render_check.mjs --update-golden   writes golden/*.png for review by eye
 */
import {bundle} from '@remotion/bundler';
import {ensureBrowser, renderFrames, renderMedia, renderStill, selectComposition} from '@remotion/renderer';
import {spawnSync} from 'node:child_process';
import {copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {PNG} from 'pngjs';

const ROOT = resolve(import.meta.dirname, '..');
const OUT = join(ROOT, 'out');
const PUBLIC = join(ROOT, 'public');
const GOLDEN = join(ROOT, 'golden');
const UPDATE_GOLDEN = process.argv.includes('--update-golden');

const MAX_FILE_BYTES = 48 * 1024 * 1024;
const VIDEO_BITRATE = '8000k';
const AUDIO_BITRATE = '192k';
const SAMPLE_RATE = 48000;
const VOICE_SECONDS = 32;

const GOLDEN_SCALE = 0.5;
const GOLDEN_CHANNEL_TOLERANCE = 24;
const GOLDEN_MAX_DIFFERENT_PIXELS = 0.005;
const CHECK_SCALE = 0.5;

// Colours nothing else in a reel uses, so counting them finds the thing they mark.
const isSecretGreen = (r, g, b) => g > 170 && r < 90 && b < 90;
const isLabelAmber = (r, g, b) => Math.abs(r - 0xf5) < 16 && Math.abs(g - 0x9e) < 16 && Math.abs(b - 0x0b) < 24;
const isWatermarkCoral = (r, g, b) => Math.abs(r - 0xf4) < 16 && Math.abs(g - 0x3f) < 16 && Math.abs(b - 0x5e) < 16;
const MIN_LABEL_PIXELS = 1500;
const MIN_WATERMARK_PIXELS = 5000;
const MIN_CONTROL_GREEN_PIXELS = 400;
const MAX_LEAKED_GREEN_PIXELS = 12;

const GOLDEN_FRAMES = [
	{name: 'hook_first_frame', sample: 'sample_feature_ar', frame: 0},
	{name: 'hook_impact', sample: 'sample_feature_ar', frame: 12},
	{name: 'hook_hero', sample: 'sample_feature_ar', frame: 60},
	{name: 'clip_hard_words', sample: 'sample_feature_ar', frame: 200},
	{name: 'caption_brand_token', sample: 'sample_feature_ar', frame: null},
	{name: 'smart_basket_mask_label', sample: 'sample_feature_ar', frame: 600},
	{name: 'tip_en', sample: 'sample_tip_en', frame: 240},
	{name: 'myth_ar', sample: 'sample_myth_ar', frame: 250},
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

const compositionFor = (serveUrl, inputProps) =>
	selectComposition({serveUrl, id: inputProps.template, inputProps, logLevel: 'error'});

const prepareInputs = async () => {
	mkdirSync(join(PUBLIC, 'audio'), {recursive: true});
	writeSilentWav(join(PUBLIC, 'audio', 'voice.wav'), VOICE_SECONDS);

	const clip = join(OUT, 'placeholder', 'clip.mp4');
	if (!existsSync(clip)) {
		const since = Date.now();
		const serveUrl = await bundle({entryPoint: join(ROOT, 'test_data', 'placeholder', 'entry.tsx')});
		const composition = await selectComposition({serveUrl, id: 'PlaceholderClip', logLevel: 'error'});
		await renderMedia({
			composition,
			serveUrl,
			codec: 'h264',
			crf: 18,
			pixelFormat: 'yuv420p',
			outputLocation: clip,
			overwrite: true,
			logLevel: 'error',
		});
		log(`generated the placeholder clip in ${seconds(since)} s`);
	}
	for (const folder of ['payday_cycle', 'smart_basket']) {
		mkdirSync(join(PUBLIC, 'clips', folder), {recursive: true});
		copyFileSync(clip, join(PUBLIC, 'clips', folder, 'clip_01.mp4'));
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
	const found = result.stdout.trim().split(/\s+/).sort();
	require(found.join() === expected.join(), `the CLI lists ${found}, and the schema lists ${expected}`);
	pass('composition IDs', `the CLI found the entry point by itself and lists ${found.join(', ')}`);
};

const main = async () => {
	mkdirSync(OUT, {recursive: true});
	await ensureBrowser();
	await prepareInputs();
	checkCliFindsEachTemplate();
	const since = Date.now();
	const serveUrl = await bundle({entryPoint: join(ROOT, 'src', 'index.ts'), publicDir: PUBLIC});
	log(`bundled in ${seconds(since)} s`);

	const fullRender = await checkFullRender(serveUrl);
	await checkSafetyOnEveryFrame(serveUrl);
	await checkGoldenFrames(serveUrl);
	await checkMissingFontFails();
	checkBundledFfmpeg(fullRender);
	log(`all ${results.length} checks passed`);
};

main().catch((error) => {
	console.error(`[render-check] FAILED: ${error instanceof CheckFailed ? error.message : error?.stack ?? error}`);
	process.exit(1);
});
