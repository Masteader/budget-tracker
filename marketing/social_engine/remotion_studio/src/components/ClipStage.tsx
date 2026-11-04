import React from 'react';
import {Easing, interpolate} from 'remotion';
import {spring} from '../lib/motion';
import type {ReelMedia, TemplateDefinition} from '../compositions/media';
import type {Rect} from '../lib/layout';
import {clipRunStartMs, clipWindow, msToFrame} from '../lib/timeline';
import type {Language, PropsClip} from '../props';
import {ClipMask} from './ClipMask';
import {DeviceFrame} from './DeviceFrame';

const ENTRY_OFFSET = 420;

/**
 * The phone with the clip and its masks in one box. The box takes its height from the clip itself,
 * so mask fractions land true at any recording shape. Nothing but this component draws a clip.
 */
export const ClipStage: React.FC<{
	clip: PropsClip;
	clips: PropsClip[];
	device: Rect;
	language: Language;
	frame: number;
	fps: number;
	motion: Pick<TemplateDefinition, 'tilt' | 'zoom'>;
	media: ReelMedia;
}> = ({clip, clips, device, language, frame, fps, motion, media}) => {
	const {from, to} = clipWindow(clip, fps);
	const runStart = msToFrame(clipRunStartMs(clips, clip), fps);
	const entry = spring({
		frame: frame - runStart + 1,
		fps,
		config: {damping: 15, stiffness: 170, mass: 0.8},
	});
	const progress = interpolate(frame, [from, Math.max(from + 1, to - 1)], [0, 1], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
		easing: Easing.bezier(0.25, 0.1, 0.25, 1),
	});
	return (
		<DeviceFrame
			kind="generic"
			language={language}
			left={device.left}
			top={device.top}
			width={device.width}
			height={device.height}
			tiltDeg={interpolate(progress, [0, 1], [motion.tilt.fromDeg, motion.tilt.toDeg])}
			scale={interpolate(progress, [0, 1], [motion.zoom.from, motion.zoom.to])}
			offsetY={interpolate(entry, [0, 1], [ENTRY_OFFSET, 0])}
		>
			<div data-clip-box="true" style={{position: 'relative', width: '100%'}}>
				<media.Clip clip={clip} fps={fps} />
				<ClipMask clip={clip} fps={fps} media={media} />
			</div>
		</DeviceFrame>
	);
};
