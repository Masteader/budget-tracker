import React from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {BrandLockup, fitNameSize} from '../components/BrandLockup';
import {FlowText} from '../components/FlowText';
import {textTokens} from '../lib/captionGrouping';
import type {CaptionToken} from '../lib/captionGrouping';
import {fontStack} from '../lib/fonts';
import {fitFlow, requireFit} from '../lib/fit';
import type {FlowPlan, MeasureText} from '../lib/fit';
import type {ReelLayout, Rect} from '../lib/layout';
import {label} from '../lib/strings';
import {baseLanguage} from '../lib/text';
import {factRevealFrame} from '../lib/timeline';
import {colors, withAlpha} from '../lib/tokens';
import type {Digits, Language} from '../props';
import type {StageContext, TemplateDefinition} from './media';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

const CHIP_HEIGHT = 52;
const CHIP_GAP = 10;
const BLOCK_GAP = 18;
const MYTH_SHARE = 0.4;
const MYTH_SMALL_SHARE = 0.25;
const FACT_SHARE = 0.36;
const LOCKUP_HEIGHT = 76;
const PIECE_ROWS = 3;
const PIECE_COLUMNS = 2;
const PIECE_GAP = 10;
const REVEAL_SECONDS = 0.5;
const BRAND_AFTER_SECONDS = 2.2;
const STAMP_DELAY_SECONDS = 0.35;
const SETTLE_EPSILON = 0.005;
const SCAN_PER_SECOND = 1.1;

type Block = {tokens: CaptionToken[]; language: Language; plan: FlowPlan};

export type ComparisonPlan = {
	mythLarge: Block;
	mythSmall: Block;
	fact: Block;
	settledHeight: number;
	fits: boolean;
};

const block = (
	text: string,
	brandNames: string[],
	reelLanguage: Language,
	digits: Digits,
	measure: MeasureText,
	maxWidth: number,
	maxHeight: number,
	maxSize: number,
	minSize: number,
): Block => {
	const language = baseLanguage(text, reelLanguage);
	const tokens = textTokens(text, brandNames);
	return {
		tokens,
		language,
		plan: fitFlow({tokens, language, digits, measure, weight: 700, maxWidth, maxHeight, maxSize, minSize, lineHeight: 1.22}),
	};
};

export const planComparison = (
	[myth = '', fact = '']: string[],
	brandNames: string[],
	reelLanguage: Language,
	digits: Digits,
	layout: ReelLayout,
	measure: MeasureText,
): ComparisonPlan => {
	const {stage} = layout;
	const at = (text: string, share: number, chip: number, maxSize: number, minSize: number) =>
		block(text, brandNames, reelLanguage, digits, measure, stage.width, stage.height * share - chip, maxSize, minSize);
	const mythLarge = at(myth, MYTH_SHARE, CHIP_HEIGHT + CHIP_GAP, 84, 22);
	const mythSmall = at(myth, MYTH_SMALL_SHARE, CHIP_HEIGHT + CHIP_GAP, 44, 16);
	const factBlock = at(fact, FACT_SHARE, CHIP_HEIGHT + CHIP_GAP, 76, 20);
	const settledHeight =
		2 * (CHIP_HEIGHT + CHIP_GAP) + mythSmall.plan.height + factBlock.plan.height + 2 * BLOCK_GAP;
	return {
		mythLarge,
		mythSmall,
		fact: factBlock,
		settledHeight,
		fits: mythLarge.plan.fits && mythSmall.plan.fits && factBlock.plan.fits && settledHeight <= stage.height,
	};
};

const Chip: React.FC<{text: string; color: string; kind: 'cross' | 'check'; language: Language}> = ({text, color, kind, language}) => (
	<div
		data-myth-card={kind}
		dir={language === 'ar' ? 'rtl' : 'ltr'}
		style={{
			display: 'inline-flex',
			alignItems: 'center',
			alignSelf: 'flex-start',
			gap: 10,
			height: CHIP_HEIGHT,
			boxSizing: 'border-box',
			padding: '0 20px 0 12px',
			paddingInlineStart: 12,
			paddingInlineEnd: 20,
			borderRadius: 18,
			fontFamily: fontStack,
			fontSize: 30,
			fontWeight: 700,
			whiteSpace: 'nowrap',
			color: colors.canvasDarkBg,
			background: color,
			boxShadow: `0 0 34px ${withAlpha(color, 0.5)}`,
		}}
	>
		<Symbol kind={kind} size={32} color={colors.canvasDarkBg} />
		<span>{text}</span>
	</div>
);

