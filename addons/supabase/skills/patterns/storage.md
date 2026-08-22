# Storage

<!-- FILL: bucket names, size and MIME limits, the path convention. What must not
     change: buckets are private by default, the path encodes ownership, and
     upload calls live in the data layer. -->

> Storage calls are data-client calls: they belong in `*.gateway.ts` /
> `services.ts` like any other (`02-architecture.md`).

## Buckets are created by migration, not by hand

```sql
-- via /database:migration
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', false, 5242880, ARRAY['image/png','image/jpeg','image/webp'])
ON CONFLICT (id) DO NOTHING;
```

`public = false` unless the content is genuinely public. A public bucket serves
every object to anyone who guesses the path, and no policy will stop it.

`file_size_limit` and `allowed_mime_types` are enforced **server-side**. The
input's `accept` attribute is a hint to the file picker, nothing more.

## Access control = RLS on `storage.objects`

Same rules as any table (`rls.md`). Ownership is encoded in the **path**, by
convention `<user_id>/<filename>`:

```sql
CREATE POLICY "avatars_read_own"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
  );

CREATE POLICY "avatars_insert_own"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
  );

CREATE POLICY "avatars_update_own"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (select auth.uid())::text)
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (select auth.uid())::text);
```

**Upsert needs INSERT + SELECT + UPDATE.** Grant only INSERT and a first upload
works while every replacement fails silently — the single most common storage
bug on this stack.

## Upload

```typescript
// features/profile/services/avatar.gateway.ts
import { supabase } from '@/lib/supabase';

/** Uploads the user's avatar. The path encodes ownership — the policy reads it. */
export async function uploadAvatar(userId: string, file: File): Promise<string> {
  const ext = file.name.split('.').pop()?.toLowerCase() ?? 'bin';
  const path = `${userId}/avatar.${ext}`;

  const { error } = await supabase.storage
    .from('avatars')
    .upload(path, file, { upsert: true, contentType: file.type });

  if (error) throw error;
  return path;
}
```

Store the **path** in your table, never a rendered URL: signed URLs expire and
the public URL changes shape if the bucket ever flips.

Do not derive the path from `file.name` alone — a user-supplied name is
user-controlled input, and it is what the policy matches on.

## Reading

| Bucket | How |
| --- | --- |
| Private | `createSignedUrl(path, expiresIn)` — short TTL, generated on demand |
| Public | `getPublicUrl(path)` — no policy check, no expiry, cacheable |

```typescript
/** Short-lived URL for a private object. */
export async function getAvatarUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from('avatars')
    .createSignedUrl(path, 60 * 60);        // 1h

  if (error) throw error;
  return data.signedUrl;
}
```

A signed URL is a bearer token in a query string: anyone holding it reads the
object until it expires, policy or not. Keep the TTL to what the UI needs, and
never log one.

## Deleting

Deleting the row does **not** delete the object. An orphaned file keeps
occupying storage — and keeps being served to anyone with a live signed URL.

```typescript
export async function deleteAvatar(path: string): Promise<void> {
  const { error } = await supabase.storage.from('avatars').remove([path]);
  if (error) throw error;
}
```

Delete the object first, then the row: the reverse order loses the path on
failure and orphans the file for good. For a hard guarantee, a trigger on the
table that enqueues the deletion is more reliable than client-side ordering.

## In the UI

Uploads are mutations like any other (`08-feedback.md`): `isPending` disables the
input, errors are logged in English and shown in French. `onUploadProgress` is
not available on the JS client — for large files, show an indeterminate state
rather than a fake percentage.

## Checklist

- [ ] Bucket created by migration, `public = false` by default
- [ ] `file_size_limit` + `allowed_mime_types` set server-side
- [ ] Path convention encodes ownership (`<user_id>/…`)
- [ ] Policies for every operation used — INSERT + SELECT + UPDATE if upsert
- [ ] Path stored in the DB, not a URL
- [ ] Private bucket → signed URLs with a short TTL
- [ ] Object deleted before (or with) its row
- [ ] Upload calls in the data layer, never in a component
