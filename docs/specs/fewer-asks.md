# Spec: Fewer asks — fix the false asks and the questions with no decision behind them
Status: DRAFT — pass 1 of 4, split from `docs/specs/fewer-validations.md` on 2026-11-09 (items V1-V4, V6, V11 as reviewed 2026-11-08). Next: `kit-boundary.md`, `loop-to-pr.md`, `auto-mode.md`.
Token profile: standard (it loosens a few guards — anchored flags, removal-only `.tdd-unfrozen` Edits, `git -C` one-line commits — and adds denies; no new trust mechanism)

## Objective
Remove the permission prompts and chat stops that ask the user nothing worth deciding, without changing who decides what: hook false positives, improvised `cd x;` prefixes, shell writes that should be Write/Edit, repeated `.tdd-unfrozen` asks, and questions whose answer is already known. Nothing here leaves the machine or widens what an agent may do alone.

## Evidence (EcoCrew `feat/metre-tableur-prix`, 2026-11-07/08)
Source: transcripts `b1c9ddda`, `8b64b672` (+ framing `aa067945`), every `permissionDecision` whose source is `user_*`; Claude Code permission mode `auto`; hook reasons read from the attachments. The 31 asked Bash commands were replayed against the current hooks (post `576f8ef`): 27 still ask. Part B (right-click menu) excluded. Shared by the four passes; the item column names the pass that owns each cause.

**Part A: 38 permission prompts**

| Cause | Count | Item |
| --- | --- | --- |
| Subagents write through the shell (`python3 - <<EOF`, `sed -i`, `node -p`, `> $S/…`, `cp`+`rm` loop) | 10 | V3 (part), V6 |
| `.claude/.tdd-unfrozen` guarded-path edits, one entry per edit (6 accepted, 1 rejected) | 7 | V4, `loop-to-pr` V10 |
| Hook false positives (see V1) | 6 | V1 |
| `kit-cwd`: `cd <root>; python3 .claude/hooks/kit-attempts.py …` (`;`, not `&&`) | 6 | V2 |
| Claude Code `cd-compound-read` (`cd dir; ls; grep`) | 3 | V6 |
| Git: push, PR, commit with a body | 3 | V12 (commit), `loop-to-pr` V5 |
| Noise: `tsc --noEmit -p .` from a subdirectory, `mv` of one file in a protected dir, compound `git switch -c` + `sed -i` | 3 | V1, V6, `kit-boundary` |

**~16 conversational stops**: ~10 real decisions; 6 avoidable: the token-profile question on every spec (always "no"), "je lance `/loop:spec` ?" → "yes", push/PR confirmed in chat then twice by the hook (`loop-to-pr`), the contract re-validated after the user's own correction, the `.tdd-unfrozen` authorisation asked in chat on top of the ask, the plan-critic cap (`review-convergence.md`, OUT).

