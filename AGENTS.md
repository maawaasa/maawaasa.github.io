# AGENTS.md

Guidance for AI agents working on the مأوى (MAWA) website.

## Repository scope

- The git repo root is this folder (`مأوى MAWA/ويب/`). The OneDrive parent directory holds unrelated design assets (PDFs/SVGs/PNGs) and is **not** part of the site — do not reference or commit anything outside `ويب/`.
- Static marketing site for a Saudi real-estate photography company. Arabic, RTL (`<html lang="ar" dir="rtl">`).
- No build step, no framework, no `package.json`, no tests, no lint/typecheck. Verify changes by opening the HTML file in a browser.

## Deploy

- `git push origin main` publishes to GitHub Pages at **https://maawaa.sa/**. There is no staging environment — the `main` branch is live.
- Commit messages are written in Arabic (see `git log`); follow that convention.

## Architecture

Three self-contained pages, each with its own inline `<style>` and `<script>`:

| File | Purpose | Supabase |
|------|---------|----------|
| `index.html` | Public marketing page (indexable) | no |
| `form.html` | Service-request form (noindex) | yes — inserts |
| `admin.html` | Private contract-management tool (noindex, `robots.txt` disallow) | yes — full CRUD |

- **There is no shared CSS or JS file across pages.** Design tokens (CSS custom properties on `:root`) and the Supabase bootstrap are **duplicated** in each page. If you change a token or a query, update every page that needs it.
- Note: variables named `--gold*` are actually blue (`#7AAAD4`) — preserve the existing names; do not "fix" them.

## Backend (Supabase)

- Loaded via CDN (`@supabase/supabase-js@2`); config in `assets/js/supabase-config.js` exposes `getSupabase()` (form.html/admin.html wrap it locally as `sb()`).
- The anon key in `supabase-config.js` is a public client key (safe in frontend), not a secret — leave it in place.
- Tables: `clients`, `contracts`, `contract_services` (services are inserted after a contract is created; editing a contract deletes then re-inserts its services).
- `admin.html` also uses `html2pdf.js` (CDN) for PDF export of contracts.

## Conventions

- All libraries are CDN-loaded; never add npm dependencies.
- Fonts: Tajawal from Google Fonts.
- Keep new content and copy in Arabic; preserve RTL layout and the glassmorphism style.
- `robots.txt` / `sitemap.xml` must stay in sync with the live URLs.
