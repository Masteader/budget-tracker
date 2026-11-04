import type {CalculateMetadataFunction} from 'remotion';
import {parseRenderProps} from '../props';
import type {RenderProps, Template} from '../props';
import {durationInFrames} from './timeline';

/** All the CLI needs when it only lists the compositions, and a render has no use for. */
const LISTING = {fps: 30, width: 1080, height: 1920, durationInFrames: 1};

/**
 * Props are checked here, before any frame, so a bad props file fails the render outright. No
 * composition has default props to fill a gap from: a sample there would let a render with no
 * hook_text go out with the sample's hook. With no props at all this answers only for a listing,
 * and ReelComposition refuses to draw a frame.
 */
export const calculateReelMetadata =
	(template: Template): CalculateMetadataFunction<RenderProps> =>
	({props}) => {
		if (Object.keys(props).length === 0) {
			return LISTING;
		}
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
