# Plan: guard-tokenizer-fd-links   (entry: docs/specs/guard-tokenizer-fd-links.md · research: docs/work/guard-tokenizer-fd-links/research.md · design: n/a)
Token profile: critical
Pipeline: light
Revision: 3 (plan-critic pass 1: C1-C4 and M1-M10 confirmed by the verifier; pass 2: 1 Critical
and 3 Majors, checked against PDC:144-149, PDC:774-782 and TH:1929-1930; all addressed below)

## Skips
- DB: SKIP. No database (kit hooks).
- Backend: SKIP. No custom backend, per the spec.
- INTERFACE: SKIP. No user surface.
- Front `utils`/`mapper`/`repository` layers: SKIP. None exist here. The kit hooks are a
  foreign toolchain (`05-testing.md`, "Foreign toolchains use their own cycle"): their
  test-first file is `.claude/hooks/test-hooks.sh`, cases `CG<n>`. The main thread writes
  them, because `test-writer` is denied on that file. RED is observed by running the suite
  before each GREEN, as in `tmp-glob-escape` and `tmp-exemption`.

## Design (decided here, binding for EXECUTE)
The tokenizer decides and the hook only reads rows. Row-level mechanisms in
`shell_targets.py` (ST), consumed by `prevent-destructive-commands.sh` (PDC).

D0. **`in_project(path)`**, one ST helper used by D1, D3 and D4. True when the path is
lexically under `CLAUDE_PROJECT_DIR`, or when the realpath of its deepest existing
directory (the path itself included, tested with `isdir`, as at HG:276-281), plus the
remaining components, is under `realpath(CLAUDE_PROJECT_DIR)`. A file link is never followed
here: that is D1's job. This is the same
test as `cwk_guard_rel`'s lexical-first, physical-fallback rule (HG:273-284), so ST never
calls "outside" a path PDC would resolve inside (M3: `rm <tmp link to .git>/config` stays a
deny). No project dir → False.

D1. **Side of a /tmp path, chosen in ST by verb and operand position.**
- Today `target()` returns `?tmp:<lexical>\x1f<physical>` and PDC picks the side
  (PDC:636-656). That choice moves into ST, at the row-building callers, through a new
  `target(word, directory, follows=True)`.
- `follows=False` only for an operand the operation applies to the link itself:
  - the operands of `rm`/`rm-r`/`rmdir`/`unlink`;
  - `mv`'s source operands;
  - `ln`'s link operand (the last one, or the `-t` dir), **unless** it resolves to an existing
    directory and none of `-n`, `-T`, `--no-dereference`, `--no-target-directory` is given.
    In that case ln creates the new link inside the folder, so the operand follows. On a link
    to a file, `ln -sf` replaces the link itself, so `ln -sf X $s/x.log` keeps passing.
- Everything else follows: `>`, `>>`, tee, cp/install/rsync destination, `mv`'s destination,
  truncate, touch, chmod, chown, shred, sed `-i`/`w`, perl/ruby `-i`, find `-delete` roots and
  `-fprint*`/`-fls` files, `--output`/`-o`/`-O` (D7) and the tool-option rows (flag-w, flag-r,
  cfg).
- For a path lexically under /tmp that a link moves, or that has a second hard link:
  - `in_project(lexical)` → the row is the lexical path (PDC's `cwk_guard_rel` guards it);
  - else, with `follows=True`, the physical path, or `?unknown:<word>` when that path is `?`;
  - else (`follows=False`), the lexical path.
- The `?tmp:` row kind is removed from the output. `exec_rows` keeps both roots (CG83): it
  calls `target(..., follows=True)` and `target(..., follows=False)` and runs each distinct
  result.
- A /tmp `?glob:` whose folder part (before the last segment) holds a glob character, and
  whose lexical folder is **not** `in_project`, becomes `?unknown:` for every verb: it may cross
  a folder link. An in-project glob keeps today's `?glob:` row, so CG42 and CG48 keep their
  reasons (M2). A /tmp `?glob:` with a plain folder that a link moves gets its physical folder.

D2. **fd-binding rows.** ST records the fd of every redirect without changing any
`redirect` signature (C1):
- `walk_segments` keeps the digit it pops at ST:559-560 and calls a new
  `Walker.note_fd(op, fd, word)` before the unchanged `self.redirect(seg, pending, tok)`.
  `SecretWalker` inherits it and never reads it; `SecretWalker.redirect(seg, op, word)` is
  untouched. CG103 pins the secret-mode verdict.
- Per call, ST computes the set of fds 0-2 that may point at a path:
  - a read redirect (`<`, `<>`) binds 0; `N<`/`N<>` binds N;
  - **a popped digit binds both N and the operator's default fd** (0 for `<`, `<>`, `<&`;
    1 for `>&`). shlex drops the whitespace, so `head -n 5 < f` and `5< f` look alike; failing
    closed on both keeps `1 < f` and `5 < f` binding fd 0 (C2);
  - a dup (`N>&M`, `N<&M`, `>&M` = fd 1, `<&M` = fd 0) copies M's binding to N, repeated
    until nothing changes, order-insensitive;
  - a `{var}` redirect binds an unknown fd, so 0, 1 and 2 all count as bound;
  - here-docs, here-strings and `<(…)` bind nothing.
