import React from 'react';
import {Composition} from 'remotion';
import {ReelComposition} from './compositions/ReelComposition';
import {calculateReelMetadata} from './lib/reelMetadata';
import {TemplateSchema} from './props';
import type {RenderProps} from './props';

const NO_DEFAULTS = {} as RenderProps;

/** Each template is a composition under its own name. Props come from the caller, whole. */
export const RemotionRoot: React.FC = () => (
	<>
		{TemplateSchema.options.map((template) => (
			<Composition
				key={template}
				id={template}
				component={ReelComposition}
				defaultProps={NO_DEFAULTS}
				calculateMetadata={calculateReelMetadata(template)}
			/>
		))}
	</>
);
