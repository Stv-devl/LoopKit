---
description: Removes dead Python code (unused imports, variables, functions)
context: fork
disable-model-invocation: true
argument-hint: [files or module, e.g. "app/services/" or "the whole backend"]
---

# Clean Python Agent

Removes dead code from the Python codebase.

## Tools

```bash
ruff check app/ --select F401,F811,F841 --output-format=full   # unused imports, redefinitions, dead vars
ruff check app/ --select F401,F811,F841 --fix                  # autofix the safe ones
vulture app/ --min-confidence 80                               # never-called functions/classes
ruff format app/
```

> **`app/`, never `.` — and that is not a scoping preference.** `ruff format .`
> and `ruff check . --fix` REWRITE files from the shell, so no PreToolUse hook
> sees them: measured, the same rewrite through `Write` is denied while
> `ruff format .` goes through silently. On `tests/services/**` that means a
> frozen test rewritten past the freeze, and `marker_is_fresh()` flipping
> `True -> False` — a mid-cycle RED destroyed by step 6 of this very command.
>
> If the repo needs a repo-wide `ruff format`, give it a real carve-out instead
> of a habit:
>
> ```toml
> [tool.ruff]
> extend-exclude = ["tests/services"]
> ```
>
> Dead code in `tests/` is a different job anyway: a test nothing calls is a
> test, and `vulture` on a test tree is noise.

## Process

1. **Scan** with the commands above
2. **Read** the findings:
   - `F401` unused import → remove
   - `F811` redefinition → decide which one survives
   - `F841` assigned, never read → remove
3. **Check the exceptions below** before deleting anything
4. **Delete**, completely — never comment out
5. **Test**: `python -m pytest -x` after each significant removal
6. **Format**: `ruff format app/`

## Never delete — imports that exist for their side effect

```python
# Model re-exports: Alembic autogenerate only sees imported models.
# Delete these and the next migration is empty — or drops your tables.
from app.models.tenant import Tenant  # noqa: F401
from app.models.user import User      # noqa: F401

# pytest fixtures: importing is registering
from tests.conftest import client, db, tenant  # noqa: F401

# Type-only imports
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from app.models.user import User

# Router / handler registration by import
from app.api import chat, documents, projects  # noqa: F401
```

Same trap class in every case: the import *is* the wiring. `ruff` cannot see it,
`vulture` cannot see it, and the failure shows up one deploy later.

## Checklist

- [ ] No unused import (`F401`) outside the exceptions above
- [ ] No dead variable (`F841`)
- [ ] No function or private method that nothing calls
- [ ] No declared dependency that nothing imports
- [ ] Every kept side-effect import carries `# noqa: F401` and a reason
- [ ] `ruff check app/` clean, `ruff format app/` applied — never `.`, see
      the box under **Tools**
- [ ] `python -m pytest -x` green

## Rules

- Delete, do not comment
- Fix the imports that the deletion broke
- Run the tests after each batch, not once at the end

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
