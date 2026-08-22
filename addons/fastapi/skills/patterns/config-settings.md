# Configuration & settings — Patterns

One `Settings` class, loaded once, validated at import. The rule that carries
the whole file: **a secret has no default, and a dangerous flag defaults to
safe.** Everything below is that sentence applied.

## The shape (`core/config.py`)

```python
from pathlib import Path
from typing import Literal

from pydantic import SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",              # dev convenience; real envs use real env vars
        env_file_encoding="utf-8",
        extra="forbid",               # a typo'd variable fails loudly instead of being ignored
    )

    # ── Environment ──────────────────────────────────────────────
    environment: Literal["local", "staging", "production"] = "production"

    # ── Required: no default, the app refuses to boot without them ──
    database_url: SecretStr
    jwt_secret_key: SecretStr
    llm_api_key: SecretStr

    # ── Optional: a default is fine because a wrong value is visible ──
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 7
    vector_url: str = "http://localhost:6333"
    upload_dir: Path = Path("uploads")
    cors_origins: list[str] = []

    @field_validator("jwt_secret_key")
    @classmethod
    def secret_must_be_real(cls, v: SecretStr) -> SecretStr:
        value = v.get_secret_value()
        if len(value) < 32 or "change" in value.lower() or "secret" == value.lower():
            raise ValueError("jwt_secret_key must be a real 32+ character secret")
        return v

    @model_validator(mode="after")
    def production_is_locked_down(self) -> "Settings":
        if self.environment == "production":
            if not self.cors_origins or "*" in self.cors_origins:
                raise ValueError("cors_origins must be an explicit list in production")
        return self


settings = Settings()   # import-time: a bad config kills the process here
```

## Why "no default" is the point

```python
jwt_secret_key: str = "change-me-in-production-min-32-chars"   # ❌
```

That line does not protect anything — it guarantees the app **starts** with a
secret that is published in the repository. Every token it signs is forgeable by
anyone who has read the source. And because it boots, nothing tells you.

A required field turns the same mistake into a `ValidationError` at startup,
with the variable name in the message. Loud, immediate, and impossible to ship
past a health check.

Same class of bug, more expensive version:

```python
dev_mode: bool = True                                          # ❌
```

Anything gated on that flag — an auth bypass, a seeded admin account, verbose
errors, a mock provider — is **on by default**. One missing environment variable
in one deploy and the API is open, silently. If a flag disables a safety, its
default is the safe value and the dev environment opts in. Better still: derive
it, never store it — `settings.environment == "local"`, no boolean of its own.

And a bypass that lives inside `get_current_user` should not exist at all,
whatever gates it (see `fastapi-auth.md`).

## Secrets never leak by accident

- `SecretStr` — its `repr` is `**********`, so a settings dump, an exception
  context or a Sentry breadcrumb does not print it. `.get_secret_value()` at the
  point of use, nowhere else
- Never `logger.info(settings)`, never a `/debug/config` route, never a settings
  object in an error response
- `.env` stays git-ignored; `.env.example` lists **names only** and is committed
- Agents do not read `.env` — the kit's `protect-files.sh` blocks it, and the
  answer to "what is in the env" is `.env.example`

## Access

```python
from app.core.config import settings
```

A module-level singleton is enough, and it makes the failure happen at import.
If you need to swap it in tests, wrap it instead:

```python
@lru_cache
def get_settings() -> Settings:
    return Settings()
```

and depend on `Annotated[Settings, Depends(get_settings)]` in routes. Pick one
of the two and keep it — half the codebase importing the singleton while the
other half injects it is how a test overrides nothing.

Never read `os.environ` outside this file. One place knows what the environment
contains; everywhere else reads a typed attribute.

## Startup checks

`lifespan` is where configuration meets reality:

```python
@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None, None]:
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))       # DB reachable
    await ensure_collection()                       # vector store reachable
    yield
    await engine.dispose()
```

Fail here rather than on the first user request. A container that will not start
is an obvious incident; a container that starts and 500s on one endpoint is a
three-hour investigation.

Do **not** seed data in `lifespan` conditionally on an environment flag. Seeding
belongs in a script you run on purpose (`scripts/seed_dev.py`), so the code path
cannot fire in an environment you did not intend.

## `.env.example`

Every variable, no values, grouped like the class, with the required ones marked:

```bash
# Required — the app will not start without these
DATABASE_URL=
JWT_SECRET_KEY=          # 32+ chars: openssl rand -hex 32
LLM_API_KEY=

# Optional — defaults in core/config.py
ENVIRONMENT=local
CORS_ORIGINS=["http://localhost:5173"]
UPLOAD_DIR=uploads
```

It is the only configuration documentation anyone reads. A variable added to
`Settings` and not added here is a variable the next deploy forgets.

## Testing

**These tests assume the `get_settings()` variant above**, not the module-level
singleton: `settings = Settings()` runs at import, so a `monkeypatch.setenv`
in a fixture arrives after the object it was meant to change. With the
singleton, test the class instead — `Settings(_env_file=None, **overrides)` —
and never the imported instance.

```python
@pytest.fixture(autouse=True)
def test_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("JWT_SECRET_KEY", "x" * 32)
    monkeypatch.setenv("DATABASE_URL", TEST_DATABASE_URL)
    monkeypatch.setenv("ENVIRONMENT", "local")
    get_settings.cache_clear()


def test_placeholder_secret_is_rejected(monkeypatch) -> None:
    monkeypatch.setenv("JWT_SECRET_KEY", "change-me-in-production-min-32-chars")
    with pytest.raises(ValidationError):
        Settings()


def test_production_requires_explicit_cors(monkeypatch) -> None:
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("CORS_ORIGINS", '["*"]')
    with pytest.raises(ValidationError):
        Settings()
```

Those two tests are the ones that keep the file honest: they prove the guard
rails still refuse the exact mistakes they exist for.
