-- Supabase's default privileges: every new table and function in public is
-- granted to anon, authenticated and service_role, so a migration must revoke
-- what they should not have. Without this the anon checks would pass even if
-- the migrations revoked nothing.
\set ON_ERROR_STOP on

alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
