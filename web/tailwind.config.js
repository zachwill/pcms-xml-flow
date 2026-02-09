/**
 * Tailwind config (Rails)
 *
 * Mirrors the React prototype (prototypes/salary-book-react/src/index.html).
 *
 * NOTE: tailwindcss-rails v4 runs the Tailwind CLI without passing --config,
 * so this file must live at the Rails root as tailwind.config.js.
 */

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./app/views/**/*.{erb,haml,html,slim}",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/assets/tailwind/**/*.css",
  ],
  darkMode: "class",
  theme: {
    extend: {
      fontFamily: {
        sans: ["Inter", "system-ui", "sans-serif"],
        mono: [
          "ui-monospace",
          "Cascadia Code",
          "Source Code Pro",
          "Menlo",
          "Consolas",
          "DejaVu Sans Mono",
          "monospace",
        ],
      },
      colors: {
        border: "var(--border)",
        background: "var(--background)",
        foreground: "var(--foreground)",
        muted: {
          DEFAULT: "var(--muted)",
          foreground: "var(--muted-foreground)",
        },
        primary: {
          DEFAULT: "var(--primary)",
          foreground: "var(--primary-foreground)",
        },
        destructive: {
          DEFAULT: "var(--destructive)",
          foreground: "var(--destructive-foreground)",
        },
      },
      keyframes: {
        "slide-down-fade": {
          from: { opacity: "0", transform: "translateY(-26px)" },
          to: { opacity: "1", transform: "translateY(0px)" },
        },
        shimmer: {
          "100%": {
            transform: "translateX(100%)",
          },
        },
        "progress-indeterminate": {
          "0%": { transform: "translateX(-100%)" },
          "100%": { transform: "translateX(400%)" },
        },
        pulse: {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.5" },
        },
      },
      animation: {
        "slide-down-fade": "slide-down-fade 0.3s ease-in-out",
        shimmer: "shimmer 2s ease-in-out infinite",
        "progress-indeterminate": "progress-indeterminate 1.5s ease-in-out infinite",
        pulse: "pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite",
      },
    },
  },
};