const Symbol: React.FC<{kind: 'cross' | 'check'; size: number; color: string}> = ({kind, size, color}) => (
	<svg width={size} height={size} viewBox="0 0 54 54" aria-hidden="true">
		<circle cx={27} cy={27} r={23} fill="none" stroke={color} strokeWidth={5} />
		{kind === 'cross' ? (
			<path d="M18 18 L36 36 M36 18 L18 36" stroke={color} strokeWidth={7} strokeLinecap="round" />
		) : (
			<path d="M15 28 L24 37 L39 19" fill="none" stroke={color} strokeWidth={7} strokeLinecap="round" strokeLinejoin="round" />
		)}
	</svg>
);

/** Where each scrap lies in the mess, as shares of the room it has. */
const SCATTER = [
	{x: 0.02, y: 0.03, rotate: -13, width: 0.4, height: 0.34, phase: 0.4},
	{x: 0.5, y: 0.0, rotate: 9, width: 0.42, height: 0.3, phase: 1.7},
	{x: 0.2, y: 0.33, rotate: -6, width: 0.46, height: 0.33, phase: 2.9},
	{x: 0.62, y: 0.38, rotate: 15, width: 0.36, height: 0.34, phase: 4.1},
	{x: 0.0, y: 0.66, rotate: 8, width: 0.38, height: 0.32, phase: 5.2},
	{x: 0.46, y: 0.7, rotate: -11, width: 0.46, height: 0.29, phase: 0.9},
];

const lerp = (from: number, to: number, amount: number): number => from + (to - from) * amount;
const settled = (value: number): number => (Math.abs(value) < SETTLE_EPSILON ? 0 : value);

