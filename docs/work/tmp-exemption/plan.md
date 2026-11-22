# Plan: tmp-exemption (bug)

Token profile: critical
Entry: docs/work/tmp-exemption/debug.md
Pipeline: BUG

## Contracts
The shell write guard in `prevent-destructive-commands.sh` covers the verbs `>`, `>>`, `mv`, the
`GUARD_SOURCE_WRITERS`, `tee` and `cp`. A target that falls under an exemption still passes, but
only when it cannot land inside `CLAUDE_PROJECT_DIR`:

- C1. fd aliases. `/dev/fd/0-2`, `/dev/stdin`, `/dev/stdout` and `/dev/stderr` stay exempt
  unless the same command re-binds that fd to a path with a read or read-write redirect. That
  means `N<`, `N<>`, `exec N<`, or a bare `<`/`<>` for fd 0. If it does, the write asks.
- C2. Glob/brace under `/tmp`. A `/tmp` target that holds a glob or a brace is not exempt
  (it asks) when any segment after the first cut can expand to `..`. Such a segment either
  starts with `.` or contains a `{`.
- C3. Symlinks under `/tmp`:
  - A `/tmp` target is resolved physically, component by component. `..` is applied after
    links, never folded away lexically first. A final component that is an existing symlink
    is followed too.
  - A `/tmp` glob is expanded at hook time. Each current match is resolved the same way.
  - Any result inside the project is guarded like the direct path.
- C4. Links made in the same command. A `/tmp` write asks when the same command also creates
  a link: `ln` (symbolic or hard) or `cp -s|-l|--symbolic-link|--link`.
- C5. These keep passing:
  - `/tmp/out.txt`, `/tmp/d/out.txt`, and `/tmp/*.log` when no match is a link into the project;
  - `/dev/null`, `>&2`, `2>&1`, `2>/dev/fd/2`, `>/dev/stderr`, `tee /dev/stderr`;
  - `sort < in.txt > /dev/stdout` (fd 0 re-bound, fd 1 written);
  - `pnpm test:run 2>&1 | tee /tmp/x.log`.

## Contracts, revision 2 (2026-11-12, after review 1/3 FAIL; user chose the fail-closed redesign)
These replace C1-C4. C5 stays, except for `/tmp/*.log` (see R2).
- R1. fd aliases. Each fd starts with no binding. A read redirect to a path binds fd N, or fd 0
  for a bare `<`/`<>`. A dup `N>&M` or `N<&M` copies M's binding to N; `>&M` is fd 1 and
  `<&M` is fd 0. A `{var}<` binds an unknown fd. Bindings are applied until nothing changes.
  A write to a bound fd's alias asks, and with an unknown fd every alias asks. A `$` just
  before a digit is not a redirect (`awk '$1<10'`).
- R2. Every `/tmp` glob or brace target outside the project asks for a write verb (the same set
  as R3). There is no hook-time expansion any more. `rm`, `mv` and `ln` of /tmp matches act on
  the matches themselves and keep passing (X9.09 `rm /tmp/x-*`). A glob inside a project that
  happens to live under /tmp is judged by the in-project glob rules, as before.
- R3. A plain `/tmp` target resolves physically (links followed in order, `..` applied
  after them) for write verbs only: `>`, `>>`, and the source writers except `ln`.
  - If the resolved path is inside the project, it is guarded like the direct path.
  - The target asks if a link in the chain points under `/proc` or `/dev`, or if the final
    target is an existing file with more than one hard link.
  - `rm`, `unlink`, `mv` and `ln` act on the link itself: they keep the lexical target.
- R4. A `/tmp` write, other than the `ln` row itself, asks when the command also makes a link:
  - any word named `ln` or `link`, whatever its path prefix or quoting;
  - `cp` with `-s`, `-l`, `-a`, `-P`, `-d` (in any short cluster) or with any `--` option.
  The scan stops at a newline, `;`, `&` or `|`.

### Revision 3 (2026-11-12, after review 2/3 FAIL; user: fix the regressions this diff introduced, ship, move the rest to a spec)
- R1 amended: `/dev/stdin` is no longer exempt; it asks, as it did at HEAD. `/dev/fd/0-2`,
  `/dev/stdout` and `/dev/stderr` keep R1.
- R3 amended:
  - A `find` root that is a `?tmp:` row runs `-exec` against its physical side, or against
    `?unknown` when that side is `?`.
  - A `/tmp` path whose lexical or physical side holds a unit separator is `?unknown`.
- Cases CG80-CG82 (pure additions after CG79):
  - CG80: `find $s/preB/ -name '*.py' -exec sed -i s/x/y/ {} +` → not pass.
  - CG81: `echo x a2<$c/src/a.py >/dev/stdin` and `true&&<$c/src/a.py echo x >/dev/stdin` → not pass.
  - CG82: `echo x > $s/L<US>`, where that link points to `$c/.claude/settings.json` → not pass.
- RED evidence: review 2/3 observed each of these passing on the revision-2 working tree with
  the probe, and proved each in real bash. The cases were added along with the fix in the
  same step, so no separate failing run of them exists.
