import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';

export const CLIP_WIDTH = 540;
export const CLIP_HEIGHT = 1170;
export const CLIP_SECONDS = 12;

const SECRET_GREEN = 'rgb(0, 255, 0)';

/**
 * A made-up app screen for the render check, with no real data. The pure green stripes stand in for
 * a store name: they sit inside the sample mask region, and nothing else in a reel is this colour,
 * so counting these pixels in a rendered frame proves whether the mask really hides them.
 */
export const PlaceholderClip: React.FC = () => {
	const frame = useCurrentFrame();
	return (
		<AbsoluteFill style={{background: 'rgb(248, 243, 245)'}}>
			<div style={{position: 'absolute', top: 0, height: '12%', width: '100%', background: 'rgb(74, 14, 30)'}} />
			<div
				style={{
					position: 'absolute',
					top: '21%',
					height: '6%',
					left: '10%',
					width: '80%',
					background: `repeating-linear-gradient(0deg, ${SECRET_GREEN} 0, ${SECRET_GREEN} 8px, black 8px, black 16px)`,
				}}
			/>
			{Array.from({length: 7}, (_, row) => (
				<div
					key={row}
					style={{
						position: 'absolute',
						top: `${32 + row * 9}%`,
						left: '6%',
						right: '6%',
						height: '7%',
						borderRadius: 16,
						background: 'white',
						boxShadow: '0 2px 10px rgba(0, 0, 0, 0.12)',
					}}
				>
					<div
						style={{
							position: 'absolute',
							top: '30%',
							left: '6%',
							height: '40%',
							width: `${30 + ((row * 17 + frame) % 50)}%`,
							borderRadius: 8,
							background: 'rgb(184, 50, 83)',
						}}
					/>
				</div>
			))}
		</AbsoluteFill>
	);
};
