# Repository Guidelines

## Project Structure & Module Organization
- `MOSSU.xcodeproj` and `MOSSU macos/`: macOS app (Swift) and resources.
- `MOSSU macosTests/` and `MOSSU macos/MOSSU macosTests/`: XCTest suites.
- `api/slack/oauth/`: serverless Slack OAuth handler (`callback.js`) and tests.
- `public/`: release artifacts (ZIP, `appcast.xml`, images).
- `deploy.sh`: version bump, build, sign, and package script.

## Build, Test, and Development Commands
- macOS app (Xcode): open `MOSSU.xcodeproj` and run scheme `MOSSU`.
- macOS app (CLI): `xcodebuild -scheme MOSSU -configuration Debug build`
- Backend tests: `npm ci && npm test` (Node 18+, ESM, `node --test`).
- Release: `./deploy.sh` (bumps version/build, archives, signs, zips, appcast).

## Coding Style & Naming Conventions
- Swift: 4‑space indentation; types `UpperCamelCase`, methods/vars `lowerCamelCase`.
  Files mirror types (e.g., `SlackStatusManager.swift`, `Office.swift`).
- JS (api): ESM modules, single quotes preferred, end lines with semicolons.
  Handlers export `default` and follow Vercel‑style paths (`api/.../callback.js`).
- Keep functions small and focused; log via existing utilities (e.g., `LogManager`).

## Testing Guidelines
- Swift: place tests in `MOSSU macosTests/*.swift`; subclass `XCTestCase`.
  Name tests descriptively: `OfficeTests`, `SlackStatusManagerTests`.
- JS: place tests in `__tests__/*.test.js` alongside code.
- Run locally before PRs: Xcode test action or
  `xcodebuild -scheme MOSSU test -destination 'platform=macOS'` and `npm test`.

## Commit & Pull Request Guidelines
- Commits: short, imperative summaries (e.g., “tweak download button”).
  Group related changes; avoid noisy formatting‑only commits.
- PRs: include scope/intent, testing notes, and screenshots for UI changes
  (menu bar/status or `public/` assets). Link issues when applicable.

## Security & Configuration Tips
- Never commit secrets. Configure env vars for OAuth backend:
  `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, `SLACK_REDIRECT_URI`, `FRONTEND_URL`.
- Validate redirects locally; example endpoint: `/api/slack/oauth/callback`.
- Keep `deploy.sh` signing identity and project settings up to date.
