# Spec: Ship audit armed by what the diff touches
Token profile: standard

## Objective
On a `critical` profile, `/loop:ship` step 1bis still runs one `security-auditor`, but on the surfaces the diff actually touches, not on the surface the profile reason names. A diff that touches no server code gets no `authz` audit; a front diff that touches session or rendering of untrusted input gets the surface that can break there; a diff that touches none of them runs no auditor and says why in one line. The auditor's Majors and Minors stop being lost: they land in `follow-ups.md`.

## Evidence (ecocrew, transcripts 2026-10-12 → 2026-10-24, git history of the same window)

53 `security-auditor` launches, 44 readable reports (9 launches left no subagent transcript). Nearly every `/loop:ship` was `critical` (46 ship invocations, ~41 ship audits): on ecocrew every endpoint is multi-tenant, so "a new table or endpoint" arms it.

| Surface | Audits | Critical | Major |
| --- | --- | --- | --- |
| `authz` | ~35 | 0 | 0 |
| `session` | 6 | 0 | 2 (whole-repo audit of 2026-10-12, likely outside ship; led to the `session-expired-stuck` fix) |
| `input-output` | 4 | 0 | 3 conditional (DWG import, story 2.1, closed by `dwg-import-hardening`) + 1 on old code outside the diff |

- No ship was ever stopped by step 1bis. Its one measured value is the `input-output` Majors of story 2.1, and they were acted on only because someone remembered them: today a Major at 1bis is written nowhere.
- `authz` audits ran on commits that touch no server file: `5d1d711` (quantity-takeoff 1.6), `9d61686` (refonte 1.5), `ff0f958` (refonte 2.1), all with 0 file under `backend/`. Their reports conclude "no new server call" or "nothing to report". 31 of the 81 commits of the window touch no `backend/` file.
- `session` audits on front-only diffs (refonte 1.1-1.4) checked a real risk, the previous user's state leaking to the next one; `944e45b fix(auth): drop the previous user's cache, clipboard and drafts on a user change` shows the class exists on the front.
- Cost per audit: ~1.5 min, ~3.7k output tokens, ~0.8M context tokens mostly cache reads (usage summed from subagent transcripts, approximate).

Rejected alternatives (2026-11-05):
- Drop step 1bis: the `input-output` Majors of the DWG import are a measured catch; a single auditor is cheap.
- Let the main thread pick surfaces by judgment alone: the same reading that armed `authz` on front-only diffs; the floor must be mechanical.
- Change what makes a profile `critical` (`11-token-budget.md`): it also drives review fan-out; a separate measure, not this spec.

## Scope
- IN :
  - **A1. Surfaces from the diff.** On `critical`, step 1bis (`ship.md:76-92`) computes the ship diff (base of the track, untracked files included) and runs `.claude/hooks/kit-audit-surface.py`, which returns the surfaces to audit with one reason each:
    - `authz`: at least one changed path under the project's server roots (routes, services, models, migrations, RLS policies).
    - `session`: added or changed lines that touch sign-in, sign-out, user switch, token or cookie handling, client caches or persisted per-user state (query-cache clear/reset, store reset, `localStorage`/`sessionStorage`/`indexedDB`).
    - `input-output`: added lines that render or follow untrusted input (`dangerouslySetInnerHTML`, `innerHTML`, a `href`/`src`/navigation built from data, `target="_blank"`), file upload or parsing, a boundary schema (Zod on a request or an API response) added or loosened, a webhook or callback.
    The plan fixes the exact path roots and line triggers; the script is the only copy.
  - **A2. The profile reason still counts, inside the diff.** The reason table (`ship.md:82-88`) is kept as a second source: its surface is added when the diff touches that surface's paths or triggers. Payment with a webhook still adds `input-output` when the webhook code changed. An explicit user request runs what the user asked, whatever the script returns.
  - **A3. The main thread may add, never remove.** It may add a surface the script missed, with a one-line reason in the ship report; it never drops one the script returned. One `security-auditor` receives all selected surfaces (`/audit:security` already lets one agent own several).
  - **A4. Nothing selected → not armed, said.** When no surface is selected, no auditor runs and the ship report prints `Audit: not armed — diff touches no audit surface (<the script's one-line reason>); review security ran`. The review `security` dimension is unchanged and still read the diff.
  - **A5. Follow-ups.** Every Major and Minor of the 1bis audit is appended to `docs/work/<slug>/follow-ups.md`, same line format as `review-convergence` C2, dimension `audit:<surface>`. The blocking rule is unchanged: only a Critical stops the ship. The ship report prints the Major count and the path.
  - **A6. Server roots declared once.** The server roots are declared in one place read by the script (the plan picks it: the `## Backend` section of `02-architecture.md` or a kit config line), filled by `/kit:init` and the backend addons (FastAPI `backend/`, Supabase `supabase/`), and checked by `/kit:doctor` against the enforced copy. A front-only project with no declared root never selects `authz` from paths.
  - **D1. Docs.** `.claude/guides/ship.md` "Why `critical` arms an audit" (`guides/ship.md:37-44`) and `docs/Claude_Workflows.md` in French: the surface follows the diff, not armed is said, follow-ups.
- OUT :
  - `/audit:security` itself (surfaces, fan-out, refutation), the review `security` dimension, `pnpm audit` and the bundle secret grep at step 1.
  - What makes a profile `critical` (`11-token-budget.md`).
  - The ship blocking rule (Critical only) and step 1bis' place before the commit.
  - No new agent.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/commands/loop/ship.md` (1bis), `.claude/guides/ship.md`, new `.claude/hooks/kit-audit-surface.py` and its suite `.claude/hooks/test-audit-surface.sh` (registered where `test-attempts.sh` is, `install.sh` and kit-ci included), the server-roots declaration and its `/kit:doctor` check, the FastAPI and Supabase addon copies, `.claude/hooks/test-workflow-contracts.sh`, `docs/Claude_Workflows.md`.

## Acceptance criteria
- [ ] A `critical` ship whose diff touches no server root runs no `authz` audit.
- [ ] A `critical` ship whose diff changes a route, a service, a model or a migration under a server root runs `authz`.
- [ ] A front-only diff that changes sign-out or a client-cache reset runs `session`; one that adds `dangerouslySetInnerHTML` or an upload runs `input-output`.
- [ ] A diff with no selected surface runs no auditor and the report prints `Audit: not armed — …; review security ran`.
- [ ] Several selected surfaces go to one `security-auditor`.
- [ ] The main thread can add a surface with a reason; a surface the script returned is never dropped.
- [ ] An explicit user request runs the requested surfaces regardless of the script.
- [ ] Every Major and Minor of the 1bis audit is in `follow-ups.md`; a Critical still stops the ship.
- [ ] `economy`/`standard` ships unchanged: no auditor, report `not armed — profile …`.
- [ ] `test-audit-surface.sh`, `test-workflow-contracts.sh`, `test-hooks.sh`, `kit-doctor`, `test-rules-floor.sh` pass.

## Business logic to cover
No TypeScript. Two layers, test-first.

Behaviour, in `test-audit-surface.sh` against `kit-audit-surface.py` (hand-written diff fixtures, expected surfaces literal):
- S1 front files only, no trigger line → no surface, reason names "no server root, no trigger".
- S2 a changed file under a server root (route, service, migration) → `authz`; an untracked new file under it → `authz`; a rename into it → `authz`.
- S3 front-only, added `queryClient.clear()` or a store reset in a sign-out path → `session`, no `authz`.
- S4 front-only, added `dangerouslySetInnerHTML` / a `href` from data / a file input → `input-output`, no `authz`.
- S5 a trigger word in a removed line or a comment only → no surface.
- S6 server root plus a session trigger → `authz` and `session`, one call.
- S7 no server root declared → `authz` never selected from paths.

Wording, in `test-workflow-contracts.sh`, each failing on today's files:
- T1 `ship.md` 1bis: contains `kit-audit-surface.py`, `not armed`, `follow-ups.md`, and "never drops".
- T2 `guides/ship.md`: the "Why `critical` arms an audit" section names the diff as the selector.

What neither layer proves: that the trigger list catches every risky front change. The main thread's add (A3) and the review `security` dimension remain the backstop; the measure below checks it.

## Order
After the harness passes and after `review-convergence` (A5 reuses its `follow-ups.md` format). If it ships first, it creates `follow-ups.md` with that same format.

## Measure after
On the next 10 ecocrew `critical` ships, then 30: audits run vs not armed, surfaces selected, auditor tokens and duration per ship, against the baseline above (~41 audits for 46 ships, ~35 `authz`). Target: no `authz` audit on a diff without a server file, total auditor tokens down. Revert criterion: one Critical or Major found later (review, `/audit:security`, a bug report) on a surface the selector skipped for that ship.
