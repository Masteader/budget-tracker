import React, {useMemo} from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {
	activeTokenIndex,
	groupIntoPages,
	mergeBrandTokens,
	pageAt,
} from '../lib/captionGrouping';
import {fontStack} from '../lib/fonts';
import {localizeDigits} from '../lib/text';
import {colors, withAlpha} from '../lib/tokens';
import type {CaptionWord, Digits, Language} from '../props';
import {Isolated, WordRuns} from './Isolated';

type Props = {
	words: CaptionWord[];
	brandNames: string[];
	language: Language;
	digits: Digits;
	highlightColor: string;
	frame: number;
	fps: number;
};

const FONT_SIZE = 66;
const WORD_GAP = 18;
const ACTIVE_SCALE = 0.12;

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
	const pageFrame = Math.max(0, frame - Math.floor((page.startMs * fps) / 1000));
	const entry = spring({frame: pageFrame + 1, fps, config: {damping: 16, stiffness: 240, mass: 0.6}});
	const active = activeTokenIndex(page, ms);

	return (
		<div
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			lang={language}
			data-captions="true"
			style={{
				display: 'flex',
				flexWrap: 'wrap',
				justifyContent: 'center',
				alignItems: 'center',
				columnGap: WORD_GAP,
				rowGap: 4,
				padding: '14px 26px',
				borderRadius: 24,
				border: `1px solid ${withAlpha(colors.textPrimaryDark, 0.08)}`,
				background: withAlpha(colors.canvasDark, 0.72),
				fontFamily: fontStack(language),
				fontWeight: 700,
				fontSize: FONT_SIZE,
				lineHeight: 1.3,
				opacity: interpolate(entry, [0, 0.6], [0, 1], {extrapolateRight: 'clamp'}),
				transform: `translateY(${interpolate(entry, [0, 1], [26, 0])}px)`,
			}}
		>
			<WordRuns
				items={page.tokens}
				textOf={(token) => token.text}
				language={language}
				gap={WORD_GAP}
				renderWord={(token, index) => {
					const isActive = index === active;
					const sinceStart = Math.max(0, frame - Math.floor((token.startMs * fps) / 1000));
					const pop = isActive
						? spring({frame: sinceStart, fps, config: {damping: 11, stiffness: 320, mass: 0.5}})
						: 0;
					return (
						<span
							key={`${token.startMs}-${token.text}`}
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
