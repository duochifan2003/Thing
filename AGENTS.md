# Repository Guidelines

## Project Structure & Module Organization

- `app/` contains the React interface and browser-side archive behavior. Keep page-level UI in `app/page.tsx`; place focused storage or queue helpers beside it (for example, `app/archive-store.mjs`).
- `tests/` holds Node built-in test-runner checks. Tests currently validate the important local-first workflows and source-level integration points.
- `db/` and `drizzle/` contain the Drizzle schema, configuration, and generated migration metadata. The `examples/d1/` directory is a separate D1 example.
- `desktop/` contains the macOS Cocoa/WebKit shell, App Group storage bridge, widget extension, and Xcode project. `desktop/build-site.sh` packages the web app for Xcode builds.
- `public/` contains static web assets; `audit/` contains README screenshots.

## Build, Test, and Development Commands

Use Node.js 22.13 or later and install locked dependencies with `npm ci`.

- `npm run dev` starts the Vite/Cloudflare local development server.
- `npm run build` produces a production build; run this before testing deployment-sensitive changes.
- `npm run start` serves the completed production build locally.
- `npm test` builds first, then runs `node --test tests/*.test.mjs`.
- `npm run lint` runs ESLint with the Next.js core-web-vitals and TypeScript rules.
- `npm run db:generate` creates Drizzle migration artifacts after an intentional schema change.

For macOS work, open `desktop/PersonEventAtlas.xcodeproj` in Xcode 15+ and run the `PersonEventAtlas` target. Verify widget and deep-link changes in the app and the Widget extension.

## Coding Style & Naming Conventions

Follow existing TypeScript, React, JavaScript, and Swift conventions: two-space indentation in web files and four spaces in Swift. Use `PascalCase` for React components and Swift types, `camelCase` for functions and variables, and descriptive kebab-case for static asset names. Keep strict TypeScript compatible; avoid `any`. Run `npm run lint` before submitting web changes.

## Testing Guidelines

Add or update `tests/*.test.mjs` tests for user-visible archive behavior, data persistence, import/export, date handling, and desktop bridge contracts. Use `node:test` with `node:assert/strict`; name tests as readable behavior statements, such as `"serializes saves after a failed write"`. Run `npm test` before a pull request.

## Commit & Pull Request Guidelines

Recent history uses brief, imperative summaries (for example, `Add macOS desktop widget support`). Keep each commit scoped to one coherent change. Pull requests should explain the user impact, list verification commands, link the related issue when available, and include screenshots for UI or widget changes. Call out any IndexedDB migration, App Group storage, or generated migration impact explicitly.
