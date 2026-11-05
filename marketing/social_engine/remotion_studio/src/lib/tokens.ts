import brandTokens from '../../public/brand_tokens.json';

/** The Velvet Burgundy palette, from assets/branding. No component writes a colour by hand. */
export const colors = brandTokens.colors;

export type ColorToken = keyof typeof colors;

const allowedColors = new Set(Object.values(colors).map((value) => value.toLowerCase()));

export const isBrandColor = (value: string): boolean => allowedColors.has(value.toLowerCase());

/** A token at some opacity, for glows and thin borders. */
export const withAlpha = (hex: string, alpha: number): string => {
	const value = hex.replace('#', '');
	const red = Number.parseInt(value.slice(0, 2), 16);
	const green = Number.parseInt(value.slice(2, 4), 16);
	const blue = Number.parseInt(value.slice(4, 6), 16);
	return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
};
