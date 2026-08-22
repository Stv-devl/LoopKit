# Pytest Backend — Patterns

pytest is already run-once: no watch trap, a gate can call it directly. Always
as **`python -m pytest`** — the reason is `sys.path` and it is the first comment
in the block below.

## Configuration

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"      # no @pytest.mark.asyncio on every test
testpaths = ["tests"]
# The console script `pytest` does NOT put the project root on sys.path; only
# `python -m pytest` does. Measured: without this line, a tree laid out exactly
# as this addon prescribes exits 2 on `No module named 'app'` — and the very
# first import of the conftest below is `from app.api.deps import ...`.
pythonpath = ["."]
```

With `asyncio_mode = "auto"`, drop the markers. Without it, every async test
file needs `pytestmark = pytest.mark.asyncio` at the top.

**What a missing marker actually does: the test FAILS**, with `async def
functions are not natively supported`. Measured on pytest 9.1.1, twice — with
pytest-asyncio 1.4.0 installed in its default strict mode, and with no async
plugin at all. Same message, same exit code: not installing the plugin is not a
way around it.

Earlier versions of this file said the test "silently skips" instead. Whether
that was ever true of some pytest release is **not** something the note above
claims — it was not measured, and the toolchain here cannot run a pytest old
enough to check. What matters is that on any version you would ship today it
fails, loudly, with a message that points at plugins rather than at your code,
and that every async test in the repo shows it at once.

The consequence for `tests/services/`, which is frozen: not one assertion runs,
so `tdd-prove-red-py.py` refuses the red and records no marker. That is the
intended outcome — a configuration problem must not read as a RED phase.

## `conftest.py`

```python
from collections.abc import AsyncGenerator

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.api.deps import get_current_user, get_db
from app.core.database import Base
from app.main import app
from app.models.tenant import Tenant
from app.models.user import User

TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"

engine = create_async_engine(TEST_DATABASE_URL, echo=False)
TestSession = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


@pytest_asyncio.fixture(autouse=True)
async def setup_db() -> AsyncGenerator[None, None]:
    """Create tables before each test, drop them after."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture
async def db() -> AsyncGenerator[AsyncSession, None]:
    async with TestSession() as session:
        yield session


@pytest_asyncio.fixture
async def tenant(db: AsyncSession) -> Tenant:
    t = Tenant(id="tenant-test", name="Test Corp", plan="pro")
    db.add(t)
    await db.commit()
    await db.refresh(t)
    return t


@pytest_asyncio.fixture
async def user(db: AsyncSession, tenant: Tenant) -> User:
    u = User(
        id="user-test",
        email="test@test.com",
        hashed_password="$2b$12$fake",
        tenant_id=tenant.id,
        role="admin",
    )
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


@pytest_asyncio.fixture
async def client(db: AsyncSession, user: User) -> AsyncGenerator[AsyncClient, None]:
    """Authenticated client, DB and auth overridden."""

    async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db

    async def override_get_current_user() -> User:
        return user

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test",
        ) as c:
            yield c
    finally:
        app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def client_no_auth(db: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """Unauthenticated client: DB overridden, auth NOT overridden."""

    async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db

    app.dependency_overrides[get_db] = override_get_db

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test",
        ) as c:
            yield c
    finally:
        app.dependency_overrides.clear()
```

**Both fixtures, always.** `client` overrides `get_current_user`, so it can
never prove a route is protected: delete the dependency from a route and every
test stays green. `client_no_auth` is the only one that fails — one test per
protected router is enough (`patterns/fastapi-auth.md`, Testing).

**`app.dependency_overrides.clear()` is not optional, and it belongs in a
`finally`.** It is process-global: a fixture that raises before the cleanup
leaks a fake user into every later test file, and the suite goes green on an app
that never authenticates. Naming that hazard and then writing the teardown after
a bare `yield` was the older shape of this file — on a test failure pytest
resumes the generator and it runs, but if the fixture body itself raises after
setting the overrides, it does not.

**SQLite is not PostgreSQL.** `ARRAY`, `JSONB`, `ILIKE`, partial indexes,
`ON CONFLICT ... DO UPDATE`, server-side defaults and native UUIDs behave
differently or not at all. Test against a real Postgres (docker service or
`pytest-postgresql`) as soon as a query uses any of them — otherwise the suite
proves the ORM works, not the query.

## Endpoint test

```python
async def test_create_project(client: AsyncClient) -> None:
    response = await client.post("/api/projects", json={"name": "Test", "phase": "active"})

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Test"
    assert "id" in body


async def test_create_project_invalid_phase(client: AsyncClient) -> None:
    response = await client.post("/api/projects", json={"name": "Test", "phase": "NOPE"})

    assert response.status_code == 422


async def test_get_project_not_found(client: AsyncClient) -> None:
    response = await client.get("/api/projects/does-not-exist")

    assert response.status_code == 404
```

## Service test

```python
async def test_create_project(db: AsyncSession, tenant: Tenant) -> None:
    result = await project_service.create(db, tenant.id, ProjectCreate(name="Test"))

    assert result.name == "Test"
    assert result.tenant_id == tenant.id
```

## Isolation test — the one that must exist

```python
async def test_get_by_id_rejects_other_tenant(db: AsyncSession, tenant: Tenant) -> None:
    """Tenant B must not reach tenant A's row."""
    project = await project_service.create(db, tenant.id, ProjectCreate(name="Secret"))

    with pytest.raises(NotFoundError):
        await project_service.get_by_id(db, "other-tenant", project.id)


