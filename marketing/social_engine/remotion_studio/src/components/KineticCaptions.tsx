import React, {useMemo} from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {
	activeTokenIndex,
	groupIntoPages,
	mergeBrandTokens,
	pageAt,
	textTokens,
} from '../lib/captionGrouping';
import type {CaptionToken} from '../lib/captionGrouping';
import {fontStack} from '../lib/fonts';
import {fitFlow, requireFit} from '../lib/fit';
import type {FlowPlan, MeasureText} from '../lib/fit';
import type {ReelLayout} from '../lib/layout';
import {localizeDigits} from '../lib/text';
import {colors, withAlpha} from '../lib/tokens';
import type {CaptionWord, Digits, Language} from '../props';
import {FlowText} from './FlowText';
import {Isolated, WordRuns} from './Isolated';

const MAX_FONT_SIZE = 62;
const MIN_FONT_SIZE = 18;
const LINE_HEIGHT = 1.24;
const WORD_GAP = 0.32;
const PANEL_PADDING_X = 26;
const PANEL_PADDING_Y = 8;
const ACTIVE_SCALE = 0.05;
const ENGLISH_GAP = 8;
const ENGLISH_ONE_LINE = 44;
const ENGLISH_TWO_LINES = 72;
const ENGLISH_MAX_SIZE = 32;
const ENGLISH_MIN_SIZE = 20;

const englishRoom = (layout: ReelLayout): number => (layout.narrow ? ENGLISH_TWO_LINES : ENGLISH_ONE_LINE);

/** A caption page, measured, so a long word or a full page still fits the panel. */
export const planCaptions = (
	tokens: CaptionToken[],
	language: Language,
	digits: Digits,
	layout: ReelLayout,
	measure: MeasureText,
	withEnglish: boolean,
): FlowPlan => {
	const room = layout.captions.height - (withEnglish ? englishRoom(layout) + ENGLISH_GAP : 0);
	return fitFlow({
		tokens,
		language,
		digits,
		measure,
		weight: 700,
		maxWidth: layout.captions.width - 2 * PANEL_PADDING_X,
		maxHeight: room - 2 * PANEL_PADDING_Y,
		maxSize: MAX_FONT_SIZE,
		minSize: MIN_FONT_SIZE,
		lineHeight: LINE_HEIGHT,
		wordGap: WORD_GAP,
	});
};

/** The English line under Arabic captions. It keeps to its room, and the name stays whole. */
export const EnglishLine: React.FC<{
	line: string;
	brandNames: string[];
	digits: Digits;
	layout: ReelLayout;
	measure: MeasureText;
}> = ({line, brandNames, digits, layout, measure}) => {
	const tokens = textTokens(line, brandNames);
	const plan = requireFit(
		fitFlow({
			tokens,
			language: 'en',
			digits,
			measure,
			weight: 500,
			maxWidth: layout.captions.width,
			maxHeight: englishRoom(layout),
			maxSize: ENGLISH_MAX_SIZE,
			minSize: ENGLISH_MIN_SIZE,
			lineHeight: 1.25,
		}),
		'The English line',
	);
	return (
		<div data-english-line="true" style={{textShadow: `0 2px 10px ${colors.canvasDarkBg}`}}>
			<FlowText
				name="english-line"
				tokens={tokens}
				plan={plan}
				language="en"
				digits={digits}
				color={colors.textSecondaryDark}
				weight={500}
				align="center"
			/>
		</div>
	);
};

type Props = {
	words: CaptionWord[];
	brandNames: string[];
	language: Language;
	digits: Digits;
	highlightColor: string;
	layout: ReelLayout;
	measure: MeasureText;
	withEnglish: boolean;
	frame: number;
	fps: number;
};

/**
 * Word-by-word captions. One word is one inline-block, the browser's rtl flex row does the
 * mirroring, and only transform, opacity, colour and glow change, so no word ever re-shapes
 * (spec Section 8.4).
 */
export const KineticCaptions: React.FC<Props> = ({
	words,
	brandNames,
	language,
	digits,
	highlightColor,
	layout,
	measure,
	withEnglish,
	frame,
	fps,
}) => {
	const pages = useMemo(
		() => groupIntoPages(mergeBrandTokens(words, brandNames)),
		[words, brandNames],
	);
	const ms = (frame * 1000) / fps;
	const page = pageAt(pages, ms);
	if (!page) {
		return null;
	}
	const plan = requireFit(planCaptions(page.tokens, language, digits, layout, measure, withEnglish), 'A caption page');
	const pageFrame = Math.max(0, frame - Math.floor((page.startMs * fps) / 1000));
	const entry = spring({frame: pageFrame + 1, fps, config: {damping: 16, stiffness: 240, mass: 0.6}});
	const active = activeTokenIndex(page, ms);
	const gap = plan.fontSize * plan.wordGap;

	return (
		<div
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			lang={language}
			data-captions="true"
			data-fit-box="captions"
			data-fit-max-width={layout.captions.width}
			data-fit-max-height={plan.maxHeight + 2 * PANEL_PADDING_Y}
			style={{
				display: 'flex',
				flexWrap: 'wrap',
				justifyContent: 'center',
				alignItems: 'center',
				columnGap: gap,
				rowGap: plan.fontSize * plan.rowGap,
				maxWidth: layout.captions.width,
				boxSizing: 'border-box',
				padding: `${PANEL_PADDING_Y}px ${PANEL_PADDING_X}px`,
				borderRadius: 22,
				border: `1px solid ${withAlpha(colors.textPrimaryDark, 0.08)}`,
				background: withAlpha(colors.canvasDark, 0.78),
				fontFamily: fontStack,
				fontWeight: 700,
				fontSize: plan.fontSize,
				lineHeight: LINE_HEIGHT,
				opacity: interpolate(entry, [0, 0.6], [0, 1], {extrapolateRight: 'clamp'}),
				transform: `translateY(${interpolate(entry, [0, 1], [26, 0])}px)`,
			}}
		>
			<WordRuns
				items={page.tokens}
				textOf={(token) => token.text}
				language={language}
				gap={gap}
				renderWord={(token, index) => {
					const isActive = index === active;
					const sinceStart = Math.max(0, frame - Math.floor((token.startMs * fps) / 1000));
					const pop = isActive
						? spring({frame: sinceStart, fps, config: {damping: 11, stiffness: 320, mass: 0.5}})
						: 0;
					return (
						<span
							key={`${token.startMs}-${token.text}`}
							data-flow-word={localizeDigits(token.text, digits)}
							data-token={localizeDigits(token.text, digits)}
							data-active={isActive ? 'true' : 'false'}
							data-brand={token.isBrand ? 'true' : undefined}
							style={{
								display: 'inline-block',
								whiteSpace: 'nowrap',
								transform: `scale(${1 + ACTIVE_SCALE * pop})`,
								color: isActive ? highlightColor : colors.textPrimaryDark,
								textShadow: isActive
									? `0 0 30px ${withAlpha(colors.roseGoldGlow, 0.7)}`
									: `0 2px 10px ${withAlpha(colors.canvasDarkBg, 0.8)}`,
							}}
						>
							<Isolated text={token.text} language={language} digits={digits} />
						</span>
					);
				}}
			/>
		</div>
	);
};
