import {Composition, registerRoot} from 'remotion';
import {CLIP_HEIGHT, CLIP_SECONDS, CLIP_WIDTH, PlaceholderClip} from './PlaceholderClip';

registerRoot(() => (
	<Composition
		id="PlaceholderClip"
		component={PlaceholderClip}
		fps={30}
		width={CLIP_WIDTH}
		height={CLIP_HEIGHT}
		durationInFrames={CLIP_SECONDS * 30}
	/>
));
