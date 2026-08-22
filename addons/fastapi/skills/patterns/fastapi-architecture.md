# FastAPI Clean Architecture — Patterns

Layer rules live in `.claude/rules/07-backend.md`. This file is the shapes.

## Endpoint (`api/`)

```python
@router.post("", response_model=ProjectResponse, status_code=201)
async def create_project(
    data: ProjectCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ProjectResponse:
    return await project_service.create(db, current_user.tenant_id, data)
```

One line of body. If an endpoint needs a second one that is not `return`, the
logic belongs in the service.

## Service (`services/`)

```python
async def create(
    db: AsyncSession, tenant_id: str, data: ProjectCreate,
) -> Project:
    project = Project(tenant_id=tenant_id, name=data.name, phase=data.phase)
    db.add(project)
    await db.commit()
    await db.refresh(project)
    return project
```

No `fastapi` import. No status code. `tenant_id` is a parameter, never read from
a global or a context var.

## Model (`models/`)

```python
class TenantMixin:
    tenant_id: Mapped[str] = mapped_column(ForeignKey("tenants.id"), index=True)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(default=func.now())
    updated_at: Mapped[datetime | None] = mapped_column(onupdate=func.now())


class Project(Base, TenantMixin, TimestampMixin):
    __tablename__ = "projects"
    __table_args__ = (
        Index("ix_projects_tenant_status", "tenant_id", "status"),
    )

    id: Mapped[str] = mapped_column(primary_key=True, default=uuid4_str)
    name: Mapped[str] = mapped_column(String(255))
    phase: Mapped[str | None] = mapped_column(String(10))
    status: Mapped[str] = mapped_column(String(20), default="active")
```

## Schema (`schemas/`)

```python
class ProjectCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    phase: str | None = Field(None, pattern="^(draft|active|archived)$")


class ProjectUpdate(BaseModel):
    """Partial update — every field optional, `exclude_unset` on apply."""
    name: str | None = Field(None, min_length=1, max_length=255)
    phase: str | None = Field(None, pattern="^(draft|active|archived)$")


class ProjectResponse(BaseModel):
    id: str
    name: str
    phase: str | None
    status: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
```

`from_attributes=True` is what lets a route return an ORM object directly.
Without it FastAPI raises at serialization time, not at import time — so it is a
runtime bug, not a typecheck one.

## Dependencies (`api/deps.py`)

```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    payload = decode_jwt(token)
    user = await db.get(User, payload["sub"])
    if user is None:
        raise HTTPException(401, "User not found")
    return user
```

This is the one place `HTTPException` is legitimate outside `api/` handlers:
dependencies *are* the HTTP layer.

`get_current_user` returns the **`User` ORM row**, everywhere, and routes read
`current_user.tenant_id` off it. `patterns/fastapi-auth.md` owns the full
version — token decoding, the `CurrentUser` alias, the role check — and returns
that same type. One extra query per request buys a role and an `is_active` read
from the database rather than from a claim frozen at login.

## Business exceptions (`core/exceptions.py`)

```python
class AppException(Exception):
    def __init__(self, message: str, code: str) -> None:
        self.message = message
        self.code = code


class NotFoundError(AppException):
    def __init__(self, entity: str, entity_id: str) -> None:
        super().__init__(f"{entity} {entity_id} not found", "NOT_FOUND")


class ForbiddenError(AppException):
    def __init__(self, message: str = "Access denied") -> None:
        super().__init__(message, "FORBIDDEN")


class UnauthorizedError(AppException):
    def __init__(self, message: str = "Not authenticated") -> None:
        super().__init__(message, "UNAUTHORIZED")


class ConflictError(AppException):
    def __init__(self, message: str) -> None:
        super().__init__(message, "CONFLICT")


class InvalidInputError(AppException):
    """Input a schema cannot reject on its own: a magic-byte mismatch, a size
    counted while streaming, a business rule on an otherwise valid payload."""

    def __init__(self, message: str) -> None:
        super().__init__(message, "INVALID_INPUT")
```

**Not named `ValidationError`, deliberately.** Pydantic exports that name, every
settings and schema test imports it (`patterns/config-settings.md`), and two
classes sharing one name in one codebase means the `except` that catches the
wrong one is invisible in review.

**The map is the contract, and every code in it needs a class — and every class
a code.** A raise whose code the map does not know falls to `.get(code, 500)`:
the service raised a 422 in spirit and the client got a 500, with no error
anywhere to explain it.

```python
# main.py — one global handler, one error shape for the whole API
STATUS_MAP = {
    "NOT_FOUND": 404,
    "FORBIDDEN": 403,
    "UNAUTHORIZED": 401,
    "CONFLICT": 409,
    "INVALID_INPUT": 422,
}


@app.exception_handler(AppException)
async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
    return JSONResponse(
        status_code=STATUS_MAP.get(exc.code, 500),
        content={"error": {"code": exc.code, "message": exc.message}},
    )
```

The frontend parses **one** error shape. Adding a second one in a single route
is how a client ends up with two error branches forever.

## Isolation — the golden rule

```python
# ✅ Always filter by the isolation key
stmt = select(Project).where(
    Project.tenant_id == tenant_id,
    Project.id == project_id,
)

# ✅ Same filter in the vector store payload
hits = await vector_client.search(
    collection_name=COLLECTION,
    query_vector=vector,
    query_filter=Filter(must=[
        FieldCondition(key="tenant_id", match=MatchValue(value=str(tenant_id))),
    ]),
)

# ❌ Cross-tenant leak — reads fine, returns another customer's row
stmt = select(Project).where(Project.id == project_id)
```

`db.get(Model, id)` bypasses the WHERE clause by construction. In a multi-tenant
service, treat every `db.get` on a business entity as a finding unless the
tenant is re-checked right after.

## Pagination

```python
async def list_all(
    self,
    db: AsyncSession,
    tenant_id: str,
    offset: int = 0,
    limit: int = 50,
) -> tuple[list[Project], int]:
    base = select(Project).where(Project.tenant_id == tenant_id)

    total = (await db.execute(
        select(func.count()).select_from(base.subquery())
    )).scalar() or 0

    stmt = base.order_by(Project.created_at.desc()).offset(offset).limit(limit)
    rows = (await db.execute(stmt)).scalars().all()
    return list(rows), total
```

A `list_*` without `.limit()` is an outage waiting for the table to grow.

## Background work

```python
@router.post("/{project_id}/documents", status_code=202)
async def upload(
    project_id: str,
    file: UploadFile,
    background: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DocumentResponse:
    doc = await document_service.create_pending(db, current_user.tenant_id, project_id, file)
    background.add_task(run_ingestion, doc.id, current_user.tenant_id)
    return doc
```

`BackgroundTasks` runs **in the same process, after the response**. It dies with
the worker and it does not retry. Fine for a best-effort job; not fine for
anything a user pays for — that wants a real queue. Say which one you chose in
the plan, not in a comment.

The task must open **its own** session: the request's `AsyncSession` is closed
when the response is sent. Which is why it takes **ids, not objects** —
`run_ingestion(document_id, tenant_id)`, never `run_ingestion(db, document, …)`.
A `Document` handed across that boundary belongs to a closed session and raises
on the first lazy attribute; `patterns/rag-ingestion.md` shows the orchestrator
opening its own and re-loading the row.

## Registration

```python
# api/router.py
api_router = APIRouter(prefix="/api")
api_router.include_router(project_router)

# main.py
app.include_router(api_router)
```

A route file nobody includes is dead code that typechecks, passes lint, and
returns 404 in production.
