# Spec: guard-tokenizer-fd-links: the /tmp and fd exemptions decided from tokenized rows
Token profile: critical

## Objective
A shell command can no longer write into, or delete from, `CLAUDE_PROJECT_DIR` without an ask
or a deny by routing the write through `/tmp`, a symlink or an fd alias. The hook decides this
from rows the `shell_targets.py` tokenizer emits, not by re-reading the raw bash text with
regexes.

## Scope
IN. The findings that are still open after `tmp-exemption` (`8e39637`), as listed in
`docs/specs/harness-hardening.md` under "From the `tmp-exemption` review 2/3":
- **Non-writer verbs through a /tmp link** (Critical). Today a `?tmp:` row takes its physical
  side only for `>`, `>>` and the source writers other than `ln`.
  - The physical side must apply to every verb that writes or deletes through the path:
    `find -delete`, `find -fprint`/`-fprintf`/`-fls`, `shred`, `chmod`/`chown`/`touch`,
    `curl --output`/`-o`, `wget -O`, and the flag-w and flag-r options.
  - The exception is a final-component `rm`, `unlink`, `mv` or `ln`, which acts on the link
    itself.
- **fd bindings come from the tokenizer** (Critical). `guard_fd_bound`'s regex is replaced by
  rows the tokenizer emits from the redirects it already parses. This closes every spelling
  the regex misses: `a2<f`, `true&&<f`, `2>&1<f`, `>&2<f`, `$<f` on `/dev/fd/0-2`, and the
  `<<<` here-string that was read as binding fd 0.
- **Structural link rule** (Critical, replaces R4's name list). A /tmp write asks when the
  same Bash call also contains one of:
  - another command that creates, copies or moves something under /tmp (a row with a /tmp
    target from a different command);
  - a command the tokenizer cannot read.

  `guard_makes_link`'s regex goes. The `ln`/`link` row itself and a lone link creation still
  pass.
- **mv/rm/ln through a /tmp glob that crosses a link to a folder** (Major). Example:
  `mv $S/evil $R/c?/settings.json`, with `cl` → `$P/.claude`. The glob asks when any folder
  segment before its last segment can be a link, or else it is resolved on its physical side.
- **`cd -P <link>/..`** (Major). `resolve_in` follows links before `..`, as `tmp_physical`
  does, for `cd -P`, and for plain `cd` when the target is under /tmp.
- **Structure** (Major, SOLID O / DRY):
  - one `guard_is_write_verb` helper replaces the 4 copies of the write-verb test, including
    the variant with `mv`;
  - the /tmp and fd exemption moves out of `guard_classify` into its own function, in the
    style of `guard_classify_tool`.

OUT:
- The fail-closed Minors: the false asks on `grep link > /tmp/x` and `cp --verbose a /tmp/b`,
  `$((1<2)) > /dev/stdout`, the `-exec cat` ask on a `?` root, `find /tmp/x -exec sed -i`
  asking under R2, and a unit separator in a link target's name.
- The test-hygiene Minors: a skipped CG77 is not counted; the CG74/CG75 fixtures are inert.
- Other items from the earlier OUT lists: alias writes (`expand_aliases`), and `dd of=`/`sort -o`
  outside /tmp.
- Any loosening of what asks today, outside the Minors that the structural rule makes
  unreachable. Every pass in CG54-CG83 and in the existing pass lists stays a pass, unless
  the plan gate names it.

## Data model
none

## Custom backend
NONE: kit hooks only (`.claude/hooks/shell_targets.py`, `prevent-destructive-commands.sh`,
`hook-guarded.sh` if `cwk_guard_rel` is touched).

## Front surface
none (kit harness)

## Acceptance criteria
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

## Business logic to cover
- The tokenizer's fd-binding rows: a read redirect binds an fd, a dup copies a binding, a
  `{var}` fd is unknown, a here-string and a here-doc bind nothing, and `$1<` is not a redirect.
- The tokenizer's per-call /tmp creation rows, which feed the structural link rule, and its
  unreadable-command marker.
- Which side of a `?tmp:` row each verb takes: physical for every write or delete through the
  path, lexical for a final-component `rm`/`unlink`/`mv`/`ln`.
- A /tmp glob that crosses a folder link, for `mv`, `rm` and `ln`.
- `cd -P` and a /tmp `cd` resolving links before `..`.
- Non-regression of the existing pass lists (C5, CG70, CG78-79) and of every ask and deny
  already pinned.
