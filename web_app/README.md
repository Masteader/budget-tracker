# Budget Tracker — Web App

React 19 + TypeScript + Vite + TailwindCSS landing page (Daylight Coastal theme, Arabic RTL and
English, payday simulator, VIP early-access form). The only backend call is the anonymous
`POST /public/inquiries` (see [`src/lib/inquiries.ts`](src/lib/inquiries.ts)).

## Develop

```bash
npm ci
npm run dev       # Vite dev server
npm run lint      # oxlint
npm run build     # tsc -b && vite build → dist/
```

There are no unit tests; lint and the type-checked build are the checks.

## Configuration (`.env`, see [`.env.example`](.env.example))

| Variable | Effect |
|---|---|
| `VITE_API_BASE_URL` unset | Form posts to `https://budget.fmsco.com.sa` |
| `VITE_API_BASE_URL=` (empty) | Same origin: use this for the build served by `ai_service` |
| `VITE_API_BASE_URL=http://localhost:8000` | Local backend (its CORS defaults allow ports 3000, 5173 and 8080) |

## Publish

The production page at `/` is this app's build committed in `ai_service/static/`. After changing
`web_app/`, rebuild with `VITE_API_BASE_URL=` and copy `dist/index.html` and `dist/assets/` there
(exact commands in the root [`README.md`](../README.md#contact-support-and-vip-early-access-email)).
Translations live in `src/i18n/translations.ts`.
