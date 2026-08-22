# FastAPI Auth — Patterns

Native auth: password hashing, JWT access + refresh, the dependency that turns a
token into an identity, and the flows around it. No external provider.

Everything downstream depends on this file being right: the isolation key that
every service filters on comes out of `get_current_user`. A bug here is not a
login bug, it is a cross-tenant read.

## Hashing (`core/auth.py`)

```python
import bcrypt


def hash_password(plain: str) -> str:
    """Hash a plain-text password with bcrypt."""
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    """Verify a plain-text password against its bcrypt hash."""
    return bcrypt.checkpw(plain.encode(), hashed.encode())
```

`bcrypt` directly, not `passlib` (maintenance stalled). `argon2-cffi` is the
other defensible choice. Never a bare `sha256`: it is fast, which is the whole
problem.

bcrypt silently truncates at **72 bytes** — cap the password length in the
schema so two different long passwords cannot become the same hash.

## Tokens

```python
def create_access_token(user_id: str, tenant_id: str) -> str:
    expire = datetime.now(UTC) + timedelta(minutes=settings.jwt_access_token_expire_minutes)
    payload = {
        "user_id": user_id,
        "tenant_id": tenant_id,
        "type": "access",          # ← so a refresh token cannot be used as an access token
        "exp": expire,
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict[str, str]:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],   # ← a list, always
        )
    except JWTError as exc:
        raise UnauthorizedError("Invalid or expired token") from exc

    if payload.get("type") != "access":
        raise UnauthorizedError("Wrong token type")
    return payload
```

Three things that are not style:

- **`algorithms=[...]` is mandatory.** Decoding without pinning the algorithm
  accepts whatever the token's own header claims — including `none` on some
  libraries. The attacker picks the algorithm; you verify nothing.
- **A `type` claim, checked.** Without it a long-lived refresh token is a valid
  access token, and your 30-minute expiry is a 7-day expiry.
- **Short access (15–30 min), long refresh (7–30 days).** The access token
  cannot be revoked — that is what its expiry is for.

Refresh tokens *can* be revoked, if you store them (hash, `user_id`,
`expires_at`, `revoked_at`) and check on use. If you do not store them, say so
out loud: logout is then client-side only, and a stolen refresh token is valid
until it expires.

## The identity dependency (`api/deps.py`)

```python
bearer_scheme = HTTPBearer()


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(bearer_scheme)],
    db: DbSession,
) -> User:
    """Decode the bearer token, then load the caller's row."""
    payload = decode_token(credentials.credentials)
    user = await db.get(User, payload["user_id"])
    if user is None or not user.is_active:
        raise UnauthorizedError("Invalid or expired token")
    return user


async def get_admin_user(current_user: CurrentUser) -> User:
    """Same identity, plus a role check read from the database row."""
    if current_user.role != "admin":
        raise ForbiddenError()
    return current_user


# Aliases — this is what routes actually type
DbSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]
AdminUser = Annotated[User, Depends(get_admin_user)]
```

```python
@router.get("")
async def list_projects(db: DbSession, user: CurrentUser) -> ProjectList:
    return await project_service.list_projects(db, tenant_id=user.tenant_id)
```

**`get_current_user` returns the `User` ORM row — one type, everywhere.** Routes
read `user.tenant_id`, services take `tenant_id: str`, and the test conftest
overrides the dependency with a real `User` fixture
(`patterns/pytest-backend.md`). A variant returning a dict of claims saves one
query per request and costs a second identity shape in the codebase; if you take
it, take it in every file at once — half the routes reading `user.tenant_id`
while the other half reads `user["tenant_id"]` is a `TypeError` waiting for the
first shared helper.

The role is read from the row, not from a claim: a `role` inside the token is a
role frozen at login, so demoting someone leaves their powers until it expires.
Same for `is_active` — a disabled account keeps working otherwise.

The alias is what makes auth **hard to forget**: a route with no `CurrentUser`
parameter has no database session either, so it cannot do anything. It also
makes the audit a one-line grep.

### Never put a bypass in this function

```python
# ❌ the single most expensive four lines you can write
if credentials is None and settings.dev_mode:
    return await db.get(User, _DEV_ADMIN_ID)
```

The moment `dev_mode` defaults to `True`, or an env file is missing in a deploy,
the whole API serves unauthenticated requests — usually on a seeded **admin**
account. There is no error, no log, nothing to notice. If a dev environment
needs a shortcut, seed a real user and log in as them with a real token: the
code path stays the same one production runs.

Same reasoning for `HTTPBearer(auto_error=False)`: it turns a missing token into
`None` instead of a 401, and every route becomes responsible for a check that
the dependency was supposed to own.

## Flows

### Signup / login

```python
async def login(db: AsyncSession, email: str, password: str) -> tuple[str, str]:
    user = await get_user_by_email(db, email)
    if user is None or not verify_password(password, user.hashed_password):
        raise UnauthorizedError("Invalid credentials")   # ← same message both ways
    return (
        create_access_token(user.id, user.tenant_id),
        create_refresh_token(user.id, user.tenant_id),
    )
```

One message for "unknown email" and "wrong password", or the endpoint becomes an
account enumerator. The email lookup is legitimately cross-tenant — it is the
one query that runs before an identity exists.

### Password reset

```python
async def request_reset(db: AsyncSession, email: str) -> None:
    user = await get_user_by_email(db, email)
    if user is not None:
        token = create_reset_token(user.id)       # short-lived, type="reset"
        await send_reset_email(user.email, token)
    # Always return the same response, user or not
```

- Same response whether the account exists or not
- Reset token: 15–30 minutes, `type="reset"`, and **single use** — bind it to
  the current password hash or store a `used_at`, otherwise the mail stays a
  valid key for its whole lifetime
- Changing the password invalidates the refresh tokens
- `change-password` (authenticated) asks for the current password too: a stolen
  session should not be enough to lock the owner out

## Rate limiting

`login`, `signup`, `forgot-password` and `refresh` are the endpoints worth
attacking. Rate-limit them per IP **and** per email — see
`.claude/skills/patterns/` middleware notes and `/backend:middleware`. Without
it, bcrypt's cost becomes your own denial of service: each attempt burns CPU on
purpose.

## Configuration

The JWT secret comes from the environment with **no default** — see
`.claude/skills/patterns/config-settings.md`. A secret with a fallback value is
a secret published in the repository.

## Testing

```python
async def test_login_wrong_password_is_indistinguishable(client: AsyncClient) -> None:
    unknown = await client.post("/api/auth/login", json={"email": "nope@x.com", "password": "x"})
    wrong = await client.post("/api/auth/login", json={"email": "known@x.com", "password": "x"})

    assert unknown.status_code == wrong.status_code == 401
    assert unknown.json() == wrong.json()


async def test_refresh_token_rejected_as_access_token(client: AsyncClient) -> None:
    _, refresh = await login(...)

    response = await client.get("/api/projects", headers={"Authorization": f"Bearer {refresh}"})

    assert response.status_code == 401


async def test_route_without_token_is_401(client_no_auth: AsyncClient) -> None:
    assert (await client_no_auth.get("/api/projects")).status_code == 401
```

That last one needs a client fixture that does **not** override
`get_current_user`. The usual `client` fixture overrides it, so it can never
prove a route is protected — and a route that lost its dependency stays green
forever. Keep both fixtures.

Also worth a test: every registered route carries an auth dependency, asserted
by walking `app.routes` and allowlisting the public ones. It is ten lines, and
it is the only check that survives someone adding a route in a hurry.
