/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        // Daylight coastal palette. Text colors meet WCAG AA on `bg` and white.
        ink: '#0c2530',
        muted: '#46616b',
        line: '#d5e5e9',
        bg: '#f4fafb',
        teal: {
          DEFAULT: '#006575',
          dark: '#004b57',
          soft: '#e0f2f4',
          mint: '#7fe0d4',
        },
        sand: { soft: '#fff3dc', ink: '#7a4300' },
        lilac: { soft: '#eef0ff', ink: '#38448a' },
      },
      fontFamily: {
        sans: ['"IBM Plex Sans Arabic"', '"IBM Plex Sans"', 'system-ui', 'sans-serif'],
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-6px)' },
        },
      },
      animation: {
        float: 'float 7s ease-in-out infinite',
      },
    },
  },
  plugins: [],
};
