import React from 'react';
import {fontStack} from '../lib/fonts';
import type {MeasureText} from '../lib/fit';
import type {Rect} from '../lib/layout';
import {ILLUSTRATIVE_AR, ILLUSTRATIVE_EN} from '../lib/strings';
import {colors, withAlpha} from '../lib/tokens';

const WEIGHT = 700;
const MAX_SIZE = 32;
const MIN_ONE_LINE_SIZE = 25;
const MIN_SIZE = 20;
const PADDING_X = 26;
const SEPARATOR = ' / ';
const STACKED_LINE: React.CSSProperties = {display: 'block', whiteSpace: 'nowrap'};

export type LabelPlan = {fontSize: number; stacked: boolean; width: number; fits: boolean};

/** One line where it fits at a readable size, and the two languages on two lines where it does not. */
export const planLabel = (areaWidth: number, measure: MeasureText): LabelPlan => {
	const room = areaWidth - 2 * PADDING_X;
	const at = (text: string, size: number) => measure(text, {size, weight: WEIGHT});
	for (let size = MAX_SIZE; size >= MIN_ONE_LINE_SIZE; size--) {
		const line = at(`${ILLUSTRATIVE_EN}${SEPARATOR}${ILLUSTRATIVE_AR}`, size);
		if (line <= room) {
			return {fontSize: size, stacked: false, width: line + 2 * PADDING_X, fits: true};
		}
	}
	for (let size = MAX_SIZE; size >= MIN_SIZE; size--) {
		const widest = Math.max(at(`${ILLUSTRATIVE_EN}${SEPARATOR}`, size), at(ILLUSTRATIVE_AR, size));
		if (widest <= room) {
			return {fontSize: size, stacked: true, width: widest + 2 * PADDING_X, fits: true};
		}
	}
	return {fontSize: MIN_SIZE, stacked: true, width: areaWidth, fits: false};
};

/**
 * Shown for as long as a smart_basket clip shows (D30). It takes no frame number and no animation,
 * so its first frame is as readable as its last, and no prop reaches it. It sits in a band of its
 * own above the phone, so it covers nothing in the clip.
 */
export const IllustrativePricesLabel: React.FC<{band: Rect; measure: MeasureText}> = ({band, measure}) => {
	const plan = planLabel(band.width, measure);
	return (
		<div
			data-illustrative-label="true"
			data-fit-box="label"
			data-fit-max-width={band.width}
			data-fit-max-height={band.height}
			style={{
				position: 'absolute',
				top: band.top,
				left: band.left,
				width: band.width,
				height: band.height,
				display: 'flex',
				justifyContent: 'center',
				alignItems: 'center',
			}}
		>
			<span
				data-label-pill="true"
				style={{
					boxSizing: 'border-box',
					maxWidth: band.width,
					whiteSpace: plan.stacked ? undefined : 'nowrap',
					padding: `6px ${PADDING_X}px`,
					borderRadius: 18,
					textAlign: 'center',
					background: colors.amberCaution,
					boxShadow: `0 8px 34px ${withAlpha(colors.amberCaution, 0.32)}`,
					color: colors.canvasDarkBg,
					fontFamily: fontStack,
					fontWeight: WEIGHT,
					fontSize: plan.fontSize,
					lineHeight: 1.25,
				}}
			>
				<span dir={plan.stacked ? 'ltr' : undefined} style={plan.stacked ? STACKED_LINE : undefined}>
					<bdi>{ILLUSTRATIVE_EN}</bdi>
					{SEPARATOR}
				</span>
				<span style={plan.stacked ? STACKED_LINE : undefined}>
					<bdi>{ILLUSTRATIVE_AR}</bdi>
				</span>
			</span>
		</div>
	);
};
