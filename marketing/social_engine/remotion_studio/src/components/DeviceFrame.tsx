import React from 'react';
import {colors, withAlpha} from '../lib/tokens';
import type {Language} from '../props';

const BEZEL = 14;
const OUTER_RADIUS = 54;
const INNER_RADIUS = 42;

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
	scale: number;
	offsetY: number;
	children: React.ReactNode;
}> = ({kind, language, left, top, width, height, tiltDeg, scale, offsetY, children}) => {
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
				padding: BEZEL,
				boxSizing: 'border-box',
				borderRadius: OUTER_RADIUS,
				border: `1px solid ${withAlpha(colors.roseGoldGlow, 0.35)}`,
				background: `linear-gradient(160deg, ${colors.surfaceDarkGradientStart}, ${colors.surfaceDarkGradientEnd})`,
				boxShadow: `0 40px 120px ${withAlpha(colors.accentRose, 0.35)}, 0 0 60px ${withAlpha(colors.roseGoldGlow, 0.16)}`,
				transformOrigin: 'center top',
				transform: `translateY(${offsetY}px) perspective(1800px) rotateY(${lean}deg) rotateX(3deg) scale(${scale})`,
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
