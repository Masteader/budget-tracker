import React, {useMemo} from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {Background} from '../components/Background';
import {ClipStage} from '../components/ClipStage';
import {HookBurst} from '../components/HookBurst';
import {HookTitle, hookLandingFrame, planHook} from '../components/HookTitle';
import {IllustrativePricesLabel} from '../components/IllustrativePricesLabel';
import {EnglishLine, KineticCaptions} from '../components/KineticCaptions';
import {ProgressHud} from '../components/ProgressHud';
import {Watermark} from '../components/Watermark';
import {cameraPose} from '../lib/camera';
import {fontStack} from '../lib/fonts';
import {CANVAS_HEIGHT, CANVAS_WIDTH, computeLayout} from '../lib/layout';
import {label} from '../lib/strings';
import {englishLineAt, heroEndMs, msToFrame, shownClip, wordsAfterHook} from '../lib/timeline';
import {colors, withAlpha} from '../lib/tokens';
import type {RenderProps} from '../props';
import {MASKED_FOLDER, REAL_BRAND_NAME_AR, REAL_BRAND_NAME_EN} from '../props';
import type {ReelMedia, StageContext, TemplateDefinition} from './media';

/** Paint order. A later layer always covers an earlier one, whatever a template draws. */
const LAYER = {
	background: 1,
	stage: 2,
	clip: 3,
	foreground: 4,
	burst: 5,
	hook: 6,
	captions: 7,
	hud: 8,
	label: 9,
	watermark: 10,
} as const;

const Layer: React.FC<{
	name: keyof typeof LAYER;
	opacity?: number;
	children: React.ReactNode;
}> = ({name, opacity, children}) => (
	<div
		data-layer={name}
		style={{
			position: 'absolute',
			inset: 0,
			zIndex: LAYER[name],
			isolation: 'isolate',
			overflow: 'hidden',
			opacity,
		}}
	>
		{children}
	</div>
);

/**
 * The one way a reel gets drawn. Templates only fill the stage and foreground, in isolated layers.
 * The clip with its masks, the illustrative label and the watermark are drawn here from props,
 * above those layers, and no template or prop can turn them off (spec Section 8.3, D30).
 */
