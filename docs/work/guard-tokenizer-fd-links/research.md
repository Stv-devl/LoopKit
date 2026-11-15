# Research: guard-tokenizer-fd-links   (entry: docs/specs/guard-tokenizer-fd-links.md)
Token profile: critical

Abbreviations: ST = `.claude/hooks/shell_targets.py` (1930 lines), PDC = `.claude/hooks/prevent-destructive-commands.sh`
(1002 lines), HG = `.claude/hooks/hook-guarded.sh` (292), TH = `.claude/hooks/test-hooks.sh`,
SG = `.claude/hooks/fixtures/_harness/shell-guard.jsonl` (896 rows). Lines are from the tree at
`8e39637`. Three explorers mapped the tokenizer, the classifier and the tests. Their maps
agree; one point is reconciled under Traps.

## Pattern to follow
- **A classifier split out of `guard_classify`.** `guard_classify_tool <verb> <target> <rel>`
  (PDC:528-565), called only at PDC:773. It reads globals, writes first-wins slots
  (`[[ -n "$SLOT" ]] || SLOT=…`) and denies through `guard_note_deny`. A
  `guard_classify_tmp_fd` would follow the same shape.
- **Rows from the tokenizer.** `Walker.finish` (ST:612-632) builds the rows. Redirect rows
  come at :615-617 (label from `redirect_verb`, ST:58-71), then the verb rows (`verb_rows`
  ST:650-677). A new row kind needs an entry in the sort dict at ST:629 (see Traps).
- **Physical resolution.** This already exists in `tmp_physical` (ST:1822-1860): links are
  followed in order, `..` is applied after them, `/proc` and `/dev` give `?`, and `st_nlink > 1`
  gives `?`. In bash, the physical helpers are `cwk_real_file` (HG:209-239, which follows the
  final link chain) and `__cwk_cd_pwd` (HG:175-181).

## Wiring points
- **Tokenizer call.** PDC:445-449 runs `python3 -B ST "$COMMAND" "$GUARD_BASE"`.
  - Exit 3 gives `GUARD_PARSE`; any other nonzero exit gives `GUARD_FAILED` (PDC:452-460).
  - Every row must match `^[^\t]+\t.+$` and the output must end in `#end\t<n>` (PDC:466-490).
  - The classify loop is at PDC:786-790.
  - On failure, the text rules apply (PDC:833-868).
- **Secret mode.** PDC:206 calls ST `--secret-reads`. `SecretWalker` (ST:788) overrides
  `redirect` (:805-809, which calls `super().redirect(seg, op, word)`) and `finish` (:811-826,
  which never calls `Walker.finish`). It shares `walk_segments`, `strip_prefixes`, `resolve_in`
  and `follow`.
- **Where the fd number is dropped.** `walk_segments` at ST:559-560 pops a digit word before a
  redirect: `if seg.words and seg.words[-1].isdigit(): seg.words.pop()`. `Walker.redirect`
  (ST:598-610) handles the rest:
  - `>&N`, `<&N`, `N>&M`, `>&-` give no row (:599-600);
  - `<` and non-digit `<&` set `seg.stdin_file` (:607-608);
  - `<<` records a heredoc and `<<<` a herestring;
  - everything else (`>`, `>>`, `>|`, `&>`, `<>`, `>&word`) is a write row (:609-610).
  - `{fd}<` is not handled: `{fd}` stays as a word (`exec {fd}>f` gives the verb `{fd}`, and
    no verb row).
- **Verb extraction.** `verb = os.path.basename(unhide(words[0]))` (ST:622), after
  `strip_prefixes` (ST:1091-1124), which strips `env command exec time nice nohup setsid sudo
  builtin stdbuf xargs timeout …`. Quoting is resolved by shlex. So `l'n'`, `\ln`, `"ln"`,
  `/bin/ln`, `command ln` and `env ln` all give `ln` (reading of ST:231-318 and :401-412).
  A verb `words[0]` that is live (`$CMD`, `$(which ln)`) is not checked with `has_live`:
  there is no row and no `?unknown`.
- **Writer families** (ST:101-103, `writer_rows` ST:1448-1470):
  - `EVERY_OPERAND` = mv, rm, rmdir, unlink, shred, truncate, touch, chmod, chown;
  - `LAST_OPERAND` = cp, install, ln, rsync;
  - also `tee`, `patch`.
  - **Verbs with no row at all**: `mkdir`, `tar`, `dd`, `sort -o`, `curl -o/-O`, `wget -O`,
    `gzip`/`unzip -d`, `make`, `awk -i inplace`. `curl`/`wget` get a row only through
    `--output` (`output_rows` ST:1438-1445).
- **find** (ST:735-757):
  - `-delete` gives row `("find", target(root))` (:745);
  - `-fprint`, `-fprint0`, `-fls`, `-fprintf` give `("find", target(next))` (:746-748);
  - `-exec`, `-execdir`, `-ok`, `-okdir` go through `exec_rows` (:759-785). A `?tmp:` root
    runs twice (:767-774).
