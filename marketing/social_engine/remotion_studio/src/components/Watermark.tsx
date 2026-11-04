import React from 'react';
import {LATIN_FAMILY} from '../lib/fonts';
import type {ReelLayout} from '../lib/layout';
import {CANVAS_HEIGHT, CANVAS_WIDTH} from '../lib/layout';
import {TEST_WATERMARK} from '../lib/strings';
import {colors, withAlpha} from '../lib/tokens';

const TILE_ROWS = 9;
const BANNER_HEIGHT = 58;

/**
 * Burned into every frame of a test reel. It takes no frame number, so nothing about it can change
 * over time, and it covers the whole canvas, so cropping cannot remove it.
 */
export const Watermark: React.FC<{layout: ReelLayout}> = ({layout}) => {
	const rows = Array.from({length: TILE_ROWS}, (_, row) => row);
	return (
		<div
			data-watermark="test"
			style={{position: 'absolute', inset: 0, overflow: 'hidden', fontFamily: LATIN_FAMILY}}
		>
			<div
				style={{
					position: 'absolute',
					left: -CANVAS_WIDTH / 2,
					top: -CANVAS_HEIGHT / 4,
					width: CANVAS_WIDTH * 2,
					height: CANVAS_HEIGHT * 1.5,
					display: 'flex',
					flexDirection: 'column',
					justifyContent: 'space-around',
					transform: 'rotate(-24deg)',
				}}
			>
				{rows.map((row) => (
					<div
						key={row}
						aria-hidden="true"
						style={{
							textAlign: 'center',
							whiteSpace: 'nowrap',
							fontSize: 56,
							fontWeight: 700,
							color: withAlpha(colors.textPrimaryDark, 0.16),
						}}
					>
						{`${TEST_WATERMARK}     ${TEST_WATERMARK}     ${TEST_WATERMARK}`}
					</div>
				))}
			</div>
			<div
				data-watermark-banner="true"
				style={{
					position: 'absolute',
					left: 0,
					right: 0,
					top: Math.max(0, layout.content.top - BANNER_HEIGHT - 6),
					height: BANNER_HEIGHT,
					display: 'flex',
					alignItems: 'center',
					justifyContent: 'center',
					background: colors.coralDanger,
					color: colors.canvasDarkBg,
					fontSize: 36,
					fontWeight: 700,
				}}
			>
				{TEST_WATERMARK}
			</div>
		</div>
	);
};
