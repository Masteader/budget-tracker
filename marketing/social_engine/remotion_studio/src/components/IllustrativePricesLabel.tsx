import React from 'react';
import {fontStack} from '../lib/fonts';
import type {Rect} from '../lib/layout';
import {ILLUSTRATIVE_AR, ILLUSTRATIVE_EN} from '../lib/strings';
import {colors} from '../lib/tokens';

const HEIGHT = 58;

/**
 * Shown for as long as a smart_basket clip shows (D30). It takes no frame number and no animation,
 * so its first frame is as readable as its last, and no prop reaches it.
 */
export const IllustrativePricesLabel: React.FC<{area: Rect; top: number}> = ({area, top}) => (
	<div
		data-illustrative-label="true"
		style={{
			position: 'absolute',
			top,
			left: area.left,
			width: area.width,
			height: HEIGHT,
			display: 'flex',
			justifyContent: 'center',
			alignItems: 'center',
		}}
	>
		<span
			style={{
				padding: '8px 26px',
				borderRadius: 18,
				background: colors.amberCaution,
				color: colors.canvasDarkBg,
				fontFamily: fontStack('ar'),
				fontWeight: 700,
				fontSize: 34,
				whiteSpace: 'nowrap',
			}}
		>
			<bdi>{ILLUSTRATIVE_EN}</bdi> / <bdi>{ILLUSTRATIVE_AR}</bdi>
		</span>
	</div>
);