export const ReelShell: React.FC<{
	props: RenderProps;
	template: TemplateDefinition;
	media: ReelMedia;
	frame: number;
	fps: number;
	durationInFrames: number;
}> = ({props, template, media, frame, fps, durationInFrames}) => {
	const layout = useMemo(() => computeLayout(props.safe_zones), [props.safe_zones]);
	const brandNames = useMemo(
		() => [props.brand.name_ar, props.brand.name_en, REAL_BRAND_NAME_AR, REAL_BRAND_NAME_EN],
		[props.brand.name_ar, props.brand.name_en],
	);
	const {language, digits, highlight_color: highlightColor} = props;
	const hook = useMemo(
		() => planHook(props.hook_text, brandNames, language, digits, layout, media.measure),
		[props.hook_text, brandNames, language, digits, layout, media.measure],
	);
	const ms = (frame * 1000) / fps;
	const clip = shownClip(props.clips, frame, fps);
	const heroEndFrame = msToFrame(heroEndMs(props), fps);
	const camera = clip
		? cameraPose({clip, clips: props.clips, frame, fps, layout, motion: template})
		: null;
	const stageContext: StageContext = {
		frame,
		fps,
		durationInFrames,
		language,
		digits,
		layout,
		onScreenText: props.on_screen_text,
		stageStartFrame: heroEndFrame,
		words: props.words,
		brandNames,
		brand: props.brand,
		highlightColor,
		media,
		clips: props.clips,
		camera,
	};
	const captionWords = useMemo(
		() => wordsAfterHook(props.words, props.hook_text, heroEndMs(props)),
		[props],
	);
	const landing = hookLandingFrame(hook.tokens.length, fps);
	const badgeIn = spring({frame: frame + 2, fps, config: {damping: 13, stiffness: 200, mass: 0.6}});
	const englishLine =
		language === 'ar' ? englishLineAt(props.subtitles_en, props.words, ms, props.duration_ms, brandNames) : null;

	return (
		<div
			data-reel={props.reel_id}
			dir={language === 'ar' ? 'rtl' : 'ltr'}
			style={{
				position: 'relative',
				width: CANVAS_WIDTH,
				height: CANVAS_HEIGHT,
				overflow: 'hidden',
				background: colors.canvasDark,
				color: colors.textPrimaryDark,
			}}
		>
			<Layer name="background">
				<Background frame={frame} fps={fps} />
			</Layer>
			<Layer name="stage" opacity={clip ? 0 : 1}>
				{template.renderStage(stageContext)}
			</Layer>
			<Layer name="clip">
				{clip && camera ? (
					<ClipStage
						clip={clip}
						layout={layout}
						language={language}
						camera={camera}
						frame={frame}
						fps={fps}
						media={media}
					/>
				) : null}
			</Layer>
			<Layer name="foreground">{template.renderForeground?.(stageContext)}</Layer>
			<Layer name="burst">
				{heroEndFrame > 0 ? (
					<HookBurst
						frame={frame}
						fps={fps}
						centerX={layout.content.left + layout.content.width / 2}
						centerY={hook.heroTop + hook.hero.height / 2}
						landingFrame={landing}
					/>
				) : null}
			</Layer>
			<Layer name="hook">
				<div
					data-zone="top"
					style={{
						position: 'absolute',
						top: layout.top.top,
						left: layout.top.left,
						width: layout.top.width,
						height: layout.top.height,
						overflow: 'hidden',
					}}
				>
					<div
						data-hook-badge="true"
						style={{
							display: 'flex',
							alignItems: 'center',
							gap: 14,
							fontFamily: fontStack,
							fontSize: 26,
							fontWeight: 600,
							opacity: interpolate(badgeIn, [0, 0.5], [0, 1], {extrapolateRight: 'clamp'}),
							transform: `translateY(${interpolate(badgeIn, [0, 1], [-40, 0])}px)`,
						}}
					>
						<span
							style={{
								padding: '2px 18px',
								borderRadius: 16,
								background: colors.primaryLight,
								border: `1px solid ${withAlpha(colors.roseGoldGlow, 0.4)}`,
								color: colors.roseGold,
								whiteSpace: 'nowrap',
							}}
						>
							{label('badge', language)}
						</span>
						<span style={{color: colors.textSecondaryDark, whiteSpace: 'nowrap'}}>
							<bdi>{props.brand.hashtag}</bdi>
						</span>
					</div>
				</div>
				<HookTitle
					plan={hook}
					digits={digits}
					highlightColor={highlightColor}
					layout={layout}
					heroEndFrame={heroEndFrame}
					frame={frame}
					fps={fps}
				/>
			</Layer>
			<Layer name="captions">
				<div
					data-zone="captions"
					style={{
						position: 'absolute',
						top: layout.captions.top,
						left: layout.captions.left,
						width: layout.captions.width,
						height: layout.captions.height,
						display: 'flex',
						flexDirection: 'column',
						justifyContent: 'flex-end',
						alignItems: 'center',
						gap: 8,
					}}
				>
					<KineticCaptions
						words={captionWords}
						brandNames={brandNames}
						language={language}
						digits={digits}
						highlightColor={highlightColor}
						layout={layout}
						measure={media.measure}
						withEnglish={Boolean(englishLine)}
						frame={frame}
						fps={fps}
					/>
					{englishLine ? (
						<EnglishLine
							line={englishLine}
							brandNames={brandNames}
							digits={digits}
							layout={layout}
							measure={media.measure}
						/>
					) : null}
				</div>
			</Layer>
			<Layer name="hud">
				<ProgressHud
					brand={props.brand}
					language={language}
					rect={layout.hud}
					narrow={layout.narrow}
					frame={frame}
					durationInFrames={durationInFrames}
					highlightColor={highlightColor}
					media={media}
				/>
			</Layer>
			<Layer name="label">
				{clip?.folder === MASKED_FOLDER ? (
					<IllustrativePricesLabel band={layout.labelBand} measure={media.measure} />
				) : null}
			</Layer>
			<Layer name="watermark">{props.watermark ? <Watermark layout={layout} /> : null}</Layer>
		</div>
	);
};
