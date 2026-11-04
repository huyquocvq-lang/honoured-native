-- Icon target revisions v1.1: hardening after the 31 Oct 2026 audit of
-- icon_revisions_v1.sql. Nothing a client sees changes; a revision made the
-- way the web makes it gives the same answer as before.
--   * revise_icon_target():
--       - "today" is read when the Icon's row lock is granted
--         (clock_timestamp()), not when the transaction began, so a call that
--         waited on the lock across the Icon's midnight cannot revise the day
--         that has just started;
--       - the signature must sit in this Icon's own revisions folder,
--         <uid>/<client_id>/revisions/<name>.png, which is where the web
--         uploads it, and its storage object must belong to the caller;
--       - a clash on the unique signature path answers invalid_signature
--         instead of raising.
--   * icon_revisions history:
--       - a revision is deleted only by the cascade of its contract or
--         account (the contract or account is gone), not by any other
--         nested delete;
--       - TRUNCATE is refused, and the service role no longer holds it.
-- On top of icon_revisions_v1.sql (checked below). Re-running is harmless.
-- Rollback: icon_revisions_v1_1_rollback.sql. icon_revisions_v1_rollback.sql
-- also undoes this file, since it drops both functions and the table.
-- Re-running icon_revisions_v1.sql after this file brings back the v1 bodies:
-- run this file again afterwards.
begin;

do $$
declare
  v_revise text := md5(pg_get_functiondef(to_regprocedure('public.revise_icon_target(uuid, uuid, numeric, text)')));
  v_immutable text := md5(pg_get_functiondef(to_regprocedure('public.icon_revisions_immutable()')));
begin
  if to_regclass('public.icon_revisions') is null or v_revise is null or v_immutable is null then
    raise exception 'icon_revisions_v1_1.sql needs icon_revisions_v1.sql applied first';
  end if;
  -- v1 as deployed on 28 Oct 2026, or this file's own bodies.
  if v_revise not in ('80e9f0d165569ca31303b173280af22e', 'aca7ea9cee15c372aa2f0c9b9787f280')
     or v_immutable not in ('401d66db9cbb67bd4d8adffcf6354af6', 'aaa8d362ce4f89601261e219c7864e31') then
    raise exception 'revise_icon_target() or icon_revisions_immutable() is neither v1 nor v1.1 (md5 % / %); not overwriting it', v_revise, v_immutable;
  end if;
end $$;

-- A revision is history: never edited or truncated, and removed only with its
-- contract or account. The cascade runs inside the parent's delete, after the
-- parent row is gone, so a nested delete whose contract and account both
-- still exist is not a cascade.
create or replace function public.icon_revisions_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    if not exists (select 1 from public.contracts c where c.id = old.contract_id)
       or not exists (select 1 from auth.users u where u.id = old.user_id) then
      return old;
    end if;
  end if;
  raise exception 'Icon revisions cannot be changed or deleted' using errcode = '42501';
end;
$$;
revoke all on function public.icon_revisions_immutable() from public, anon, authenticated;

drop trigger if exists icon_revisions_no_truncate on public.icon_revisions;
create trigger icon_revisions_no_truncate before truncate on public.icon_revisions
  for each statement execute function public.icon_revisions_immutable();
revoke truncate on public.icon_revisions from service_role;

