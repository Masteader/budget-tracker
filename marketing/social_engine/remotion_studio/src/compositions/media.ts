import type React from 'react';
import type {ReelLayout} from '../lib/layout';
import type {Digits, Language, PropsClip} from '../props';

/**
 * Video and images are handed in, because Remotion's own components need a running composition,
 * and unit tests render with react-dom/server.
 */
export type ReelMedia = {
	Clip: React.FC<{clip: PropsClip; fps: number}>;
	Logo: React.FC<{src: string; size: number}>;
};

/** What a template gets to draw with. It holds no watermark, mask or label setting. */
export type StageContext = {
	frame: number;
	fps: number;
	durationInFrames: number;
	language: Language;
	digits: Digits;
	layout: ReelLayout;
	onScreenText: string[];
	stageStartFrame: number;
};

/**
 * A template decides how the stage looks and how the phone moves. The watermark, clips, masks and
 * the label are drawn by ReelShell above whatever a template returns, so none can remove them.
 */
export type TemplateDefinition = {
	tilt: {fromDeg: number; toDeg: number};
	zoom: {from: number; to: number};
	renderStage: (context: StageContext) => React.ReactNode;
	renderForeground?: (context: StageContext) => React.ReactNode;
};
