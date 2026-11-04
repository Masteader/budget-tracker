import React from 'react';
import {Composition} from 'remotion';
import type {CalculateMetadataFunction} from 'remotion';
import sampleProps from '../test_data/sample_feature_ar.json';
import {ReelComposition} from './compositions/ReelComposition';
import {durationInFrames} from './lib/timeline';
import {parseRenderProps, TemplateSchema} from './props';
import type {RenderProps, Template} from './props';

/** Props are checked here, before any frame, so a bad props file fails the render outright. */
const metadataFor =
	(template: Template): CalculateMetadataFunction<RenderProps> =>
	({props}) => {
		const parsed = parseRenderProps(props);
		if (parsed.template !== template) {
			throw new Error(`props are for ${parsed.template}, but this is the ${template} composition`);
		}
		return {
			props: parsed,
			fps: parsed.fps,
			width: parsed.width,
			height: parsed.height,
			durationInFrames: durationInFrames(parsed),
		};
	};

const defaults = sampleProps as RenderProps;

export const RemotionRoot: React.FC = () => (
	<>
		{TemplateSchema.options.map((template) => (
			<Composition
				key={template}
				id={template}
				component={ReelComposition}
				defaultProps={{...defaults, template}}
				calculateMetadata={metadataFor(template)}
				fps={defaults.fps}
				width={defaults.width}
				height={defaults.height}
				durationInFrames={durationInFrames(defaults)}
			/>
		))}
	</>
);