- It emits one row `fd-bound\t<n>` per bound fd among 0-2.
- PDC reads those rows into `GUARD_FD_BOUND` before the classify loop and skips the label in
  the loop. `guard_fd_bound` (PDC:567-596) is deleted.

D3. **Link makers (the structural link rule), decided per command in ST.**
- A command is a *link maker* when it can create a link or move one into place:
  - (a) verb in `LINK_CAPABLE` = ln, link, cp, mv, rsync, install, tar, cpio, unzip, busybox,
    bsdtar, pax, plus `git` with a working-tree-writing subcommand (checkout, switch, restore,
    reset, clone, pull, merge, rebase, cherry-pick, revert, am, apply, stash, worktree,
    read-tree, checkout-index). The verb is the one ST tokenized: quotes, backslashes, path
    prefixes and prefix words (`env`, `xargs`, `sudo`, `command`…) are already stripped;
  - (b) a live verb (`words[0]` with `has_live`), a `{var}` word as the verb, `eval`,
    `source`, `.`;
  - (c) an interpreter running a file or inline program (python, node, ruby, perl, sh, bash);
  - (d) an **inner** command (C4): a runner's `exec`/`dlx`/`x` verb and `npx <verb>`, and each
    `find -exec`/`-execdir`/`-ok`/`-okdir` verb, classified by (a)-(c)/(e); an awk program
    (awk, gawk, mawk, nawk) that holds `system` or pipes to a command (`| "`); a sed script
    with an `e` command or an `s///e` flag;
  - (e) a verb in no known set: not in `WRITERS`, `LINK_CAPABLE` or `NON_CREATING`, and not a
    runner script, a `FLAG_TOOLS` tool, `find` or `sed`.
- Not a link maker: a runner running a package script (`pnpm build`, `pnpm test:run`). Those
  scripts live in `package.json`, a guarded path. This is an accepted residual, named at the
  gate.
- `NON_CREATING` lists read-only or output-only commands and builtins (M6): echo printf cat
  grep egrep fgrep rg ls sort head tail wc cut tr uniq diff cmp comm jq yq awk (outside (d))
  test `[` `[[` true false `:` pwd date basename dirname realpath readlink stat file which type
  command sleep printenv id whoami uname tee seq column fold nl paste join od xxd hexdump md5sum
  sha256sum base64 cd pushd popd export unset set local declare readonly shift exit return wait
  read mkdir, the reserved words (if then elif else fi for while until do done case esac `{`
  `}` `!`), and git in a read-only subcommand (status, diff, log, show, rev-parse, branch with
  no argument, ls-files, grep, blame). Its exact final list lives in `shell_targets.py`; a
  missing entry fails closed (it asks).
- **Counting** (C3): a find segment counts one link maker per inner command that is one; an awk
  or sed segment under (d) counts two. Every other link-maker command counts one.
