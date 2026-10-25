---
topic: fastapi
checked: 2026-08-22
stability: pinned
sources:
  - addons/fastapi/skills/patterns/pytest-backend.md (measured locally on pytest 9.1.1 and pytest-asyncio 1.4.0, twice; no URL)
---

Version-specific facts behind `addons/fastapi/skills/patterns/`.

- A missing `pytest.mark.asyncio` (with `asyncio_mode` unset) makes an
  `async def` test fail with `async def functions are not natively supported`.
  Measured on pytest 9.1.1, with pytest-asyncio 1.4.0 in strict mode and with no
  async plugin at all: same message, same exit code. An older claim that the test
  "silently skips" was never measured and could not be checked.
- The console script `pytest` does not put the project root on `sys.path`; only
  `python -m pytest` does. Without `pythonpath = ["."]`, a tree laid out as the
  addon prescribes exits 2 on `No module named 'app'`. Measured.
- Collection-time import errors and their exit code: see `testing-tooling.md`.
