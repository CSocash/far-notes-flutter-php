# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

FAA Regulations Study Log: a local, single-machine study tracker for Part 61 and Part 91 regulations. This repo is the PHP + Flutter rewrite of the original Node/Capacitor app (still in the upstream repo `far-notes-playwright-agentic`), kept to the same API contract, rules and page labels, so the same pytest suite proved both before the Node code was removed.

- **Server:** plain PHP (8.2+, no framework, no Composer) in `backend/`, with PDO SQLite and libsodium, run by PHP's built-in web server (`php -S`). PHP is installed with php.new at `~/.config/herd-lite/bin`.
- **Website:** vanilla HTML/CSS/JS with no build step, at the repo root, served by the PHP router.
- **App:** Flutter (3.50, Material from `package:material_ui`) for iOS and Android in `app/`. Flutter is at `~/development/flutter/bin`.
- The `.claude/skills/` docs and the "Business Rule: server.js ›" labels in `docs/test-scenarios.md` still name the old Node code; the PHP equivalents are in `backend/router.php` (camelCase names became snake_case, e.g. `isAllowedOrigin` → `is_allowed_origin`).

## Commands

- `npm start` (= `sh backend/start.sh`) — runs the migrations (`backend/migrate.php`), then `php -S` with `backend/router.php` on http://127.0.0.1:3000 (override with `PORT` and `HOST`, e.g. `HOST=0.0.0.0` to reach it from a phone on the LAN). `PHP_CLI_SERVER_WORKERS` (default 4) sets how many requests run at once.
- `INITIAL_PASSWORD='at-least-15-chars' npm run setup-user` (= `php backend/setup-user.php`) — creates the initial account (defaults `VMC43` / `VMC43@test.com`, override with `INITIAL_USERNAME` / `INITIAL_EMAIL`). Refuses to overwrite an existing account.
- Password reset has no email service: `POST /api/auth/forgot-password` prints a one-time reset link (30 min expiry) to the server terminal.
- The app must be loaded through the server, not by opening `index.html` directly.
- Flutter app (`app/`): `flutter run` from `app/` (start the server first), `flutter analyze`, `flutter test` (unit tests for `lib/core.dart`). Without `--dart-define=FAR_NOTES_API_URL=...`, the iOS Simulator calls `http://127.0.0.1:3000` and the Android emulator calls `http://10.0.2.2:3000`. Code is formatted with `dart format lib test` (120 columns).
- Tests are Python: pytest + pytest-playwright (Playwright 1.64, Chromium).
  - One-time setup: `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt && .venv/bin/playwright install chromium`.
  - `.venv/bin/pytest` runs everything.
  - `.venv/bin/pytest -m api`, `-m component`, `-m e2e` or `-m smoke` runs one group. The layer markers come from the test's folder.
  - `.venv/bin/pytest -k tc_002` runs a single test.
  - `.venv/bin/ruff check tests` lints the Python (rules in `ruff.toml`: core bug checks only, 120 columns). The pipeline runs it before the tests, and a `PostToolUse` hook in `.claude/settings.json` runs it on every Python file Claude edits, reporting problems back (exit code 2) so they're fixed right away.
  - `.venv/bin/pytest --run-device -m device` runs the Appium tests in `tests/device`: the Flutter app on the iPhone 17 Simulator (XCUITest driver) and on the `Pixel_10_Pro` Android emulator (UiAutomator2 driver; started for the session unless one is running). Add `-k ios` or `-k android` for one platform. They are left out of plain runs. Each session builds the app with `flutter build` against the test server on port 3100 (the emulator reaches it as `10.0.2.2`) and copies it to `.test-data/`. Add `--slowmo 1000` to watch it step by step.
  - Appium and Flutter: elements are found by the same accessible names as the website ("Mark 91.103(a) as covered"). Flutter builds only list rows on or near the screen, so the page objects scroll until a row is visible and at rest before tapping. Android shows a text box's label only as a hint, so the sign-in fields carry test ids (`Semantics(identifier:)`, Android `resource-id`).
  - Allure report: `.venv/bin/pytest --alluredir=allure-results --clean-alluredir`, then `npx allure@3.22.1 generate allure-results` and `npx allure@3.22.1 open allure-report` (plain `npx allure` runs an old Allure 2 install).
  - Load tests use Locust (`tests/load/locustfile.py`, not collected by pytest). Install with `.venv/bin/pip install -r requirements-load.txt`. Start a throwaway server with `FAR_NOTES_DB=.test-data/load.sqlite FAR_NOTES_DISABLE_RATE_LIMIT=1 PORT=3300 npm start`, then run `.venv/bin/locust -f tests/load/locustfile.py --host http://127.0.0.1:3300` (web UI on http://localhost:8089, or add `--headless -u 10 -r 2 -t 30s`). Never point it at port 3000.
  - The one exception is unit tests for the JavaScript helpers. They use Node's built-in runner, `node --test tests/unit` (none written yet).
  - A session fixture in `tests/conftest.py` starts its own server (`backend/start.sh`) on port 3100 with `FAR_NOTES_DB=.test-data/far-notes-test.sqlite` and `FAR_NOTES_DISABLE_RATE_LIMIT=1`, so tests never touch `data/part91.sqlite`. Its output goes to `.test-data/*.log`, never an unread pipe: `php -S` logs every request and blocks when a pipe fills.
  - `--base-url` points the tests at another server (reused if it answers; a remote one must already be running). Port 3000, the dev server with the real `data/part91.sqlite`, is refused unless you add `--allow-dev-server`.
  - Test browsers stay offline: Chromium runs with its sandbox on, and every request not to the server under test (Google Fonts, eCFR) is blocked. A context a test creates itself with `browser.new_context` needs `block_outside_requests` from `tests/support/network.py`.
  - Test conventions are in the `playwright-best-practices` skill.

## Architecture

**`backend/` is the whole server** (plain PHP, every file `declare(strict_types=1)`):

- `router.php` — the router for `php -S`. Every request goes through it, so the built-in server never serves a file from disk on its own. Handlers throw `HttpError(status, message)`, answered as `{"error": message}`; anything else is a logged 500.
- `database.php` — `open_database()` (PDO, `busy_timeout` 5000, foreign keys on), the `rows`/`row`/`run` query helpers, the subsection catalog, `create_starter_regulations_for_user` and `migrate()`.
- `migrate.php` — runs `migrate()` once per server start (PHP keeps nothing between requests, so start-up work can't live in the router).
- `passwords.php` — scrypt through libsodium (`sodium_crypto_pwhash_scryptsalsa208sha256`, opslimit 524288 = N 16384, r 8, p 1, 64-byte key, 32-character hex salt), identical to the old Node server's hashes, so its accounts still sign in.
- `validation.php` — `is_iso_date`, `check_username`, `check_email`, `check_password`, each returning the client error message or `null`.
- `starter-regulations.php` — the built-in starter headings (`STARTER_REGULATIONS['91' | '61']`).
- `setup-user.php`, `start.sh`.

- **Startup migrations run on every boot.** `CREATE TABLE IF NOT EXISTS` plus `PRAGMA table_info` checks add columns (`part`, `is_locked`, `user_id`) to older databases. It then (re)seeds starter lists per user, re-locks starter rows, and back-fills `regulation_subsections` for every regulation from `regulation-subsections.json` (`INSERT OR IGNORE`, and subsection titles are overwritten from the catalog). Schema changes must stay idempotent and must preserve existing user data — legacy section-level `covered/date/notes` are copied down into subsections.
- **Data model:** `users` → `regulations` (per user, per `part` "61"/"91"; `is_locked=1` marks built-in starter headings) → `regulation_subsections` (one row per lettered paragraph `code`, or a single row with `code=''` / "Entire section" when the catalog has none). Coverage, date, and notes live on **subsections**, not regulations. Also `sessions` and `password_resets`, which store only SHA-256 hashes of tokens, and `rate_limits` (the auth rate limits, emptied on each start, since PHP has no memory between requests).
- **Starter lists** are `[sectionNumber, heading]` pairs. The section number is parsed from the heading text (`/^\s*(\d+\.\d+)/`) to look up subsections in `regulation-subsections.json` (eCFR snapshot dated 2026-06-01, `parts[part][section] = [{code, title}]`).
- **Routing** is a chain of path/method checks in `handle_auth_request` (`/api/auth/*`: me, login, register, logout, forgot-password, reset-password) and `handle_api_request` (`GET/POST /api/regulations`, `PATCH /api/regulations/:id`, `PATCH /api/subsections/:id`). Every regulation API call needs `?part=61|91`. Static files come from the `STATIC_FILES` allowlist plus `PUBLIC_PATHS` — **a new frontend file has to be registered in both** — and the tracker files in `TRACKER_PATHS` (`/`, `/index.html`, `/app.js`, `/app-core.js`) require auth (they redirect to `/login`).
- **Security conventions to keep:** state-changing requests check `is_allowed_origin` (same origin or one of the app origins in `FAR_NOTES_APP_ORIGINS`); requests from an app origin authenticate only by `Authorization: Bearer` (`session_token`), never the cookie, and the login body includes the token only for `X-Far-Notes-Client: app`; auth endpoints use `consume_rate_limit`; passwords use scrypt with a per-user salt (minimum 15 characters, max 1024 bytes); session cookie `study_session` is HttpOnly + SameSite=Strict, 7-day TTL; every query is scoped by `user_id`; locked headings reject PATCH with 403; there is no delete endpoint by design.

**Shared pure logic** (no DOM, network or globals, so `node --test` can unit-test it):
- `app-core.js`: `sectionNumber`, `ecfrUrl`, `referenceFor`, `normalizeQuery`, `matchingSubsections(regulation, query, filter)`, `summarize` and `localDate(now)`. It's a classic script wrapped in a function. In the browser it sets `window.FarNotesCore`, which `app.js` reads (`index.html` loads it first), and under Node it exports the same object with `module.exports`.

**Website frontend:** every page loads `api-client.js` first and makes requests and redirects through `FarNotesApi.fetch` / `FarNotesApi.goTo` (never bare `fetch` or `location.replace`). Each HTML page has its own script (`login.js`, `create-account.js`, `forgot-password.js`, `reset-password.js`). `app.js` drives the main tracker: it loads a part via `apiRequest` (which redirects to `/login` on 401), renders section rows and subsection rows from `<template>` elements in `index.html`, links citations to eCFR, and autosaves edits through `queueSave` → `persistItem` (350 ms debounce, with one serialized promise queue per item so PATCHes don't race).

**Flutter app (`app/lib`):** `core.dart` ports `app-core.js` (same names and behavior; unit tests in `app/test`), `api.dart` calls the server with `X-Far-Notes-Client: app` and keeps the bearer token in `shared_preferences`, `save_queue.dart` autosaves like `queueSave` (350 ms debounce, one serialized queue per item), and `screens/` holds sign-in, create account, forgot password and the tracker. Keep its accessibility labels identical to the website's; the Appium page objects (`tests/pages/ios_app.py`, `tests/pages/android_app.py`) depend on them. App id: `com.farnotes.studylog`. Plain `http` is allowed only to local addresses (iOS `NSAllowsLocalNetworking`, Android `network_security_config.xml`).

The database (`data/*.sqlite*`) is gitignored.
