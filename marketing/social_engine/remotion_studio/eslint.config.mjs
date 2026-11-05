import {config} from '@remotion/eslint-config-flat';

const nodeGlobals = {
	console: 'readonly',
	process: 'readonly',
	Buffer: 'readonly',
};

export default [
	...config,
	{
		files: ['scripts/**/*.mjs'],
		languageOptions: {globals: nodeGlobals},
	},
	{
		// Tests stand in for Remotion's media and feed the schema deliberately broken props.
		files: ['src/__tests__/**'],
		rules: {
			'@remotion/warn-native-media-tag': 'off',
			'@typescript-eslint/no-explicit-any': 'off',
		},
	},
];
