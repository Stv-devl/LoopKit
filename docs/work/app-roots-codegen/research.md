# Research: App roots and codegen   (entry: docs/specs/app-roots-codegen.md)
Token profile: critical

Sources: the 2 explorers of 2026-11-10 (guard/cfg/init/doctor/install; redirects/codegen/frozen-row sweep), on top of `docs/work/kit-boundary/research.md`. Line numbers are from HEAD e4837f2.

## Pattern to follow
- **Guarded paths.**
  - `CWK_GUARDED` lives in `hook-guarded.sh:20-39`; `cwk_is_guarded` at `:76` matches root-anchored globs or a folder above one.
  - Write/Edit ask: `protect-files.sh:251`.
  - Shell side: `prevent-destructive-commands.sh` checks the cfg branch at `:520`/`:529`, the `>` branch at `:604`, writer verbs at `:620`, and the text fallback `guard_text_writes` at `:677`.
- **Source-writer deny** (fewer-asks V3), the sibling of the codegen deny.
  - The writer verbs are in `GUARD_SOURCE_WRITERS` (`prevent-destructive-commands.sh:494`): `sed perl cp tee install rsync ln patch truncate`.
  - The rule is at `:608-617` and covers `\.(tsx?|py)$`.
  - Deny text, `:616`: "This edits a source from the shell, around every Write/Edit guardrail. Use Write/Edit."
- **Precedent for a safe project-file read in Python:** `shell_targets.py` `kit_cwd_ok` `:1208-1254` (`islink`/`isfile` checks, bounded `read(4096)`, `OSError`/`UnicodeDecodeError` caught).
- **Precedent for a guard row carrying more than verb+target:** the `?unknown:` labels `kit-cwd` (`shell_targets.py:549`), `kit-doctor` (`:607`) and `option` (`:1321`).

## Wiring points
- **The cfg path.**
  - Resolver chain in `shell_targets.py`: `runner_rows` `:632` → `runner_exec` `:902` → `verb_rows` `:603` → `tool_rows` `:1295`.
  - `flag_kind` `:1086-1104`:
    - tsc `-p/--project`;
    - vite/vitest/playwright `-c/--config/--root/--dir`;
    - vitest `-r`;
    - script rows.
  - Base dir comes from `package_base(state.dir)` `:1068-1083`, which walks up to the nearest `package.json`, bounded by the project.
  - Runner options that change the base: `-C/--dir/--prefix/--cwd` (`:72`).
  - Decision (`prevent-destructive-commands.sh:511-533`):
    - a **dir** target passes only if its real path is the project root (`:527`), else it asks `<rel> (cfg)` (`:532`, text `:734-735`);
    - a **file** target passes if `cwk_is_guarded` (`:529-530`).
  - The EcoCrew cases (cwd `frontend/` with `-p .`, and `-p frontend` from root) both produce the row `("cfg", <root>/frontend)`, a dir, which asks today.
- **Redirections.**
  - `Walker.walk_segments` `shell_targets.py:497-520` sets `pending` on a redirect operator. `redirect()` `:552-564` appends to `seg.redirects`. Every operator becomes verb `>` (`finish` `:570`).
  - The segment's words are in the same Segment at `finish` (`:566-585`, `strip_prefixes` `:567`, defined at `:1032-1065`). Attaching the command words to a `>` row is a local change.
  - `cat >> x <<EOF` gives one `>` row for `x` (the heredoc body is used only by `interpreter()` `:680-681`).
  - Row format is `verb\ttarget` (`:1792-1794`). The bash parser `GUARD_ROW_RE` (`prevent-destructive-commands.sh:465`) splits on the first tab, then `guard_classify` (`:538`) dispatches on `case "$target"` (`:540-581`).
- **Today's verdicts for a `>` under the project:**

  | Target | Verdict | Where |
  | --- | --- | --- |
  | `.ts`/`.tsx` | ask "TypeScript source from the shell" | `SRC_WRITE_SEEN` set at `:411` (text) and `:603` (row), ask at `:832-834`, the last ask |
  | TS test-first name or test | deny TS_TDD | `:412-413`, `:598-599` |
  | PY layer (`CWK_TDD_PY_TARGET_RE`, path-anchored) | deny | `:394`, `:401-403`, `:600-601` |
  | other `.py` | **pass** | — |
  | guarded | ask "guarded path" | `:604-606`, `:710-712` |
  | `.md` | pass | — |
  | `/tmp` | pass | `:576-579` |
  | outside the project | ask | `:580-581` |
  | no project dir | pass | `:571-572` |
