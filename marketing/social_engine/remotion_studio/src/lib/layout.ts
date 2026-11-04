import type {SafeZones} from '../props';

/** The four zones of spec Section 8.2, worked out from the safe zones in props. */

export const CANVAS_WIDTH = 1080;
export const CANVAS_HEIGHT = 1920;

const MIN_CONTENT_HEIGHT = 700;
const MIN_CONTENT_WIDTH = 420;
const HUD_HEIGHT = 92;
const GAP = 14;
const DEVICE_ASPECT = 0.5;
const DEVICE_OVERLAP = 130; // the phone's lower edge runs behind the caption panel

export type Rect = {top: number; left: number; width: number; height: number};

export type ReelLayout = {
	content: Rect;
	top: Rect;
	stage: Rect;
	captions: Rect;
	hud: Rect;
	device: Rect;
	labelTop: number;
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
	const topHeight = Math.round(Math.min(250, height * 0.2));
	const captionHeight = Math.round(Math.min(270, height * 0.21));
	const hudTop = top + height - HUD_HEIGHT;
	const captionTop = hudTop - GAP - captionHeight;
	const stageTop = top + topHeight + GAP;
	const stageHeight = captionTop - GAP - stageTop;
	const deviceHeight = stageHeight + DEVICE_OVERLAP;
	const deviceWidth = Math.min(Math.round(deviceHeight * DEVICE_ASPECT), width);

	return {
		content: {top, left, width, height},
		top: {top, left, width, height: topHeight},
		stage: {top: stageTop, left, width, height: stageHeight},
		captions: {top: captionTop, left, width, height: captionHeight},
		hud: {top: hudTop, left, width, height: HUD_HEIGHT},
		device: {
			top: stageTop,
			left: left + Math.round((width - deviceWidth) / 2),
			width: deviceWidth,
			height: deviceHeight,
		},
		labelTop: stageTop + 6,
	};
};
