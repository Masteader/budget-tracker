import React from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {BrandLockup, fitNameSize} from '../components/BrandLockup';
import {FlowText} from '../components/FlowText';
import {FOCAL_REST_SHARE} from '../lib/camera';
import {textTokens} from '../lib/captionGrouping';
import {fitFlow, requireFit} from '../lib/fit';
import type {FlowPlan, MeasureText} from '../lib/fit';
import type {ReelLayout} from '../lib/layout';
import {baseLanguage} from '../lib/text';
import {afterLastClip, itemIndexAt} from '../lib/timeline';
import {colors, withAlpha} from '../lib/tokens';
import type {Digits, Language} from '../props';
import type {StageContext, TemplateDefinition} from './media';

const PADDING_X = 28;
const PADDING_Y = 12;
const SIDE_MARGIN = 20;
const BAND_MARGIN = 8;
const MAX_SIZE = 46;
const MIN_SIZE = 22;
const FEATURE_REACH = 170;
const FEATURE_REACH_SHARE = 0.24;
const SETTLED = 0.98;
const CLOSING_MARGIN = 24;
const CLOSING_LOGO = 132;
const CLOSING_DROP = 0.14;

export type CalloutPlan = {
	text: FlowPlan;
	tokens: ReturnType<typeof textTokens>;
	language: Language;
	/** Where it goes by default: under the feature, above the captions. */
	top: number;
	height: number;
	fits: boolean;
};

/** Measured against the room under the feature, so it can reach neither the feature nor the captions. */
export const planCallout = (
	text: string,
	brandNames: string[],
	reelLanguage: Language,
	digits: Digits,
	layout: ReelLayout,
	measure: MeasureText,
): CalloutPlan => {
	const {view, content} = layout;
	const language = baseLanguage(text, reelLanguage);
	const tokens = textTokens(text, brandNames);
	const reach = Math.min(FEATURE_REACH, view.height * FEATURE_REACH_SHARE);
	const bandTop = view.top + view.height * FOCAL_REST_SHARE + reach;
	const bandBottom = view.top + view.height - BAND_MARGIN;
	const plan = requireFit(
		fitFlow({
			tokens,
			language,
			digits,
			measure,
			weight: 600,
			maxWidth: content.width - 2 * (SIDE_MARGIN + PADDING_X),
			maxHeight: bandBottom - bandTop - 2 * PADDING_Y,
			maxSize: MAX_SIZE,
			minSize: MIN_SIZE,
			lineHeight: 1.26,
		}),
		'A callout',
	);
	const height = plan.height + 2 * PADDING_Y;
	return {text: plan, tokens, language, top: bandBottom - height, height, fits: plan.fits};
};

const Callouts: React.FC<{context: StageContext}> = ({context}) => {
	const {frame, fps, durationInFrames, language, digits, layout, onScreenText, stageStartFrame, brandNames, media, camera, clips} =
		context;
	const count = onScreenText.length;
	const index = itemIndexAt(count, frame, stageStartFrame, durationInFrames);
	const text = onScreenText[index];
	if (text === undefined || (camera && camera.pushed < SETTLED)) {
		return null;
	}
	const plan = planCallout(text, brandNames, language, digits, layout, media.measure);
	const span = (durationInFrames - stageStartFrame) / count;
	const startedAt = stageStartFrame + Math.round(index * span);
	const hit = spring({
		frame: frame - startedAt,
		fps,
		config: {damping: 13, stiffness: 210, mass: 0.6},
	});
	const fromSide = language === 'ar' ? 90 : -90;
	const {stage, view, content} = layout;
	const reach = Math.min(FEATURE_REACH, view.height * FEATURE_REACH_SHARE);
	// A feature near the bottom of a clip rests lower, so the callout moves above it.
	const top = !camera
		? afterLastClip(clips, frame, fps)
			? stage.top + CLOSING_MARGIN
			: stage.top + (stage.height - plan.height) / 2
		: camera.focalCanvas.y + reach > plan.top
			? view.top + BAND_MARGIN
			: plan.top;
	return (
		<div
			data-callout="true"
			style={{
				position: 'absolute',
				top,
				left: content.left,
				width: content.width,
				display: 'flex',
				justifyContent: 'center',
				opacity:
					interpolate(hit, [0, 0.5], [0, 1], {extrapolateRight: 'clamp'}) *
					(camera ? interpolate(camera.pushed, [SETTLED, 1], [0, 1]) : 1),
				transform: `translateX(${interpolate(hit, [0, 1], [fromSide, 0])}px)`,
			}}
		>
			<div
				style={{
					padding: `${PADDING_Y}px ${PADDING_X}px`,
					borderRadius: 22,
					background: `linear-gradient(135deg, ${colors.primaryLightGradient}, ${colors.primaryLight})`,
					border: `1px solid ${withAlpha(colors.roseGoldGlow, 0.5)}`,
					boxShadow: `0 16px 50px ${withAlpha(colors.canvasDarkBg, 0.6)}, 0 0 50px ${withAlpha(colors.roseGoldGlow, 0.3)}`,
				}}
			>
				<FlowText
					name="callout"
					tokens={plan.tokens}
					plan={plan.text}
					language={plan.language}
					digits={digits}
					color={colors.textPrimaryDark}
					weight={600}
					align="center"
				/>
			</div>
		</div>
	);
};

/** Once the clips are over, the stage closes on the brand. */
const Closing: React.FC<{context: StageContext}> = ({context}) => {
	const {frame, fps, clips, layout, brand, language, media} = context;
	if (!afterLastClip(clips, frame, fps)) {
		return null;
	}
	const lastEnd = Math.max(...clips.map((clip) => Math.ceil((clip.end_ms * fps) / 1000)));
	const hit = spring({frame: frame - lastEnd, fps, config: {damping: 12, stiffness: 170, mass: 0.7}});
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
				alignItems: 'center',
				justifyContent: 'center',
				paddingTop: stage.height * CLOSING_DROP,
				boxSizing: 'border-box',
				opacity: interpolate(hit, [0, 0.4], [0, 1], {extrapolateRight: 'clamp'}),
				transform: `scale(${interpolate(hit, [0, 1], [0.8, 1]) * (1 + 0.01 * Math.sin((frame / fps) * 2))})`,
			}}
		>
			<BrandLockup
				brand={brand}
				language={language}
				media={media}
				logoSize={CLOSING_LOGO}
				nameSize={fitNameSize(brand, media.measure, stage.width - CLOSING_LOGO * 1.28, 72)}
				glow={0.6 + 0.4 * Math.sin((frame / fps) * 3)}
				maxWidth={stage.width}
			/>
		</div>
	);
};

/** Template A, Feature in Action: a real clip, with the camera pushing in on the feature. */
export const FeatureDemo: TemplateDefinition = {
	tilt: {fromDeg: 14, toDeg: 3},
	zoom: {from: 1, to: 1.5},
	renderStage: (context) => <Closing context={context} />,
	renderForeground: (context) => <Callouts context={context} />,
};
