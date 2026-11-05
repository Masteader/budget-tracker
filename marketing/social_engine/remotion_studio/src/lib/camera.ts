import {Easing, interpolate} from 'remotion';
import type {PropsClip} from '../props';
import type {ReelLayout} from './layout';
import {DEVICE_BEZEL} from './layout';
import {clipRunStartMs, clipWindow, msToFrame} from './timeline';

/**
 * The camera on a clip, as pure arithmetic. The phone opens wide with all of it in view, pushes in
 * until the feature named by the focal point fills the clear part of the screen, keeps creeping in,
 * and pulls back before the clip ends.
 *
 * The zoom is a transform on the box that holds the clip and its masks, with percentages that the
 * browser works out from that box's own height. So the focal point lands true at any recording
 * shape, and masks stay on their target because they are in the same box.
 */

export const DEFAULT_FOCAL_POINT = {x: 0.5, y: 0.42};

const WIDE_SECONDS = 0.55;
const PUSH_SECONDS = 1;
const PULL_SECONDS = 0.6;
const FULL_TIMING_SECONDS = WIDE_SECONDS + PUSH_SECONDS + PULL_SECONDS;
const CREEP_PER_SECOND = 0.012;
const MAX_CREEP = 0.14;
const END_DEVICE_SCALE = 1.06;
const MIN_WIDE_SCALE = 0.4;
const ENTRY_OFFSET = 300;
const SWAY_DEGREES = 1;
const TILT_X_DEGREES = 3;

/** Where the feature rests, from the top of the clear part of the screen. */
export const FOCAL_REST_SHARE = 0.34;

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const lerp = (from: number, to: number, amount: number): number => from + (to - from) * amount;
const easeInOut = Easing.bezier(0.65, 0, 0.2, 1);

export type CameraPose = {
	deviceScale: number;
	offsetY: number;
	tiltDeg: number;
	tiltXDeg: number;
	zoom: number;
	translateX: number;
	translateY: string;
	/** 0 when wide, 1 when pushed all the way in. */
	pushed: number;
	/** Where the focal point is on the canvas, for a recording shaped like the phone's screen. */
	focalCanvas: {x: number; y: number};
};

export const cameraPose = ({
	clip,
	clips,
	frame,
	fps,
	layout,
	motion,
}: {
	clip: PropsClip;
	clips: PropsClip[];
	frame: number;
	fps: number;
	layout: ReelLayout;
	motion: {tilt: {fromDeg: number; toDeg: number}; zoom: {from: number; to: number}};
}): CameraPose => {
	const {device, view} = layout;
	const focal = clip.focal_point ?? DEFAULT_FOCAL_POINT;
	const {from, to} = clipWindow(clip, fps);
	const seconds = (frame - from) / fps;
	const length = Math.max(1 / fps, (to - from) / fps);
	// A short clip plays the same moves, faster.
	const pace = Math.min(1, length / FULL_TIMING_SECONDS);
	const pushFrom = WIDE_SECONDS * pace;
	const pushTo = pushFrom + PUSH_SECONDS * pace;
	const pullFrom = Math.max(pushTo, length - PULL_SECONDS * pace - 1 / fps);
	const pushedIn = interpolate(seconds, [pushFrom, pushTo], [0, 1], {...clamp, easing: easeInOut});
	const pulledOut = interpolate(seconds, [pullFrom, length - 1 / fps], [0, 1], {...clamp, easing: easeInOut});
	const pushed = pushedIn * (1 - pulledOut);
	const creep = Math.min(MAX_CREEP, Math.max(0, seconds - pushTo) * CREEP_PER_SECOND);

	const screenWidth = device.width - 2 * DEVICE_BEZEL;
	const screenHeight = device.height - 2 * DEVICE_BEZEL;
	const wideScale = Math.max(MIN_WIDE_SCALE, Math.min(1, (view.top + view.height - device.top) / device.height));
	const deviceScale = lerp(wideScale, END_DEVICE_SCALE, pushed);
	const zoom = lerp(motion.zoom.from, motion.zoom.to + creep, pushed);

	// Where the focal point should rest, in the screen's own pixels at the end of the push.
	const restY = view.top + view.height * FOCAL_REST_SHARE;
	const middleX = device.left + device.width / 2;
	const targetX = screenWidth / 2;
	const targetY = (restY - device.top) / END_DEVICE_SCALE - DEVICE_BEZEL;
	const viewBottom = (view.top + view.height - device.top) / END_DEVICE_SCALE - DEVICE_BEZEL;

	const translateX = Math.min(0, Math.max(screenWidth * (1 - zoom), pushed * (targetX - zoom * focal.x * screenWidth)));
	const toTarget = (pushed * targetY).toFixed(2);
	const toFocal = (pushed * zoom * focal.y * 100).toFixed(3);
	const lowest = viewBottom.toFixed(2);
	const translateY = `min(0px, max(calc(${lowest}px - ${(zoom * 100).toFixed(3)}%), calc(${toTarget}px - ${toFocal}%)))`;

	// The same sum for a clip as tall as the screen, so tests and the callouts can see where it lands.
	const inScreenY = Math.min(0, Math.max(viewBottom - zoom * screenHeight, pushed * (targetY - zoom * focal.y * screenHeight)));
	const entryFrames = frame - msToFrame(clipRunStartMs(clips, clip), fps);
	const entry = interpolate(entryFrames, [0, 0.4 * fps], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
	const offsetY = lerp(ENTRY_OFFSET, 0, entry);
	const focalCanvas = {
		x: middleX + deviceScale * (DEVICE_BEZEL + zoom * focal.x * screenWidth + translateX - device.width / 2),
		y: device.top + offsetY + deviceScale * (DEVICE_BEZEL + zoom * focal.y * screenHeight + inScreenY),
	};

	const sway = Math.sin((frame / fps) * 0.9) * SWAY_DEGREES;
	return {
		deviceScale,
		offsetY,
		tiltDeg: lerp(motion.tilt.fromDeg, motion.tilt.toDeg, pushed) + sway,
		tiltXDeg: lerp(TILT_X_DEGREES, TILT_X_DEGREES / 3, pushed),
		zoom,
		translateX,
		translateY,
		pushed,
		focalCanvas,
	};
};
