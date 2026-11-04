import React from 'react';
import type {ReelMedia} from '../compositions/media';
import {fontStack} from '../lib/fonts';
import type {Rect} from '../lib/layout';
import {colors, withAlpha} from '../lib/tokens';
import type {Language, RenderProps} from '../props';

const LOGO_SIZE = 52;

/**
 * The bottom HUD: progress, which fills from the side the language reads from, and the brand tag.
 * The logo is only ever the one named in props.
 */
export const ProgressHud: React.FC<{
	brand: RenderProps['brand'];
	language: Language;
	rect: Rect;
	frame: number;
	durationInFrames: number;
	highlightColor: string;
	media: ReelMedia;
}> = ({brand, language, rect, frame, durationInFrames, highlightColor, media}) => {
	const progress = durationInFrames > 1 ? Math.min(1, frame / (durationInFrames - 1)) : 1;
	const [first, second] =
		language === 'ar' ? [brand.name_ar, brand.name_en] : [brand.name_en, brand.name_ar];
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
				flexDirection: 'column',
				justifyContent: 'flex-end',
				gap: 12,
				fontFamily: fontStack(language),
			}}
		>
			<div
				data-brand-tag="true"
				style={{
					display: 'flex',
					alignItems: 'center',
					gap: 14,
					whiteSpace: 'nowrap',
					fontSize: 30,
					fontWeight: 600,
					color: colors.textPrimaryDark,
				}}
			>
				<media.Logo src={brand.logo_src} size={LOGO_SIZE} />
				<span>
					<bdi>{first}</bdi> <bdi>{second}</bdi>
				</span>
			</div>
			<div
				style={{
					height: 10,
					borderRadius: 5,
					overflow: 'hidden',
					background: withAlpha(colors.textPrimaryDark, 0.14),
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