- **`/kit:init`** (`.claude/commands/kit/init.md`):
  - Phase 1 inspect `:31-47` reads manifests at the root only and has no subdir detection.
  - Phase 2 is the closed-question gate (`:49-65`).
  - Phase 3 applies `docs/ADAPTATION.md` sections in order (`:67-96`); ADAPTATION §14 "Chemins gardés" is at `:448`.
- **`kit-doctor.py`:**
  - `Finding(name, STATUS, summary, [evidence])`, statuses at `:35`;
  - `CHECKS` registry `:1296-1310`;
  - output `  DIVERGENCE  <name>` (`main` `:1312`).
  - Its test `test-kit-doctor.sh` builds a scratch tree and greps `DIVERGENCE  <name>` / `ok          <name>`.
- **`install.sh`:**
  - `copy_tree` `:201-212` copies every file under `.claude/` except settings.json and runtime files, so a kit `.claude/project.json` ships automatically.
  - `copy_file` `:86-96` writes `.new` when the target exists, so an existing `project.json` is never overwritten.
  - Precedent: `.claude/workflow-routing.yml`.
  - `GUARD_FILES` `:212` + `# cwk-guard-api: N` stamps `:237-240` (hold-back logic).

## Reusable
- `cwk_is_guarded`, `cwk_guard_rel`, `cwk_real_path` (`hook-guarded.sh`).
- `package_base`, `flag_kind`, `strip_prefixes` (`shell_targets.py`).
- The source-writer deny branch and its text.
- `kit_cwd_ok`'s safe-read idiom.
- The shell-guard `setup` mechanism (`test-hooks.sh:131-294`, `SHELL_SETUP` from the jsonl `setup` key at `:962`; `pkgsub` `:152` is the only subdir tree).
- `guard_expect` / `guard_rel_expect` unit checks (`test-hooks.sh:691, :705`).
- The `test-kit-doctor.sh` scratch pattern.

## Blast radius
- **Frozen rows flipped by the codegen deny (ask → deny), exactly 6:**
  - X28.79 `echo 'export const a = 1' > src/b.ts`
  - X32.07 `echo x > src/a.ts`
  - X32.08 `cat >> src/a.ts <<'EOF'`
  - X42.04 `echo x >src/App.t's'`
  - X42.05 `echo x >src/App.ts`
  - X24.413 `echo x > addons/fastapi/hooks/tdd_py_lib.py` (guarded ask → deny, losing the guarded text, unless guarded keeps priority)
- **Not flipping:**
  - X23 no-base (`test-hooks.sh:1605`) stays pass, because with no project the hook returns at `:571-572` before classifying. This corrects the kit-boundary critic's "surely flips".
  - X9.16 and X41.01-03 (`>` and `=>` inside quoted text) pass on rows, but a text-level rule would flip them.
  - Already deny: X42.01-03, harness `01-deny`, fixtures 11/12, X25.01-03.
- **Rows pinning today's subdir behaviour:**
  - `test-hooks.sh:741-745` (`apps/web/package.json` NOT guarded);
  - `fixtures/protect-files.sh/30-w5-nested-package-pass.json` (pass);
  - root ask fixtures 12/15/16/17;
  - shell-guard cfg rows in subdirs, all ask: X24.043, 048-050, 055-057, 059-060, 074-075, 142-144, 148-155, 189-192, 208-209, 224-233, 237-238, 253-254;
  - root passes X24.051, 052, 054, 101, 164-166.
  - With no `app_roots` declared, none of these may move.
- **Guard api bumps:** `hook-guarded.sh`, `prevent-destructive-commands.sh`, `shell_targets.py`, `protect-files.sh`, kept in sync with `GUARD_FILES` (`test-workflow-contracts.sh:765`).
- **Docs:**
  - `docs/ADAPTATION.md` §14 (`:448`, and the `:462-464` sentence on installed projects asking only on package.json/vite.config);
  - `kit/init.md`, `kit/doctor.md`;
  - `README.md`.

## Live DB state
n/a (kit tooling).

## External surface
n/a, no third party. Hook JSON semantics as today [settled by the existing suites].