/** One scrap of a note in the mess, and one tidy row of a budget after the reveal. */
const Piece: React.FC<{
	index: number;
	context: StageContext;
	field: Rect;
	panel: Rect;
	revealAt: number;
}> = ({index, context, field, panel, revealAt}) => {
	const {frame, fps, highlightColor} = context;
	const scatter = SCATTER[index % SCATTER.length] ?? {x: 0, y: 0, rotate: 0, width: 0.3, height: 0.3, phase: 0};
	const seconds = frame / fps;
	const landed = spring({
		frame: frame - (context.stageStartFrame + index * 2),
		fps,
		config: {damping: 11, stiffness: 180, mass: 0.6},
	});
	const tidy = frame < revealAt ? 0 : spring({frame: frame - revealAt - index * 2, fps, config: {damping: 15, stiffness: 150, mass: 0.7}});
	const columnWidth = (panel.width - PIECE_GAP * (PIECE_COLUMNS - 1)) / PIECE_COLUMNS;
	const rowHeight = (panel.height - PIECE_GAP * (PIECE_ROWS - 1)) / PIECE_ROWS;
	const column = index % PIECE_COLUMNS;
	const row = Math.floor(index / PIECE_COLUMNS);
	const orderedColumn = context.language === 'ar' ? PIECE_COLUMNS - 1 - column : column;
	const jitter = (1 - tidy) * 7;
	const fromX = field.left + scatter.x * field.width + Math.sin(seconds * 2.7 + scatter.phase) * jitter;
	const fromY = field.top + scatter.y * field.height + Math.cos(seconds * 2.1 + scatter.phase) * jitter + (1 - landed) * -120;
	const toX = panel.left + orderedColumn * (columnWidth + PIECE_GAP);
	const toY = panel.top + row * (rowHeight + PIECE_GAP);
	const rotate = settled(
		lerp(scatter.rotate * landed + Math.sin(seconds * 1.9 + scatter.phase) * 3, 0, tidy),
	);
	const width = lerp(scatter.width * field.width, columnWidth, tidy);
	const height = lerp(scatter.height * field.height, rowHeight, tidy);
	const tickPop = frame < revealAt ? 0 : spring({frame: frame - revealAt - Math.round((0.45 + index * 0.14) * fps), fps, config: {damping: 11, stiffness: 240, mass: 0.5}});
	const breathe = 0.78 + 0.16 * Math.sin(seconds * 1.7 + index * 1.1);
	const barLength = lerp(0, breathe, interpolate(frame, [revealAt + 0.3 * fps, revealAt + 1.1 * fps], [0, 1], clamp));
	// Once in order, one row after another lights up, so the panel keeps its life.
	const scanAt = ((seconds * SCAN_PER_SECOND) % SCATTER.length + SCATTER.length) % SCATTER.length;
	const scanGap = Math.min(Math.abs(scanAt - index), SCATTER.length - Math.abs(scanAt - index));
	const scan = tidy * tickPop * Math.max(0, 1 - scanGap);
	return (
		<div
			data-note-piece={index}
			style={{
				position: 'absolute',
				left: 0,
				top: 0,
				width,
				height,
				boxSizing: 'border-box',
				overflow: 'hidden',
				borderRadius: lerp(10, 16, tidy),
				opacity: interpolate(landed, [0, 0.3], [0, 1], clamp),
				border: `2px solid ${withAlpha(tidy > 0.5 ? colors.emeraldSafe : colors.coralDanger, 0.45 + 0.5 * scan)}`,
				background: tidy > 0.5 ? colors.surfaceDark : `linear-gradient(160deg, ${colors.primaryLight}, ${colors.surfaceDark})`,
				boxShadow: `0 14px 40px ${withAlpha(colors.canvasDarkBg, 0.55)}, 0 0 ${(44 * scan).toFixed(1)}px ${withAlpha(colors.emeraldSafe, 0.55 * scan)}`,
				transform: `translate(${lerp(fromX, toX, tidy).toFixed(2)}px, ${lerp(fromY, toY, tidy).toFixed(2)}px) rotate(${rotate.toFixed(2)}deg)`,
			}}
		>
			<svg width="100%" height="100%" viewBox="0 0 200 110" preserveAspectRatio="none" aria-hidden="true" style={{position: 'absolute', inset: 0, opacity: 1 - tidy}}>
				<path d={`M14 ${28 + index * 2} C 50 ${10 + index}, 80 ${48 - index}, 120 ${24 + index} S 170 ${40 - index}, 186 ${22 + index}`} fill="none" stroke={withAlpha(colors.textSecondaryDark, 0.75)} strokeWidth={5} strokeLinecap="round" />
				<path d={`M18 ${64 - index} C 60 ${84 - index}, 90 ${44 + index}, 130 ${70 - index} S 160 ${84 - index}, 176 ${62 + index}`} fill="none" stroke={withAlpha(colors.textSecondaryDark, 0.5)} strokeWidth={5} strokeLinecap="round" />
				<path d={`M26 ${94 - index} C 60 ${86 + index}, 96 ${102 - index}, 128 ${90 + index}`} fill="none" stroke={withAlpha(colors.coralDanger, 0.7)} strokeWidth={5} strokeLinecap="round" />
			</svg>
			<div
				dir={context.language === 'ar' ? 'rtl' : 'ltr'}
				style={{
					position: 'absolute',
					inset: 0,
					display: 'flex',
					alignItems: 'center',
					gap: 12,
					padding: '0 14px',
					opacity: interpolate(tidy, [0.5, 1], [0, 1], clamp),
				}}
			>
				{tickPop > 0.01 ? (
					<span data-fact-tick="true" style={{display: 'flex', transform: `scale(${tickPop})`}}>
						<Symbol kind="check" size={Math.min(34, rowHeight - 8)} color={colors.emeraldSafe} />
					</span>
				) : null}
				<div style={{flex: 1, height: Math.max(6, rowHeight * 0.2), borderRadius: 6, overflow: 'hidden', background: withAlpha(colors.textPrimaryDark, 0.1)}}>
					<div
						style={{
							width: '100%',
							height: '100%',
							borderRadius: 6,
							background: index % 3 === 2 ? highlightColor : colors.emeraldSafe,
							transformOrigin: context.language === 'ar' ? 'right center' : 'left center',
							transform: `scaleX(${barLength.toFixed(3)})`,
						}}
					/>
				</div>
			</div>
		</div>
	);
};

const Scribble: React.FC<{field: Rect; frame: number; fps: number; startAt: number; opacity: number}> = ({field, frame, fps, startAt, opacity}) => {
	const drawn = interpolate(frame, [startAt, startAt + 1.2 * fps], [0, 1], clamp);
	const turn = Math.sin((frame / fps) * 1.2) * 4;
	return (
		<svg
			width={field.width}
			height={field.height}
			viewBox="0 0 400 300"
			preserveAspectRatio="none"
			aria-hidden="true"
			style={{position: 'absolute', left: field.left, top: field.top, opacity, transform: `rotate(${turn}deg)`}}
		>
			<path
				d="M20 150 C 60 20, 150 280, 200 120 S 320 30, 300 170 S 120 290, 150 140 S 330 90, 380 200 S 240 280, 90 230 S 30 60, 190 60"
				fill="none"
				stroke={withAlpha(colors.coralDanger, 0.55)}
				strokeWidth={5}
				strokeLinecap="round"
				pathLength={1}
				strokeDasharray={`${drawn} 1`}
			/>
		</svg>
	);
};

