import React from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {textTokens} from '../lib/captionGrouping';
import type {CaptionToken} from '../lib/captionGrouping';
import {fontStack} from '../lib/fonts';
import {fitFlow, requireFit} from '../lib/fit';
import type {FlowPlan, MeasureText} from '../lib/fit';
import type {ReelLayout} from '../lib/layout';
import {baseLanguage, localizeDigits} from '../lib/text';
import {colors, withAlpha} from '../lib/tokens';
import type {Digits, Language} from '../props';
import {FlowText} from './FlowText';
import {Isolated, WordRuns} from './Isolated';

const LINE_HEIGHT = 1.22;
const WORD_GAP = 0.28;
const ROW_GAP = 0.1;
const ACCENT_PADDING = 0.16;
const HERO_MAX_SIZE = 132;
const HERO_MIN_SIZE = 22;
const COMPACT_MAX_SIZE = 72;
const COMPACT_MIN_SIZE = 36;
const AREA_GAP = 14;
const MOVE_SECONDS = 0.42;
const WORD_STAGGER_SECONDS = 0.08;
const FIRST_FRAME_HEAD_START = 2;
const PUNCH_DECAY_FRAMES = 3;

/** Room for the badge above the hook. */
const BADGE_ROOM = 52;

export type HookPlan = {
	tokens: CaptionToken[];
	language: Language;
	hero: FlowPlan;
	heroTop: number;
	/** Null when the hook would be too small to read in the top zone, so it leaves the screen. */
	compact: FlowPlan | null;
	compactTop: number;
};

/** Bigger is better for a hook, up to what its words, measured, leave room for. */
export const planHook = (
	text: string,
	brandNames: string[],
	reelLanguage: Language,
	digits: Digits,
	layout: ReelLayout,
	measure: MeasureText,
): HookPlan => {
	const tokens = textTokens(text, brandNames);
	const language = baseLanguage(text, reelLanguage);
	const {content, top, captions} = layout;
	const shared = {
		tokens,
		language,
		digits,
		measure,
		weight: 700,
		maxWidth: content.width,
		lineHeight: LINE_HEIGHT,
		wordGap: WORD_GAP,
		rowGap: ROW_GAP,
		extraEm: (index: number) => (index === tokens.length - 1 ? ACCENT_PADDING * 2 : 0),
	};
	const areaTop = top.top + BADGE_ROOM;
	const areaHeight = captions.top - AREA_GAP - areaTop;
	const hero = requireFit(
		fitFlow({...shared, maxHeight: areaHeight, maxSize: HERO_MAX_SIZE, minSize: HERO_MIN_SIZE}),
		'The hook',
	);
	const compact = fitFlow({
		...shared,
		maxHeight: top.height - BADGE_ROOM,
		maxSize: COMPACT_MAX_SIZE,
		minSize: COMPACT_MIN_SIZE,
	});
	return {
		tokens,
		language,
		hero,
		heroTop: areaTop + (areaHeight - hero.height) / 2,
		compact: compact.fits ? compact : null,
		compactTop: top.top + BADGE_ROOM,
	};
};

/** The frame the last word of the hook lands on, which the burst fires from. */
export const hookLandingFrame = (wordCount: number, fps: number): number =>
	Math.round((wordCount - 1) * WORD_STAGGER_SECONDS * fps);

/** A small jolt of the whole block each time a word lands. */
const hookPunch = (frame: number, wordCount: number, fps: number): number => {
	const stagger = Math.max(1, Math.round(WORD_STAGGER_SECONDS * fps));
	const lastLanding = (wordCount - 1) * stagger;
	const landed = Math.min(lastLanding, Math.floor(frame / stagger) * stagger);
	const since = frame - landed;
	return 0.045 * Math.exp(-since / PUNCH_DECAY_FRAMES) * (frame <= lastLanding + 12 ? 1 : 0);
};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/**
 * The opening of the reel. Words slam in one at a time at full size, the last one gets a rose gold
 * pill swept behind it, and the block then rises and hands over to a headline set for the top zone.
 * Each word is one inline-block and only transform and opacity animate, so Arabic letters keep
 * their joins.
 */
