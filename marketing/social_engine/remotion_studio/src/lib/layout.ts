import type {SafeZones} from '../props';

/** The zones of spec Section 8.2, worked out from the safe zones in props. */

export const CANVAS_WIDTH = 1080;
export const CANVAS_HEIGHT = 1920;

const MIN_CONTENT_HEIGHT = 700;
const MIN_CONTENT_WIDTH = 420;
const NARROW_BELOW = 640;
const HUD_ROW_HEIGHT = 64;
const HUD_STACKED_HEIGHT = 96;
const GAP = 14;
const TOP_HEIGHT = 190;
const TOP_SHARE = 0.15;
const CAPTION_HEIGHT = 212;
const CAPTION_SHARE = 0.18;
const LABEL_ONE_LINE_HEIGHT = 62;
const LABEL_TWO_LINES_HEIGHT = 104;
const LABEL_GAP = 4;
const DEVICE_WIDTH_SHARE = 0.82;
const DEVICE_MAX_WIDTH = 740;
// A phone recording: 1080 x 2340, and only the bezel around it.
const SCREEN_ASPECT = 1080 / 2340;

export const DEVICE_BEZEL = 14;

export type Rect = {top: number; left: number; width: number; height: number};

export type ReelLayout = {
	content: Rect;
	top: Rect;
	stage: Rect;
	captions: Rect;
	hud: Rect;
	/** The phone at full size. Its lower part runs on behind the captions. */
	device: Rect;
	/** The part of the screen no overlay ever covers. */
	view: Rect;
	/** Reserved between the hook and the phone, so the label covers nothing in a clip. */
	labelBand: Rect;
	narrow: boolean;
};

export const computeLayout = (zones: SafeZones): ReelLayout => {
	const width = CANVAS_WIDTH - zones.left - zones.right;
	const height = CANVAS_HEIGHT - zones.top - zones.bottom;
	if (height < MIN_CONTENT_HEIGHT || width < MIN_CONTENT_WIDTH) {
		throw new Error(
			`safe zones leave ${width}x${height} px, and a reel needs at least ` +
				`${MIN_CONTENT_WIDTH}x${MIN_CONTENT_HEIGHT}`,
		);
	}
	const {left, top} = zones;
	const narrow = width < NARROW_BELOW;
	const hudHeight = narrow ? HUD_STACKED_HEIGHT : HUD_ROW_HEIGHT;
	const topHeight = Math.round(Math.min(TOP_HEIGHT, height * TOP_SHARE));
	const captionHeight = Math.round(Math.min(CAPTION_HEIGHT, height * CAPTION_SHARE));
	const hudTop = top + height - hudHeight;
	const captionTop = hudTop - GAP - captionHeight;
	const stageTop = top + topHeight + GAP;
	const stageHeight = captionTop - GAP - stageTop;

	const labelHeight = narrow ? LABEL_TWO_LINES_HEIGHT : LABEL_ONE_LINE_HEIGHT;
	const deviceTop = stageTop + labelHeight + LABEL_GAP;
	const deviceWidth = Math.min(Math.round(width * DEVICE_WIDTH_SHARE), DEVICE_MAX_WIDTH);
	const screenWidth = deviceWidth - 2 * DEVICE_BEZEL;
	const deviceHeight = Math.round(screenWidth / SCREEN_ASPECT) + 2 * DEVICE_BEZEL;

	return {
		content: {top, left, width, height},
		top: {top, left, width, height: topHeight},
		stage: {top: stageTop, left, width, height: stageHeight},
		captions: {top: captionTop, left, width, height: captionHeight},
		hud: {top: hudTop, left, width, height: hudHeight},
		device: {
			top: deviceTop,
			left: left + Math.round((width - deviceWidth) / 2),
			width: deviceWidth,
			height: deviceHeight,
		},
		view: {top: deviceTop, left, width, height: captionTop - GAP - deviceTop},
		labelBand: {top: stageTop, left, width, height: labelHeight},
		narrow,
	};
};