- **Directory tracking.** `State` (ST:428-471) and `resolve_in` (ST:474-481) are purely
  lexical (`normpath`). `skip_cd_options` (ST:484-491) skips `-P`/`-L` and ignores what they
  mean. `follow` (ST:634-648) applies `cd`/`pushd`/`popd`.
- **`target()`** (ST:1863-1893). Its callers: ST:617, 711, 745, 747, 768, 1434, 1442, 1444,
  1467, 1645, 1647.
- **How the hook branches on the target kind** (PDC:605-784, mapped in full by explorer 2):
  - `?inline:`/`?unknown:` → slots or `ASK_U` (:615-633);
  - `?tmp:` (:636-656) takes the physical side only when `cwk_guard_rel` on the lexical side
    fails AND the verb is `>`/`>>`/a source writer other than `ln` (:645-646);
  - `?glob:` (:657-669) asks on a /tmp glob for that same verb set (:663-664);
  - the outside-project branch (:675-699) holds the fd case (:680-690, `guard_fd_bound`) and
    the /tmp exemption (:692-697, `guard_makes_link`), then `ASK_O` (:699).
- **The write-verb test is spelled 4 ways** (PDC:646, 663-664, 711, 726):
  - :646 and :663-664: `>`/`>>`/`GUARD_SOURCE_WRITERS` minus `ln`, without `mv`;
  - :711 and :726: `>`/`>>`/`mv`/`GUARD_SOURCE_WRITERS`, with `ln`.
  - `GUARD_SOURCE_WRITERS` = `sed perl cp tee install rsync ln patch truncate` (PDC:506).
  - The text fallback has its own list (PDC:842).
- **Raw-text regexes on `COMMAND`** in the guard section:
  - `guard_fd_bound` (PDC:567-596, caller :687);
  - `guard_makes_link` (PDC:598-603, caller :694);
  - `cmd_joined` / `*shopt*` (:710, :717);
  - extglob (:724-725);
  - and the text fallback (:833-858).

## Reusable
- `tmp_physical`, `under_tmp`, `under` (ST:1814-1860). Reuse them for `cd` resolution and for
  non-writer verbs; do not rewrite them.
- `cwk_real_file` and `cwk_real_rel` (HG:209-250) are the physical counterparts on the bash side.
- `guard_classify_tool`, `guard_note_deny` (PDC), `guard_show` (PDC:508) and
  `guard_is_root_or_above` (PDC:520).
- On the test side: `pd_probe` (TH:1630), `g15_expect` (TH:1211), `make_app_tree` (TH:1593),
  and the JSONL runner `run_shell_guard_cases` (TH:938-982; a row may have a `setup` and a `cwd`).

## Blast radius
- **Row consumers.** Only PDC reads the main-mode rows. `enforce-git-workflow.sh` has its own
  parser. No test asserts row text directly (explorer 3, §3): a new row kind is invisible
  until it reaches a verdict. PDC `guard_classify` has no `*)` branch, so an unknown `?kind:`
  falls into the plain-path logic. Nothing pins that.
- **Guard API header.** ST, PDC and HG each carry `# cwk-guard-api: 4` on line 2.
  test-install.sh:477-478 rewrites ST's header to 2 in a copy and expects
  `P1 held back: .claude/hooks/shell_targets.py`. The header must stay consistent if the
  row contract changes, which means deciding whether a new row kind bumps the API (see Open
  questions).
- **SecretWalker.** It depends on `Walker.redirect`'s signature `(seg, op, word)` and on `<`
  and non-digit `<&` still meaning stdin. Recording fds must not change either.
- **The non-regression set** (explorer 3, §2). Pass rows are the tripwires for over-blocking:
  - CG13 `/tmp/a.py`, CG29, CG33, CG60, CG70, CG78-79;
  - X9.09 `rm /tmp/x-*`, X24.104-107, X42.07;
  - X34.01-05, X39.23, X42.06, X9.12, X9.14, X24.363 (the `2>&1`/`>&2`/`/dev/null` family);
  - X23.14, X24.462, X24.476.

  The ask/deny pins on the same surfaces: X1.01, X4.02, X10.05/07, X33.01, X15.01/02,
  X17.01/05, X18.01, X22.10, X24.072/223, X24.412/414, X30.06/08, X40.01, X2.01-08 (find),
  X23.03, X24.439-456 (`cd -P` with pnpmlink), X1.10 (`ln -sf`), X1.12 (rsync), and CG54-CG83.
- **Message text.** `This write goes through a /tmp or fd path` and `This writes outside the
  project` are asserted nowhere. `outside the project` is asserted by the git guard
  (TH:1385-1387, git-guard.jsonl:542): do not reuse that wording in a PDC message. The
  `unresolved write target` text is asserted in 12 TH cases and 46 SG rows, and `guarded path:`
  in many.
