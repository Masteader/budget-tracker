import React from 'react';
import type {ReelMedia} from '../compositions/media';
import {colors, withAlpha} from '../lib/tokens';
import type {PropsClip} from '../props';

const BLUR_PX = 22;

const percent = (fraction: number): string => `${fraction * 100}%`;

/**
 * Draws each mask region over the clip it belongs to. A region shows a heavily blurred copy of the
 * same clip, over an opaque base, so nothing sharp can come through. It lives in the same box as
 * the sharp clip and is placed in fractions of it, so it stays on target at any recording shape
 * and through every tilt and zoom (D30, G19). Blur is a filter on the copy rather than a backdrop
 * blur, because a backdrop blur can silently stop working inside a 3D-transformed parent.
 */
export const ClipMask: React.FC<{clip: PropsClip; fps: number; media: ReelMedia}> = ({
	clip,
	fps,
	media,
}) => {
	if (clip.mask_regions.length === 0) {
		return null;
	}
	return (
		<div data-clip-masks="true" style={{position: 'absolute', inset: 0, zIndex: 1}}>
			{clip.mask_regions.map((region) => (
				<div
					key={`${region.x}-${region.y}-${region.width}-${region.height}`}
					data-mask-region={`${region.x},${region.y},${region.width},${region.height}`}
					style={{
						position: 'absolute',
						left: percent(region.x),
						top: percent(region.y),
						width: percent(region.width),
						height: percent(region.height),
						overflow: 'hidden',
						background: colors.surfaceDark,
					}}
				>
					<div
						aria-hidden="true"
						style={{
							position: 'absolute',
							left: percent(-region.x / region.width),
							top: percent(-region.y / region.height),
							width: percent(1 / region.width),
							filter: `blur(${BLUR_PX}px)`,
						}}
					>
						<media.Clip clip={clip} fps={fps} />
					</div>
					<div
						style={{
							position: 'absolute',
							inset: 0,
							background: withAlpha(colors.surfaceDark, 0.45),
							border: `1px solid ${withAlpha(colors.roseGoldGlow, 0.25)}`,
						}}
					/>
				</div>
			))}
		</div>
	);
};