-- M2.3: revise a running Icon's target from its next Icon day.
-- p_target is the new number in the unit the target is written in (the
-- number the person types); p_request_id is the client's id for this
-- revision, so a retry returns the same revision; p_signature_path is the new
-- signature, already uploaded to <uid>/<client_id>/revisions/. Answers
-- { ok: true, revision, effectiveDay, targetText, targetValue, days,
-- duplicate } or { ok: false, reason }.
create or replace function public.revise_icon_target(
  p_contract_id uuid,
  p_request_id uuid,
  p_target numeric,
  p_signature_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  v_contract public.contracts%rowtype;
  v_done public.icon_revisions%rowtype;
  v_current_text text;
  v_current_value double precision;
  v_signed_number numeric;
  v_unit text;
  v_max numeric;
  v_decimals integer;
  v_text text;
  v_value double precision;
  v_effective date;
  v_folder text;
  v_revision integer;
  v_days integer;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_contract_id is null or p_request_id is null or p_target is null or p_signature_path is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  -- Revisions of one Icon queue here, so each sees the one before it.
  select * into v_contract
  from public.contracts c
  where c.id = p_contract_id
    and c.user_id = caller_id
    and c.icon_weekdays is not null
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- A retry of a revision that went through gets it back, unchanged.
  select * into v_done
  from public.icon_revisions r
  where r.contract_id = p_contract_id and r.request_id = p_request_id;
  if found then
    return jsonb_build_object('ok', true, 'duplicate', true, 'revision', v_done.revision,
      'effectiveDay', v_done.effective_day, 'targetText', v_done.target_text,
      'targetValue', v_done.target_value, 'days', 0);
  end if;

  if v_contract.status <> 'active' then
    return jsonb_build_object('ok', false, 'reason', 'not_active');
  end if;
  if v_contract.word_source_id is not null then
    return jsonb_build_object('ok', false, 'reason', 'not_supported');
  end if;

  -- The terms in force: the latest revision, or the signing.
  select r.target_text, r.target_value into v_current_text, v_current_value
  from public.icon_revisions r
  where r.contract_id = p_contract_id
  order by r.revision desc
  limit 1;
  if not found then
    v_current_text := v_contract.primary_target;
    v_current_value := v_contract.icon_target;
  end if;

  -- Targets are written "<number> <unit>" (target-units.ts); only the number
  -- changes, within the unit's rules there.
  v_unit := substring(v_current_text from '^[0-9]+(?:\.[0-9]+)? ([a-z]+)$');
  v_signed_number := substring(v_contract.primary_target from '^([0-9]+(?:\.[0-9]+)?) [a-z]+$')::numeric;
  if v_unit is null or v_signed_number is null or v_signed_number <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'not_supported');
  end if;
  select u.max_value, u.decimals into v_max, v_decimals
  from (values ('min', 120, 0), ('hrs', 24, 0), ('km', 50, 1), ('mi', 30, 1),
               ('steps', 50000, 0), ('kcal', 2000, 0), ('reps', 500, 0))
       as u(unit, max_value, decimals)
  where u.unit = v_unit;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_supported');
  end if;
  -- NaN and Infinity sort above every number, so the upper bound rejects them.
  if p_target <= 0 or p_target > v_max
     or p_target * power(10::numeric, v_decimals) <> trunc(p_target * power(10::numeric, v_decimals)) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_target');
  end if;
  v_text := case when p_target = trunc(p_target) then trunc(p_target)::text
                 else round(p_target, 1)::text end || ' ' || v_unit;
  if v_text = v_current_text then
    return jsonb_build_object('ok', false, 'reason', 'unchanged');
  end if;
  -- Health Icons also carry the target in the metric's unit, in the same
  -- proportion as the signed one (10 km is 10000 meters).
  if v_contract.icon_metric is not null then
    v_value := (v_contract.icon_target::numeric * p_target / v_signed_number)::double precision;
  end if;

  -- From the next Icon day in the Icon's own time zone: today's day, closed
  -- days and days past their cut-off keep their target. Today is read now,
  -- after the row lock, not at the start of the transaction.
  select min(d.day) into v_effective
  from public.icon_days d
  where d.contract_id = p_contract_id
    and d.status = 'pending'
    and d.day > (clock_timestamp() at time zone v_contract.icon_timezone)::date;
  if v_effective is null then
    return jsonb_build_object('ok', false, 'reason', 'no_future_day');
  end if;

  -- The new signature: a file of its own in this Icon's revisions folder,
  -- uploaded by the caller.
  v_folder := caller_id::text || '/' || v_contract.client_id || '/revisions/';
  if v_contract.client_id !~ '^[A-Za-z0-9_-]{1,128}$'
     or left(p_signature_path, length(v_folder)) <> v_folder
     or substr(p_signature_path, length(v_folder) + 1) !~ '^[A-Za-z0-9_-]{1,128}\.png$'
     or exists (select 1 from public.icon_revisions r where r.signature_path = p_signature_path) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_signature');
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'signatures' and o.name = p_signature_path
      and (o.owner_id = caller_id::text or o.owner = caller_id)
  ) then
    return jsonb_build_object('ok', false, 'reason', 'signature_missing');
  end if;

  select coalesce(max(r.revision), 0) + 1 into v_revision
  from public.icon_revisions r
  where r.contract_id = p_contract_id;

  begin
    insert into public.icon_revisions (
      contract_id, user_id, revision, request_id,
      previous_target_text, previous_target_value, target_text, target_value,
      effective_day, signature_path
    ) values (
      p_contract_id, caller_id, v_revision, p_request_id,
      v_current_text, v_current_value, v_text, v_value,
      v_effective, p_signature_path
    );
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'invalid_signature');
  end;

  update public.icon_days d
  set target_text = v_text,
      target_value = v_value,
      target_revision = v_revision
  where d.contract_id = p_contract_id
    and d.status = 'pending'
    and d.day >= v_effective;
  get diagnostics v_days = row_count;

  return jsonb_build_object('ok', true, 'duplicate', false, 'revision', v_revision,
    'effectiveDay', v_effective, 'targetText', v_text, 'targetValue', v_value, 'days', v_days);
end;
$$;

revoke all on function public.revise_icon_target(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.revise_icon_target(uuid, uuid, numeric, text) to authenticated, service_role;

commit;
