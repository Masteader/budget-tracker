import React, {useMemo} from 'react';
import {interpolate} from 'remotion';
import {spring} from '../lib/motion';
import {Background} from '../components/Background';
import {ClipStage} from '../components/ClipStage';
import {HookBurst} from '../components/HookBurst';
import {HookTitle, hookLandingFrame} from '../components/HookTitle';
import {IllustrativePricesLabel} from '../components/IllustrativePricesLabel';
import {KineticCaptions} from '../components/KineticCaptions';
import {ProgressHud} from '../components/ProgressHud';
import {Watermark} from '../components/Watermark';
import {fontStack, LATIN_FAMILY} from '../lib/fonts';
import {CANVAS_HEIGHT, CANVAS_WIDTH, computeLayout} from '../lib/layout';
import {label} from '../lib/strings';
import {englishLineAt, heroEndMs, msToFrame, shownClip, wordsAfterHook} from '../lib/timeline';
import {colors, withAlpha} from '../lib/tokens';
import type {RenderProps} from '../props';
import {MASKED_FOLDER, REAL_BRAND_NAME_AR, REAL_BRAND_NAME_EN} from '../props';
import {Isolated} from '../components/Isolated';
import type {ReelMedia, TemplateDefinition} from './media';

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
	const ms = (frame * 1000) / fps;
	const clip = shownClip(props.clips, frame, fps);
	const heroEndFrame = msToFrame(heroEndMs(props), fps);
	const stageContext = {
		frame,
		fps,
		durationInFrames,
		language,
		digits,
		layout,
		onScreenText: props.on_screen_text,
		stageStartFrame: heroEndFrame,
	};
	const captionWords = useMemo(
		() => wordsAfterHook(props.words, props.hook_text, heroEndMs(props)),
		[props],
	);
	const landing = hookLandingFrame(props.hook_text, brandNames, fps);
	const badgeIn = spring({frame: frame + 2, fps, config: {damping: 13, stiffness: 200, mass: 0.6}});
	const englishLine =
		language === 'ar' ? englishLineAt(props.subtitles_en, props.words, ms, props.duration_ms) : null;

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
				{clip ? (
					<ClipStage
						clip={clip}
						clips={props.clips}
						device={layout.device}
						language={language}
						frame={frame}
						fps={fps}
						motion={template}
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
						centerY={layout.content.top + layout.content.height / 2}
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
					}}
				>
					<div
						data-hook-badge="true"
						style={{
							display: 'flex',
							alignItems: 'center',
							gap: 16,
							fontFamily: fontStack(language),
							fontSize: 30,
							fontWeight: 600,
							opacity: interpolate(badgeIn, [0, 0.5], [0, 1], {extrapolateRight: 'clamp'}),
							transform: `translateY(${interpolate(badgeIn, [0, 1], [-40, 0])}px)`,
						}}
					>
						<span
							style={{
								padding: '6px 22px',
								borderRadius: 18,
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
					text={props.hook_text}
					brandNames={brandNames}
					language={language}
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
						gap: 10,
					}}
				>
					<KineticCaptions
						words={captionWords}
						brandNames={brandNames}
						language={language}
						digits={digits}
						highlightColor={highlightColor}
						frame={frame}
						fps={fps}
					/>
					{englishLine ? (
						<div
							data-english-line="true"
							dir="ltr"
							style={{
								fontFamily: LATIN_FAMILY,
								fontSize: 32,
								fontWeight: 500,
								textAlign: 'center',
								color: colors.textSecondaryDark,
								textShadow: `0 2px 10px ${colors.canvasDarkBg}`,
							}}
						>
							<Isolated text={englishLine} language="en" digits={digits} />
						</div>
					) : null}
				</div>
			</Layer>
			<Layer name="hud">
				<ProgressHud
					brand={props.brand}
					language={language}
					rect={layout.hud}
					frame={frame}
					durationInFrames={durationInFrames}
					highlightColor={highlightColor}
					media={media}
				/>
			</Layer>
			<Layer name="label">
				{clip?.folder === MASKED_FOLDER ? (
					<IllustrativePricesLabel area={layout.content} top={layout.labelTop} />
				) : null}
			</Layer>
			<Layer name="watermark">{props.watermark ? <Watermark layout={layout} /> : null}</Layer>
		</div>
	);
};
