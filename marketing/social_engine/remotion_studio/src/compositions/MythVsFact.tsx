import React from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {Isolated} from '../components/Isolated';
import {fontStack, LATIN_FAMILY} from '../lib/fonts';
import {label} from '../lib/strings';
import {hasArabic} from '../lib/text';
import {colors, withAlpha} from '../lib/tokens';
import type {StageContext, TemplateDefinition} from './media';

const FACT_AT_FRACTION = 0.45;

const Card: React.FC<{
	heading: string;
	text: string | undefined;
	accent: string;
	symbol: 'cross' | 'check';
	language: StageContext['language'];
	digits: StageContext['digits'];
	hit: number;
	fromY: number;
	dimmed: number;
}> = ({heading, text, accent, symbol, language, digits, hit, fromY, dimmed}) => (
	<div
		data-myth-card={symbol}
		dir={language === 'ar' ? 'rtl' : 'ltr'}
		style={{
			position: 'relative',
			padding: '30px 34px',
			borderRadius: 24,
			background: `linear-gradient(150deg, ${colors.surfaceDarkGradientStart}, ${colors.surfaceDarkGradientEnd})`,
			border: `2px solid ${withAlpha(accent, 0.7)}`,
			boxShadow: `0 0 70px ${withAlpha(accent, 0.3)}`,
			opacity: interpolate(hit, [0, 0.4], [0, 1], {extrapolateRight: 'clamp'}) * (1 - dimmed * 0.45),
			transform: `translateY(${interpolate(hit, [0, 1], [fromY, 0])}px) scale(${interpolate(hit, [0, 1], [1.2, 1] )})`,
		}}
	>
		<div
			style={{
				display: 'flex',
				alignItems: 'center',
				gap: 18,
				marginBottom: 14,
				fontFamily: fontStack(language),
				fontWeight: 700,
				fontSize: 42,
				color: accent,
			}}
		>
			<Symbol kind={symbol} color={accent} />
			<span>{heading}</span>
		</div>
		{text ? (
			<div
				dir={hasArabic(text) ? 'rtl' : 'ltr'}
				style={{
					textAlign: language === 'ar' ? 'right' : 'left',
					fontFamily: hasArabic(text) ? fontStack('ar') : LATIN_FAMILY,
					fontWeight: 600,
					fontSize: 50,
					lineHeight: 1.25,
					color: colors.textPrimaryDark,
				}}
			>
				<Isolated text={text} language={hasArabic(text) ? 'ar' : 'en'} digits={digits} />
			</div>
		) : null}
	</div>
);

const Symbol: React.FC<{kind: 'cross' | 'check'; color: string}> = ({kind, color}) => (
	<svg width={54} height={54} viewBox="0 0 54 54" aria-hidden="true">
		<circle cx={27} cy={27} r={25} fill="none" stroke={color} strokeWidth={4} />
		{kind === 'cross' ? (
			<path d="M18 18 L36 36 M36 18 L18 36" stroke={color} strokeWidth={6} strokeLinecap="round" />
		) : (
			<path d="M15 28 L24 37 L39 19" fill="none" stroke={color} strokeWidth={6} strokeLinecap="round" strokeLinejoin="round" />
		)}
	</svg>
);

const Comparison: React.FC<{context: StageContext}> = ({context}) => {
	const {frame, fps, durationInFrames, language, digits, layout, onScreenText, stageStartFrame} =
		context;
	const factAt =
		stageStartFrame + Math.round((durationInFrames - stageStartFrame) * FACT_AT_FRACTION);
	const config = {damping: 12, stiffness: 200, mass: 0.7};
	const mythHit = spring({frame: frame - stageStartFrame, fps, config});
	const factHit = frame < factAt ? 0 : spring({frame: frame - factAt, fps, config});
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
				gap: 30,
			}}
		>
			<Card
				heading={label('stopDoingThis', language)}
				text={onScreenText[0]}
				accent={colors.coralDanger}
				symbol="cross"
				language={language}
				digits={digits}
				hit={mythHit}
				fromY={-180}
				dimmed={factHit}
			/>
			{frame >= factAt ? (
				<Card
					heading={label('theSmartWay', language)}
					text={onScreenText[1]}
					accent={colors.emeraldSafe}
					symbol="check"
					language={language}
					digits={digits}
					hit={factHit}
					fromY={180}
					dimmed={0}
				/>
			) : null}
		</div>
	);
};

/** Template C, Stop Doing This vs. The Smart Way: a fast comparison. Needs no clip. */
export const MythVsFact: TemplateDefinition = {
	tilt: {fromDeg: 12, toDeg: 6},
	zoom: {from: 1, to: 1.08},
	renderStage: (context) => <Comparison context={context} />,
};
