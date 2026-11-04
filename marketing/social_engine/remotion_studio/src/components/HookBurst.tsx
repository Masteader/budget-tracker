import React from 'react';
import {interpolate} from 'remotion';
import {colors, withAlpha} from '../lib/tokens';

const FLASH_SECONDS = 0.3;
const BURST_SECONDS = 0.55;
const SPARK_COUNT = 16;

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** The pattern break: a flash on the first frame, then a ring and sparks when the hook lands. */
export const HookBurst: React.FC<{
	frame: number;
	fps: number;
	centerX: number;
	centerY: number;
	landingFrame: number;
}> = ({frame, fps, centerX, centerY, landingFrame}) => {
	const flashFrames = Math.round(FLASH_SECONDS * fps);
	const burstFrames = Math.round(BURST_SECONDS * fps);
	const since = (frame - landingFrame) / burstFrames;
	const showFlash = frame < flashFrames;
	const showBurst = since >= 0 && since < 1;
	if (!showFlash && !showBurst) {
		return null;
	}
	return (
		<div style={{position: 'absolute', inset: 0, overflow: 'hidden'}}>
			{showFlash ? (
				<div
					data-hook-flash="true"
					style={{
						position: 'absolute',
						inset: 0,
						background: colors.roseGoldGlow,
						opacity: interpolate(frame, [0, flashFrames], [0.42, 0], clamp),
					}}
				/>
			) : null}
			{showBurst ? (
				<div
					data-hook-burst="true"
					style={{position: 'absolute', left: centerX, top: centerY, width: 0, height: 0}}
				>
					{[0, 0.18].map((delay) => {
						const ring = interpolate(since, [delay, 1], [0, 1], clamp);
						return (
							<div
								key={delay}
								style={{
									position: 'absolute',
									left: -420,
									top: -420,
									width: 840,
									height: 840,
									borderRadius: '50%',
									border: `10px solid ${withAlpha(colors.roseGold, 0.85)}`,
									opacity: interpolate(ring, [0, 1], [0.8, 0]),
									transform: `scale(${interpolate(ring, [0, 1], [0.25, 1.55])})`,
								}}
							/>
						);
					})}
					{Array.from({length: SPARK_COUNT}, (_, index) => {
						const angle = (index / SPARK_COUNT) * Math.PI * 2;
						const reach = interpolate(since, [0, 1], [160, 620 + (index % 3) * 90]);
						return (
							<div
								key={angle}
								style={{
									position: 'absolute',
									width: 14,
									height: 14,
									borderRadius: '50%',
									background: colors.roseGoldGlow,
									boxShadow: `0 0 26px ${colors.roseGold}`,
									opacity: interpolate(since, [0, 0.8, 1], [1, 0.8, 0], clamp),
									transform: `translate(${Math.cos(angle) * reach}px, ${Math.sin(angle) * reach}px) scale(${interpolate(since, [0, 1], [1.3, 0.3])})`,
								}}
							/>
						);
					})}
				</div>
			) : null}
		</div>
	);
};