const Comparison: React.FC<{context: StageContext}> = ({context}) => {
	const {frame, fps, durationInFrames, language, digits, layout, onScreenText, stageStartFrame, brandNames, brand, media} = context;
	if (frame < stageStartFrame) {
		return null;
	}
	const {stage} = layout;
	const plan = requireFit(planComparison(onScreenText, brandNames, language, digits, layout, media.measure), 'The comparison');
	const revealAt = factRevealFrame(stageStartFrame, durationInFrames, fps);
	const config = {damping: 12, stiffness: 200, mass: 0.7};
	const mythHit = spring({frame: frame - stageStartFrame, fps, config});
	const factHit = frame < revealAt ? 0 : spring({frame: frame - revealAt, fps, config});
	const revealFrames = Math.max(1, Math.round(REVEAL_SECONDS * fps));
	const wipe = interpolate(frame, [revealAt - 2, revealAt + revealFrames], [0, 1], clamp);
	const wiping = wipe > 0 && wipe < 1;
	const seconds = frame / fps;
	const after = frame >= revealAt;

	const mythLargeHeight = CHIP_HEIGHT + CHIP_GAP + plan.mythLarge.plan.height;
	const field: Rect = {
		top: stage.top + mythLargeHeight + BLOCK_GAP,
		left: stage.left,
		width: stage.width,
		height: Math.max(120, stage.height - mythLargeHeight - BLOCK_GAP),
	};
	const textBottom = stage.top + plan.settledHeight;
	const brandAt = revealAt + Math.round(BRAND_AFTER_SECONDS * fps);
	const panelTop = textBottom + BLOCK_GAP;
	const panelBottom = stage.top + stage.height - LOCKUP_HEIGHT - PIECE_GAP;
	const panel: Rect = {
		top: panelTop,
		left: stage.left,
		width: stage.width,
		height: Math.max(84, panelBottom - panelTop),
	};
	const stampHit = spring({
		frame: frame - stageStartFrame - Math.round(STAMP_DELAY_SECONDS * fps),
		fps,
		config: {damping: 9, stiffness: 260, mass: 0.6},
	});
	const strike = interpolate(frame, [revealAt + 0.15 * fps, revealAt + 0.55 * fps], [0, 1], clamp);
	const brandHit = frame < brandAt ? 0 : spring({frame: frame - brandAt, fps, config: {damping: 13, stiffness: 180, mass: 0.7}});
	const sway = 1 + 0.012 * Math.sin(seconds * 1.4);
	const mythChip = <Chip text={label('stopDoingThis', language)} color={colors.coralDanger} kind="cross" language={language} />;
	const dir = language === 'ar' ? 'rtl' : 'ltr';
	return (
		<div style={{position: 'absolute', inset: 0}}>
			<div
				aria-hidden="true"
				data-myth-mood={after ? 'fact' : 'myth'}
				style={{
					position: 'absolute',
					inset: 0,
					background: after
						? `radial-gradient(ellipse at 50% 62%, ${withAlpha(colors.emeraldSafe, 0.2 + 0.05 * Math.sin(seconds * 2))} 0%, ${withAlpha(colors.emeraldSafe, 0)} 62%)`
						: `radial-gradient(ellipse at 50% 62%, ${withAlpha(colors.coralDanger, 0.26 + 0.07 * Math.sin(seconds * 5))} 0%, ${withAlpha(colors.coralDanger, 0)} 66%)`,
				}}
			/>
			{after ? null : <Scribble field={field} frame={frame} fps={fps} startAt={stageStartFrame} opacity={1} />}
			{SCATTER.map((_, index) => (
				<Piece key={index} index={index} context={context} field={field} panel={panel} revealAt={revealAt} />
			))}
			{after ? null : (
				<div
					data-myth-stamp="true"
					aria-hidden="true"
					style={{
						position: 'absolute',
						left: field.left + field.width / 2 - 130,
						top: field.top + field.height / 2 - 130,
						opacity: interpolate(stampHit, [0, 0.3], [0, 1], clamp),
						transform: `rotate(-12deg) scale(${interpolate(stampHit, [0, 1], [3, 1]) * (1 + 0.03 * Math.sin(seconds * 6))})`,
						filter: `drop-shadow(0 0 40px ${withAlpha(colors.coralDanger, 0.8)})`,
					}}
				>
					<Symbol kind="cross" size={260} color={colors.coralDanger} />
				</div>
			)}
			{after ? null : (
				<div
					dir={dir}
					style={{
						position: 'absolute',
						top: stage.top,
						left: stage.left,
						width: stage.width,
						display: 'flex',
						flexDirection: 'column',
						gap: CHIP_GAP,
						opacity: interpolate(mythHit, [0, 0.4], [0, 1], clamp),
						transform: `translateY(${interpolate(mythHit, [0, 1], [-90, 0])}px) scale(${interpolate(mythHit, [0, 1], [1.14, 1]) * sway})`,
						transformOrigin: 'center top',
					}}
				>
					{mythChip}
					<FlowText
						name="myth"
						tokens={plan.mythLarge.tokens}
						plan={plan.mythLarge.plan}
						language={plan.mythLarge.language}
						digits={digits}
						color={colors.textPrimaryDark}
						weight={700}
					/>
				</div>
			)}
			{after ? (
				<div
					dir={dir}
					style={{
						position: 'absolute',
						top: stage.top,
						left: stage.left,
						width: stage.width,
						display: 'flex',
						flexDirection: 'column',
						gap: BLOCK_GAP,
					}}
				>
					<div style={{display: 'flex', flexDirection: 'column', gap: CHIP_GAP, opacity: 0.72}}>
						{mythChip}
						<div style={{position: 'relative', alignSelf: 'flex-start'}}>
							<FlowText
								name="myth-small"
								tokens={plan.mythSmall.tokens}
								plan={plan.mythSmall.plan}
								language={plan.mythSmall.language}
								digits={digits}
								color={colors.textSecondaryDark}
								weight={700}
							/>
							<div
								data-myth-strike="true"
								aria-hidden="true"
								style={{
									position: 'absolute',
									left: 0,
									right: 0,
									top: plan.mythSmall.plan.fontSize * 0.64,
									height: Math.max(4, plan.mythSmall.plan.fontSize * 0.09),
									borderRadius: 4,
									background: colors.coralDanger,
									transformOrigin: language === 'ar' ? 'right center' : 'left center',
									transform: `scaleX(${strike})`,
								}}
							/>
						</div>
					</div>
					<div
						style={{
							display: 'flex',
							flexDirection: 'column',
							gap: CHIP_GAP,
							opacity: interpolate(factHit, [0, 0.35], [0, 1], clamp),
							transformOrigin: language === 'ar' ? 'right top' : 'left top',
							transform: `translateY(${interpolate(factHit, [0, 1], [70, 0])}px) scale(${interpolate(factHit, [0, 1], [1.22, 1]) * sway})`,
						}}
					>
						<Chip text={label('theSmartWay', language)} color={colors.emeraldSafe} kind="check" language={language} />
						<FlowText
							name="fact"
							tokens={plan.fact.tokens}
							plan={plan.fact.plan}
							language={plan.fact.language}
							digits={digits}
							color={colors.textPrimaryDark}
							weight={700}
						/>
					</div>
				</div>
			) : null}
			{brandHit > 0.001 ? (
				<div
					style={{
						position: 'absolute',
						top: stage.top + stage.height - LOCKUP_HEIGHT,
						left: stage.left,
						width: stage.width,
						height: LOCKUP_HEIGHT,
						display: 'flex',
						alignItems: 'center',
						justifyContent: 'center',
						opacity: interpolate(brandHit, [0, 0.4], [0, 1], clamp),
						transform: `translateY(${interpolate(brandHit, [0, 1], [40, 0])}px)`,
					}}
				>
					<BrandLockup
						brand={brand}
						language={language}
						media={media}
						logoSize={64}
						nameSize={fitNameSize(brand, media.measure, stage.width - 82, 38)}
						glow={0.5 + 0.5 * Math.sin(seconds * 3)}
						maxWidth={stage.width}
					/>
				</div>
			) : null}
			{wiping ? (
				<div
					aria-hidden="true"
					style={{
						position: 'absolute',
						inset: 0,
						background: `linear-gradient(115deg, ${withAlpha(colors.emeraldSafe, 0)} ${wipe * 150 - 40}%, ${withAlpha(colors.emeraldSafe, 0.85)} ${wipe * 150 - 16}%, ${withAlpha(colors.textPrimaryDark, 0.85)} ${wipe * 150 - 12}%, ${withAlpha(colors.emeraldSafe, 0.85)} ${wipe * 150 - 8}%, ${withAlpha(colors.emeraldSafe, 0)} ${wipe * 150}%)`,
					}}
				/>
			) : null}
		</div>
	);
};

/**
 * Template C, Stop Doing This vs. The Smart Way: scraps of notes and a tangle of memory, stamped
 * wrong, then a wipe that snaps the same scraps into a clear budget. Needs no clip.
 */
export const MythVsFact: TemplateDefinition = {
	tilt: {fromDeg: 12, toDeg: 4},
	zoom: {from: 1, to: 1.5},
	renderStage: (context) => <Comparison context={context} />,
};