export const HookTitle: React.FC<{
	plan: HookPlan;
	digits: Digits;
	highlightColor: string;
	layout: ReelLayout;
	heroEndFrame: number;
	frame: number;
	fps: number;
}> = ({plan, digits, highlightColor, layout, heroEndFrame, frame, fps}) => {
	const {tokens, language, hero, heroTop, compact, compactTop} = plan;
	const {content, top: topZone} = layout;
	const moveFrames = Math.max(1, Math.round(MOVE_SECONDS * fps));
	const moveStart = heroEndFrame - moveFrames;
	const moved =
		heroEndFrame <= 0
			? 1
			: spring({
					frame: frame - moveStart,
					fps,
					config: {damping: 18, stiffness: 150, mass: 0.8},
					durationInFrames: moveFrames,
				});
	const landing = hookLandingFrame(tokens.length, fps);
	const punch = heroEndFrame > 0 ? hookPunch(frame, tokens.length, fps) : 0;
	const drift = interpolate(frame, [0, Math.max(1, heroEndFrame)], [1, 1.04], {extrapolateRight: 'clamp'});
	const heroCenter = heroTop + hero.height / 2;
	const compactCenter = topZone.top + topZone.height / 2;
	const heroOpacity = interpolate(moved, [0.3, 0.75], [1, 0], clamp);
	const showHero = heroEndFrame > 0 && heroOpacity > 0.001;
	const compactOpacity = interpolate(moved, [0.45, 0.95], [0, 1], clamp);
	const dir = language === 'ar' ? 'rtl' : 'ltr';
	return (
		<>
			{showHero ? (
				<div
					data-hook-title="true"
					data-fit-box="hook"
					data-fit-max-width={content.width}
					data-fit-max-height={hero.maxHeight}
					dir={dir}
					lang={language}
					style={{
						position: 'absolute',
						top: heroTop,
						left: content.left,
						width: content.width,
						display: 'flex',
						flexWrap: 'wrap',
						justifyContent: 'center',
						alignContent: 'flex-start',
						columnGap: hero.fontSize * WORD_GAP,
						rowGap: hero.fontSize * ROW_GAP,
						fontFamily: fontStack,
						fontWeight: 700,
						fontSize: hero.fontSize,
						lineHeight: LINE_HEIGHT,
						color: colors.textPrimaryDark,
						transformOrigin: 'center center',
						opacity: heroOpacity,
						transform: `translateY(${interpolate(moved, [0, 1], [0, compactCenter - heroCenter])}px) scale(${interpolate(moved, [0, 1], [drift, 0.45]) * (1 + punch)})`,
					}}
				>
					<WordRuns
						items={tokens}
						textOf={(word) => word.text}
						language={language}
						gap={hero.fontSize * WORD_GAP}
						renderWord={(word, index) => {
							const isAccent = index === tokens.length - 1;
							const delay = Math.round(index * WORD_STAGGER_SECONDS * fps);
							const hit = spring({
								frame: frame - delay + FIRST_FRAME_HEAD_START,
								fps,
								config: {damping: 11, stiffness: 240, mass: 0.6},
							});
							const shown = localizeDigits(word.text, digits);
							const sweep = isAccent
								? spring({
										frame: frame - landing - Math.round(0.1 * fps),
										fps,
										config: {damping: 18, stiffness: 200, mass: 0.6},
									})
								: 0;
							return (
								<span
									key={`${index}-${word.text}`}
									data-hook-word={shown}
									data-hook-accent={isAccent ? shown : undefined}
									style={{
										position: 'relative',
										display: 'inline-block',
										whiteSpace: 'nowrap',
										isolation: 'isolate',
										padding: isAccent ? `0 ${hero.fontSize * ACCENT_PADDING}px` : 0,
										color: sweep > 0.5 ? colors.canvasDarkBg : colors.textPrimaryDark,
										textShadow:
											sweep > 0.5
												? 'none'
												: `0 0 44px ${withAlpha(colors.roseGoldGlow, 0.5)}, 0 6px 26px ${withAlpha(colors.canvasDarkBg, 0.75)}`,
										opacity: interpolate(hit, [0, 0.3], [0, 1], clamp),
										transform: `translateY(${interpolate(hit, [0, 1], [70, 0])}px) scale(${interpolate(hit, [0, 1], [1.8, 1])})`,
									}}
								>
									{isAccent ? (
										<span
											data-accent-pill="true"
											aria-hidden="true"
											style={{
												position: 'absolute',
												inset: 0,
												zIndex: -1,
												borderRadius: 24,
												background: highlightColor,
												boxShadow: `0 0 60px ${withAlpha(colors.roseGoldGlow, 0.6)}`,
												transformOrigin: language === 'ar' ? 'right center' : 'left center',
												transform: `scaleX(${Math.max(0, sweep)})`,
											}}
										/>
									) : null}
									<Isolated text={word.text} language={language} digits={digits} />
								</span>
							);
						}}
					/>
				</div>
			) : null}
			{compact && compactOpacity > 0.001 ? (
				<div
					data-hook-compact="true"
					style={{
						position: 'absolute',
						top: compactTop,
						left: content.left,
						width: content.width,
						display: 'flex',
						justifyContent: 'center',
						opacity: compactOpacity,
						transformOrigin: 'center top',
						transform: `translateY(${interpolate(moved, [0.45, 1], [34, 0], clamp)}px) scale(${interpolate(moved, [0.45, 1], [1.16, 1], clamp)})`,
					}}
				>
					<FlowText
						name="hook-compact"
						tokens={tokens}
						plan={compact}
						language={language}
						digits={digits}
						color={colors.textPrimaryDark}
						weight={700}
						align="center"
						wordStyle={(_word, index) =>
							index === tokens.length - 1
								? {
										padding: `0 ${compact.fontSize * ACCENT_PADDING}px`,
										borderRadius: 14,
										background: highlightColor,
										color: colors.canvasDarkBg,
										boxShadow: `0 0 34px ${withAlpha(colors.roseGoldGlow, 0.45)}`,
									}
								: {textShadow: `0 2px 18px ${withAlpha(colors.canvasDarkBg, 0.8)}`}
						}
					/>
				</div>
			) : null}
		</>
	);
};
