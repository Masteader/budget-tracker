import React from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {BrandLockup, fitNameSize} from '../components/BrandLockup';
import {FlowText} from '../components/FlowText';
import {Isolated} from '../components/Isolated';
import {textTokens} from '../lib/captionGrouping';
import {fontStack} from '../lib/fonts';
import {fitFlow, requireFit} from '../lib/fit';
import type {FlowPlan, MeasureText} from '../lib/fit';
import type {ReelLayout} from '../lib/layout';
import {baseLanguage} from '../lib/text';
import {tipBeats} from '../lib/timeline';
import {colors, withAlpha} from '../lib/tokens';
import type {Digits, Language} from '../props';
import type {StageContext, TemplateDefinition} from './media';

const CARD_COUNT = 3;
const STEPPER_HEIGHT = 56;
const STEPPER_GAP = 18;
const CARD_PADDING = 40;
const CARD_RING = 128;
const CARD_GAP = 24;
const CARD_MAX_SIZE = 92;
const CARD_MIN_SIZE = 26;
const WORD_STAGGER_FRAMES = 3;
const EXIT_SECONDS = 0.28;
const BAR_COUNT = 14;
const MIN_BARS_ROOM = 70;
const GHOST_SIZE = 620;

const PANEL_PADDING = 28;
const HEADER_GAP = 22;
const ROW_TICK = 58;
const ROW_TICK_GAP = 18;
const ROW_GAP = 14;
const ROW_MAX_SIZE = 66;
const ROW_MIN_SIZE = 18;
const ROW_LINE_HEIGHT = 1.24;

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

const headerRingFor = (layout: ReelLayout): number => (layout.narrow ? 108 : 168);

/** One card at a time has the whole stage, so its text can be big. */
export const planTipCard = (
	text: string,
	brandNames: string[],
	reelLanguage: Language,
	digits: Digits,
	layout: ReelLayout,
	measure: MeasureText,
): FlowPlan & {tokens: ReturnType<typeof textTokens>; language: Language} => {
	const {stage} = layout;
	const language = baseLanguage(text, reelLanguage);
	const tokens = textTokens(text, brandNames);
	const plan = fitFlow({
		tokens,
		language,
		digits,
		measure,
		weight: 700,
		maxWidth: stage.width - 2 * CARD_PADDING,
		maxHeight: stage.height - STEPPER_HEIGHT - STEPPER_GAP - 2 * CARD_PADDING - CARD_RING - CARD_GAP,
		maxSize: CARD_MAX_SIZE,
		minSize: CARD_MIN_SIZE,
		lineHeight: 1.2,
		rowGap: 0.06,
	});
	return {...plan, tokens, language};
};

type RecapRow = {tokens: ReturnType<typeof textTokens>; language: Language; plan: FlowPlan};

export type RecapPlan = {rows: RecapRow[]; rowsHeight: number; maxRowsHeight: number; fits: boolean};

/** All three together, at one size, in what the panel leaves under its header. */
export const planTipRecap = (
	texts: string[],
	brandNames: string[],
	reelLanguage: Language,
	digits: Digits,
	layout: ReelLayout,
	measure: MeasureText,
): RecapPlan => {
	const {stage} = layout;
	const maxRowsHeight = stage.height - 2 * PANEL_PADDING - headerRingFor(layout) - HEADER_GAP;
	const maxWidth = stage.width - 2 * PANEL_PADDING - ROW_TICK - ROW_TICK_GAP;
	const at = (size: number): RecapPlan => {
		const rows = texts.map((text) => {
			const language = baseLanguage(text, reelLanguage);
			const tokens = textTokens(text, brandNames);
			const plan = fitFlow({
				tokens,
				language,
				digits,
				measure,
				weight: 600,
				maxWidth,
				maxHeight: maxRowsHeight,
				maxSize: size,
				minSize: size,
				lineHeight: ROW_LINE_HEIGHT,
			});
			return {tokens, language, plan};
		});
		const rowsHeight =
			rows.reduce((sum, row) => sum + Math.max(ROW_TICK, row.plan.height), 0) + ROW_GAP * Math.max(0, rows.length - 1);
		return {
			rows,
			rowsHeight,
			maxRowsHeight,
			fits: rowsHeight <= maxRowsHeight && rows.every((row) => row.plan.fits),
		};
	};
	for (let size = ROW_MAX_SIZE; size > ROW_MIN_SIZE; size -= 2) {
		const plan = at(size);
		if (plan.fits) {
			return plan;
		}
	}
	return at(ROW_MIN_SIZE);
};