## Traps (points of vigilance for the review)
- **One list, two meanings.** `CWK_GUARDED` drives both the Write ask (`protect-files.sh:251`) and the cfg **file** pass (`:529`). Adding `<root>/tsconfig*.json` makes `-p frontend/tsconfig.app.json` pass. That is acceptable only for a declared root. With nothing declared, behaviour must stay today's.
- **A dir target never passes today** unless it is the project root (`:527`). The app-root pass is a new dir branch. It must compare real paths, so `frontend/../frontend` and a symlink alias resolve the same way.
- **`package_base` walk-up bypass.** A cwd without its own `package.json` resolves a relative cfg target against an ancestor's base. The pass must key on the resolved target being exactly a declared root, not on the cwd.
- **The codegen exemption must read the redirect's own segment command** from the row, never the raw text. Raw text is bypassable (`gen; echo x > src/a.ts`, `echo $(gen) > src/a.ts`) and gives false positives (X9.16, X41.*). Raw-text rules already match quoted text: one blocked a probe in this research.
- **Extending the row protocol.** A new `?prefix:` target missing from `kind()`/`order` (`shell_targets.py:1747`, `:582`) raises an uncaught KeyError, and the hook falls to the text rules. Adding text to the verb splits the dedupe (`:578-581`). `MAX_ROWS = 64` (`:24`) turns an overflow into one `?unknown` ask.
- **Resolver contract.** The `shell_targets.py` docstring says it "resolves, never classifies" (`:11`). Matching codegen prefixes inside it is classification; `kit_cwd_rows` (`:543-549`) is the only exception today.
- **Writer verbs.** The source-writer deny already covers `tee`/`cp`/`sed -i`… onto `.ts/.tsx/.py`. A codegen exemption on `>` only leaves `gen | tee src/types/x.ts` denied while `gen > src/types/x.ts` asks. State it, or extend the exemption.
- **`.py` redirect** onto a non-layer, unguarded file is a pass today, so its deny is a new verdict. The `PY_TDD` and `TS_TDD` denies keep their own texts and priority.
- **Guarded `.py`/`.ts` targets** (X24.413): decide whether the guarded ask or the codegen deny wins, and keep the reason readable.
- **Protect-files fixtures run with project = kit root.** Testing an `app_roots` project there needs a new per-case project mechanism. The shell-guard `setup` block is the only existing one.
- **`project.json` is not guarded** by the `.claude/` folder rule (that rule guards folders above patterns, not files inside `.claude/`). It must be added to `CWK_GUARDED` explicitly.
- **Read cost.** `cwk_is_guarded` is reached only on writes (protect-files Write/Edit, shell rows that write or load), never on Read/Grep/Glob. `auto-approve-config.sh` uses its own list (`:80-88`). Reading `project.json` therefore adds no cost to reads, but a per-row reread in the shell guard would add up.
- **The `.tdd-unfrozen` bash parser** has 3 copies, which must change together (`tdd-require-red.sh:144-145`). The `project.json` reader must not become a fourth hand-rolled parser.
- **Fastapi gate configs** live in the target's `pyproject.toml` (`[tool.ruff]`, `[tool.pytest.ini_options]`, `[tool.coverage.*]`: `addons/fastapi/rules/07-backend.md:53-57`, `skills/patterns/pytest-backend.md:10-12,229-233`). None is guarded today, even at the root.
- **`eslint -c/--config` is not recognised** as cfg (no row, pass; `FLAG_TOOLS` `:76`). Pre-existing.

## Open questions
1. **Reader.** Hooks already require `jq` (`cwk_require_jq` in 8 hooks; Python hooks parse JSON natively). Options:
   - read `project.json` with `jq` in shell and with `json` in `shell_targets.py`, one validation spec and two readers;
   - or one Python reader whose output the shell consumes (one start-up per hook run).

   Which one? Note that validation must reject a `..` root, an absolute root and a non-list codegen entry identically on both sides.
2. **Where the codegen classification lives.**
   - (a) `shell_targets.py` emits the segment's leading command words with the `>` row (a new row kind, e.g. `>cmd`, in `kind()`/`order`), and the bash hook matches them against `codegen_commands`;
   - (b) the resolver reads `codegen_commands` itself and emits `>cg`, a classification exception like `kit_cwd_rows`.

   Which one?
3. **Exemption scope.** Does the codegen exemption cover only `>`/`>>`, so that `gen | tee x.ts` stays denied like every writer verb? Or does it also cover `tee` when the pipe's first segment is a listed command?
4. **Priority on a guarded source.** Should a redirect onto a guarded `.ts`/`.py` (X24.413) keep the guarded **ask**, or become the codegen **deny**?
5. **pyproject roots** (spec open question). Should a declared app root holding `pyproject.toml` guard `<root>/pyproject.toml` (and `ruff.toml`, `mypy.ini`, `pytest.ini`)? Should the root-level `pyproject.toml` join `CWK_GUARDED` too, when the fastapi addon is installed?
6. **App-root config patterns.** Use the same 6 root patterns, or a subset? `playwright.config.*` in a subdir is rare. `package.json` there holds the app's gate scripts, so it must be in.
7. **Invalid `project.json`.** Is the fallback silent (no roots, no codegen) with the reason reported only by `kit-doctor.py`, or does the shell guard also ask once with the reason, so that a broken file is visible during a session?