async def test_list_filters_by_tenant(db: AsyncSession, tenant: Tenant) -> None:
    await project_service.create(db, tenant.id, ProjectCreate(name="Mine"))

    rows, total = await project_service.list_all(db, "other-tenant")

    assert rows == []
    assert total == 0
```

Isolation is enforced by a WHERE clause in Python, not by the database. Nothing
warns you when it is missing — only this test does.

## Mocking external services

Assert the **behaviour** — what the function returned, or what the database and
the vector store hold afterwards. `05-testing.md` applies here in full: a test
that only asserts a mock was called survives every refactor of the logic and
fails on every refactor of the plumbing, which is exactly backwards.

```python
from unittest.mock import AsyncMock, patch


async def test_ingestion_indexes_every_chunk(db: AsyncSession, tenant: Tenant) -> None:
    embed = AsyncMock(return_value=[[0.1] * 1024, [0.2] * 1024])

    with patch("app.services.ingestion.embedding.embed_texts", embed):
        await run_ingestion(document.id, tenant.id)

    await db.refresh(document)
    assert document.status == "ready"          # ← the observable outcome
    assert document.chunk_count == 2
```

The exception `05-testing.md` allows — an effect with no return value and no
other observable trace — is real here, and the isolation filter is the case:

```python
async def test_search_scopes_query_to_the_calling_tenant(
    db: AsyncSession, tenant: Tenant
) -> None:
    """The document belongs to another tenant; the filter must carry the caller's."""
    await document_service.create(db, "other-tenant", DocumentCreate(name="Theirs"))
    search = AsyncMock(return_value=[])

    with patch("app.services.search.vector_client.search", search):
        await search_documents(tenant_id=tenant.id, project_id=..., query="x", filters=...)

    conditions = search.call_args.kwargs["query_filter"].must
    scoped = [c for c in conditions if c.key == "tenant_id"]
    assert len(scoped) == 1
    assert scoped[0].match.value == tenant.id       # ← the VALUE, not the key
    assert scoped[0].match.value != "other-tenant"
```

The filter is sent to a store this suite does not run, so there is no state to
read back and no return value that carries it. Asserting the call **is** the
only observation available — and the thing being asserted is a security barrier,
not a plumbing detail. Everywhere else, read the outcome.

**Assert the VALUE, and bring a second tenant in to prove it.** The shorter form
this snippet used to ship —
`assert any("tenant_id" in str(c) for c in payload_filter.must)` — never reads
what the filter is scoped *to*. A service passing the wrong variable
(`uploader_tenant`, the tenant from the document rather than from the caller)
satisfies it completely, and the only implementation change that fails it is
renaming the column: the change detector `05-testing.md` defines, on the one
assertion the whole tenant barrier rests on. Seeding a row for a *second* tenant
first is what makes the last line able to fail: with only one tenant in the
database, every id in sight is the same one and the equality cannot disagree
with anything.

Patch **where the name is looked up**, not where it is defined:
`app.services.search.vector_client`, not `qdrant_client.QdrantClient`. A
`from x import y` in the service binds a local name, and patching the origin
module leaves the service holding the real client — the test passes, the network
call happens.

Never let a test reach a real LLM or vector endpoint: it is slow, non-
deterministic, and billed.

## Conventions

| Aspect     | Rule                                                                 |
| ---------- | -------------------------------------------------------------------- |
| File       | `tests/api/test_{domain}.py`, `tests/services/test_{name}.py`        |
| Mirroring  | `tests/` mirrors `app/`                                              |
| Pattern    | Arrange → Act → Assert, one logical assertion per test               |
| Naming     | `test_{action}_{scenario}`                                           |
| Fixtures   | in `conftest.py`, composed rather than inherited                     |
| Mocks      | `AsyncMock` + `patch` on the import site                             |
| DB         | one isolated session per test, no shared state                       |
| Isolation  | every service that takes a tenant key gets a cross-tenant test       |
| Types      | no `Any` in tests either                                             |

## Test gate

Business logic added or changed = tests added, and `python -m pytest` green. Missing tests
on new logic = **FAIL**, not a Minor.

Which layers are mandatory, the coverage floor and its `pyproject.toml` config
live in **`.claude/rules/07-backend.md`, "Tests — order, freeze, floor"** — the
only copy. Read the thing that changes how you write the file before you write
it: **`tests/services/` is test-first and then frozen**, `tests/api/`,
`tests/core/` and the rest are test-after. The kit's core TDD hooks key on
TypeScript filenames and never see a `.py`; this addon ships a Python trio that
does.

Two consequences for the shapes below. A `tests/services/` file is written
**before** its module, so it cannot be derived from the code — it comes from
`docs/work/<slug>/plan.md`'s `Test plan`. And once proved red it stops moving:
appending a case is allowed, rewriting an assertion is not.
