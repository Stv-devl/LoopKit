# Spec: The git hook reads the real subcommand
Token profile: standard (a guardrail fix: a push or a merge into a protected branch can pass unasked today)

## Objective
`enforce-git-workflow.sh` matches git commands with patterns such as `\bgit\s+push\b` (`enforce-git-workflow.sh:133`, `:137`) and `\bgit\s+(merge|rebase)\b` (`:145`). Any global option between `git` and the subcommand defeats them: `git -C <dir> push`, `git --no-pager push`, `git -c x=y push`, `git -C <main-tree> merge feat/x` all pass without the prompt the hook exists to raise. The hook finds the subcommand first, then applies its existing rules to it, unchanged.

## Scope
- IN :
  - **H1. Subcommand parsing, per segment**, one function in `enforce-git-workflow.sh`, replacing the single `-C` lookup of `enforce-git-workflow.sh:88-91`:
    - the command is split into segments on `;`, `&&`, `||`, `|`, `&` and newlines; every segment whose first word is `git` is parsed on its own, so `git -C a log && git -C b merge x` checks the merge against `b`;
    - in a segment, skip global options before the subcommand: every token starting with `-`, plus the value of the options that take one as a separate token: `-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`, `--config-env`, `--exec-path`, `--attr-source` (the `--opt=value` form is one token). Every `-C` counts, wherever it sits among the globals, combined as git does (`-C a -C b` is `a/b`); surrounding quotes are stripped;
    - the first remaining token is the subcommand; the rules that matched `git\s+<sub>` now match on it, with the same arguments after it;
    - **rules that do not need a directory run first**: the push, `send-pack` and alias asks (H2, H3) never depend on resolving `-C`. Then the segment's directory (its `-C`, else the hook's `cwd`) feeds the branch checks. A directory that does not resolve no longer exits 0 (`enforce-git-workflow.sh:91` today): for `merge`, `rebase`, `commit`, `reset`, `switch`, `checkout` it **asks**, naming the unresolved path; for read-only subcommands it passes as today.
  - **H2. Aliases**: asks on `git -c alias.<x>=…` and `git --config-env alias.<x>=…`; resolves a subcommand that is not a git builtin through `git config --get alias.<sub>` (read-only) and asks when the value contains `push`, `merge`, `rebase`, `send-pack` or starts with `!`. One level is enough: an alias chain asks.
  - **H3. `git send-pack`** asks, as `push` does.
- OUT :
  - No change to what each rule decides (ask, deny, pass); only to what reaches it.
  - No change to the other hooks.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/hooks/enforce-git-workflow.sh`, `.claude/hooks/test-hooks.sh` and its fixture harness: a fixture repo with a `main` worktree and a `feat/x` worktree, exposed to fixtures as `__MAIN_TREE__` and `__FEAT_TREE__` placeholders next to the existing `__PROJECT_ROOT__`, and a repo-local `alias.p=push` for G3.

## Acceptance criteria
- [ ] Every form below asks exactly as its plain form does; every plain form keeps its current decision.
- [ ] `test-hooks.sh` passes, existing cases unchanged.

## Business logic to cover
Hook fixtures (`test-hooks.sh`):
- G1 `git -C __MAIN_TREE__ push origin main`, `git -C /nonexistent push`, `git -C "__MAIN_TREE__" push`, `git --no-pager push`, `git -P push`, `git -c a=b push`, `git --git-dir /tmp/x/.git push`, `git --namespace n push`, `git --attr-source HEAD push`: ask, as `git push`.
- G2 from `__FEAT_TREE__`: `git -C __MAIN_TREE__ merge --ff-only feat/x`, `git --no-pager -C __MAIN_TREE__ merge feat/x`, `git -C __FEAT_TREE__ log && git -C __MAIN_TREE__ merge feat/x`: ask, as `git merge` on a protected branch. `git -C /nonexistent merge x`: ask, naming the path.
- G3 `git -c alias.p=push p`, `git p` with `alias.p=push` in the fixture config, `git q` with `alias.q=!sh -c x`, `git send-pack x`: ask.
- G4 `git -C __FEAT_TREE__ status`, `git --no-pager log`, `git -C __FEAT_TREE__ diff`, `git -C /nonexistent status`: same decision as the plain form (no new ask).
- G5 `git log --oneline` and every existing fixture: unchanged.

## Order
1. Fixtures G1-G5 first, observed failing on G1-G3.
2. H1, H2, H3.