**Part C, `feat/metre-sommes-saisie`** (transcript `8b64b672`, 14:03-16:32, PR #25 stacked on #24 ← #23): **33 prompts** in 2 h 30, replayed: they still ask.

| Cause | Count | Item |
| --- | --- | --- |
| `.claude/.tdd-unfrozen` edits: 5 adding entries (1 rejected by mistake; C1-C10 already approved in the plan go at 14:20), 6 removing applied entries at ship, within one minute at 16:19 | 11 | V4, `loop-to-pr` V10 |
| `kit-cwd` | 7 | V2 |
| Subagent shell commands: `python3 -` rewriting an e2e spec, an empty `cat >> e2e/x.spec.ts <<EOF` probe, two no-op `python3 - <<EOF print("noop")` | 4 | V3 |
| Git: push, PR, `git -C <repo> commit -m … -m <body>`, `cd x; git switch -c …; mkdir` | 4 | V12, V6, `loop-to-pr` V5 |
| False positives: `sed -n` on `takeoff-cctp-vivid…` (`-vi`), `prettier --write … >/dev/null 2>&1` | 2 | V1 |
| `pnpm exec tsc --noEmit -p .` from `frontend/` ("targets frontend (cfg)") | 2 | `kit-boundary` (`APP_ROOTS`) |
| `sed -i` on the Claude auto-memory, outside the project | 2 | V11 |
| `sed -n "${n},$((n+22))p"`: the sed-script reader fails on `$((…))`, the hook says "shell_targets.py is missing, broken" | 1 | V1 |

7 conversational stops: 3 real, 4 avoidable (token profile; the follow-up to the mistaken `.tdd-unfrozen` reject; C11-C13 asked alone; "Je pousse et j'ouvre la PR ?"). Part B (not counted) adds ~8 main-thread `python3 - <<EOF` edits of `plan.md` / `handoff.md` / `design.md` (V3).

Spikes settled 2026-11-09: Claude Code raises no prompt of its own on `.claude/.tdd-unfrozen` — every `safetyCheck` followed a kit-hook ask (`docs/product/spikes/safetycheck-tdd-unfrozen.md`); Write/Edit on the auto-memory raises none (`docs/product/spikes/auto-memory-write-prompt.md`).

Expected after this pass: part A ~38 → ~15 prompts, part C ~33 → ~12 (the rest is owned by the next passes), ~4 avoidable stops gone.

## Scope
- IN :
  - **V1. Hook false positives**, each with a fixture that fails today (`prevent-destructive-commands.sh`):
    - The source-write flags are unanchored: `(-[a-zA-Z]*i|--in-place)` matches `-li` inside a file name, `(-c|-e|--eval|-p)\b` matches `-p` inside one (`:371-372`, `:382-383`). They produce asks **and denies**: `sed -n 196,262p e2e/takeoff-measurement-lines.public.spec.ts` asks "writes a TypeScript source"; `sed -n 1,5p src/features/a/services/a-line.repository.ts` and `sed -n 1p app/services/a-list.py` are **denied** as writes to the test-first layer; `node scripts/x-p.ts` asks. Every flag alternative is anchored on `(^|[[:space:]])`, in `SRC_WRITE_RE` and `PY_WRITE_RE`.
    - The formatter-wide loop (`:711-725`) counts redirections as targets: `prettier --write src/a.ts >/dev/null`, `… 2>&1` and `… > /dev/null` ask "whole folder". Skip every word matching `^[0-9]*[<>&]+` and, after a bare operator, the word that follows it.
    - **`$((…))` in a sed script.** The shell parser already lifts `$((…))` (`shell_targets.py:215`, `:273`, `ARITH`). The failure is in the sed-script reader: `sed_writes` (`:1608-1691`) raises `Unreadable("unknown sed command")` on the placeholder, so `sed -n "1,$((3+2))p" x.py` sets `GUARD_FAILED` and falls through to "shell guard unavailable: shell_targets.py is missing, broken" (`prevent-destructive-commands.sh:638-640`), which is false. Fix: `sed_rows` replaces an arithmetic region with a digit before `sed_writes`; any other live expansion in a sed script (`$(…)`, `${…}`) stays unreadable and asks. `shell_targets.py` exits with a distinct code on `Unreadable`, its stderr is kept (today discarded, `:421`), and the hook says "the shell guard could not parse this command: <construct>" for every command; "missing, broken" is kept for a missing or crashing script.
    - `mv` of one named file under a protected dir reported as "recursive delete/move": decided in the plan.
  - **V2. `kit-cwd`.** The rule lives in `shell_targets.py` (`kit_cwd_rows` `:534-549`, `cd_to_root` `:1199`). The kit's snippets already run `python3 .claude/hooks/kit-attempts.py …` bare (`orchestrate.md:55`, `:88`); the `cd <root>;` prefix was improvised after the cwd drifted. Fix: `orchestrate.md` Phase 0 states "kit scripts run from the project root by relative path, never behind `cd x;`"; `&&` stays the only accepted prefix form.
  - **V3. Deny, not ask, for shell edits of sources.** An ask goes to the user; a deny goes back to the agent, which retries with Edit. Keyed on `shell_targets.py` rows, not the text regex: a row whose target resolves to a `.ts`/`.tsx`/`.py` under the project through `sed` in place, `perl -i`, `cp`/`tee` → **deny** "use Write/Edit". This also closes the quoted-flag bypass V1's anchoring would open (`sed '-i' s/a/b/ src/a.ts`). `mv` keeps its ask. An inline program (`python3 -`/`-c`, `node -e`/`-p`, an `?inline:` row) containing a quoted token that `target()` resolves under the project root → **deny** "inline programs are not used here: Read/Grep to read, Write/Edit to write"; read-only idioms too, on purpose (no kit flow uses one). An inline program naming no repo path keeps its ask. **Redirections** (`>`/`>>`, `cat >> x <<EOF`) onto a `.ts`/`.tsx`/`.py` keep today's ask in this pass: telling codegen from a plain write needs `CODEGEN_COMMANDS`, which `kit-boundary.md` brings. Rules: `implementer.md:47` and `test-writer.md:130` already forbid inline programs and redirections; `e2e-tester.md` gets the whole rule; all three add: no no-op probes (`python3 - <<EOF print("noop")`, an empty `cat >> x <<EOF`), no `> $S/…` to keep gate output (run the exact gate command and read its output).
    - **The main thread too.** `orchestrate.md` Phase 0: work artifacts (`plan.md`, `handoff.md`, `design.md`) are written with Write/Edit, never from the shell; appending a `## Gate` block is an Edit.
  - **V4. `.tdd-unfrozen` in one write per gate.** All the entries a gate needs go in one Edit, one line per path, several ids on a line as `# U2, U5: …` (`orchestrate.md:262`). The chat never asks again what the hook's ask asks. **Removal never asks:** an Edit of `.tdd-unfrozen` whose result only deletes lines or turns them into comments narrows the escape hatch; `protect-files.sh` allows it with no prompt (the spike shows a hook decision is enough), and the clean-up at ship is one Edit.
  - **V6. No question without a decision behind it.**
    - The token profile is inferred from the spec: asked only when the spec touches payment, authorisation, destructive data, **or loosens a kit guard / widens what runs without a prompt**; otherwise printed at the framing (`Token profile: economy`), which the user validates.
    - Never end a turn on "je lance X ?" when X is the next step of what the user just asked and stays local and reversible.
    - A contract amendment that is exactly the user's own correction is recorded, not re-asked.
    - No `cd dir; …` in Bash: absolute paths, or Read/Grep/Glob.
  - **V11. The Claude auto-memory is written with Write/Edit.** `CLAUDE.md`'s "Never write source from the shell" becomes "never write any file from the shell, the auto-memory included". No hook change. The spike shows Write/Edit on the auto-memory raises no prompt (318 writes, 0 prompts).
  - **V12. The commit is one line, from any tree** (moved here from V5: local, nothing leaves the machine). `github.md:127-130` already requires `git commit -m "<one line>"`; in part C the main thread's prompt asked the `github` agent for "Body bullets". `ship.md` step 4 hands the agent a subject only; `github.md` says a body asked by the caller goes into the PR body, never into the commit. Hook: `commit_form` (`enforce-git-workflow.sh:1582`) is `^git commit -m …` and asks on `git -C <tree> commit -m "<one line>"`, the form subagents use and `small.md:16` prescribes; `grammar_strict` accepts it with the tree check `grammar_add_ok` already applies.
- OUT :
  - `APP_ROOTS` (`tsc -p .` from an app subdirectory) and `CODEGEN_COMMANDS` (redirect deny): `docs/specs/kit-boundary.md`.
  - Push, PR, the record, V10 (plan-approved unfreezes with no second ask): `docs/specs/loop-to-pr.md`.
  - The `auto` mode: `docs/specs/auto-mode.md`.
  - The plan-critic / review cap: `docs/specs/review-convergence.md`.

## Open questions
- V1's single-file `mv` in a protected dir: pass, or keep the ask with a clearer message (decide in the plan).

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- Hooks: `prevent-destructive-commands.sh`, `shell_targets.py`, `protect-files.sh`, `enforce-git-workflow.sh`, their fixtures, `test-hooks.sh`.
- Commands: `.claude/commands/loop/{orchestrate,ship,spec}.md`.
- Agents: `implementer`, `test-writer`, `e2e-tester`, `github`.
- `CLAUDE.md` (no file written from the shell, auto-memory included).

## Business logic to cover
Hook fixtures (each fails today unless noted):
- F1 `sed -n` on a `-li…` `.ts`/`.py` test-first file: pass (today ask/deny); `sed -i.bak x.ts`, `perl -pi -e … x.ts`: deny.
- F2 `prettier --write a.ts >/dev/null`, `2>&1`, `> /dev/null`: pass; `prettier --write .`: ask.
- F3 `python3 -c "open('src/a.ts','w')…"`: deny; `node -p "require('./package.json').version"`: deny with the Read pointer; `python3 -c "print(1)"`, `python3 -c "print('a.ts')"` (no file of that name): ask (unchanged); `sed '-i' s/a/b/ src/a.ts`, `sed "-i" …`: deny; `echo x > src/a.ts`: ask (unchanged in this pass).
- F9 `sed -n "1,$((3+2))p" x.py`: pass; `sed -n "$(echo 1w src/a.ts)" x.py`: ask with the parse-failure message naming the construct, never "missing, broken".
- F11 `python3 - <<EOF` writing `docs/work/x/plan.md`: deny; `cat >> docs/work/x/plan.md <<'EOF'`: pass (unchanged, instruction only); `python3 - <<EOF print("noop")`: ask (unchanged).
- F12a an Edit of `.tdd-unfrozen` that only deletes or comments out lines: pass; one that adds a line: ask (unchanged).
- F14 `git -C <repo> commit -m "feat(x): one line"`: pass; `git -C <repo> commit -m a -m b`: ask (unchanged).
- `cd <root> && python3 .claude/hooks/kit-attempts.py …`: pass; `cd <root>; …`: ask (unchanged).

Contract greps (`test-workflow-contracts.sh`): `orchestrate.md` carries the kit-scripts-from-root line and the main-thread "work artifacts with Write/Edit" line; `ship.md` step 4 hands a subject only; `github.md` routes a requested body to the PR; `e2e-tester.md` carries the inline-program rule; `CLAUDE.md` says "never write any file from the shell, the auto-memory included".

## Acceptance criteria
- [ ] F1-F3, F9: read-only `sed`/`prettier` commands no longer ask or deny; in-place edits and inline programs naming a repo path are denied with a Write/Edit pointer, quoted flags included; unrelated inline programs and redirections keep their ask; any parse failure names its construct.
- [ ] `orchestrate.md` says kit scripts run from the root, never behind `cd x;`; `cd <root> && …` passes, `cd <root>; …` still asks.
- [ ] `implementer`, `e2e-tester`, `test-writer` state "no inline programs, no no-op probes, no redirect to keep gate output"; the main thread writes work artifacts with Write/Edit.
- [ ] A gate needing several `.tdd-unfrozen` entries asks once; the chat does not ask it again; removal-only Edits do not ask.
- [ ] A spec touching none of payment / authorisation / destructive data / kit guards asks no token-profile question; one touching them does.
- [ ] No "je lance X ?" stop when X is the next step of the user's request; a contract amendment equal to the user's own correction is not re-asked.
- [ ] F14: a one-line `git -C <tree> commit -m` runs with no ask; `ship.md` never asks the `github` agent for a commit body.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Measure after
Re-run the transcript count on the next real EcoCrew feature (`moi` mode): permission prompts by cause, conversational stops by kind, against 38 / ~16 (part A) and 33 / 7 (part C). Expected ~12-15 prompts, the remainder being the causes the next passes own (push/PR, `.tdd-unfrozen` additions, `tsc -p .` from `frontend/`, redirections).

## Next work
At `/loop:ship`, once the commit is done, propose this to the user as the next step (do not start it without their go):
1. **Measure first**: run the next real EcoCrew feature with the kit updated (`install.sh`), then count prompts and stops as in *Measure after*. Compare with the expected numbers above.
2. **Then `docs/specs/kit-boundary.md`** (pass 2 of 4): the project config file, kit code off-limits in an installed project, `APP_ROOTS` and `CODEGEN_COMMANDS`. If the measure shows a cause this pass should have removed, fix it before starting pass 2.