const Ring: React.FC<{size: number; progress: number; color: string; children?: React.ReactNode}> = ({
	size,
	progress,
	color,
	children,
}) => {
	const radius = size / 2 - 8;
	const around = 2 * Math.PI * radius;
	return (
		<div style={{position: 'relative', flex: `0 0 ${size}px`, width: size, height: size}}>
			<svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" style={{position: 'absolute', inset: 0}}>
				<circle cx={size / 2} cy={size / 2} r={radius} fill={withAlpha(colors.canvasDarkBg, 0.55)} stroke={withAlpha(colors.textPrimaryDark, 0.14)} strokeWidth={10} />
				<circle
					cx={size / 2}
					cy={size / 2}
					r={radius}
					fill="none"
					stroke={color}
					strokeWidth={10}
					strokeLinecap="round"
					strokeDasharray={`${around * Math.min(1, progress)} ${around}`}
					transform={`rotate(-90 ${size / 2} ${size / 2})`}
				/>
			</svg>
			<div style={{position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
				{children}
			</div>
		</div>
	);
};

/** Where the reel is among the cards. It fills without stopping, in reading direction. */
const Stepper: React.FC<{count: number; position: number; context: StageContext}> = ({count, position, context}) => {
	const {language, digits, highlightColor} = context;
	return (
		<div
			data-tip-stepper="true"
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			style={{height: STEPPER_HEIGHT, display: 'flex', alignItems: 'center', gap: 10, fontFamily: fontStack}}
		>
			{Array.from({length: count}, (_, index) => {
				const reached = position >= index;
				const fill = Math.max(0, Math.min(1, position - index));
				return (
					<React.Fragment key={index}>
						<div
							style={{
								flex: '0 0 48px',
								height: 48,
								borderRadius: 24,
								display: 'flex',
								alignItems: 'center',
								justifyContent: 'center',
								fontSize: 28,
								fontWeight: 700,
								background: reached ? highlightColor : withAlpha(colors.textPrimaryDark, 0.12),
								color: reached ? colors.canvasDarkBg : colors.textSecondaryDark,
								boxShadow: reached ? `0 0 26px ${withAlpha(colors.roseGoldGlow, 0.45)}` : 'none',
							}}
						>
							<Isolated text={String(index + 1)} language={language} digits={digits} />
						</div>
						{index < count - 1 ? (
							<div style={{flex: 1, height: 6, borderRadius: 3, overflow: 'hidden', background: withAlpha(colors.textPrimaryDark, 0.12)}}>
								<div
									style={{
										width: '100%',
										height: '100%',
										background: highlightColor,
										transformOrigin: language === 'ar' ? 'right center' : 'left center',
										transform: `scaleX(${fill})`,
									}}
								/>
							</div>
						) : null}
					</React.Fragment>
				);
			})}
		</div>
	);
};

/** A row of bars that rise as the card goes on, so a card is never a still picture. No figures. */
const Bars: React.FC<{progress: number; seconds: number; color: string; dir: 'rtl' | 'ltr'}> = ({progress, seconds, color, dir}) => (
	<div
		data-tip-bars="true"
		aria-hidden="true"
		dir={dir}
		style={{position: 'relative', flex: 1, minHeight: 0, display: 'flex', alignItems: 'flex-end', gap: 10}}
	>
		{Array.from({length: BAR_COUNT}, (_, index) => {
			const lit = index / BAR_COUNT <= progress;
			const wave = 0.3 + 0.7 * Math.abs(Math.sin(seconds * 1.5 + index * 0.55));
			return (
				<div
					key={index}
					style={{
						flex: 1,
						height: `${(wave * 100).toFixed(1)}%`,
						borderRadius: 8,
						background: lit ? withAlpha(color, 0.72) : withAlpha(colors.textPrimaryDark, 0.1),
						boxShadow: lit ? `0 0 22px ${withAlpha(colors.roseGoldGlow, 0.3)}` : 'none',
					}}
				/>
			);
		})}
	</div>
);

const TipCard: React.FC<{
	context: StageContext;
	text: string;
	index: number;
	at: number;
	end: number;
}> = ({context, text, index, at, end}) => {
	const {frame, fps, language, digits, layout, brandNames, media, highlightColor} = context;
	const plan = requireFit(planTipCard(text, brandNames, language, digits, layout, media.measure), 'A tip card');
	const enter = spring({frame: frame - at, fps, config: {damping: 14, stiffness: 180, mass: 0.75}});
	const exitFrames = Math.max(1, Math.round(EXIT_SECONDS * fps));
	const exit = interpolate(frame, [end - exitFrames, end], [0, 1], clamp);
	const progress = interpolate(frame, [at, end], [0, 1], clamp);
	const fromSide = language === 'ar' ? 1 : -1;
	const seconds = (frame - at) / fps;
	const float = Math.sin(seconds * 1.6) * 7;
	const scale = interpolate(enter, [0, 1], [0.88, 1]) * (1 + 0.03 * progress);
	const sheenAt = interpolate(frame, [at, end], [-40, 140], clamp);
	const dir = plan.language === 'ar' ? 'rtl' : 'ltr';
	const roomForBars =
		layout.stage.height - STEPPER_HEIGHT - STEPPER_GAP - 2 * CARD_PADDING - CARD_RING - 2 * CARD_GAP - plan.height;
	const lastWord = plan.tokens.length - 1;
	return (
		<div
			data-tip-card={index}
			dir={dir}
			style={{
				position: 'relative',
				flex: 1,
				minHeight: 0,
				boxSizing: 'border-box',
				overflow: 'hidden',
				padding: CARD_PADDING,
				display: 'flex',
				flexDirection: 'column',
				gap: CARD_GAP,
				borderRadius: 24,
				background: `linear-gradient(150deg, ${colors.primaryLightGradient} 0%, ${colors.primaryLight} 34%, ${colors.surfaceDark} 100%)`,
				border: `1px solid ${withAlpha(colors.roseGoldGlow, 0.32)}`,
				boxShadow: `0 30px 90px ${withAlpha(colors.canvasDarkBg, 0.55)}, 0 0 90px ${withAlpha(colors.accentRose, 0.35)}`,
				opacity: interpolate(enter, [0, 0.4], [0, 1], clamp) * (1 - exit),
				transform: `translateX(${interpolate(enter, [0, 1], [fromSide * 620, 0]) - fromSide * exit * 760}px) translateY(${float}px) rotate(${(1 - enter) * fromSide * 5 - exit * fromSide * 4}deg) scale(${scale})`,
			}}
		>
			<div
				aria-hidden="true"
				style={{
					position: 'absolute',
					top: -GHOST_SIZE * 0.2,
					insetInlineEnd: 6,
					fontFamily: fontStack,
					fontSize: GHOST_SIZE,
					fontWeight: 700,
					lineHeight: 1,
					color: withAlpha(colors.textPrimaryDark, 0.06),
					transform: `translateY(${(progress * 40).toFixed(2)}px) scale(${(1 + 0.08 * progress).toFixed(4)})`,
				}}
			>
				<Isolated text={String(index + 1)} language={language} digits={digits} />
			</div>
			<div
				aria-hidden="true"
				style={{
					position: 'absolute',
					inset: 0,
					background: `linear-gradient(115deg, ${withAlpha(colors.roseGoldGlow, 0)} ${sheenAt - 18}%, ${withAlpha(colors.roseGoldGlow, 0.13)} ${sheenAt}%, ${withAlpha(colors.roseGoldGlow, 0)} ${sheenAt + 18}%)`,
				}}
			/>
			<Ring size={CARD_RING} progress={progress} color={highlightColor}>
				<span
					style={{
						fontFamily: fontStack,
						fontSize: 66,
						fontWeight: 700,
						lineHeight: 1,
						color: colors.textPrimaryDark,
						transform: `scale(${interpolate(enter, [0, 1], [1.8, 1])})`,
					}}
				>
					<Isolated text={String(index + 1)} language={language} digits={digits} />
				</span>
			</Ring>
			<div style={{position: 'relative'}}>
				<FlowText
					name="tip-card"
					tokens={plan.tokens}
					plan={plan}
					language={plan.language}
					digits={digits}
					color={colors.textPrimaryDark}
					weight={700}
					wordStyle={(token, word) => {
						const pop = spring({
							frame: frame - at - 4 - word * WORD_STAGGER_FRAMES,
							fps,
							config: {damping: 13, stiffness: 260, mass: 0.5},
						});
						return {
							color: token.isBrand || word === lastWord ? highlightColor : colors.textPrimaryDark,
							opacity: interpolate(pop, [0, 0.4], [0, 1], clamp),
							transform: `translateY(${interpolate(pop, [0, 1], [34, 0])}px) scale(${interpolate(pop, [0, 1], [1.16, 1])})`,
						};
					}}
				/>
			</div>
			{roomForBars >= MIN_BARS_ROOM ? <Bars progress={progress} seconds={seconds} color={highlightColor} dir={dir} /> : null}
		</div>
	);
};

/** A budget split into its parts, as a picture of what the brand does. It holds no figures. */
const BudgetRing: React.FC<{size: number; progress: number; turn: number}> = ({size, progress, turn}) => {
	const thickness = size * 0.13;
	const radius = size / 2 - thickness / 2 - 2;
	const around = 2 * Math.PI * radius;
	const parts = [
		{share: 0.42, color: colors.roseGold},
		{share: 0.33, color: colors.emeraldSafe},
		{share: 0.25, color: colors.accentRose},
	];
	let start = 0;
	return (
		<svg
			data-budget-ring="true"
			width={size}
			height={size}
			viewBox={`0 0 ${size} ${size}`}
			aria-hidden="true"
			style={{flex: `0 0 ${size}px`, transform: `rotate(${turn}deg)`}}
		>
			<circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke={withAlpha(colors.textPrimaryDark, 0.1)} strokeWidth={thickness} />
			{parts.map((part) => {
				const from = start;
				start += part.share;
				const length = Math.max(0, part.share * progress - 0.012) * around;
				return (
					<circle
						key={part.color}
						cx={size / 2}
						cy={size / 2}
						r={radius}
						fill="none"
						stroke={part.color}
						strokeWidth={thickness}
						strokeDasharray={`${length} ${around}`}
						transform={`rotate(${from * progress * 360 - 90} ${size / 2} ${size / 2})`}
					/>
				);
			})}
		</svg>
	);
};

const Tick: React.FC<{amount: number}> = ({amount}) => (
	<svg
		width={ROW_TICK}
		height={ROW_TICK}
		viewBox="0 0 44 44"
		aria-hidden="true"
		style={{flex: `0 0 ${ROW_TICK}px`, transform: `scale(${amount})`}}
	>
		<circle cx={22} cy={22} r={20} fill={colors.emeraldSafe} />
		<path d="M12 23 L19 30 L32 15" fill="none" stroke={colors.canvasDarkBg} strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" />
	</svg>
);

const Recap: React.FC<{context: StageContext; cards: string[]; at: number}> = ({context, cards, at}) => {
	const {frame, fps, language, digits, layout, brandNames, brand, media} = context;
	const {stage} = layout;
	const plan = requireFit(planTipRecap(cards, brandNames, language, digits, layout, media.measure), 'The recap');
	const enter = spring({frame: frame - at, fps, config: {damping: 15, stiffness: 150, mass: 0.8}});
	const seconds = (frame - at) / fps;
	const ringSize = headerRingFor(layout);
	const logoSize = layout.narrow ? 56 : 92;
	const lockupWidth = stage.width - 2 * PANEL_PADDING - ringSize - HEADER_GAP;
	const sheenAt = ((seconds * 34) % 200) - 40;
	return (
		<div
			data-tip-recap="true"
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			style={{
				position: 'relative',
				flex: 1,
				minHeight: 0,
				boxSizing: 'border-box',
				overflow: 'hidden',
				padding: PANEL_PADDING,
				display: 'flex',
				flexDirection: 'column',
				gap: HEADER_GAP,
				borderRadius: 24,
				background: `linear-gradient(165deg, ${colors.primaryLight}, ${colors.surfaceDarkGradientStart} 40%, ${colors.surfaceDarkGradientEnd})`,
				border: `1px solid ${withAlpha(colors.roseGoldGlow, 0.35)}`,
				boxShadow: `0 0 110px ${withAlpha(colors.accentRose, 0.42)}`,
				opacity: interpolate(enter, [0, 0.4], [0, 1], clamp),
				transform: `translateY(${interpolate(enter, [0, 1], [200, 0])}px) scale(${interpolate(enter, [0, 1], [0.9, 1])})`,
			}}
		>
			<div
				aria-hidden="true"
				style={{
					position: 'absolute',
					inset: 0,
					background: `linear-gradient(115deg, ${withAlpha(colors.roseGoldGlow, 0)} ${sheenAt - 16}%, ${withAlpha(colors.roseGoldGlow, 0.1)} ${sheenAt}%, ${withAlpha(colors.roseGoldGlow, 0)} ${sheenAt + 16}%)`,
				}}
			/>
			<div style={{position: 'relative', display: 'flex', alignItems: 'center', gap: HEADER_GAP, height: ringSize}}>
				<BudgetRing size={ringSize} progress={interpolate(seconds, [0.1, 1.4], [0, 1], clamp)} turn={seconds * 14} />
				<BrandLockup
					brand={brand}
					language={language}
					media={media}
					logoSize={logoSize}
					nameSize={fitNameSize(brand, media.measure, lockupWidth - logoSize * 1.28, 54)}
					glow={0.5 + 0.5 * Math.sin(seconds * 3)}
					align="start"
					maxWidth={lockupWidth}
				/>
			</div>
			<div style={{position: 'relative', flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', justifyContent: 'space-evenly', gap: ROW_GAP}}>
				{cards.map((text, index) => {
					const row = plan.rows[index];
					const hit = spring({
						frame: frame - at - Math.round((0.35 + index * 0.3) * fps),
						fps,
						config: {damping: 12, stiffness: 220, mass: 0.6},
					});
					return row ? (
						<div
							key={`${index}-${text}`}
							data-tip-card={index}
							dir={row.language === 'ar' ? 'rtl' : 'ltr'}
							style={{
								display: 'flex',
								alignItems: 'center',
								gap: ROW_TICK_GAP,
								opacity: interpolate(hit, [0, 0.4], [0, 1], clamp),
								transform: `translateY(${interpolate(hit, [0, 1], [40, 0])}px)`,
							}}
						>
							<Tick amount={Math.max(0, hit)} />
							<FlowText
								name="recap-row"
								tokens={row.tokens}
								plan={row.plan}
								language={row.language}
								digits={digits}
								color={colors.textPrimaryDark}
								weight={600}
							/>
						</div>
					) : null;
				})}
			</div>
		</div>
	);
};

const TipStage: React.FC<{context: StageContext}> = ({context}) => {
	const {frame, fps, durationInFrames, layout, onScreenText, stageStartFrame, words, brandNames} = context;
	const cards = onScreenText.slice(0, CARD_COUNT);
	if (cards.length === 0 || frame < stageStartFrame) {
		return null;
	}
	const {cardAt, outroAt} = tipBeats({
		stageStartFrame,
		durationInFrames,
		fps,
		words,
		brandNames,
		cardCount: cards.length,
	});
	const {stage} = layout;
	let current = 0;
	cardAt.forEach((at, index) => {
		if (frame >= at) {
			current = index;
		}
	});
	const start = cardAt[current] ?? stageStartFrame;
	const end = cardAt[current + 1] ?? outroAt;
	const inOutro = frame >= outroAt;
	const position = inOutro ? cards.length : current + (frame - start) / Math.max(1, end - start);
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
				gap: STEPPER_GAP,
			}}
		>
			{inOutro ? (
				<Recap context={context} cards={cards} at={outroAt} />
			) : (
				<>
					<Stepper count={cards.length} position={position} context={context} />
					<TipCard context={context} text={cards[current] ?? ''} index={current} at={start} end={end} />
				</>
			)}
		</div>
	);
};

/**
 * Template B, Daily Money Hack: a punchy hook, three cards paced to the script, each with the stage
 * to itself, then a recap that shows how the brand helps. Needs no clip.
 */
export const DailyTip: TemplateDefinition = {
	tilt: {fromDeg: 12, toDeg: 4},
	zoom: {from: 1, to: 1.5},
	renderStage: (context) => <TipStage context={context} />,
};
