import React from 'react';
import type {CaptionToken} from '../lib/captionGrouping';
import {fontStack} from '../lib/fonts';
import type {FlowPlan} from '../lib/fit';
import {localizeDigits} from '../lib/text';
import type {Digits, Language} from '../props';
import {Isolated, WordRuns} from './Isolated';

/**
 * A block of on-screen text. One word is one inline-block, the name is one word, and a number stays
 * with its unit, so no line can break through them. The size comes from a fit, and data-fit-* lets a
 * real render check the room it was given.
 */
export const FlowText: React.FC<{
	name: string;
	tokens: CaptionToken[];
	plan: FlowPlan;
	language: Language;
	digits: Digits;
	color: string;
	weight: number;
	align?: 'start' | 'center';
	wordStyle?: (token: CaptionToken, index: number) => React.CSSProperties;
}> = ({name, tokens, plan, language, digits, color, weight, align = 'start', wordStyle}) => (
	<div
		data-flow-text={language === 'ar' ? 'rtl' : 'ltr'}
		data-fit-box={name}
		data-fit-max-width={plan.maxWidth}
		data-fit-max-height={plan.maxHeight}
		dir={language === 'ar' ? 'rtl' : 'ltr'}
		lang={language}
		style={{
			display: 'flex',
			flexWrap: 'wrap',
			justifyContent: align === 'center' ? 'center' : 'flex-start',
			alignContent: 'flex-start',
			columnGap: plan.fontSize * plan.wordGap,
			rowGap: plan.fontSize * plan.rowGap,
			maxWidth: plan.maxWidth,
			fontFamily: fontStack,
			fontSize: plan.fontSize,
			fontWeight: weight,
			lineHeight: plan.lineHeight,
			color,
		}}
	>
		<WordRuns
			items={tokens}
			textOf={(token) => token.text}
			language={language}
			gap={plan.fontSize * plan.wordGap}
			renderWord={(token, index) => (
				<span
					key={`${index}-${token.text}`}
					data-flow-word={localizeDigits(token.text, digits)}
					style={{display: 'inline-block', whiteSpace: 'nowrap', ...wordStyle?.(token, index)}}
				>
					<Isolated text={token.text} language={language} digits={digits} />
				</span>
			)}
		/>
	</div>
);
