import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {renderToStaticMarkup} from 'react-dom/server';
import type {ReelMedia} from '../compositions/media';
import {ReelView} from '../compositions/ReelView';
import {durationInFrames} from '../lib/timeline';
import type {RenderProps} from '../props';
import {parseRenderProps} from '../props';

/** Stands in for Remotion's video and image, which need a running composition. */
export const fakeMedia: ReelMedia = {
	Clip: ({clip}) => <img data-clip-media={clip.src} alt="" style={{display: 'block', width: '100%'}} />,
	Logo: ({src, size}) => <img data-logo-src={src} alt="" width={size} height={size} />,
};

const fixture = JSON.parse(
	readFileSync(resolve(process.cwd(), 'fixtures/props_valid.json'), 'utf-8'),
) as RenderProps;

/** The synced fixture, which holds a plain clip at 3 to 15 s and a Smart Basket clip at 15 to 27 s. */
export const featureProps = (overrides: Partial<RenderProps> = {}): RenderProps =>
	parseRenderProps({...structuredClone(fixture), ...overrides});

const CARDS = ['Know your payday cycle', 'Plan by category', 'Check before you spend'];

export const tipProps = (overrides: Partial<RenderProps> = {}): RenderProps =>
	featureProps({
		template: 'DailyTip',
		clips: [],
		duration_ms: 6000,
		words: [],
		on_screen_text: CARDS,
		...overrides,
	});

export const mythProps = (overrides: Partial<RenderProps> = {}): RenderProps =>
	featureProps({
		template: 'MythVsFact',
		clips: [],
		duration_ms: 6000,
		words: [],
		on_screen_text: ['Keeping it all in your head', 'A clear budget by category'],
		...overrides,
	});

export const realBrand = {
	name_ar: 'قوام المال',
	name_en: 'Qawam Money',
	hashtag: '#QawamMoney',
	logo_src: 'approved_mark.svg',
};

export const renderReel = (props: RenderProps, frame: number): string =>
	renderToStaticMarkup(<ReelView props={props} frame={frame} media={fakeMedia} />);

export const framesOf = (props: RenderProps): number[] =>
	Array.from({length: durationInFrames(props)}, (_, frame) => frame);

/** An inline style value from the first element carrying this data attribute. */
export const styleOf = (markup: string, attribute: string): Record<string, string> => {
	const element = new RegExp(`<[a-z]+[^>]*${attribute}[^>]*>`).exec(markup)?.[0] ?? '';
	const style = /style="([^"]*)"/.exec(element)?.[1] ?? '';
	return Object.fromEntries(
		style
			.split(';')
			.filter(Boolean)
			.map((rule) => {
				const colon = rule.indexOf(':');
				return [rule.slice(0, colon), rule.slice(colon + 1)];
			}),
	);
};

/** Text with its tags gone, as a reader would see it. */
export const visibleText = (markup: string): string =>
	markup.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&');
