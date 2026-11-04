import React from 'react';
import {DEVICE_BEZEL} from '../lib/layout';
import {colors, withAlpha} from '../lib/tokens';
import type {Language} from '../props';

const OUTER_RADIUS = 62;
const INNER_RADIUS = 50;

/**
 * A plain rounded phone with no maker's shape or mark on it (D31). The tilt mirrors with the
 * language, so the phone leans the way the reel reads.
 */
export const DeviceFrame: React.FC<{
	kind: 'generic';
	language: Language;
	left: number;
	top: number;
	width: number;
	height: number;
	tiltDeg: number;
	tiltXDeg?: number;
	scale: number;
	offsetY: number;
	children: React.ReactNode;
}> = ({kind, language, left, top, width, height, tiltDeg, tiltXDeg = 3, scale, offsetY, children}) => {
	if (kind !== 'generic') {
		throw new Error(`only the generic device frame is allowed (D31), got ${String(kind)}`);
	}
	const lean = language === 'ar' ? -tiltDeg : tiltDeg;
	return (
		<div
			data-device-frame={kind}
			style={{
				position: 'absolute',
				left,
				top,
				width,
				height,
				padding: DEVICE_BEZEL,
				boxSizing: 'border-box',
				borderRadius: OUTER_RADIUS,
				border: `2px solid ${withAlpha(colors.roseGoldGlow, 0.5)}`,
				background: `linear-gradient(160deg, ${colors.primaryLight}, ${colors.surfaceDarkGradientEnd} 45%, ${colors.canvasDarkBg})`,
				boxShadow: `0 50px 160px ${withAlpha(colors.accentRose, 0.5)}, 0 0 90px ${withAlpha(colors.roseGoldGlow, 0.24)}, inset 0 0 0 2px ${withAlpha(colors.canvasDarkBg, 0.9)}`,
				transformOrigin: 'center top',
				transform: `translateY(${offsetY}px) perspective(2200px) rotateY(${lean}deg) rotateX(${tiltXDeg}deg) scale(${scale})`,
			}}
		>
			<div
				data-device-screen="true"
				style={{
					position: 'relative',
					width: '100%',
					height: '100%',
					overflow: 'hidden',
					borderRadius: INNER_RADIUS,
					background: colors.canvasDarkBg,
				}}
			>
				{children}
			</div>
		</div>
	);
};
