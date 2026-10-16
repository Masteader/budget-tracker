/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        "primary": "#006575",
        "primary-container": "#008093",
        "on-primary": "#ffffff",
        "on-primary-container": "#f8fdff",
        "secondary": "#006c4d",
        "secondary-container": "#73fbc4",
        "on-secondary": "#ffffff",
        "on-secondary-container": "#007352",
        "tertiary": "#4f5b7e",
        "tertiary-container": "#687498",
        "on-tertiary": "#ffffff",
        "surface": "#faf9ff",
        "surface-dim": "#d4d9ec",
        "surface-bright": "#faf9ff",
        "surface-container-lowest": "#ffffff",
        "surface-container-low": "#f1f3ff",
        "surface-container": "#e9edff",
        "surface-container-high": "#e3e8fb",
        "surface-container-highest": "#dde2f5",
        "on-surface": "#161b29",
        "on-surface-variant": "#3d494c",
        "outline": "#6d797c",
        "outline-variant": "#bdc9cc",
        "background": "#faf9ff",
        "on-background": "#161b29",
        "error": "#ba1a1a",
        "electric-teal": "#00e5bf",
        "ice-cyan": "#4de6f7",
        "deep-navy": "#0b1528",
        "navy-slate": "#15243e"
      },
      fontFamily: {
        sans: ["IBM Plex Sans", "IBM Plex Sans Arabic", "Inter", "sans-serif"],
        display: ["IBM Plex Sans", "IBM Plex Sans Arabic", "sans-serif"],
        mono: ["IBM Plex Sans", "monospace"]
      }
    },
  },
  plugins: [],
}
