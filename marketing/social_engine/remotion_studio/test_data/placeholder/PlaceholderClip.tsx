import React, {useEffect, useState} from 'react';
import {AbsoluteFill, cancelRender, continueRender, delayRender, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

export const CLIP_WIDTH = 1080;
export const CLIP_HEIGHT = 2340;
export const CLIP_SECONDS = 12;

const SECRET_GREEN = 'rgb(0, 255, 0)';
const BURGUNDY = 'rgb(74, 14, 30)';
const ROSE = 'rgb(184, 50, 83)';
const INK = 'rgb(42, 5, 14)';
const MUTED = 'rgb(120, 90, 100)';

const ROWS = [
	{name: 'Rent', share: 62, amount: '2,500'},
	{name: 'Groceries', share: 34, amount: '800'},
	{name: 'Bills', share: 22, amount: '450'},
	{name: 'Transport', share: 18, amount: '300'},
	{name: 'Family', share: 40, amount: '950'},
	{name: 'Savings', share: 28, amount: '600'},
	{name: 'Shopping', share: 12, amount: '200'},
];

const useOutfit = (): void => {
	const [handle] = useState(() => delayRender('Loading the placeholder font'));
	useEffect(() => {
		new FontFace('Outfit', `url("${staticFile('fonts/outfit/Outfit-Variable.ttf')}")`, {weight: '100 900'})
			.load()
			.then((face) => {
				document.fonts.add(face);
				continueRender(handle);
			})
			.catch((error: unknown) => cancelRender(error));
	}, [handle]);
};

/**
 * A made-up app screen for the render check, with no real data and text at the size an app has it,
 * so a frame shows whether a phone in a reel can be read. The pure green stripes stand in for a store
 * name: they sit inside the sample mask region, and nothing else in a reel is this colour, so counting
 * these pixels in a rendered frame proves whether the mask really hides them.
 */
export const PlaceholderClip: React.FC = () => {
	useOutfit();
	const frame = useCurrentFrame();
	const {width} = useVideoConfig();
	const unit = width / CLIP_WIDTH;
	const stripe = 24 * unit;
	return (
		<AbsoluteFill style={{background: 'rgb(248, 243, 245)', fontFamily: 'Outfit', color: INK}}>
			<div
				style={{
					position: 'absolute',
					top: 0,
					height: '12%',
					width: '100%',
					background: BURGUNDY,
					color: 'white',
					display: 'flex',
					alignItems: 'flex-end',
					boxSizing: 'border-box',
					padding: `0 ${60 * unit}px ${36 * unit}px`,
					fontSize: 64 * unit,
					fontWeight: 700,
				}}
			>
				Sample budget
			</div>
			<div
				style={{
					position: 'absolute',
					top: '21%',
					height: '6%',
					left: '10%',
					width: '80%',
					background: `repeating-linear-gradient(0deg, ${SECRET_GREEN} 0, ${SECRET_GREEN} ${stripe}px, black ${stripe}px, black ${stripe * 2}px)`,
				}}
			/>
			{ROWS.map((row, index) => (
				<div
					key={row.name}
					style={{
						position: 'absolute',
						top: `${32 + index * 9}%`,
						left: '6%',
						right: '6%',
						height: '7%',
						boxSizing: 'border-box',
						padding: `${22 * unit}px ${40 * unit}px`,
						borderRadius: 32 * unit,
						background: 'white',
						border: `${2 * unit}px solid rgb(236, 224, 229)`,
						display: 'flex',
						flexDirection: 'column',
						justifyContent: 'space-between',
					}}
				>
					<div style={{display: 'flex', justifyContent: 'space-between', fontSize: 46 * unit, fontWeight: 600}}>
						<span>{row.name}</span>
						<span style={{color: MUTED}}>{row.amount}</span>
					</div>
					<div style={{height: 22 * unit, borderRadius: 11 * unit, background: 'rgb(240, 228, 233)', overflow: 'hidden'}}>
						<div
							style={{
								height: '100%',
								width: `${row.share + 6 * Math.sin((frame + index * 11) / 22)}%`,
								borderRadius: 11 * unit,
								background: ROSE,
							}}
						/>
					</div>
				</div>
			))}
		</AbsoluteFill>
	);
};
