import type {Digits, Language} from '../props';
import type {CaptionToken} from './captionGrouping';
import {groupWordRuns, localizeDigits} from './text';

/**
 * Text fitting by measuring. Character counts cannot tell how wide a line is, so the size of each
 * block of text comes from the real width of its words. Nothing is ever clipped: a text that cannot
 * fit at the smallest size fails the render.
 */

export type FontSpec = {size: number; weight: number};
export type MeasureText = (text: string, font: FontSpec) => number;

export class TextFitError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'TextFitError';
	}
}

const REFERENCE_SIZE = 100;
// The browser's line can come out a little over the sum of the measured words.
const WIDTH_MARGIN = 0.985;
const SIZE_STEP = 2;
const PIXEL_TOLERANCE = 2;

const DEFAULT_LINE_HEIGHT = 1.28;
const DEFAULT_WORD_GAP = 0.27;
const DEFAULT_ROW_GAP = 0.04;

export type FlowRequest = {
	tokens: CaptionToken[];
	language: Language;
	digits?: Digits;
	measure: MeasureText;
	weight: number;
	maxWidth: number;
	maxHeight: number;
	maxSize: number;
	minSize: number;
	maxLines?: number;
	lineHeight?: number;
	wordGap?: number;
	rowGap?: number;
	extraEm?: (index: number) => number;
};

export type FlowPlan = {
	fontSize: number;
	lineCount: number;
	width: number;
	height: number;
	fits: boolean;
	lineHeight: number;
	wordGap: number;
	rowGap: number;
	maxWidth: number;
	maxHeight: number;
};

type Run = {direction: unknown; pieces: number[]};

/** Lines break the way the flex row breaks them: whole pieces at a time. */
const flowLines = (runs: Run[], size: number, gap: number, max: number): {count: number; widest: number} => {
	let count = 1;
	let used = 0;
	let widest = 0;
	const place = (width: number) => {
		if (used > 0 && used + gap + width > max) {
			count++;
			used = width;
		} else {
			used = used > 0 ? used + gap + width : width;
		}
		widest = Math.max(widest, used);
	};
	for (const {direction, pieces} of runs) {
		const widths = pieces.map((piece) => piece * size);
		const whole = widths.reduce((sum, width) => sum + width, 0) + gap * (widths.length - 1);
		if (direction && whole <= max) {
			place(whole);
		} else if (direction) {
			// A run too long for one line starts on its own line and wraps inside itself.
			if (used > 0) {
				count++;
				used = 0;
			}
			widths.forEach(place);
			used = max;
		} else {
			widths.forEach(place);
		}
	}
	return {count, widest};
};

/** The largest size from maxSize down at which the text fits. `fits` is false if none does. */
export const fitFlow = ({
	tokens,
	language,
	digits = 'western',
	measure,
	weight,
	maxWidth,
	maxHeight,
	maxSize,
	minSize,
	maxLines = Number.POSITIVE_INFINITY,
	lineHeight = DEFAULT_LINE_HEIGHT,
	wordGap = DEFAULT_WORD_GAP,
	rowGap = DEFAULT_ROW_GAP,
	extraEm = () => 0,
}: FlowRequest): FlowPlan => {
	const widths = new Map(
		tokens.map((token, index) => [
			token,
			measure(localizeDigits(token.text, digits), {size: REFERENCE_SIZE, weight}) / REFERENCE_SIZE + extraEm(index),
		]),
	);
	const runs: Run[] = groupWordRuns(tokens, (token) => token.text, language).map((run) => ({
		direction: run.direction,
		pieces: run.atoms.map(
			(atom) => atom.reduce((sum, token) => sum + (widths.get(token) ?? 0), 0) + wordGap * (atom.length - 1),
		),
	}));
	const usable = maxWidth * WIDTH_MARGIN;
	const plan = (fontSize: number): FlowPlan => {
		const {count, widest} = flowLines(runs, fontSize, wordGap * fontSize, usable);
		const height = count * fontSize * lineHeight + (count - 1) * fontSize * rowGap;
		return {
			fontSize,
			lineCount: count,
			width: widest,
			height,
			fits: widest <= usable && height <= maxHeight && count <= maxLines,
			lineHeight,
			wordGap,
			rowGap,
			maxWidth,
			maxHeight,
		};
	};
	for (let fontSize = maxSize; fontSize > minSize; fontSize -= SIZE_STEP) {
		const candidate = plan(fontSize);
		if (candidate.fits) {
			return candidate;
		}
	}
	return plan(minSize);
};

/** For text the reel cannot do without: if it does not fit, the render stops and says which. */
export const requireFit = <T extends {fits: boolean}>(plan: T, what: string): T => {
	if (!plan.fits) {
		throw new TextFitError(`${what} does not fit its space, even at the smallest size`);
	}
	return plan;
};

type FitElement = {
	offsetWidth: number;
	offsetHeight: number;
	getAttribute: (name: string) => string | null;
	querySelectorAll: (selector: string) => ArrayLike<{offsetWidth: number}>;
};

/**
 * What the browser really laid out, against the room each text was given. Layout sizes ignore the
 * transforms that animate a block, so a word caught mid-spring does not count as overflow.
 */
export const findFitProblems = (elements: ArrayLike<FitElement>): string[] => {
	const problems: string[] = [];
	for (const element of Array.from(elements)) {
		const name = element.getAttribute('data-fit-box') ?? 'text';
		const maxWidth = Number(element.getAttribute('data-fit-max-width'));
		const maxHeight = Number(element.getAttribute('data-fit-max-height'));
		const widest = Math.max(
			element.offsetWidth,
			...Array.from(element.querySelectorAll('[data-flow-word]')).map((word) => word.offsetWidth),
		);
		if (widest > maxWidth + PIXEL_TOLERANCE) {
			problems.push(`${name} is ${widest} px wide, with room for ${maxWidth}`);
		}
		if (element.offsetHeight > maxHeight + PIXEL_TOLERANCE) {
			problems.push(`${name} is ${element.offsetHeight} px tall, with room for ${maxHeight}`);
		}
	}
	return problems;
};
