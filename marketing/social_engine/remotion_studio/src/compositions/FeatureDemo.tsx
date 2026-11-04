import React from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {Isolated} from '../components/Isolated';
import {fontStack, LATIN_FAMILY} from '../lib/fonts';
import {hasArabic} from '../lib/text';
import {itemIndexAt} from '../lib/timeline';
import {colors, withAlpha} from '../lib/tokens';
import type {StageContext, TemplateDefinition} from './media';

const Callouts: React.FC<{context: StageContext}> = ({context}) => {
	const {frame, fps, durationInFrames, language, digits, layout, onScreenText, stageStartFrame} =
		context;
	const count = onScreenText.length;
	const index = itemIndexAt(count, frame, stageStartFrame, durationInFrames);
	const text = onScreenText[index];
	if (text === undefined) {
		return null;
	}
	const span = (durationInFrames - stageStartFrame) / count;
	const startedAt = stageStartFrame + Math.round(index * span);
	const hit = spring({
		frame: frame - startedAt,
		fps,
		config: {damping: 13, stiffness: 210, mass: 0.6},
	});
	const fromSide = language === 'ar' ? 90 : -90;
	const {stage} = layout;
	return (
		<div
			data-callout="true"
			dir={hasArabic(text) ? 'rtl' : 'ltr'}
			style={{
				position: 'absolute',
				top: stage.top + stage.height - 120,
				left: stage.left,
				width: stage.width,
				display: 'flex',
				justifyContent: 'center',
				opacity: interpolate(hit, [0, 0.5], [0, 1], {extrapolateRight: 'clamp'}),
				transform: `translateX(${interpolate(hit, [0, 1], [fromSide, 0])}px)`,
			}}
		>
			<div
				style={{
					padding: '14px 28px',
					borderRadius: 22,
					background: `linear-gradient(135deg, ${colors.primaryLightGradient}, ${colors.primaryLight})`,
					border: `1px solid ${withAlpha(colors.roseGoldGlow, 0.45)}`,
					boxShadow: `0 0 50px ${withAlpha(colors.roseGoldGlow, 0.28)}`,
					fontFamily: hasArabic(text) ? fontStack('ar') : LATIN_FAMILY,
					fontWeight: 600,
					fontSize: 40,
					color: colors.textPrimaryDark,
					textAlign: 'center',
				}}
			>
				<Isolated text={text} language={hasArabic(text) ? 'ar' : 'en'} digits={digits} />
			</div>
		</div>
	);
};

/** Template A, Feature in Action: a real clip, with the phone tilting and zooming into it. */
export const FeatureDemo: TemplateDefinition = {
	tilt: {fromDeg: 16, toDeg: 7},
	zoom: {from: 1, to: 1.12},
	renderStage: () => null,
	renderForeground: (context) => <Callouts context={context} />,
};
