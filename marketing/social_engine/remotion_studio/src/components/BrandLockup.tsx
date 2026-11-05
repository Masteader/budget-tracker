import React from 'react';
import type {ReelMedia} from '../compositions/media';
import type {MeasureText} from '../lib/fit';
import {fontStack} from '../lib/fonts';
import {colors, withAlpha} from '../lib/tokens';
import type {Language, RenderProps} from '../props';

/** The largest size up to `largest` at which the wider name fits this width. */
export const fitNameSize = (
	brand: Pick<RenderProps['brand'], 'name_ar' | 'name_en'>,
	measure: MeasureText,
	width: number,
	largest: number,
): number => {
	const reference = 100;
	const widest = Math.max(
		measure(brand.name_ar, {size: reference, weight: 700}),
		measure(brand.name_en, {size: reference, weight: 700}),
	);
	return Math.min(largest, Math.floor((width / widest) * reference));
};

/**
 * The brand, in full, in both languages. The mark is only ever the one named in props. Each name is
 * one no-wrap line, so the full name can never break (G18).
 */
export const BrandLockup: React.FC<{
	brand: RenderProps['brand'];
	language: Language;
	media: ReelMedia;
	logoSize: number;
	nameSize: number;
	glow: number;
	align?: 'center' | 'start';
	maxWidth: number;
}> = ({brand, language, media, logoSize, nameSize, glow, align = 'center', maxWidth}) => {
	const [first, second] = language === 'ar' ? [brand.name_ar, brand.name_en] : [brand.name_en, brand.name_ar];
	return (
		<div
			data-brand-lockup="true"
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			style={{
				display: 'flex',
				alignItems: 'center',
				justifyContent: align === 'center' ? 'center' : 'flex-start',
				gap: logoSize * 0.28,
				maxWidth,
				fontFamily: fontStack,
			}}
		>
			<div
				style={{
					flex: `0 0 ${logoSize}px`,
					height: logoSize,
					borderRadius: logoSize * 0.26,
					overflow: 'hidden',
					boxShadow: `0 0 ${40 + glow * 50}px ${withAlpha(colors.roseGoldGlow, 0.25 + glow * 0.45)}`,
				}}
			>
				<media.Logo src={brand.logo_src} size={logoSize} />
			</div>
			<div style={{display: 'flex', flexDirection: 'column', whiteSpace: 'nowrap', minWidth: 0}}>
				<span style={{fontSize: nameSize, fontWeight: 700, lineHeight: 1.2, color: colors.textPrimaryDark}}>
					<bdi>{first}</bdi>
				</span>
				<span style={{fontSize: nameSize * 0.56, fontWeight: 600, lineHeight: 1.25, color: colors.roseGold}}>
					<bdi>{second}</bdi>
				</span>
			</div>
		</div>
	);
};