- After review 3/3 (CONCERNS, ceiling reached; the user chose a tiny fix with no extra
  review): `exec_rows` runs `-exec` on both sides of a `?tmp:` root, the lexical and the
  physical. These rows are a strict superset of HEAD's.
  - CG83: a project whose `.claude` is a link into /tmp, with `find .claude/ -exec /bin/rm {} +`
    and `-exec unlink` → not pass.
  - RED evidence: review 3/3's probe and its real-bash proof.
- Follow-up spec `guard-tokenizer-fd-links` takes the rest of review 2/3 (C2 regex gaps on fd
  0-2, C3 link-maker spellings, M1, M3, M4). It is recorded in
  `docs/specs/harness-hardening.md`.

### Revision 2 cases (pure additions after CG70)
| Id | Command | Expected |
| --- | --- | --- |
| CG71 | `shopt -u globskipdots; echo x > /tmp/.[.]$c/src/a.py`, and the same with `.?` and `.*` | not pass |
| CG72 | `echo x 3<$c/src/a.py 2>&3 >/dev/fd/2`, `exec 1<$c/.claude/settings.json 2>&1; echo x > /dev/stderr`, `exec 3<$c/.claude/settings.json; exec 1>&3; echo x > /dev/stdout` | not pass |
| CG73 | `/bin/ln -s $c/src/a.py $s/l9 && echo x > $s/l9`, `'ln' -s … && …`, `cp --sym $c/src/a.py $s/l9 && echo x > $s/l9`, `cp -a $s/x.log $s/l9 && echo x > $s/l9` | not pass |
| CG74 | `echo x \| tee $s/*.log` with several links into `docs/` and one into `src/a.py` | not pass |
| CG75 | `echo x > $s/[^x]reB/a.py`, `shopt -s dotglob; echo x > $s/*/a.py` | not pass |
| CG76 | `exec 2<$c/.claude/settings.json; echo x > $s/errl` (`errl` → `/dev/stderr`) | not pass |
| CG77 | `echo x > $s/hard` (`hard` is a hard link to `$c/src/a.py`, made by the fixture) | not pass |
| CG78 | `rm $s/set.lnk`, `unlink $s/set.lnk`, `mv $s/set.lnk $s/ok/`, `ln -sfn $c/src/a.py $s/x2.log` (`set.lnk` → `$c/.claude/settings.json`) | pass |
| CG79 | `awk '$1<10' f > /dev/stdout`, `cp a /tmp/b` followed by a newline and `ls -l` | pass |

The hard-link fixture is skipped (the case is counted as such) when `/tmp` and the project are
on different filesystems.

**R2 correction to frozen cases:** `echo x > /tmp/*.log` in CG29 (app-roots-codegen), CG60 and
CG70 now expects `ask`. It is removed from their pass lists, and `CG60-R2` asserts the ask.

## Reproduction cases
The cases go in `test-hooks.sh` as pure additions after CG60, using `pd_probe` and
`g15_expect`. "Not pass" means ask or deny.

`$c` is the probe project. `$S` is a fixture folder under `/tmp`, created by the case and
removed with `rm -r` on that exact path. It holds:
- `preB` → `$c/src` (link to a folder);
- `x.log` → `$c/src/a.py` (link to a file);
- `ok/` (a plain folder).

The main thread writes these cases, because test-writer is denied on `test-hooks.sh`.

| Id | Command | Expected |
| --- | --- | --- |
| CG61 | `echo x 1<$c/src/a.py >/dev/fd/1` | not pass |
| CG62 | `exec 2<$c/.claude/settings.json; echo x > /dev/stderr` and the same with `/dev/fd/2` | not pass |
| CG63 | `echo x 0<$c/src/a.py >/dev/fd/0` | not pass |
| CG64 | `echo x \| tee /tmp/{.,}.$c/src/a.py` and `cp /etc/hostname /tmp/{.,}.$c/src/a.py /tmp/` | not pass |
| CG65 | `shopt -u globskipdots; echo x > /tmp/.[.]$c/.claude/settings.json`, and the same with `.?` and `.*` | not pass |
| CG66 | `ln -s $c/.claude $S/l && echo x > $S/l/settings.json` | not pass |
| CG67 | `echo x > $S/preB/../.claude/settings.json` | not pass |
| CG68 | `echo x > $S/pre?/settings.json` | not pass |
| CG69 | `echo x > $S/x.log`, `echo x \| tee $S/x.log`, `cp /etc/hostname $S/x.log`, `echo x > $S/*.log` | not pass |
| CG70 | each C5 command, plus `echo x > $S/ok/out.txt` | pass |

CG61 to CG69 fail today (the verdict is pass). CG70 passes today and pins C5. Before writing
the cases, each one is checked against the HEAD hook with the probe.

## Gate
- 2026-11-12 test plan: **go** (C1-C5, CG61-CG70 as written).
- 2026-11-12 plan-level correction (user go), two cases that were wrong in the plan, not in the code:
  - CG64: the `cp /etc/hostname /tmp/{.,}.$c/src/a.py /tmp/` variant is removed. In real bash
    the brace gives two sources, both copied into `/tmp/`, and the project file is unchanged.
  - CG68: the target `settings.json` becomes `a.py`. With `preB` → `src`, the old target was
    `src/settings.json`, whose direct path passes.
  - `test-hooks.sh` is outside the freeze matcher (`src/`, `shared/`), so this record stands in
    for a `.tdd-unfrozen` line.
