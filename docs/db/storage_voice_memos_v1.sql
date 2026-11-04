-- Voice of Change storage lockdown (found Oct 2026 while checking the
-- signatures bucket). Applied externally to Lovable Cloud; no build runs it.
--
-- The private `voice-memos` bucket also had three permissive policies for
-- `anon` and `authenticated` that only checked the bucket id, so anyone with
-- the public anon key could list, download, upload and delete every person's
-- recordings. They are ORed with the per-user policies, which made those
-- meaningless. The web app only uses the bucket while signed in, inside
-- `<user id>/`, and plays recordings through signed URLs, so the per-user
-- policies are all it needs:
--   Users can read / upload / update / delete their own voice memos
--   (bucket_id = 'voice-memos' and the first folder = auth.uid()).
-- Recordings made signed out stay in the browser (IndexedDB) and never
-- reach the bucket.
--
-- Seventeen ownerless objects uploaded at the bucket root in July and August
-- 2026 under the old policies are referenced by no contract or journal entry;
-- after this change only the service role can read them.
begin;

drop policy if exists "Anyone can read voice memos" on storage.objects;
drop policy if exists "Anyone can upload voice memos" on storage.objects;
drop policy if exists "Anyone can delete voice memos" on storage.objects;

commit;
