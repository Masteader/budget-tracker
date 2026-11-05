import React, {useEffect, useLayoutEffect, useMemo, useState} from 'react';
import {
	Audio,
	cancelRender,
	continueRender,
	delayRender,
	Img,
	OffthreadVideo,
	Sequence,
	staticFile,
	useCurrentFrame,
} from 'remotion';
import {findFitProblems, TextFitError} from '../lib/fit';
import type {MeasureText} from '../lib/fit';
import {displayTexts, fontStack, loadBrandFonts} from '../lib/fonts';
import {clipWindow, musicVolumeAt} from '../lib/timeline';
import {parseRenderProps} from '../props';
import type {RenderProps} from '../props';
import type {ReelMedia} from './media';
import {ReelView} from './ReelView';

/** Holds every frame back until the fonts are in, and fails the render if one is missing. */
const useBrandFonts = (texts: string[]): boolean => {
	const [handle] = useState(() => delayRender('Loading the brand fonts'));
	const [ready, setReady] = useState(false);
	useEffect(() => {
		loadBrandFonts(
			{
				createFace: (family, source, weight) => new FontFace(family, source, {weight}),
				addFace: (face) => document.fonts.add(face as FontFace),
				isAvailable: (cssFont, sample) => document.fonts.check(cssFont, sample),
				fileUrl: staticFile,
				readFont: async (file) => {
					const response = await fetch(staticFile(file));
					if (!response.ok) {
						throw new Error(`${file} did not load: ${response.status}`);
					}
					return response.arrayBuffer();
				},
			},
			texts,
		)
			.then(() => setReady(true))
			.catch((error: unknown) => cancelRender(error));
		// The fonts load once. The texts are checked again only if the props change, which they do not.
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);
	useEffect(() => {
		if (ready) {
			continueRender(handle);
		}
	}, [ready, handle]);
	return ready;
};

/** Widths from the browser's own shaping, so Arabic joins and kerning count. */
const createMeasure = (): MeasureText => {
	const context = document.createElement('canvas').getContext('2d');
	if (!context) {
		throw new Error('no canvas to measure text with');
	}
	const known = new Map<string, number>();
	return (text, {size, weight}) => {
		const key = `${weight}|${size}|${text}`;
		const cached = known.get(key);
		if (cached !== undefined) {
			return cached;
		}
		context.font = `${weight} ${size}px ${fontStack}`;
		const width = context.measureText(text).width;
		known.set(key, width);
		return width;
	};
};

const baseMedia: Pick<ReelMedia, 'Clip' | 'Logo'> = {
	Clip: ({clip, fps}) => {
		const {from, to} = clipWindow(clip, fps);
		return (
			<Sequence from={from} durationInFrames={to - from} layout="none" name={clip.folder}>
				<OffthreadVideo
					src={staticFile(clip.src)}
					muted
					style={{display: 'block', width: '100%', height: 'auto'}}
				/>
			</Sequence>
		);
	},
	Logo: ({src, size}) => <Img src={staticFile(src)} width={size} height={size} alt="" />,
};

const ReelAudio: React.FC<{props: RenderProps}> = ({props}) => {
	const {words, duck_under_voice: under, duck_in_pauses: pauses, fps} = props;
	return (
		<>
			<Audio src={staticFile(props.audio_src)} />
			{props.music_src ? (
				<Audio
					src={staticFile(props.music_src)}
					volume={(frame) => musicVolumeAt((frame * 1000) / fps, words, under, pauses)}
				/>
			) : null}
		</>
	);
};

/** The browser's word on each frame: text that overflowed its room stops the render. */
const useFitCheck = (frame: number, ready: boolean): void => {
	useLayoutEffect(() => {
		const problems = findFitProblems(document.querySelectorAll<HTMLElement>('[data-fit-box]'));
		if (problems.length > 0) {
			cancelRender(new TextFitError(`frame ${frame}: ${problems.join('; ')}`));
		}
	}, [frame, ready]);
};

const Reel: React.FC<{props: RenderProps}> = ({props}) => {
	const frame = useCurrentFrame();
	const texts = useMemo(() => displayTexts(props), [props]);
	const ready = useBrandFonts(texts);
	const media = useMemo<ReelMedia | null>(
		() => (ready ? {...baseMedia, measure: createMeasure()} : null),
		[ready],
	);
	useFitCheck(frame, ready);
	if (!media) {
		return null;
	}
	return (
		<>
			<ReelView props={props} frame={frame} media={media} />
			<ReelAudio props={props} />
		</>
	);
};

/** Checked here as well as in the metadata, so a render given no props at all draws nothing. */
export const ReelComposition: React.FC<RenderProps> = (props) => {
	const parsed = useMemo(() => parseRenderProps(props), [props]);
	return <Reel props={parsed} />;
};
