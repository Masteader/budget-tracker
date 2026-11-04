import React from 'react';
import type {ReelMedia} from '../compositions/media';
import {DEFAULT_FOCAL_POINT} from '../lib/camera';
import type {CameraPose} from '../lib/camera';
import {CANVAS_HEIGHT, CANVAS_WIDTH} from '../lib/layout';
import type {ReelLayout} from '../lib/layout';
import {colors, withAlpha} from '../lib/tokens';
import type {Language, PropsClip} from '../props';
import {ClipMask} from './ClipMask';
import {DeviceFrame} from './DeviceFrame';

const SCRIM_RISE = 150;
const SPOTLIGHT_STRENGTH = 0.38;
const PERCENT = 100;

/**
 * The phone with the clip and its masks in one box, and the camera on that box. The box takes its
 * height from the clip itself, so mask fractions and the focal point land true at any recording
 * shape, at any zoom. Nothing but this component draws a clip.
 */
export const ClipStage: React.FC<{
	clip: PropsClip;
	layout: ReelLayout;
	language: Language;
	camera: CameraPose;
	frame: number;
	fps: number;
	media: ReelMedia;
}> = ({clip, layout, language, camera, frame, fps, media}) => {
	const {device, view} = layout;
	const focus = clip.focal_point ?? DEFAULT_FOCAL_POINT;
	const scrimTop = view.top + view.height - SCRIM_RISE;
	const pulse = 0.5 + 0.5 * Math.sin((frame / fps) * 2.4);
	return (
		<>
			<div
				aria-hidden="true"
				style={{
					position: 'absolute',
					left: device.left - 180,
					top: device.top - 80,
					width: device.width + 360,
					height: Math.min(device.height, CANVAS_HEIGHT - device.top),
					borderRadius: '50%',
					background: `radial-gradient(ellipse at center, ${withAlpha(colors.accentRose, 0.34 + pulse * 0.1)} 0%, ${withAlpha(colors.accentRose, 0)} 68%)`,
				}}
			/>
			<DeviceFrame
				kind="generic"
				language={language}
				left={device.left}
				top={device.top}
				width={device.width}
				height={device.height}
				tiltDeg={camera.tiltDeg}
				tiltXDeg={camera.tiltXDeg}
				scale={camera.deviceScale}
				offsetY={camera.offsetY}
			>
				<div
					data-clip-box="true"
					style={{
						position: 'relative',
						width: '100%',
						transformOrigin: '0 0',
						transform: `translate(${camera.translateX.toFixed(2)}px, ${camera.translateY}) scale(${camera.zoom.toFixed(4)})`,
					}}
				>
					<media.Clip clip={clip} fps={fps} />
					<ClipMask clip={clip} fps={fps} media={media} />
					<div
						aria-hidden="true"
						data-clip-spotlight="true"
						style={{
							position: 'absolute',
							inset: 0,
							zIndex: 2,
							opacity: camera.pushed * SPOTLIGHT_STRENGTH,
							background: `radial-gradient(ellipse 90% 30% at ${focus.x * PERCENT}% ${focus.y * PERCENT}%, ${withAlpha(colors.canvasDarkBg, 0)} 55%, ${withAlpha(colors.canvasDarkBg, 0.95)} 100%)`,
						}}
					/>
				</div>
			</DeviceFrame>
			<div
				aria-hidden="true"
				style={{
					position: 'absolute',
					left: 0,
					top: scrimTop,
					width: CANVAS_WIDTH,
					height: CANVAS_HEIGHT - scrimTop,
					opacity: camera.pushed,
					background: `linear-gradient(180deg, ${withAlpha(colors.canvasDarkBg, 0)} 0%, ${withAlpha(colors.canvasDarkBg, 0.92)} 26%, ${colors.canvasDarkBg} 100%)`,
				}}
			/>
		</>
	);
};
