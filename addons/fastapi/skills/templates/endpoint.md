# Endpoint Template — FastAPI

Full CRUD scaffold. Replace `Feature` / `feature` / `features` throughout.
Layer rules: `.claude/rules/07-backend.md`.

## Files generated

```
app/
├── models/{name}.py        # SQLAlchemy model
├── schemas/{name}.py       # Pydantic request/response
├── services/{name}.py      # Business logic
└── api/{name}.py           # FastAPI router
tests/
├── api/test_{name}.py
└── services/test_{name}.py
alembic/versions/…          # generated, then read
```

---

## `models/{name}.py`

```python
from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TenantMixin, TimestampMixin, uuid4_str


class Feature(Base, TenantMixin, TimestampMixin):
    __tablename__ = "features"
    __table_args__ = (
        Index("ix_features_tenant_project", "tenant_id", "project_id"),
    )

    id: Mapped[str] = mapped_column(primary_key=True, default=uuid4_str)
    name: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(String(1000))
    status: Mapped[str] = mapped_column(String(20), default="active")
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"))

    project: Mapped["Project"] = relationship(back_populates="features")
```

---

## `schemas/{name}.py`

```python
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class FeatureCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    description: str | None = Field(None, max_length=1000)
    project_id: str


class FeatureUpdate(BaseModel):
    """Partial: every field optional, applied with exclude_unset."""

    name: str | None = Field(None, min_length=1, max_length=255)
    description: str | None = Field(None, max_length=1000)
    status: str | None = Field(None, pattern="^(active|archived)$")


class FeatureResponse(BaseModel):
    id: str
    name: str
    description: str | None
    status: str
    project_id: str
    created_at: datetime
    updated_at: datetime | None

    model_config = ConfigDict(from_attributes=True)


class FeatureListResponse(BaseModel):
    items: list[FeatureResponse]
    total: int
```

---

## `services/{name}.py`

```python
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError
from app.models.feature import Feature
from app.schemas.feature import FeatureCreate, FeatureUpdate


class FeatureService:
    """Feature business logic. No HTTP concepts."""

    async def create(
        self, db: AsyncSession, tenant_id: str, data: FeatureCreate,
    ) -> Feature:
        feature = Feature(
            tenant_id=tenant_id,
            name=data.name,
            description=data.description,
            project_id=data.project_id,
        )
        db.add(feature)
        await db.commit()
        await db.refresh(feature)
        return feature

    async def get_by_id(
        self, db: AsyncSession, tenant_id: str, feature_id: str,
    ) -> Feature:
        stmt = select(Feature).where(
            Feature.tenant_id == tenant_id,
            Feature.id == feature_id,
        )
        feature = (await db.execute(stmt)).scalar_one_or_none()
        if feature is None:
            raise NotFoundError("Feature", feature_id)
        return feature

    async def list_all(
        self,
        db: AsyncSession,
        tenant_id: str,
        project_id: str | None = None,
        offset: int = 0,
        limit: int = 50,
    ) -> tuple[list[Feature], int]:
        base = select(Feature).where(Feature.tenant_id == tenant_id)
        if project_id:
            base = base.where(Feature.project_id == project_id)

        total = (await db.execute(
            select(func.count()).select_from(base.subquery())
        )).scalar() or 0

        stmt = base.order_by(Feature.created_at.desc()).offset(offset).limit(limit)
        rows = (await db.execute(stmt)).scalars().all()
        return list(rows), total

    async def update(
        self, db: AsyncSession, tenant_id: str, feature_id: str, data: FeatureUpdate,
    ) -> Feature:
        feature = await self.get_by_id(db, tenant_id, feature_id)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(feature, field, value)
        await db.commit()
        await db.refresh(feature)
        return feature

    async def delete(
        self, db: AsyncSession, tenant_id: str, feature_id: str,
    ) -> None:
        feature = await self.get_by_id(db, tenant_id, feature_id)
        await db.delete(feature)
        await db.commit()


feature_service = FeatureService()
```

`update` and `delete` go through `get_by_id`, so the tenant check happens once
and cannot be forgotten in a branch.

---

## `api/{name}.py`

```python
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.feature import (
    FeatureCreate,
    FeatureListResponse,
    FeatureResponse,
    FeatureUpdate,
)
from app.services.feature import feature_service

router = APIRouter(prefix="/features", tags=["features"])


@router.post("", response_model=FeatureResponse, status_code=201)
async def create_feature(
    data: FeatureCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> FeatureResponse:
    return await feature_service.create(db, current_user.tenant_id, data)


@router.get("", response_model=FeatureListResponse)
async def list_features(
    project_id: str | None = Query(None),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> FeatureListResponse:
    items, total = await feature_service.list_all(
        db, current_user.tenant_id, project_id, offset, limit,
    )
    return FeatureListResponse(items=items, total=total)


@router.get("/{feature_id}", response_model=FeatureResponse)
async def get_feature(
    feature_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> FeatureResponse:
    return await feature_service.get_by_id(db, current_user.tenant_id, feature_id)


@router.patch("/{feature_id}", response_model=FeatureResponse)
async def update_feature(
    feature_id: str,
    data: FeatureUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> FeatureResponse:
    return await feature_service.update(db, current_user.tenant_id, feature_id, data)


@router.delete("/{feature_id}", status_code=204)
async def delete_feature(
    feature_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    await feature_service.delete(db, current_user.tenant_id, feature_id)
```

---

## Registration — `api/router.py`

```python
from app.api.feature import router as feature_router

api_router.include_router(feature_router)
```

---

## Verbs

| Action | Method | Route            | Status |
| ------ | ------ | ---------------- | ------ |
| Create | POST   | `/features`      | 201    |
| List   | GET    | `/features`      | 200    |
| Get    | GET    | `/features/{id}` | 200    |
| Update | PATCH  | `/features/{id}` | 200    |
| Delete | DELETE | `/features/{id}` | 204    |

---

## Checklist

- [ ] Model: `TenantMixin` + `TimestampMixin`, composite index, explicit `String(N)`
- [ ] Schemas: Create, Update (partial), Response (`from_attributes`), ListResponse
- [ ] Service: every query filtered by `tenant_id`, `NotFoundError` not `HTTPException`
- [ ] Endpoints: `Depends(get_current_user)` on all five, no logic in the body
- [ ] Router registered in `api/router.py`
- [ ] Migration generated **and read** before applying
- [ ] Tests: happy path, 422, 404, cross-tenant isolation
- [ ] `python -m pytest` green, `ruff check .` clean
