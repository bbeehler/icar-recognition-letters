-- Emails the team adds to a store stick: the monthly upload never overwrites them.
-- The email from the I-CAR export is kept separately (list_email) for reference.
-- New "no email on file" filter in Notify customers, and a quick save from the Notify window.
alter table public.recognitions
  add column email_by_team boolean not null default false,
  add column list_email text;

do $$
declare d text;
begin
  -- monthly upload: keep a team-entered email; always record what the export says
  d := pg_get_functiondef('public.replace_recognition_list'::regproc);
  d := replace(d,
    $x$contact_email = coalesce(nullif(lower(left(trim(c.r->>'contact_email'), 320)), ''), r.contact_email),$x$,
    $x$contact_email = case when r.email_by_team and r.contact_email is not null then r.contact_email
                       else coalesce(nullif(lower(left(trim(c.r->>'contact_email'), 320)), ''), r.contact_email) end,
    list_email = nullif(lower(left(trim(c.r->>'contact_email'), 320)), ''),$x$);
  d := replace(d,
    $x$is_active, source, change_status, first_listed_on)
  select v_upload, v_upload,$x$,
    $x$is_active, source, change_status, first_listed_on, list_email)
  select v_upload, v_upload,$x$);
  d := replace(d,
    $x$true, 'list', c.status, v_today
    from _chg c$x$,
    $x$true, 'list', c.status, v_today, nullif(lower(left(trim(c.r->>'contact_email'), 320)), '')
    from _chg c$x$);
  if position('email_by_team' in d) = 0 or position('v_today, nullif(lower' in d) = 0 then raise exception 'upload patch failed'; end if;
  execute d;

  -- editing a store: an email typed by the team is marked as theirs
  d := pg_get_functiondef('public.save_recognition'::regproc);
  d := replace(d,
    $x$contact_name = nullif(left(trim(p_data->>'contact_name'), 200), ''), contact_email = nullif(lower(left(trim(p_data->>'contact_email'), 320)), ''),$x$,
    $x$contact_name = nullif(left(trim(p_data->>'contact_name'), 200), ''), contact_email = nullif(lower(left(trim(p_data->>'contact_email'), 320)), ''),
      email_by_team = case when nullif(lower(left(trim(p_data->>'contact_email'), 320)), '') is distinct from v_old.contact_email
                           then nullif(lower(left(trim(p_data->>'contact_email'), 320)), '') is not null else email_by_team end,$x$);
  if position('email_by_team' in d) = 0 then raise exception 'save patch failed'; end if;
  execute d;

  -- Notify filter: active stores with no email on file
  d := pg_get_functiondef('public.get_customer_list'::regproc);
  d := replace(d, $x$when 'off' then not is_active$x$, $x$when 'off' then not is_active
      when 'no_email' then is_active and not expired and coalesce(contact_email, '') = ''$x$);
  d := replace(d, $x$'off', count(*) filter (where not is_active)$x$,
    $x$'off', count(*) filter (where not is_active), 'no_email', count(*) filter (where is_active and not expired and coalesce(contact_email, '') = '')$x$);
  if position('no_email' in d) = 0 then raise exception 'list patch failed'; end if;
  execute d;
end $$;

-- STAFF: add or fix a store's email from the Notify window
create or replace function public.set_store_email(p_id bigint, p_email text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if v_email is not null and v_email !~ '^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$' then raise exception 'Enter one valid email address' using errcode = '22023'; end if;
  update public.recognitions set contact_email = v_email, email_by_team = v_email is not null where id = p_id;
  if not found then raise exception 'Store not found' using errcode = '22023'; end if;
  return jsonb_build_object('ok', true, 'email', v_email);
end $$;
revoke execute on function public.set_store_email from public, anon, authenticated;
grant execute on function public.set_store_email to authenticated;

-- If a file has no Gold Class level column (the app sends aluminum = null), keep each store's current level
-- instead of treating every Aluminum store as a level change.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.replace_recognition_list'::regproc);
  d := replace(d,
    $x$lower(trim(coalesce(i.r->>'aluminum', ''))) in ('true', 'yes', 'y', 'oui', 'o', 'x', '1', 'aluminum', 'aluminium') as new_alu$x$,
    $x$case when i.r->>'aluminum' is null and r.id is not null then r.aluminum
                else lower(trim(coalesce(i.r->>'aluminum', ''))) in ('true', 'yes', 'y', 'oui', 'o', 'x', '1', 'aluminum', 'aluminium') end as new_alu$x$);
  if position('when i.r->>''aluminum'' is null' in d) = 0 then raise exception 'patch failed'; end if;
  execute d;
end $$;
