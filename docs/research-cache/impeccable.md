---
topic: impeccable
checked: 2026-09-20
stability: volatile
sources:
  - https://raw.githubusercontent.com/pbakaus/impeccable/main/README.md
  - https://api.github.com/repos/pbakaus/impeccable/releases
  - https://registry.npmjs.org/impeccable/latest
  - https://impeccable.style/docs
  - https://raw.githubusercontent.com/pbakaus/impeccable/main/skill/reference/init.md
  - https://github.com/pbakaus/impeccable/issues/427
  - (web search result snippets, not opened pages: PRODUCT.md / register query)
---

Note: answers below come from a small-model summary of each page, not verbatim reads. Re-verify any exact command before coding against it.

## 1. Install methods for Claude Code
- Plugin marketplace (README "recommended"): `/plugin marketplace add pbakaus/impeccable`, then open `/plugin` and install. README table: lands in `~/.claude/` (user scope).
- `npx impeccable install`: detects harness folders, prompts for provider; installs skill + hook manifest into project `.claude/` or global `~/.claude/`.
- Manual: `cp -r dist/claude-code/.claude your-project/` (project) or `cp -r dist/claude-code/.claude/* ~/.claude/` (global). `dist/` is in the repo.
- On disk: `.claude/skills/impeccable/` (scripts/ launcher + config). One skill name: `impeccable`. Hooks need `npx impeccable install` or manual `.claude/settings.local.json` entries.
- Update: `npx impeccable update`.

## 2. Command list and invocation
All via `/impeccable <command> [target]`. Foundation: init, craft, shape, document, extract. Quality: critique, audit, polish, harden. Direction: bolder, quieter, distill, colorize, typeset, layout. Enhancement: animate, delight, overdrive, onboard. Optimization: clarify, adapt, optimize. Live: live, generate.
- critique: UX design review (hierarchy, clarity, emotional resonance).
- audit: technical quality (a11y, performance, responsive), optional target.
- polish: final pass, design-system alignment, shipping readiness.
- `detect` is not a slash command; it is the npm CLI (Q3).
- `/impeccable pin audit` creates a `/audit` shortcut command.
- Interactive session need: not stated in the sources read. They are prompt-driven skill commands, so they run inside an agent session; init interviews the user.

## 3. Deterministic detector (standalone CLI)
- Package `impeccable` on npm, `npx impeccable detect <target>`. Latest npm version 4.1.0, `bin: cli/bin/cli.js`, `engines.node >=22.18.0` (README says Node only needed for the npx shim; the engine binary runs standalone).
- Targets: directories, HTML files, URLs (URLs need installed Chrome/Chromium/Edge). Scans rendered DOM, computed layout, linked stylesheets. "61 deterministic issues". VERIFIED 2026-09-20 on impeccable@4.1.0, Node 24: non-HTML files (JSX/TSX/CSS) are regex-scanned and report file:line; HTML is statically analysed; URLs use Puppeteer. Exit 0 clean / 1 target unreadable / 2 findings, same in text and --json mode. A directory with nothing scannable exits 0 with `[]`; an unknown path exits 1. The npm package has no install scripts and no `context` command; `detect` loads a local DESIGN.md without error (a pointer file is accepted).
- Flags: `--json` (stdout), `--no-config`, `--no-inline-ignores`.
- Exit codes: 0 = no primary findings; 1 = a target could not be scanned; 2 = primary findings.
- CI/non-interactive: yes. README example: `npx impeccable detect --json . > findings.json`.
- Note: this repo's Node floor (20.19+ / 22.12+ in 01-stack.md) is below the package's `>=22.18.0`.

## 4. init / PRODUCT.md / DESIGN.md
- PRODUCT.md written by `/impeccable init` (agent interview + exploration, asks only for material gaps). Path: `PROJECT_ROOT/PRODUCT.md`, resolved by `impeccable context`; child apps in a monorepo ask shared vs app-specific scope.
- Format: markdown with marker `<!-- impeccable:product-schema 1 -->`; ten canonical sections: Platform, Users, Product Purpose, Positioning, Operating Context, Capabilities and Constraints, Brand Commitments, Evidence on Hand, Product Principles, Accessibility & Inclusion (plus Stack for greenfield). Omit irrelevant sections.
- DESIGN.md: NOT written by init. Written by `new-work` (new visual world) or `/impeccable document` (records incumbent design from code). Also root.
- Missing PRODUCT.md: init.md says init is incomplete until the file exists; interview notes cannot substitute. Whether other commands hard-fail or prompt when it is absent: not found in what was read.
- Overwrite: init updates an existing PRODUCT.md ("never silently overwrite"), asks what is stale; legacy files get only missing durable facts; an existing DESIGN.md is left untouched.
- Thin pointer file: not documented as acceptable; init.md treats the real file with content as the completion requirement. A pointer is unverified and likely not satisfying the schema marker/sections.

## 5. Brand vs product mode
- Old model (v3 and earlier, still in README/spec text): `## Register (brand | product)` in PRODUCT.md.
- Retired in v4 (issue #427): replaced by four visitor modes, Persuade / Operate / Read / Experience, chosen per surface and persisted in that surface's brief, not per project. README still contains outdated v3 wording.

## 6. License, version, caveats
- License: Apache-2.0 (README and npm).
- Latest (releases API, 2026-09-08/09): Skill 4.3.1 (2026-09-09), Skill 4.3.0, Skill 4.2.3, Engine 0.1.5, CLI 4.1.0 (npm `impeccable` latest = 4.1.0). Separate versioning for skill, CLI, engine.
- Caveats: Claude Code needs hooks installed via `npx impeccable install` or manual settings.local.json; hooks respect per-app config in monorepos since 4.2.3; live mode unsupported on HTTPS/production sites, use only on trusted local projects; optional `scripts["impeccable:manual-edit-validate"]` in package.json; Windows/managed-network fixes in 4.2.3/4.3.1. Install may write hooks into settings, which interacts with this kit's own hooks (not investigated).

## Not found
- Whether critique/audit/polish require an interactive session (not stated).
- (resolved) `detect` parses JSX/TSX by regex; see Targets.
- Whether commands fail vs prompt when PRODUCT.md is missing (beyond init).
- Any doc endorsing a thin/pointer PRODUCT.md.
- No Claude-Code-specific breaking-change notes in the last 5 releases.