- **Cost.** About 1,150 hook processes per `test-hooks.sh` run (896 JSONL rows, about 200 in
  codegen, plus the rest), more than 10 minutes. There is no single-group filter.

## Live DB state
n/a (kit hooks, no database).

## External surface
n/a. Bash and coreutils behaviour is settled in the prior units, proven in real bash 5.2.21:
`docs/work/tmp-exemption/debug.md` and the review reports recorded in
`docs/specs/harness-hardening.md`.

## Traps (points of vigilance for the review)
- **Test projects live under /tmp.** `mktemp -d`, `$c`, `$s` and every `__FIXTURE_ROOT__` are
  there. "Under /tmp" never means "outside the project": a project path under /tmp must
  still be classified in-project first (rev 2 already hit this, 14 failures).
- **The sort dict at ST:629.** A new `?kind` missing from it raises KeyError, exit 1, and the
  text fallback runs silently. Every new kind needs an entry and a test that reaches a verdict.
- **The fd number lives in `walk_segments`** (ST:559-560), not in `redirect()`. Recording it
  must still drop the digit from `words` (`echo 2 > f` already loses `2`), and must not change
  `SecretWalker.redirect`'s contract.
- **Reconciled point.** Explorer 1's verb-extraction trace shows that `l'n'` and `/bin/ln`
  already reach the tokenizer as `ln`. The leak in review 2/3 was in the bash regex, not in
  the tokenizer. But a live verb (`$(which ln)`, `$CMD`) and the no-row verbs (`tar`, `mkdir`,
  `unzip`, `dd`) are invisible to any rule built on rows. The structural link rule needs an
  explicit "unreadable or unmodelled command" signal.
- **Bash 3.2 compatibility in PDC.** X16 (TH:2297-2323) forbids `mapfile`, `readarray`,
  `[-1]`, `declare -A` and `local -A` in PDC. `set -e` is on (PDC:16): a trailing
  `[[ … ]] && x` in a function can exit the hook.
- **Final-component link semantics.** `rm`, `unlink`, `mv` (source), `ln` (target with
  `-n`/`-f`) act on the link. But `mv X /tmp/link-to-dir` moves *into* the folder, and
  `cp`/`tee`/`>` follow the link. The physical-side rule must key on the verb **and** the
  operand position (`mv`'s destination vs its source).
- **`touch -t STAMP f` turns the timestamp into a row** (ST:1485-1486, over-reports). With the
  physical side applied to `touch`, a bogus `/tmp/…` stamp row is harmless, but do not rely on
  it.
- **`exec_rows` calls `self.finish` on an inner segment.** That runs `note_kit`, which can
  shift the kit-cwd sequence (ST:624, read but not run). Keep that in mind if `exec_rows`
  changes.
- **`cwk_guard_rel` is lexical first** (HG:262-290): an in-project symlinked folder is not
  resolved. The `?tmp:` lexical-in-project check (PDC:645) relies on this. Do not "fix" it
  as a side effect.
- **Message wording.** No test pins `GUARD_ASK_T`'s text, so a reworded message is not a
  regression, but it should name the real cause (review 1 Minor).

## Open questions
1. **The structural link rule needs a definition of "a command that creates something under
   /tmp".** Rows exist only for modelled writers, and `tar`, `mkdir`, `unzip`, `dd` and live
   verbs produce no row. Which definition does the plan use?
   - (a) A /tmp write asks when another command in the call has a /tmp row, or when its verb
     is not on an allowlist of known non-creating commands (echo, cat, grep, ls, sort, head,
     tail, wc, the test runners, …).
   - (b) Add rows for tar, unzip, mkdir and dd, and treat only a live or `{fd}` verb as
     unreadable.

   (a) is the "no list of creators" option the user picked, at the cost of more asks; (b)
   brings back a list.
2. **Does the new row contract bump `# cwk-guard-api` from 4 to 5** in ST, PDC and HG
   together? That changes the install hold-back (test-install.sh:477-478). It is needed if an
   older PDC paired with a newer ST would misread the new rows; adding the kinds to PDC in
   the same commit avoids a mixed state only inside one install.
3. **fd-binding row shape.** One row per binding (`fd<\t><n>=path`, `fd<\t><n>=&<m>`,
   `fd<\t>?`)? Or a single per-call summary row giving the bound set, computed in Python? The
   second keeps PDC simpler and is consistent with "the tokenizer decides". The plan should
   pick one.
4. **`cd` under /tmp (M3).** Should `State` hold the physical directory after `cd -P` and after
   any `cd` into /tmp (via `tmp_physical`)? Or only after `cd -P`? X24.439-456 (pnpmlink, `cd -P
   node_modules/foo/../..`) are in-project asks today and must keep asking.
