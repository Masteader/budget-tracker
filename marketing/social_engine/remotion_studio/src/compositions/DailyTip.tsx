import React from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {Isolated} from '../components/Isolated';
import {fontStack, LATIN_FAMILY} from '../lib/fonts';
import {hasArabic} from '../lib/text';
import {colors, withAlpha} from '../lib/tokens';
import type {StageContext, TemplateDefinition} from './media';

const CARD_COUNT = 3;
const MAX_CARD_GAP_SECONDS = 2.2;

const TipCards: React.FC<{context: StageContext}> = ({context}) => {
	const {frame, fps, durationInFrames, language, digits, layout, onScreenText, stageStartFrame} =
		context;
	const cards = onScreenText.slice(0, CARD_COUNT);
	if (cards.length === 0) {
		return null;
	}
	const gap = Math.min(
		MAX_CARD_GAP_SECONDS * fps,
		Math.max(1, (durationInFrames - stageStartFrame) / cards.length),
	);
	const fromSide = language === 'ar' ? 1 : -1;
	const {stage} = layout;
	return (
		<div
			style={{
				position: 'absolute',
				top: stage.top,
				left: stage.left,
				width: stage.width,
				height: stage.height,
				display: 'flex',
				flexDirection: 'column',
				justifyContent: 'center',
				gap: 26,
			}}
		>
			{cards.map((text, index) => {
				const hit = spring({
					frame: frame - stageStartFrame - Math.round(index * gap),
					fps,
					config: {damping: 13, stiffness: 190, mass: 0.7},
				});
				return (
					<div
						key={text}
						data-tip-card={index}
						dir={language === 'ar' ? 'rtl' : 'ltr'}
						style={{
							display: 'flex',
							alignItems: 'center',
							gap: 26,
							padding: '26px 30px',
							borderRadius: 24,
							background: `linear-gradient(150deg, ${colors.surfaceDarkGradientStart}, ${colors.surfaceDarkGradientEnd})`,
							border: `1px solid ${withAlpha(colors.textPrimaryDark, 0.08)}`,
							boxShadow: `0 0 60px ${withAlpha(colors.accentRose, 0.25)}`,
							opacity: interpolate(hit, [0, 0.4], [0, 1], {extrapolateRight: 'clamp'}),
							transform: `translateX(${interpolate(hit, [0, 1], [fromSide * 520, 0])}px) scale(${interpolate(hit, [0, 1], [0.9, 1])})`,
						}}
					>
						<div
							style={{
								flex: '0 0 84px',
								height: 84,
								display: 'flex',
								alignItems: 'center',
								justifyContent: 'center',
								borderRadius: 22,
								background: colors.roseGold,
								color: colors.canvasDarkBg,
								fontFamily: fontStack(language),
								fontWeight: 700,
								fontSize: 48,
							}}
						>
							<Isolated text={String(index + 1)} language={language} digits={digits} />
						</div>
						<div
							dir={hasArabic(text) ? 'rtl' : 'ltr'}
							style={{
								flex: 1,
								textAlign: language === 'ar' ? 'right' : 'left',
								fontFamily: hasArabic(text) ? fontStack('ar') : LATIN_FAMILY,
								fontWeight: 600,
								fontSize: 46,
								lineHeight: 1.25,
								color: colors.textPrimaryDark,
							}}
						>
							<Isolated text={text} language={hasArabic(text) ? 'ar' : 'en'} digits={digits} />
						</div>
					</div>
				);
			})}
		</div>
	);
};

/** Template B, Daily Money Hack: a punchy hook, then three fast cards. Needs no clip. */
export const DailyTip: TemplateDefinition = {
	tilt: {fromDeg: 12, toDeg: 6},
	zoom: {from: 1, to: 1.08},
	renderStage: (context) => <TipCards context={context} />,
};
