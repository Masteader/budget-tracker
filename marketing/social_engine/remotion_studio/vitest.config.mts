import {defineConfig} from 'vitest/config';

// Components are rendered with react-dom/server, so no DOM library is needed.
export default defineConfig({
	test: {
		environment: 'node',
		include: ['src/__tests__/**/*.test.{ts,tsx}'],
		testTimeout: 120_000,
	},
});
