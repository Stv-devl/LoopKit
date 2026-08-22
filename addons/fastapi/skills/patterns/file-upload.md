# File upload & storage — Patterns

Accepting a file, putting it somewhere, giving it back, and deleting all of it.
Every step has one trap and they are all cheap to avoid.

## The route

```python
@router.post("/projects/{project_id}/documents", status_code=202)
async def upload_document(
    project_id: str,
    file: UploadFile,
    background: BackgroundTasks,
    db: DbSession,
    user: CurrentUser,
) -> DocumentRead:
    doc = await document_service.upload(db, user.tenant_id, project_id, file)
    background.add_task(run_ingestion, doc.id, user.tenant_id)
    return doc
```

`202`, not `201`: the row exists, the processing does not. The client polls the
status or listens to a progress stream.

## Validation, in this order

```python
ALLOWED_EXTENSIONS = {".pdf", ".docx", ".xlsx"}
MAX_FILE_SIZE = 50 * 1024 * 1024
CHUNK = 1024 * 1024

async def upload(
    db: AsyncSession, tenant_id: str, project_id: str, file: UploadFile,
) -> Document:
    # 1. Parent belongs to the caller — before touching the filesystem
    await project_service.get_project(db, tenant_id, project_id)

    # 2. Extension against an allowlist
    display_name = sanitize_filename(file.filename or "unknown")
    ext = Path(display_name).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise InvalidInputError(f"Format not allowed: {ext}")

    # 3. Row first, so the file has an id to be named after
    doc = Document(project_id=project_id, filename=display_name, status="processing")
    db.add(doc)
    await db.commit()
    await db.refresh(doc)

    # 4. Stream to disk under a generated name, counting as we go
    target = UPLOAD_DIR / str(project_id) / f"{doc.id}{ext}"
    target.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    try:
        with target.open("wb") as out:
            while chunk := await file.read(CHUNK):
                written += len(chunk)
                if written > MAX_FILE_SIZE:
                    raise InvalidInputError(f"File too large (max {MAX_FILE_SIZE} bytes)")
                out.write(chunk)
        assert_magic_bytes(target, ext)      # 5. the header must match the extension
    except Exception:
        target.unlink(missing_ok=True)       # 6. no orphan file, ever
        await db.delete(doc)
        await db.commit()
        raise

    doc.size = written
    await db.commit()
    return doc
```

`InvalidInputError` comes from `core/exceptions.py` and the global handler maps
its code to **422** — that is what makes the tests at the bottom of this file
assert 422 rather than 500. A code the map does not know is a 500, silently:
`patterns/fastapi-architecture.md`, "Business exceptions".

### `await file.read()` with no argument is the bug to avoid

It loads the whole upload into memory **before** any size check can run. Ten
concurrent 2 GB uploads is 20 GB of RSS and an OOM kill — the size limit that
comes after is decoration. Read in chunks, count as you go, stop at the ceiling.

`content-length` is not a substitute either: it is client-supplied, and chunked
encoding omits it. It is a cheap early rejection, not the limit.

### The extension is a claim, and so is the content type

`file.content_type` comes from the client. Check the first bytes against the
format the extension promises:

| Format | Magic bytes |
| ------ | ----------- |
| PDF | `%PDF-` |
| DOCX / XLSX (zip) | `PK\x03\x04` |
| PNG | `\x89PNG\r\n\x1a\n` |
| JPEG | `\xff\xd8\xff` |

A `.pdf` that is really a zip bomb or an HTML page with a script is how a
document viewer becomes stored XSS.

### The client's filename never becomes a path

```python
def sanitize_filename(raw: str) -> str:
    """Keep a readable name for display — it is never used as a path."""
    return re.sub(r"[^\w\s.\-]", "_", Path(raw).name)[:255]
```

`Path(raw).name` strips `../../etc/`, and the disk name is
`{uuid}{ext}` anyway. Two independent barriers, because this one is worth two:
the sanitized name is stored in the database for display, the generated name is
what exists on disk.

## Layout

```
uploads/
└── {project_id}/
    └── {document_id}{ext}
```

Path derived from ids you generated, never from user input. Never a flat
directory: a few hundred thousand entries and every `ls`, every backup and every
`readdir` slows to a crawl.

`UPLOAD_DIR` is configuration, not a constant next to the code — a container
loses it on restart unless it is a mounted volume. Say which one it is in
`.claude/rules/07-backend.md`.

Object storage (S3, MinIO) changes only the write and the read: everything
above — validation order, generated names, the DB row as the source of truth —
stays identical. Prefer it as soon as there is more than one instance, because
the local disk stops being shared.

## Serving it back

```python
@router.get("/documents/{document_id}/download")
async def download(document_id: str, db: DbSession, user: CurrentUser) -> FileResponse:
    doc = await document_service.get(db, user.tenant_id, document_id)  # ← the check
    return FileResponse(
        path=storage_path(doc),
        filename=doc.filename,
        media_type="application/octet-stream",
        content_disposition_type="attachment",
    )
```

- The tenant check happens on the **database row**, before any path is built
- No endpoint ever takes a path or a filename as a parameter — only an id
- `attachment` + `application/octet-stream` for anything not rendered inline; an
  inline `text/html` served from your domain runs with your cookies
- For object storage, hand out a short-lived presigned URL instead of proxying
  the bytes through the API

## Deleting

Deleting a document is three deletions, and they are not in one transaction:

```python
async def delete(db: AsyncSession, tenant_id: str, document_id: str) -> None:
    doc = await get(db, tenant_id, document_id)     # tenant-checked read
    await delete_document_vectors(document_id)      # 1. vector store
    storage_path(doc).unlink(missing_ok=True)       # 2. disk
    await db.delete(doc)                            # 3. row
    await db.commit()
```

Order matters: derived data first, the row last. If step 1 or 2 fails, the row
is still there and the delete can be retried. Delete the row first and the file
becomes an orphan nobody can name.

Orphans accumulate anyway — a crash between two steps, a failed upload, a
restored backup. Ship a reconciliation script (`scripts/`) that lists files with
no row, rows with no file, and points with no row, and run it on a schedule.
`/backend:rag-audit` looks at exactly those three numbers.

## Quotas

Per-tenant storage is not enforced by anything unless you write it: sum `size`
for the tenant, compare to the plan's ceiling, reject with `413` before writing.
Without it, one account fills the disk for everyone.

## Testing

```python
async def test_upload_rejects_bad_extension(client: AsyncClient) -> None:
    response = await client.post(url, files={"file": ("x.exe", b"MZ", "application/exe")})
    assert response.status_code == 422


async def test_upload_rejects_oversized_file(client: AsyncClient) -> None:
    payload = b"%PDF-" + b"0" * (MAX_FILE_SIZE + 1)
    assert (await client.post(url, files={"file": ("big.pdf", payload)})).status_code == 422


async def test_upload_rejects_content_type_mismatch(client: AsyncClient) -> None:
    assert (await client.post(url, files={"file": ("x.pdf", b"<html>")})).status_code == 422


async def test_traversal_filename_is_not_a_path(client: AsyncClient, tmp_path) -> None:
    await client.post(url, files={"file": ("../../evil.pdf", b"%PDF-")})
    assert not (tmp_path.parent / "evil.pdf").exists()


async def test_delete_removes_file_and_vectors(client: AsyncClient, tmp_path) -> None:
    ...
```

Point `UPLOAD_DIR` at `tmp_path` in the fixture — a test suite that writes into
the real upload directory leaves you cleaning up by hand.