- **Rewrite**, once the walk is over: when the call holds at least one link maker, every row
  whose target is lexically under /tmp and not `in_project` becomes `?link:<lexical path>`,
  **unless the call holds exactly one link maker and the row comes from that same segment**,
  or the row is a **settled** `follows=False` operand (rm/unlink/rmdir operands, mv sources,
  ln's link operand under D1).
  - Settled means two things. The operand's parent folder exists at hook time. And no other
    link-maker row in the call targets the operand or one of its parent folders.
  - A settled operand acts on the link itself, so it keeps its existing verdict: CG35
    (`supabase gen types > src/types/db.ts && mv /tmp/x lib/b.ts`) keeps its TypeScript-source
    reason.
  - An unsettled one becomes `?link:` (revision 4, pass-3 Critical). In
    `ln -s P/.claude /tmp/L && rm /tmp/L/settings.json`, L does not exist yet. In
    `ln -s P/.claude/hooks /tmp/D && ln -sf x /tmp/D`, the first ln targets /tmp/D. Both rows
    ask.
  So:
  - `ln -s X /tmp/l` alone, `cp a /tmp/b` alone, `pnpm build > /tmp/out.txt 2>&1` and
    `git diff > /tmp/x.diff` pass;
  - `ln -s P/src/a.py /tmp/l && cp /tmp/evil /tmp/l` gives two link makers, so cp's row is
    rewritten and asks (C3);
  - `tar -xf t.tar -C S && echo x > S/l` gives `?link:`, which asks.
  - Rows carry no segment number: ST keeps a segment ordinal while it builds rows and rewrites
    the targets itself.
- PDC: a `?link:` target sets `GUARD_ASK_T`, then returns. `guard_makes_link` (PDC:598-603) is
  deleted.

D4. **`cd -P` and `cd` into /tmp follow links before `..`** (M1, M8, pass-2 Major).
- `skip_cd_options` also reports whether `-P` was given.
- `State` carries a `physical` flag, set by `set -P`, `set -o physical` and
  `shopt -s -o physical` (and cleared by `set +P`, `set +o physical`, `shopt -u -o physical`).
  The rest of the call runs as if every later `cd`/`pushd` had `-P`. A spelling ST cannot read
  (a live word after `set`/`shopt`) sets the flag, which fails closed.
- `env -C DIR` / `env --chdir=DIR` always takes the physical join: chdir(2) resolves links.
- `State.cd`/`pushd` join the word to the current directory **before** normalising, then:
  - with `-P` (or the flag): `tmp_physical(joined)` is applied wherever the path lies, in the project or
    not. A physical result under `realpath(CLAUDE_PROJECT_DIR)` is mapped back onto the
    lexical project prefix, so the kit-cwd rule and every in-project row keep the spelling
    PDC expects;
  - without `-P`, under /tmp and not `in_project`: bash resolves `..` logically, so
    `cd $s/clsub/..` lands in `$s`. The cwd stays lexical; a later write through the link
    (`cd $s/cl && echo x > settings.json`) is caught by D1 on its own row.
  - `tmp_physical` returning None means "no link moves it": the normalised join is kept.
    `?` means unknown: the cwd becomes None.
- This follows bash's semantics and narrows the spec's "plain cd under /tmp follows links
  before `..`", which would ask on a write that lands in /tmp. It is put to the gate.

D8. **`find -delete` roots get their own label** (pass-2 Critical). Today the direct
`find src/ -delete` is caught only by the raw-text `PROTECTED_TARGET` deny (PDC:144-149). A
link (`find $s/srcl/ -delete`) or a quoted spelling (`find $c/s''rc/ -delete`) yields a plain
`find` row that guard_classify passes.
- ST's find root parser (ST:736-740) first skips find's leading global options: `-H`, `-L`,
  `-P`, `-D <arg>` and `-O<n>`. Without this, it stops at the first `-` word and falls back to
  `.` (revision 4, pass-3 Major).
- ST labels each `-delete` root `find-delete` (ST:744-745); `-fprint*`/`-fls` rows keep
  `find`.
- PDC: on a protected dir (`GUARD_PROTECTED_RE`), `find-delete` asks through `ASK_P`, as
  `rm-r` does (PDC:778). The branch sits after `cwk_is_guarded`, as rm-r's does, so X2.05
  keeps its "guarded path:" reason.
  - At the project root it adds no deny: the root is guarded and asks today
    (`find . -name '*.pyc' -delete`).
  - Anywhere else it is classified exactly as `find` is today. A filtered find inside a
    protected dir (`find dist/assets -name '*.map' -delete`) now asks through ASK_P; the direct
    spelling is already denied by the raw-text rule (PDC:144-149). `find`, which no PDC branch keys
  on, keeps every other verdict (`find $s/ok -name '*.log' -delete` still passes).
- The raw-text deny at PDC:144-149 stays as the first floor.

D5. **PDC structure**, behaviour-preserving (M4, M5).
- `guard_is_write_verb <verb> [mv]` is the single write-verb test: `>`, `>>`, or a verb in
  `GUARD_SOURCE_WRITERS`; with the `mv` argument, `mv` too. That is exactly the set of the
  4 copies at HEAD:
  - PDC:646 (the `?tmp:` branch, deleted) and PDC:663-664 (R2, the /tmp glob ask) use it
    without `mv`, with `&& verb != ln` at the call site;
  - PDC:711 and PDC:726 use it with `mv`.
  - No copy gains or loses a verb: `mv /tmp/x-* /tmp/d/` still passes and X9.09 `rm /tmp/x-*`
    is still a pass.
- `guard_classify_outside <verb> <target>` holds PDC:675-699 as they are, in the shape of
  `guard_classify_tool`:
  - the no-project early return (`[[ -n "${CLAUDE_PROJECT_DIR:-}" ]] || return 0`);
  - `/dev/null` passes;
  - `/dev/fd/0`, `/dev/stdout`, `/dev/fd/1`, `/dev/stderr`, `/dev/fd/2` ask when their fd is in
    `GUARD_FD_BOUND`, else pass; `/dev/stdin` is not exempt;
  - a /tmp target passes for every verb **except** `rm-r`, `flag-r` and `cfg`, which keep
    `ASK_O` (`rm -rf /tmp/x`, `pnpm tsc --outDir /tmp/x`, `pnpm vitest -c /tmp/e.config.ts`);
  - otherwise `ASK_O`.
  - `guard_classify` calls it on a `cwk_guard_rel` failure. A link-exposed /tmp row never
    reaches it: ST already turned it into `?link:`.
- The `?tmp:` branch (PDC:636-656) is deleted. PDC skips the `fd-bound` label in the classify
  loop.
- The `GUARD_ASK_T` message names the cause: "fd N is bound to a path in this command", "a
  link made in this command may lead this write into the project", "a /tmp glob may expand
  through a link into the project". One slot, first wins, one template per cause.

D6. **Guard API.** ST and PDC go from `# cwk-guard-api: 4` to `5` in the same commit. The
row contract changed: an old PDC would read `fd-bound 1` as a relative path. The install
hold-back (install.sh `guard_api_missing`) then holds P1 back until both are merged.
`hook-guarded.sh` stays at 4 (untouched).

D7. **`curl -o` and `wget -O` rows** (M7). `output_rows` (ST:1438-1445) also reads:
- curl: `-o FILE`, `-oFILE`, and a short-flag cluster ending in `o` (`-sSLo FILE`);
- wget: `-O FILE`, `-OFILE`, `--output-document FILE`, `--output-document=FILE`.
- Its rows follow (D1). This also closes the direct `curl -o P/package.json URL`, which passes
  at HEAD.

## Write chain (sequential)
1. DB: SKIP.
2. Backend: SKIP.
3. Kit hooks, one mechanism at a time, each RED (cases added, suite run, the Reproduction
   cases of that step seen failing) → GREEN:
   1. **[D0+D1+D7 RED→GREEN]**: `in_project`, `target(…, follows)` and its callers, the
      `ln -n` rule, the removal of `?tmp:`, the `exec_rows` double root, the /tmp glob folder
      rule with its in-project carve-out, the curl/wget rows, and the `find-delete` label (D8).
      Cases CG84-CG87, CG89, CG94, CG99, CG105, CG107.
   2. **[D2 RED→GREEN]**: `note_fd`, the per-call bound set with the popped-digit rule,
      `fd-bound` rows, the `GUARD_FD_BOUND` pre-scan, and deleting `guard_fd_bound`.
      Cases CG90, CG95, CG103.
   3. **[D3 RED→GREEN]**: `LINK_CAPABLE`, `NON_CREATING`, the inner-command and counting
      rules, the `?link:` rewrite, the PDC `?link:` branch, and deleting `guard_makes_link`.
      Cases CG91, CG96, CG97, CG100, CG101, CG102, CG106, CG108.
   4. **[D4 RED→GREEN]**: `cd -P`, the physical flag, `env -C`, and /tmp `cd`. Cases CG92,
      CG104.
   5. **D5 + D6** (refactor under a green suite, no case edited): `guard_is_write_verb`,
      `guard_classify_outside`, the message per cause, the API bump. Case CG98 is RED before
      the refactor.
4. Wiring: none beyond PDC reading the new rows (inside steps 3.2 and 3.3).
5. Tests: the Characterisation block (CG93, CG99-CG103's characterisation lines) is written
   with step 3.1 and stays green at every step. Full kit suites after each GREEN.
6. Refactor: step 3.5.

## Parallel lots (inside this track, same tree)
None: fully sequential. Every step edits ST, PDC and `test-hooks.sh`.

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: the kit guard pair (`shell_targets.py`,
  `prevent-destructive-commands.sh`) and their API number. No other pass that edits a hook
  may run in parallel until this one is committed.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/shell_targets.py` | Edit | D0-D4, D7, D8 label, API 5 |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | D1 consumer, D2/D3 rows, D5, D8 branch, API 5 |
| `.claude/hooks/test-hooks.sh` | Edit | CG84-CG87, CG89-CG108 (CG88 dropped) (pure additions in a new `run_tokenizer_cases`, called after `run_codegen_cases`) |
| `docs/specs/harness-hardening.md` | Edit | close the items this pass fixes; record the OUT residuals below |
| `docs/work/guard-tokenizer-fd-links/*` | Create/Edit | plan, handoff, attempts |

## Contracts
- **ST row output** (main mode), one per line: `<label>\t<target>`, then `#end\t<n>`.
  - Target kinds: absolute path · `?glob:<folder>\x1f<last segment>` · `?unknown:<text>` ·
    `?inline:<program>` · new `?link:<lexical /tmp path>`. `?tmp:` is removed.
  - New labels: `fd-bound`, whose target is `0`, `1` or `2`; `find-delete` (D8).
  - The `order` dict at ST:629 gains `"?link": 0`. A numeric target counts as `path`, so no
    KeyError.
- **ST functions**: `in_project(path) -> bool` (D0); `target(word, directory, follows=True)
  -> str` (D1); `Walker.note_fd(op, fd, word) -> None` (D2). `Walker.redirect` and
  `SecretWalker.redirect` keep the signature `(seg, op, word)`.
- **PDC**:
  - `guard_is_write_verb <verb> [mv]` returns 0 or 1;
  - `guard_classify_outside <verb> <target>` sets GUARD_* slots, first-wins;
  - `GUARD_FD_BOUND` (` 0 1 2 ` style) is filled before the loop;
  - a `?link:` target asks through `GUARD_ASK_T`.
- **API**: `# cwk-guard-api: 5` on line 2 of ST and PDC.

## Test plan (gate: validated by the user before EXECUTE)
All cases go in `.claude/hooks/test-hooks.sh`, in a new `run_tokenizer_cases` called right
after `run_codegen_cases`.

Fixture:
- A project `$c` built with `make_app_tree … codegen`, holding `src/a.py`, `package.json`,
  `.claude/settings.json`, `.claude/sub/`, `.git/config`, and `docs/l` → `$c/.claude/sub`.
- A link folder `$s` from `mktemp -d /tmp/cg-tok.XXXXXX`, holding:
  - `srcl` → `$c/src`; `pkg` → `$c/package.json`; `cl` → `$c/.claude`;
    `clsub` → `$c/.claude/sub`; `gl` → `$c/.git`;
  - `x.log` and `x2.log`, each → `$c/src/a.py` (M9);
  - `ok/` (a plain folder holding a plain file `f`) and `d/` (a plain folder holding a link
    `z.log` → `$c/src/a.py`);
  - `evil`, a plain file;
  - `t.tar`, a tar archive containing a symlink `l` → `$c/src/a.py`, built with `tar -cf` in
    the fixture.
- Both folders are removed at the end, each by its exact path.
- "Not pass" means ask or deny.
- Each case line is probed against `8e39637` before it is written. A Reproduction line must
  fail there; a Characterisation line must already give the expected verdict. A line whose
  probe disagrees with its block moves to the other block, and the move is reported at the
  next checkpoint. Its expected verdict never changes.

### Test-first: `.claude/hooks/test-hooks.sh` (kit toolchain, `run_tokenizer_cases`)

**Reproduction** (this plan corrects review findings: each line fails on `8e39637`)
- [ ] CG84 `find $s/srcl/ -delete` is not pass (it would empty `src`).
- [ ] CG85 `find . -fprint $s/pkg` is not pass (it would overwrite `package.json`).
- [ ] CG86 `shred $s/pkg`, `chmod 600 $s/pkg` and `touch $s/pkg` are each not pass.
- [ ] CG87 `curl --output $s/pkg https://example.invalid` and
      `pnpm vitest run --outputFile=$s/pkg` are each not pass.
- CG88: dropped (pass 2). `ln -s /etc/hostname $c/src` and `cp /etc/hostname $c/src` also
  pass on the direct path, so "as the direct path does" means pass. This is recorded as an OUT
  residual.
- [ ] CG89 `mv $s/evil $s/c?/settings.json`, `rm $s/c?/settings.json` and
      `ln -sf $s/evil $s/c?/settings.json` are each not pass (a glob crossing the `cl` folder
      link).
- [ ] CG90 `echo x a2<$c/src/a.py >/dev/fd/0`, `true&&<$c/src/a.py echo x >/dev/fd/0`,
      `echo x 2>&1<$c/src/a.py >/dev/fd/0`, `echo x >&2<$c/src/a.py >/dev/fd/0` and
      `echo $<$c/src/a.py >/dev/fd/0` are each not pass.
- [ ] CG91 each of these is not pass:
  - `l'n' -s $c/src/a.py $s/l && echo x > $s/l`
  - `l\n -s $c/src/a.py $s/l && echo x > $s/l`
  - `rsync -a $s/x.log $s/l && echo x > $s/l`
  - `cp -r $s/d $s/e && echo x > $s/e/z.log`
  - `mv $s/x.log $s/l && echo x > $s/l`
  - `tar -xf $s/t.tar -C $s && echo x > $s/l`
  - `$(which ln) -s $c/src/a.py $s/l && echo x > $s/l`
- [ ] CG92 `cd -P $s/clsub/.. && echo x > settings.json` and, with cwd `$c`,
      `cd -P docs/l/.. && echo x > settings.json` (both write `.claude/settings.json`) are
      each not pass.
- [ ] CG99 `curl -o $s/pkg URL`, `curl -sSLo $s/pkg URL`, `wget -O $s/pkg URL`,
      `wget --output-document=$s/pkg URL` and `curl -o $c/package.json URL` are each not pass.
- [ ] CG104 bash's physical modes and `env -C` (each writes `$c/.claude/settings.json`) are
      each not pass:
  - `set -P; cd $s/clsub/.. && echo x > settings.json`;
  - `set -o physical; cd $s/clsub/.. && echo x > settings.json`;
  - `env -C $s/clsub/.. tee settings.json`.
- [ ] CG107 with cwd `$c/docs`, `find -P $s/srcl/ -delete`, `find -H $s/srcl -delete` and
      `find -H $c/s''rc -delete` are each not pass (find's global options before the root).
- [ ] CG108 `ln -s $c/.claude/hooks $s/D && ln -sf /tmp/x/f $s/D` is not pass (a link
      operand that the same call makes into a folder link).
- [ ] CG105 `find $c/s''rc/ -delete` (a quoted spelling the raw-text deny misses) is not pass.
- [ ] CG103 `cat 1 < $c/src/a.py > /dev/stdout` is not pass. It was moved from
      Characterisation by the probe rule: it passes at `8e39637`.

**Characterisation** (already holds on `8e39637`; must keep holding)
- [ ] CG93 each of these passes:
  - acting on a link itself: `rm $s/x.log`, `unlink $s/x.log`, `mv $s/x.log $s/ok/`,
    `ln -sfn $c/src/a.py $s/x2.log` (an existing link), `ln -sf /etc/hostname $s/x2.log`
    (a link to a file is replaced, not followed), `ln -sfn /etc/hostname $s/srcl`,
    `ln -s $c/src/a.py $s/l2` (alone);
  - reserved words and here-docs: `if true; then pnpm build > /tmp/o.txt; fi`,
    `cat <<EOF > /dev/stdout` (a here-doc binds nothing);
  - ordinary /tmp writes: `pnpm build > /tmp/out.txt 2>&1`,
    `echo a > /tmp/a.txt; echo b > /tmp/b.txt`, `find $s/ok -name '*.log' -delete`,
    `chmod 600 $s/ok/f`, `touch $s/ok/f`, `cd $s/clsub/.. && echo x > $s/ok/f`;
  - builtins before a /tmp write: `cd $c && pnpm build > /tmp/out.txt 2>&1`,
    `export X=1; echo x > /tmp/o.txt`;
  - fd and redirect forms: `cat <<<hi > /dev/stdout`, `exec 3>&1; echo x >/dev/stdout`,
    `sort < in.txt > /dev/stdout`, `awk '$1<10' f > /dev/stdout`,
    `pnpm test:run 2>&1 | tee /tmp/x.log`, `ls /tmp && echo x > /tmp/out.txt`;
  - in-project writes: `echo x > docs/a.md` (with cwd `$c`).
- [ ] CG94 these resolve to the project file on their physical side:
  - `echo x > $s/x.log` is denied ("src/a.py written by a redirect");
  - `echo x | tee $s/pkg` asks with "guarded path: package.json";
  - `truncate -s0 $s/pkg` and `mv /tmp/f $s/srcl` are each not pass;
  - `cd $s/cl && echo x > settings.json` is not pass.
- [ ] CG95 `exec {fd}<$c/src/a.py; echo x > /dev/stdout` is not pass (an unknown fd binding).
      `echo x > /dev/stdin` is not pass (no exemption).
- [ ] CG100 a second link maker (C3): `ln -s $c/src/a.py $s/l3 && cp $s/evil $s/l3` is not
      pass.
- [ ] CG101 inner link makers (C4) are each not pass:
  - `pnpm exec ln -s $c/src/a.py $s/l4 && echo x > $s/l4`;
  - `find . -maxdepth 0 -exec ln -s $c/src/a.py $s/l5 \; && echo x > $s/l5`;
  - `awk 'BEGIN{system("ln -s '$c'/src/a.py '$s'/l6")}' && echo x > $s/l6`, and the same with
    `;` instead of `&&`.
- [ ] CG106 a follows=False operand under a folder link made in the same call (pass-3
      Critical) is each not pass:
  - `ln -s $c/.claude $s/L && rm $s/L/settings.json`;
  - `ln -s $c/.claude $s/L && unlink $s/L/settings.json`;
  - `ln -s $c/.claude $s/L && mv $s/L/settings.json /tmp/z`;
  - `ln -s $c/.git $s/G && rm $s/G/config`.
- [ ] CG102 the physical fallback (M3): `cp $s/evil /tmp/b && rm $s/gl/config` is denied
      (".git/config written by rm"), not asked.
- [ ] CG103 the fd rule and secret mode:
  - `head -n 5 < $c/src/a.py > /dev/fd/0` is not pass (C2, a spaced digit binds fd 0 too);
  - in secret mode, `cat 2< .env` keeps its verdict at `8e39637` (C1: no crash, no lost
    verdict).
- [ ] CG109 awk/sed link makers are read from the program text only: `sed -n '1,20p' f > /tmp/x`,
      `awk '{print $1}' logs/system.log > /tmp/x` pass; `sed -e 's/x/y/e' f > /tmp/x` is not pass.
- [ ] CG110 `cat 2< .e''nv` is denied in secret mode. CG111 a Unicode digit (`²`) is no fd and
      does not crash. CG112 npm drops its first `--` (`npm exec foo -- --output package.json`
      not pass, `npx` form passes). CG113 `pnpm dlx foo-gen` is an unknown program, one maker
      (`... && echo x > /tmp/out.txt` not pass, alone passes). CG114 `find -L/-follow $s ...
      -delete` not pass, `find -H` passes. CG115 a shell_targets.py of guard API 4 fails closed.
- [ ] CG116 everyday awk writing to /tmp passes (`/systemd/`, `"system ok"`, `"|"` in print, OFS,
      split and tables, `-v`/`--assign`/`--field-separator` values, `~ /a|b/`).
- [ ] CG117 real awk makers are not pass: `system(...)`, `print "x" | "sh"`, `"cmd" | getline`,
      `print | c`, `c | getline`, `|&`, `-f`/`--file` (fail closed).
- [ ] CG118 sed is weighed by `sed_rows`: `sed 's/foo/\/etc/' f && echo x > /tmp/o` and
      `sed -n '1,20p' src/x/services.ts > /tmp/s.txt` pass; `s///e`, `1e`, `$e`, `/x/e`,
      `--expression=`, `--expr=` and `-f` are not pass.
- [ ] CG119 `find -L $s -exec grep|cat` and `-follow` inside an `-exec` pass; `-exec rm|cp` under
      `-L` and `-follow` among find's own words are not pass.

**Business rules** (RED as passes: the structural rule makes these false asks unreachable)
- [ ] CG96 an unknown or read-only verb:
  - `frobnicate $s && echo x > /tmp/out.txt` is not pass (an unknown command in another
    segment);
  - `grep -rn link src > /tmp/hits.txt` passes (grep is non-creating; the word "link" no
    longer matters);
  - `git diff > /tmp/x.diff` passes (git diff is read-only);
  - `git checkout x && echo y > /tmp/out.txt` is not pass (git checkout writes the working
    tree).
- [ ] CG97 cp alone vs. cp followed by another write:
  - `cp --verbose a /tmp/b` passes (cp alone, its own segment);
  - `cp a /tmp/b && echo x > /tmp/b2` is not pass (cp is link-capable, and another segment
    writes to /tmp).

**Edge cases / structure**
- [ ] CG98 a structural check:
  - `prevent-destructive-commands.sh` contains neither `guard_fd_bound` nor
    `guard_makes_link`;
  - it defines `guard_is_write_verb` exactly once, and `guard_classify_outside` once;
  - `shell_targets.py` emits no `?tmp:` (grep);
  - both files carry `# cwk-guard-api: 5`.

### Test-after
- None beyond the above. The existing suites (`test-hooks.sh` with its 2192 cases, and the 8
  other kit suites) are the non-regression gate after every GREEN. test-install's hold-back
  case (test-install.sh:477-478) must stay green with API 5.

## OUT residuals (recorded in harness-hardening.md, not fixed here)
- A package script run by a runner (`pnpm build`) is not a link maker (D3).
- `cp a 5 < f`: the popped `5` is lost as a cp operand, so its write row is missing.
  Pre-existing at HEAD.
- `ln`/`cp` into a protected folder (`cp x src`, or the same through a /tmp folder link)
  passes, on the direct path too. No row rule keys on a link-capable verb into a protected
  dir.
- `mv <link to src> /tmp/x` asks with ASK_M at HEAD and after this plan. Acceptance 1's
  `mv <link> /tmp/x` is read as a link to a file (CG93).
- A read-only verb that runs a program through its environment or config
  (`GIT_EXTERNAL_DIFF=… git diff`, `git -c diff.external=…`, `LD_PRELOAD=…`) is not a link
  maker. Same gap at HEAD.
- The text pre-filter at PDC:840 still strips `N>&M` before it looks for `>`. It only decides
  whether to run the tokenizer and binds nothing, so it is not the fd regex acceptance 6
  removes.
- Accepted cost (D3, fail closed): `awk -f prog.awk f > /tmp/o` alone still asks, because an
  unreadable awk program counts two link makers and no carve-out is invented.
- Pre-existing Major, follow-up (user, 2026-11-15): `tokens()` (ST:408-419) turns `\;`,
  `';'` and `\(…\)` into operators, and `cwk_segments` (hook-lib.sh:217/221) splits on `\;`.
  Everything after the first escaped terminator goes unchecked: `-exec … \; -delete`, a second
  `-exec sed -i … \;`, `-fprint/-fls/-fprintf`, the `\(…\) -delete` root ask. Recorded in
  `docs/specs/harness-hardening.md`.
- Review 1/3 Minors, not fixed (user, 2026-11-13):
  - `?link:` asks when `CLAUDE_PROJECT_DIR` is unset.
  - `shopt -so physical` and `set -eo physical` are missed by the physical-mode tracking
    (pre-existing).
  - False asks: `mv` destination and `touch -h`.
  - Plan-allowed false asks on everyday chains: `cp a b && cp c d`, `cp x /tmp/b && rm /tmp/b`,
    GIT_READ lacks merge-base, rev-list, remote, describe, tag, cat-file, ls-tree and reflog,
    a venv activation then pytest, `npx tsc; eslint`.
  - `find docs -delete` passes where `rm -r docs` asks (pre-existing).
  - O/L/I: the `link_maker_weight` kind ladder and the mutable module global `ACTS_ON_LINK`.
  - NON_CREATING holds `patch` and `trap`, beyond the plan.
  - `cp -a` as the sole link maker into a folder that already holds a link (known limit).
  - `settled()` ignores `?unknown` makers.
  - ST has no marker for an old PDC paired with a new ST (only PDC checks ST line 2).

## Vigilance (carried from research and the critic)
- Test projects live under /tmp: every "outside" test goes through `in_project` (D0), which
  mirrors `cwk_guard_rel`'s physical fallback (CG102, CG42, CG48).
- Every new label must sort without a KeyError at ST:629, and must reach a verdict in a test
  (CG90/91/95/96).
- No `redirect` signature changes: the fd goes through `note_fd`. The secret-mode rows of the
  existing suite must stay identical (CG103).
- A popped digit binds both N and the default fd (CG103).
- A live, unknown, interpreter or inner link-making verb makes its command a link maker
  (CG91, CG96, CG101). Builtins and read-only verbs do not (CG93).
- The own-segment exemption applies only to a sole link maker (CG100). A pipeline counts as
  several segments. Only settled `follows=False` rows escape the `?link:` rewrite: their parent
  exists, and no other link maker targets them or a parent (CG35, CG102, CG106, CG108).
- find's root parser skips `-H/-L/-P/-D/-O` (CG107).
- `find-delete` changes no verdict outside a protected dir or the root (CG93's
  `find $s/ok … -delete`).
- The physical flag and `env -C` only change the cwd State; they never add a row of their own.
- PDC stays bash-3.2-safe (X16): no `mapfile`, `readarray`, `[-1]`, `declare -A` or
  `local -A`. Under `set -e`, no trailing `[[ … ]] && x` in a function.
- Final-component semantics key on verb, operand position **and** flags (`mv` source vs
  destination, `ln`'s last operand only with `-n`/`-T`) (CG88, CG93).
- `cwk_guard_rel` stays lexical-first: do not change hook-guarded.sh.
- `exec_rows` → `self.finish` → `note_kit` shifts kit-cwd numbering. The double root must
  not double the kit-cwd asks (the X24.4xx kitwt rows stay as they are). The `cd -P`
  mapping back to the lexical project prefix keeps X24.439-456 as they are.
- D5 changes no verdict: the R2 set has no `mv`; the outside path keeps the no-project return
  and the rm-r/flag-r/cfg `ASK_O`.
- No PDC message reuses "outside the project" wording (the git-guard asserts it).
- API bump: ST and PDC both go to 5; HG stays at 4; test-install stays green.

## Acceptance criteria (carried from the entry artifact)
- [ ] With the scratch project and a /tmp link to `src` or `package.json`: `find <link>/ -delete`,
      `find . -fprint <link>`, `shred <link>`, `chmod 600 <link>`, `curl --output <link> URL`
      and `pnpm vitest run --outputFile=<link>` each ask or deny, as the direct path does.
      `rm <link>`, `unlink <link>`, `mv <link> /tmp/x` and `ln -sfn X <link>` pass.
- [ ] `echo x a2<P/src/a.py >/dev/fd/0`, `true&&<f echo x >/dev/fd/0`, `echo x 2>&1<f >/dev/fd/0`
      and `echo x >&2<f >/dev/fd/0` ask. So do the CG61-63, CG72 and CG81 spellings.
      `sort < in > /dev/stdout`, `cat <<<hi > /dev/stdout`, `2>&1 | tee /tmp/x.log`,
      `exec 3>&1` and `awk '$1<10' f > /dev/stdout` pass.
- [ ] `l'n' -s P/src/a.py S/l && echo x > S/l`, `rsync -a S/x.log S/l && echo x > S/l`,
      `cp -r S/d S/e && echo x > S/e/z.log`, `mv S/x.log S/l && echo x > S/l` and
      `tar -xf t.tar -C S && echo x > S/l` ask. `ln -s X /tmp/l` alone passes.
      `pnpm build > /tmp/out.txt 2>&1` passes.
- [ ] `mv S/evil R/c?/settings.json` and `rm R/c?/settings.json`, with `cl` → `P/.claude`,
      ask, as the direct path does.
- [ ] `cd -P R/clsub/.. && echo x > settings.json`, with `clsub` → `P/.claude/sub`, asks.
- [ ] The write-verb test exists once, in `guard_is_write_verb`. `guard_classify` no longer
      holds the /tmp and fd exemption, and no raw-text fd or link regex remains in
      `prevent-destructive-commands.sh`.
- [ ] Every kit suite is green (`test-hooks.sh` and the 8 others). Every case of CG54-CG83
      keeps its verdict, unless the plan gate names a correction.

## Plan critic
- pass 1: completeness 66 · quality 34. Blockers C1-C4, M1-M10, all confirmed by the
  verifier; addressed in revision 2 (C1/C2 → D2, C3/C4/M6 → D3, M1/M8 → D4, M2 → D1,
  M3 → D0, M4/M5 → D5, M7 → D7, M9/M10 → fixture and CG99-CG103).
- pass 2: completeness 70 · quality 58. Blockers:
  - Critical: no row rule for `find -delete` on a protected dir → D8, CG105;
  - Major: `set -P`/`env -C` left lexical → D4, CG104;
  - Major: CG88 could never go GREEN → dropped, OUT residual;
  - Major: the `?link:` rewrite broke CG35 → D3 exclusion.
  The cited lines were checked in the main thread (PDC:144-149, PDC:774-782, TH:1929-1930).
  Minors fixed in passing: the `ln -sf` file link (D1), the reserved words (D3), the D0
  wording, and the here-doc case.
- pass 3: completeness 80 · quality 60. **BLOCKED: plan-critic failed 3x** (no 4th rewrite).
  Surviving blockers:
  - Critical: D3's follows=False exemption reopens C3. With
    `ln -s P/.claude /tmp/L && rm /tmp/L/settings.json`, L does not exist at hook time, so the
    row stays a plain /tmp path and passes. HEAD asks.
    - Proposed fix: exempt a follows=False row only when its parent folder exists at hook time,
      and add one case per verb (rm, unlink, mv source, ln).
  - Major: ST's find root parser drops roots after `-H/-L/-P/-D/-O`. With cwd=docs,
    `find -P /tmp/x/srcl/ -delete` passes.
    - Proposed fix: skip those options before reading roots, and add -P/-H variants of
      CG84/CG105.
  - Minors: D8 denies at the root where HEAD asks (`find . -name '*.pyc' -delete`); D8 makes
    `find dist/assets … -delete` ask; the D8 branch must sit after cwk_is_guarded (X2.05).
- Revision 4 (user, 2026-11-12: "Fix, then the gate", no 4th critic pass). Both proposed
  fixes applied:
  - D3 settled operands, cases CG106 and CG108;
  - the find global options in D8, case CG107;
  - the D8 Minors (no new deny at the root; the branch placed after cwk_is_guarded).
- surviving blockers: none known. A 4th pass was waived by the user; RED→GREEN and the
  review are the remaining checks.

## Gate
- 2026-11-12 go (revision 4)
- Contract: as written
- Creator definition → structural D3: LINK_CAPABLE, unknown, live and interpreter verbs, and
  inner commands; a missing NON_CREATING entry asks (CG91, CG96, CG97, CG101)
- guard-api bump → ST and PDC to 5, HG stays at 4 (CG98)
- fd row shape → one `fd-bound\tN` row per bound fd, computed in Python (CG90, CG95, CG103)
- cd physical → `cd -P`, `set -P` and `env -C` follow links everywhere; plain `cd` under /tmp
  stays logical (CG92, CG104, CG93)
- Decisions: package scripts are not link makers; CG88 dropped; a filtered `find -delete`
  inside a protected dir asks
- 2026-11-12, before the review: threat model = **careless agent**. The shell guard stops
  plausible mistakes. A deliberate contortion (a link made then followed, a re-bound fd, an
  inner command) is recorded as a known limit, never a blocker. The review of this pass is the
  last on the /tmp, fd and link family; review ceiling 3, held strictly.
