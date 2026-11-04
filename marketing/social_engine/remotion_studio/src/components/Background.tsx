import React from 'react';
import {random} from 'remotion';
import {CANVAS_HEIGHT, CANVAS_WIDTH} from '../lib/layout';
import {colors, withAlpha} from '../lib/tokens';

const MOTES = Array.from({length: 22}, (_, index) => ({
	x: random(`mote-x-${index}`) * CANVAS_WIDTH,
	y: random(`mote-y-${index}`) * CANVAS_HEIGHT,
	size: 4 + random(`mote-size-${index}`) * 10,
	speed: 0.4 + random(`mote-speed-${index}`) * 1.1,
	phase: random(`mote-phase-${index}`) * Math.PI * 2,
}));

/** Velvet light that keeps moving, so no frame of the reel feels static. */
export const Background: React.FC<{frame: number; fps: number}> = ({frame, fps}) => {
	const seconds = frame / fps;
	const x1 = 28 + Math.sin(seconds * 0.7) * 16;
	const y1 = 22 + Math.cos(seconds * 0.5) * 10;
	const x2 = 74 + Math.cos(seconds * 0.6) * 18;
	const y2 = 72 + Math.sin(seconds * 0.45) * 12;
	return (
		<div
			style={{
				position: 'absolute',
				inset: 0,
				overflow: 'hidden',
				background: [
					`radial-gradient(circle at ${x1}% ${y1}%, ${withAlpha(colors.primaryLightGradient, 0.95)} 0%, ${withAlpha(colors.primaryLightGradient, 0)} 58%)`,
					`radial-gradient(circle at ${x2}% ${y2}%, ${withAlpha(colors.accentRose, 0.42)} 0%, ${withAlpha(colors.accentRose, 0)} 52%)`,
					`linear-gradient(170deg, ${colors.canvasDark} 0%, ${colors.primaryDarkMaroon} 55%, ${colors.canvasDarkBg} 100%)`,
				].join(', '),
			}}
		>
			{MOTES.map((mote) => {
				const y =
					((mote.y - frame * mote.speed * (30 / fps) * 2) % CANVAS_HEIGHT + CANVAS_HEIGHT) %
					CANVAS_HEIGHT;
				return (
					<div
						key={`${mote.x}-${mote.y}`}
						style={{
							position: 'absolute',
							left: mote.x + Math.sin(seconds + mote.phase) * 26,
							top: y,
							width: mote.size,
							height: mote.size,
							borderRadius: '50%',
							background: withAlpha(colors.roseGoldGlow, 0.35),
							boxShadow: `0 0 ${mote.size * 3}px ${withAlpha(colors.roseGoldGlow, 0.55)}`,
						}}
					/>
				);
			})}
			<div
				style={{
					position: 'absolute',
					inset: 0,
					background: `radial-gradient(ellipse at center, ${withAlpha(colors.canvasDarkBg, 0)} 45%, ${withAlpha(colors.canvasDarkBg, 0.85)} 100%)`,
				}}
			/>
		</div>
	);
};
