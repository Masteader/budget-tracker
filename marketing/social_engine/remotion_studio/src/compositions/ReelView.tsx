import React from 'react';
import {durationInFrames} from '../lib/timeline';
import type {RenderProps} from '../props';
import type {ReelMedia} from './media';
import {ReelShell} from './ReelShell';
import {TEMPLATES} from './templates';

/** A reel at one frame, as a pure function of its props. */
export const ReelView: React.FC<{props: RenderProps; frame: number; media: ReelMedia}> = ({
	props,
	frame,
	media,
}) => (
	<ReelShell
		props={props}
		template={TEMPLATES[props.template]}
		media={media}
		frame={frame}
		fps={props.fps}
		durationInFrames={durationInFrames(props)}
	/>
);
