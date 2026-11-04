import React, {useEffect, useState} from 'react';
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
import {loadBrandFonts} from '../lib/fonts';
import {clipWindow, musicVolumeAt} from '../lib/timeline';
import type {RenderProps} from '../props';
import type {ReelMedia} from './media';
import {ReelView} from './ReelView';

/** Holds every frame back until the fonts are in, and fails the render if one is missing. */
const useBrandFonts = (): void => {
	const [handle] = useState(() => delayRender('Loading the brand fonts'));
	useEffect(() => {
		loadBrandFonts({
			createFace: (family, source, weight) => new FontFace(family, source, {weight}),
			addFace: (face) => document.fonts.add(face as FontFace),
			isAvailable: (cssFont, sample) => document.fonts.check(cssFont, sample),
			fileUrl: staticFile,
		})
			.then(() => continueRender(handle))
			.catch((error: unknown) => cancelRender(error));
	}, [handle]);
};

const remotionMedia: ReelMedia = {
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

export const ReelComposition: React.FC<RenderProps> = (props) => {
	useBrandFonts();
	const frame = useCurrentFrame();
	return (
		<>
			<ReelView props={props} frame={frame} media={remotionMedia} />
			<ReelAudio props={props} />
		</>
	);
};
