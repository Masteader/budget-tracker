import React from 'react';
import type {ReelMedia} from '../compositions/media';
import {fontStack} from '../lib/fonts';
import type {Rect} from '../lib/layout';
import {colors, withAlpha} from '../lib/tokens';
import type {Language, RenderProps} from '../props';

const LOGO_SIZE = 44;
const TAG_MAX_SIZE = 28;
const TAG_MIN_SIZE = 16;
const TAG_GAP = 12;
const ROW_SHARE = 0.6;

/**
 * The bottom HUD: progress, which fills from the side the language reads from, and the brand tag on
 * one row, or stacked where the zone is narrow. The logo is only ever the one named in props.
 */
export const ProgressHud: React.FC<{
	brand: RenderProps['brand'];
	language: Language;
	rect: Rect;
	narrow: boolean;
	frame: number;
	durationInFrames: number;
	highlightColor: string;
	media: ReelMedia;
}> = ({brand, language, rect, narrow, frame, durationInFrames, highlightColor, media}) => {
	const progress = durationInFrames > 1 ? Math.min(1, frame / (durationInFrames - 1)) : 1;
	const [first, second] =
		language === 'ar' ? [brand.name_ar, brand.name_en] : [brand.name_en, brand.name_ar];
	const room = (narrow ? rect.width : rect.width * ROW_SHARE) - LOGO_SIZE - TAG_GAP;
	let size = TAG_MAX_SIZE;
	while (size > TAG_MIN_SIZE && media.measure(`${first} ${second}`, {size, weight: 600}) > room) {
		size -= 2;
	}
	return (
		<div
			data-zone="hud"
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			style={{
				position: 'absolute',
				top: rect.top,
				left: rect.left,
				width: rect.width,
				height: rect.height,
				display: 'flex',
				flexDirection: narrow ? 'column' : 'row',
				alignItems: narrow ? 'stretch' : 'center',
				justifyContent: narrow ? 'flex-end' : 'flex-start',
				gap: narrow ? 8 : 18,
				fontFamily: fontStack,
			}}
		>
			<div
				data-brand-tag="true"
				style={{
					display: 'flex',
					alignItems: 'center',
					gap: TAG_GAP,
					whiteSpace: 'nowrap',
					fontSize: size,
					fontWeight: 600,
					color: colors.textPrimaryDark,
					textShadow: `0 2px 12px ${withAlpha(colors.canvasDarkBg, 0.9)}`,
				}}
			>
				<media.Logo src={brand.logo_src} size={LOGO_SIZE} />
				<span>
					<bdi>{first}</bdi> <bdi>{second}</bdi>
				</span>
			</div>
			<div
				style={{
					flex: narrow ? '0 0 8px' : 1,
					height: 8,
					borderRadius: 4,
					overflow: 'hidden',
					background: withAlpha(colors.textPrimaryDark, 0.16),
				}}
			>
				<div
					data-progress-fill="true"
					style={{
						width: '100%',
						height: '100%',
						background: highlightColor,
						transformOrigin: language === 'ar' ? 'right center' : 'left center',
						transform: `scaleX(${progress})`,
					}}
				/>
			</div>
		</div>
	);
};
