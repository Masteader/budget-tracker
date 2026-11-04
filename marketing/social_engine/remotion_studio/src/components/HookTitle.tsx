import React, {useMemo} from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {mergeBrandTokens} from '../lib/captionGrouping';
import {fontStack} from '../lib/fonts';
import type {ReelLayout} from '../lib/layout';
import {localizeDigits} from '../lib/text';
import {colors, withAlpha} from '../lib/tokens';
import type {Digits, Language} from '../props';
import {Isolated, WordRuns} from './Isolated';

const LINE_HEIGHT = 1.28;
const AVERAGE_CHAR_WIDTH = 0.52; // of the font size, for Cairo and Outfit at bold
const MOVE_SECONDS = 0.42;
const WORD_STAGGER_SECONDS = 0.08;
const FIRST_FRAME_HEAD_START = 2;
const MAX_COMPACT_SCALE = 0.5;

/** Bigger is better for a hook, until it would not fit the safe width. */
const fontSizeFor = (text: string): number => {
	const chars = text.length;
	if (chars <= 26) {
		return 128;
	}
	if (chars <= 44) {
		return 110;
	}
	if (chars <= 80) {
		return 88;
	}
	if (chars <= 130) {
		return 70;
	}
	return 58;
};

const estimatedHeight = (text: string, fontSize: number, width: number): number => {
	const perLine = Math.max(1, Math.floor(width / (fontSize * AVERAGE_CHAR_WIDTH)));
	return Math.ceil(text.length / perLine) * fontSize * LINE_HEIGHT;
};

const hookWordsOf = (text: string, brandNames: string[]) =>
	mergeBrandTokens(
		text
			.trim()
			.split(/\s+/)
			.map((word) => ({text: word, start_ms: 0, end_ms: 0})),
		brandNames,
	);

/** The frame the last word of the hook lands on, which the burst fires from. */
export const hookLandingFrame = (text: string, brandNames: string[], fps: number): number =>
	Math.round((hookWordsOf(text, brandNames).length - 1) * WORD_STAGGER_SECONDS * fps);

/**
 * The opening of the reel. Words slam in one at a time at full size, the last one gets a rose gold
 * pill swept behind it, and the whole block then rises into the top zone. Each word is one
 * inline-block and only transform and opacity animate, so Arabic letters keep their joins.
 */
export const HookTitle: React.FC<{
	text: string;
	brandNames: string[];
	language: Language;
	digits: Digits;
	highlightColor: string;
	layout: ReelLayout;
	heroEndFrame: number;
	frame: number;
	fps: number;
}> = ({text, brandNames, language, digits, highlightColor, layout, heroEndFrame, frame, fps}) => {
	const words = useMemo(() => hookWordsOf(text, brandNames), [text, brandNames]);
	const fontSize = fontSizeFor(text);
	const {top: topZone, content} = layout;
	const heroHeight = estimatedHeight(text, fontSize, content.width);
	// The block only scales down, so its lines stay broken as they are in the hero.
	const compactScale = Math.min(MAX_COMPACT_SCALE, (topZone.height - BADGE_ROOM) / Math.max(1, heroHeight));
	const compactTop = topZone.top + BADGE_ROOM;
	const heroTop = content.top + Math.max(0, (content.height - heroHeight) / 2);

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
	const landing = Math.round((words.length - 1) * WORD_STAGGER_SECONDS * fps);
	const punch = heroEndFrame > 0 ? hookPunch(frame, words.length, fps) : 0;
	const drift = interpolate(frame, [0, Math.max(1, heroEndFrame)], [1, 1.04], {
		extrapolateRight: 'clamp',
	});
	const scale = interpolate(moved, [0, 1], [drift, compactScale]) * (1 + punch);
	const translateY = interpolate(moved, [0, 1], [heroTop - compactTop, 0]);

	return (
		<div
			data-hook-title="true"
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			lang={language}
			style={{
				position: 'absolute',
				top: compactTop,
				left: content.left,
				width: content.width,
				display: 'flex',
				flexWrap: 'wrap',
				justifyContent: 'center',
				alignContent: 'flex-start',
				columnGap: fontSize * 0.28,
				rowGap: fontSize * 0.1,
				fontFamily: fontStack(language),
				fontWeight: 700,
				fontSize,
				lineHeight: LINE_HEIGHT,
				color: colors.textPrimaryDark,
				transformOrigin: 'center top',
				transform: `translateY(${translateY}px) scale(${scale})`,
			}}
		>
			<WordRuns
				items={words}
				textOf={(word) => word.text}
				language={language}
				gap={fontSize * 0.28}
				renderWord={(word, index) => {
					const isAccent = index === words.length - 1;
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
								padding: isAccent ? `0 ${fontSize * 0.16}px` : 0,
								color: sweep > 0.5 ? colors.canvasDarkBg : colors.textPrimaryDark,
								textShadow:
									sweep > 0.5
										? 'none'
										: `0 0 44px ${withAlpha(colors.roseGoldGlow, 0.5)}, 0 6px 26px ${withAlpha(colors.canvasDarkBg, 0.75)}`,
								opacity: interpolate(hit, [0, 0.3], [0, 1], {
									extrapolateLeft: 'clamp',
									extrapolateRight: 'clamp',
								}),
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
	);
};

const BADGE_ROOM = 76;
const PUNCH_DECAY_FRAMES = 3;

/** A small jolt of the whole block each time a word lands. */
const hookPunch = (frame: number, wordCount: number, fps: number): number => {
	const stagger = Math.max(1, Math.round(WORD_STAGGER_SECONDS * fps));
	const lastLanding = (wordCount - 1) * stagger;
	const landed = Math.min(lastLanding, Math.floor(frame / stagger) * stagger);
	const since = frame - landed;
	return 0.045 * Math.exp(-since / PUNCH_DECAY_FRAMES) * (frame <= lastLanding + 12 ? 1 : 0);
};
