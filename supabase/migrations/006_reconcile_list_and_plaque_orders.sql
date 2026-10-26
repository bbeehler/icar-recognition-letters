-- The monthly list no longer replaces the database. Stores are kept permanently; each upload
-- tells us who is on and who is off the list, and brings in new expiry dates. Expiry is checked
-- against the database. Each upload also queues St. Joseph plaque and year-plate orders.

alter table public.recognitions
  add column first_listed_on date,
  add column off_list_since date,
  add column last_upload_id bigint references public.list_uploads(id) on delete set null;
create index recognitions_last_upload_idx on public.recognitions (last_upload_id);
update public.recognitions set first_listed_on = coalesce(added_at::date, current_date) where first_listed_on is null;
create unique index recognitions_store_key on public.recognitions (program, icar_id_norm);

-- St. Joseph plaque / year plate orders
create table public.plaque_orders (
  id bigint generated always as identity primary key,
  label text not null,
  item_count integer not null default 0,
  created_by uuid references public.staff(user_id) on delete set null,
  created_at timestamptz not null default now()
);
create index plaque_orders_created_by_idx on public.plaque_orders (created_by);

create table public.plaque_items (
  id bigint generated always as identity primary key,
  recognition_id bigint references public.recognitions(id) on delete set null,
  icar_id text not null,
  icar_id_norm text not null,
  kind text not null check (kind in ('plaque', 'plate')),
  aluminum boolean not null default false,
  language text not null check (language in ('en', 'fr')),
  renewal_date date not null,
  shop_name text not null,
  raw_name text,
  address text, city text, province text, postal_code text,
  reason text,
  upload_id bigint references public.list_uploads(id) on delete set null,
  order_id bigint references public.plaque_orders(id) on delete set null,
  created_by uuid references public.staff(user_id) on delete set null,
  created_at timestamptz not null default now(),
  unique (icar_id_norm, renewal_date)
);
create index plaque_items_recognition_idx on public.plaque_items (recognition_id);
create index plaque_items_upload_idx on public.plaque_items (upload_id);
create index plaque_items_order_idx on public.plaque_items (order_id);
create index plaque_items_created_by_idx on public.plaque_items (created_by);
alter table public.plaque_orders enable row level security;
alter table public.plaque_items enable row level security;
create policy plaque_orders_select on public.plaque_orders for select to authenticated using ((select public.is_staff()));
create policy plaque_items_select on public.plaque_items for select to authenticated using ((select public.is_staff()));
revoke all on public.plaque_orders, public.plaque_items from anon;
revoke insert, update, delete on public.plaque_orders, public.plaque_items from authenticated;

-- Quebec stores get French plaques
create or replace function public.store_language(p_province text) returns text
language sql immutable set search_path = '' as $$
  select case when lower(coalesce(p_province, '')) ~ '^(qc|que|qu[eé]bec)' then 'fr' else 'en' end;
$$;

-- STAFF: monthly reconcile (keeps the name replace_recognition_list for the app)
create or replace function public.replace_recognition_list(p_program public.program_type, p_filename text, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_upload bigint; v_total integer := coalesce(jsonb_array_length(p_rows), 0); v_first boolean;
  v_on integer; v_new integer; v_renewed integer; v_returned integer; v_level integer; v_dropped integer; v_merged integer;
  v_plaques integer; v_plates integer; v_today date := (now() at time zone 'America/Toronto')::date;
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  drop table if exists pg_temp._in; drop table if exists pg_temp._chg;
  create temp table _in on commit drop as
    select distinct on (public.norm_id(r->>'icar_id')) public.norm_id(r->>'icar_id') as k, r
      from jsonb_array_elements(p_rows) r
     where coalesce(trim(r->>'icar_id'), '') <> '' and coalesce(trim(r->>'name'), '') <> ''
     order by public.norm_id(r->>'icar_id'), (r->>'expires_on') desc nulls last;
  if not exists (select 1 from _in) then raise exception 'No valid rows found. Nothing was changed.' using errcode = '22023'; end if;

  -- first upload (no stores from a list on file yet): everyone is the baseline, no new/renewed flags or plaque orders
  v_first := not exists (select 1 from public.recognitions where program = p_program and source = 'list');

  update public.list_uploads set is_active = false where program = p_program and is_active;
  insert into public.list_uploads (program, filename, uploaded_by) values (p_program, left(p_filename, 255), (select auth.uid())) returning id into v_upload;

  -- what changed, worked out against the database before it is updated
  create temp table _chg on commit drop as
    select i.k, i.r, r.id as rec_id, r.source as old_source, r.is_active as was_active, r.aluminum as old_alu, r.expires_on as old_exp,
           case when coalesce(i.r->>'expires_on', '') ~ '^\d{4}-\d{2}-\d{2}$' then (i.r->>'expires_on')::date end as new_exp,
           lower(trim(coalesce(i.r->>'aluminum', ''))) in ('true', 'yes', 'y', 'oui', 'o', 'x', '1', 'aluminum', 'aluminium') as new_alu
      from _in i left join public.recognitions r on r.program = p_program and r.icar_id_norm = i.k;
  alter table _chg add column status text, add column kind text, add column reason text;
  update _chg set status = case
      when v_first then null
      when rec_id is null or old_source = 'manual' then 'new'
      when not was_active then 'returned'
      when new_exp is not null and new_exp > coalesce(old_exp, '1900-01-01') then 'renewed'
      when old_alu is distinct from new_alu then 'level'
      else null end
   where true;  -- the API blocks UPDATE without WHERE
  update _chg set kind = case
      when status is null then null
      when status = 'new' then 'plaque'
      when old_alu is distinct from new_alu then 'plaque'
      when status in ('renewed', 'returned') then 'plate' end,
    reason = case
      when status is null then null
      when status = 'new' then 'New Gold Class store'
      when old_alu is distinct from new_alu then case when new_alu then 'Now Gold Class – Aluminum' else 'Now Gold Class (no longer Aluminum)' end
      when status = 'returned' then 'Back on the list'
      else 'Renewed' end
   where true;

  select count(*) filter (where old_source = 'manual') into v_merged from _chg;

  -- update stores already on file (names: a saved correction wins, otherwise the cleaned name)
  update public.recognitions r set
    display_name = coalesce(o.display_name, left(trim(c.r->>'name'), 300)),
    raw_name = nullif(left(trim(c.r->>'raw_name'), 400), ''),
    address = coalesce(nullif(trim(c.r->>'address'), ''), r.address), city = coalesce(nullif(trim(c.r->>'city'), ''), r.city),
    province = coalesce(nullif(trim(c.r->>'province'), ''), r.province), postal_code = coalesce(nullif(trim(c.r->>'postal_code'), ''), r.postal_code),
    postal_norm = case when nullif(trim(c.r->>'postal_code'), '') is not null then public.norm_postal(c.r->>'postal_code') else r.postal_norm end,
    contact_phone = coalesce(nullif(left(trim(c.r->>'contact_phone'), 60), ''), r.contact_phone),
    contact_email = coalesce(nullif(lower(left(trim(c.r->>'contact_email'), 320)), ''), r.contact_email),
    contact_name = coalesce(nullif(left(trim(c.r->>'contact_name'), 200), ''), r.contact_name),
    prev_expires_on = r.expires_on,
    expires_on = coalesce(c.new_exp, r.expires_on),
    aluminum = c.new_alu,
    name_norm = public.norm_name(coalesce(o.display_name, c.r->>'name')),
    is_active = true, off_list_since = null, source = 'list',
    first_listed_on = coalesce(case when r.source = 'manual' then v_today end, r.first_listed_on, v_today),
    upload_id = v_upload, last_upload_id = v_upload,
    change_status = c.status
  from _chg c left join public.store_name_overrides o on o.program = p_program and o.icar_id_norm = c.k
  where c.rec_id = r.id;

  -- add stores we have never seen
  insert into public.recognitions
    (upload_id, last_upload_id, program, icar_id, display_name, raw_name, address, city, province, postal_code, expires_on,
     contact_name, contact_email, contact_phone, aluminum, icar_id_norm, postal_norm, last_name_norm, name_norm,
     is_active, source, change_status, first_listed_on)
  select v_upload, v_upload, p_program, left(trim(c.r->>'icar_id'), 64), coalesce(o.display_name, left(trim(c.r->>'name'), 300)),
         nullif(left(trim(c.r->>'raw_name'), 400), ''), nullif(trim(c.r->>'address'), ''), nullif(trim(c.r->>'city'), ''),
         nullif(trim(c.r->>'province'), ''), nullif(trim(c.r->>'postal_code'), ''), c.new_exp,
         nullif(left(trim(c.r->>'contact_name'), 200), ''), nullif(lower(left(trim(c.r->>'contact_email'), 320)), ''), nullif(left(trim(c.r->>'contact_phone'), 60), ''),
         c.new_alu, c.k, public.norm_postal(c.r->>'postal_code'), '', public.norm_name(coalesce(o.display_name, c.r->>'name')),
         true, 'list', c.status, v_today
    from _chg c left join public.store_name_overrides o on o.program = p_program and o.icar_id_norm = c.k
   where c.rec_id is null;

  -- stores on file from earlier lists that are not on this one: off the list (kept, can't download)
  update public.recognitions r set is_active = false, off_list_since = coalesce(r.off_list_since, v_today), change_status = 'dropped'
   where r.program = p_program and r.source = 'list' and r.is_active
     and not exists (select 1 from _in i where i.k = r.icar_id_norm);
  get diagnostics v_dropped = row_count;

  -- queue St. Joseph orders: plaque for new stores or a level change, year plate for renewals
  insert into public.plaque_items (recognition_id, icar_id, icar_id_norm, kind, aluminum, language, renewal_date, shop_name, raw_name,
                                   address, city, province, postal_code, reason, upload_id, created_by)
  select r.id, r.icar_id, r.icar_id_norm, c.kind, r.aluminum, public.store_language(r.province),
         coalesce((r.expires_on - interval '1 year')::date, v_today), r.display_name, r.raw_name,
         r.address, r.city, r.province, r.postal_code, c.reason, v_upload, (select auth.uid())
    from _chg c join public.recognitions r on r.program = p_program and r.icar_id_norm = c.k
   where c.kind is not null
  on conflict (icar_id_norm, renewal_date) do nothing;

  select count(*), count(*) filter (where status = 'new'), count(*) filter (where status = 'renewed'), count(*) filter (where status = 'returned'),
         count(*) filter (where status is not null and old_alu is distinct from new_alu and status <> 'new'),
         count(*) filter (where kind = 'plaque'), count(*) filter (where kind = 'plate')
    into v_on, v_new, v_renewed, v_returned, v_level, v_plaques, v_plates from _chg;
  update public.list_uploads set row_count = v_on where id = v_upload;
  drop table if exists pg_temp._in; drop table if exists pg_temp._chg;
  return jsonb_build_object('upload_id', v_upload, 'inserted', v_on, 'skipped', v_total - v_on, 'merged_manual', v_merged, 'first', v_first,
    'new', v_new, 'renewed', v_renewed, 'returned', v_returned, 'level_changed', v_level, 'dropped', v_dropped,
    'off_list', (select count(*) from public.recognitions where program = p_program and not is_active),
    'plaques', v_plaques, 'plates', v_plates,
    'expired', (select count(*) from public.recognitions where program = p_program and is_active and expires_on < v_today));
end $$;

-- PUBLIC: stores off the list get their own message
create or replace function public.request_letter(
  p_program public.program_type, p_icar_id text, p_check text, p_requester_name text, p_requester_email text,
  p_language text default 'en', p_marketing_consent boolean default false
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id text := public.norm_id(p_icar_id);
  v_rec public.recognitions; v_fail integer; v_raw text; v_code text;
  v_lang text := case when p_language in ('en', 'fr') then p_language else 'en' end;
  v_now timestamptz := now();
begin
  if v_id = '' or coalesce(trim(p_check), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_fields');
  end if;
  if coalesce(trim(p_requester_name), '') = '' or coalesce(trim(p_requester_email), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_contact');
  end if;
  select count(*) into v_fail from public.lookup_failures f where f.icar_id_norm = v_id and f.created_at > v_now - interval '1 hour';
  if v_fail >= 10 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;
  select * into v_rec from public.recognitions r
   where r.program = 'gold_class' and r.icar_id_norm = v_id
     and r.postal_norm <> '' and r.postal_norm = public.norm_postal(p_check)
   limit 1;
  if not found then
    insert into public.lookup_failures (program, icar_id_norm) values ('gold_class', v_id);
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if not v_rec.is_active then
    return jsonb_build_object('ok', false, 'error', 'off_list', 'expires_on', v_rec.expires_on);
  end if;
  if v_rec.expires_on is not null and v_rec.expires_on < (v_now at time zone 'America/Toronto')::date then
    return jsonb_build_object('ok', false, 'error', 'expired', 'expires_on', v_rec.expires_on);
  end if;
  loop
    v_raw := upper(encode(extensions.gen_random_bytes(5), 'hex'));
    exit when not exists (select 1 from public.letter_requests l where l.code_norm = v_raw);
  end loop;
  v_code := substr(v_raw, 1, 5) || '-' || substr(v_raw, 6, 5);
  insert into public.letter_requests
    (recognition_id, program, icar_id, recipient_name, requester_name, requester_email, marketing_consent, language, verification_code, code_norm, created_at)
  values (v_rec.id, v_rec.program, v_rec.icar_id, v_rec.display_name, left(trim(p_requester_name), 200),
          lower(left(trim(p_requester_email), 320)), coalesce(p_marketing_consent, false), v_lang, v_code, v_raw, v_now);
  return jsonb_build_object('ok', true, 'code', v_code, 'program', v_rec.program, 'language', v_lang,
    'name', v_rec.display_name, 'icar_id', v_rec.icar_id, 'address', v_rec.address, 'city', v_rec.city, 'province', v_rec.province,
    'postal_code', v_rec.postal_code, 'recognition_date', v_rec.recognition_date, 'expires_on', v_rec.expires_on,
    'aluminum', v_rec.aluminum, 'issued_at', v_now);
end $$;

-- STAFF: one record per store number, on or off the list
create or replace function public.save_recognition(p_program public.program_type, p_data jsonb, p_id bigint default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_icar text := left(trim(coalesce(p_data->>'icar_id', '')), 64);
  v_name text := left(trim(coalesce(p_data->>'name', '')), 300);
  v_norm text := public.norm_id(p_data->>'icar_id');
  v_existing public.recognitions; v_row public.recognitions; v_old public.recognitions;
  v_exp date := case when coalesce(p_data->>'expires_on', '') ~ '^\d{4}-\d{2}-\d{2}$' then (p_data->>'expires_on')::date end;
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if v_icar = '' or v_name = '' then raise exception 'Enter the store number and name.' using errcode = '22023'; end if;
  if public.norm_id(p_data->>'postal_code') = '' then
    raise exception 'Enter the business postal code. The customer confirms with it.' using errcode = '22023'; end if;
  select * into v_existing from public.recognitions r
   where r.program = p_program and r.icar_id_norm = v_norm and (p_id is null or r.id <> p_id) limit 1;
  if found then
    if v_existing.is_active then
      raise exception 'Store % is already on the list as %.', v_icar, v_existing.display_name using errcode = '23505';
    else
      raise exception 'Store % (%) is on file but off the current list. Find it under "Off the list" in Notify customers.', v_icar, v_existing.display_name using errcode = '23505';
    end if;
  end if;
  if p_id is not null then
    select * into v_old from public.recognitions where id = p_id and program = p_program;
    if not found then raise exception 'Record not found' using errcode = '22023'; end if;
    update public.recognitions set
      icar_id = case when source = 'list' then icar_id else v_icar end, display_name = v_name,
      address = nullif(trim(p_data->>'address'), ''), city = nullif(trim(p_data->>'city'), ''),
      province = nullif(trim(p_data->>'province'), ''), postal_code = nullif(trim(p_data->>'postal_code'), ''),
      expires_on = coalesce(v_exp, expires_on),
      contact_name = nullif(left(trim(p_data->>'contact_name'), 200), ''), contact_email = nullif(lower(left(trim(p_data->>'contact_email'), 320)), ''),
      contact_phone = nullif(left(trim(p_data->>'contact_phone'), 60), ''),
      aluminum = coalesce((p_data->>'aluminum')::boolean, false),
      icar_id_norm = case when source = 'list' then icar_id_norm else v_norm end,
      postal_norm = public.norm_postal(p_data->>'postal_code'), name_norm = public.norm_name(v_name)
    where id = p_id returning * into v_row;
    if v_row.source = 'list' and v_name is distinct from v_old.display_name then
      insert into public.store_name_overrides (program, icar_id_norm, display_name, updated_by)
      values (p_program, v_row.icar_id_norm, v_name, (select auth.uid()))
      on conflict (program, icar_id_norm) do update set display_name = excluded.display_name, updated_by = excluded.updated_by, updated_at = now();
    end if;
  else
    insert into public.recognitions
      (program, icar_id, display_name, address, city, province, postal_code, expires_on,
       contact_name, contact_email, contact_phone, aluminum, icar_id_norm, postal_norm, last_name_norm, name_norm, is_active, source, added_by, added_at, change_status, first_listed_on)
    values
      (p_program, v_icar, v_name, nullif(trim(p_data->>'address'), ''), nullif(trim(p_data->>'city'), ''), nullif(trim(p_data->>'province'), ''),
       nullif(trim(p_data->>'postal_code'), ''), v_exp,
       nullif(left(trim(p_data->>'contact_name'), 200), ''), nullif(lower(left(trim(p_data->>'contact_email'), 320)), ''), nullif(left(trim(p_data->>'contact_phone'), 60), ''),
       coalesce((p_data->>'aluminum')::boolean, false), v_norm, public.norm_postal(p_data->>'postal_code'), '', public.norm_name(v_name),
       true, 'manual', (select auth.uid()), now(), 'new', current_date)
    returning * into v_row;
  end if;
  return to_jsonb(v_row) - 'icar_id_norm' - 'postal_norm' - 'last_name_norm' - 'name_norm';
end $$;

-- STAFF: store list, now including stores that are off the list
create or replace function public.get_customer_list(
  p_program public.program_type, p_q text default '', p_status text default 'all', p_limit integer default 50, p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_q text := nullif(trim(coalesce(p_q, '')), ''); v_today date := (now() at time zone 'America/Toronto')::date; v_res jsonb;
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  with base as (
    select r.*, (r.expires_on is not null and r.expires_on < v_today) as expired,
      c.contacted_at as last_contact_at, c.method as last_contact_method, coalesce(s.full_name, s.email) as last_contact_by,
      (select count(*) from public.customer_contacts c2 where c2.program = r.program and c2.icar_id_norm = r.icar_id_norm) as contacts,
      l.n as letters, l.last_at as last_letter_at,
      (select p.kind from public.plaque_items p where p.icar_id_norm = r.icar_id_norm and p.order_id is null order by p.created_at desc limit 1) as pending_order
    from public.recognitions r
    left join lateral (select * from public.customer_contacts c where c.program = r.program and c.icar_id_norm = r.icar_id_norm order by c.contacted_at desc limit 1) c on true
    left join public.staff s on s.user_id = c.contacted_by
    left join lateral (select count(*) n, max(created_at) last_at from public.letter_requests l where l.program = r.program and l.icar_id_norm = r.icar_id_norm) l on true
    where r.program = p_program
      and (v_q is null or r.display_name ilike '%' || v_q || '%' or r.raw_name ilike '%' || v_q || '%' or r.icar_id ilike '%' || v_q || '%'
           or r.contact_email ilike '%' || v_q || '%' or r.contact_name ilike '%' || v_q || '%' or r.city ilike '%' || v_q || '%'
           or r.contact_phone ilike '%' || v_q || '%')
  ), filtered as (
    select * from base where case p_status
      when 'new' then is_active and change_status in ('new', 'renewed', 'returned', 'level') and not expired
      when 'not_contacted' then is_active and last_contact_at is null and letters = 0 and not expired
      when 'contacted' then is_active and last_contact_at is not null and letters = 0 and not expired
      when 'downloaded' then is_active and letters > 0
      when 'expired' then is_active and expired
      when 'off' then not is_active
      else is_active end
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'rows', coalesce((select jsonb_agg(to_jsonb(f) - 'icar_id_norm' - 'postal_norm' - 'last_name_norm' - 'name_norm' - 'upload_id')
                      from (select * from filtered order by (change_status is null), (letters > 0), (last_contact_at is not null), display_name
                            limit greatest(1, least(p_limit, 500)) offset greatest(0, p_offset)) f), '[]'::jsonb),
    'summary', (select jsonb_build_object(
        'total', count(*) filter (where is_active),
        'new', count(*) filter (where is_active and change_status in ('new', 'renewed', 'returned', 'level') and not expired),
        'not_contacted', count(*) filter (where is_active and last_contact_at is null and letters = 0 and not expired),
        'contacted', count(*) filter (where is_active and last_contact_at is not null and letters = 0 and not expired),
        'downloaded', count(*) filter (where is_active and letters > 0),
        'expired', count(*) filter (where is_active and expired),
        'off', count(*) filter (where not is_active)) from base))
  into v_res;
  return v_res;
end $$;

create or replace function public.get_dashboard_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_today date := (now() at time zone 'America/Toronto')::date;
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  return jsonb_build_object(
    'lists', coalesce((select jsonb_agg(jsonb_build_object('program', u.program, 'row_count', u.row_count, 'filename', u.filename,
                'uploaded_at', u.uploaded_at, 'uploaded_by', s.full_name, 'uploaded_by_email', s.email))
              from public.list_uploads u left join public.staff s on s.user_id = u.uploaded_by where u.is_active), '[]'::jsonb),
    'stores', (select count(*) from public.recognitions where is_active and program = 'gold_class'),
    'aluminum', (select count(*) from public.recognitions where is_active and program = 'gold_class' and aluminum),
    'expired', (select count(*) from public.recognitions where is_active and program = 'gold_class' and expires_on < v_today),
    'off_list', (select count(*) from public.recognitions where not is_active and program = 'gold_class'),
    'new', (select count(*) from public.recognitions where is_active and program = 'gold_class' and change_status in ('new', 'renewed', 'returned', 'level') and not coalesce(expires_on < v_today, false)),
    'pending_plaques', (select count(*) from public.plaque_items where order_id is null and kind = 'plaque'),
    'pending_plates', (select count(*) from public.plaque_items where order_id is null and kind = 'plate'),
    'letters_total', (select count(*) from public.letter_requests),
    'letters_30d', (select count(*) from public.letter_requests where created_at > now() - interval '30 days'),
    'unique_recipients', (select count(distinct (program, icar_id_norm)) from public.letter_requests),
    'contacted', (select count(distinct (program, icar_id_norm)) from public.customer_contacts),
    'not_contacted', (select count(*) from public.recognitions r where r.is_active and not coalesce(r.expires_on < v_today, false)
        and not exists (select 1 from public.customer_contacts c where c.program = r.program and c.icar_id_norm = r.icar_id_norm)
        and not exists (select 1 from public.letter_requests l where l.program = r.program and l.icar_id_norm = r.icar_id_norm)));
end $$;

-- STAFF: add a store to the next St. Joseph order by hand (plaque or year plate)
create or replace function public.add_plaque_item(p_recognition_id bigint, p_kind text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_rec public.recognitions; v_id bigint; v_date date;
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if p_kind not in ('plaque', 'plate') then raise exception 'Choose plaque or plate' using errcode = '22023'; end if;
  select * into v_rec from public.recognitions where id = p_recognition_id;
  if not found then raise exception 'Record not found' using errcode = '22023'; end if;
  v_date := coalesce((v_rec.expires_on - interval '1 year')::date, (now() at time zone 'America/Toronto')::date);
  if exists (select 1 from public.plaque_items where icar_id_norm = v_rec.icar_id_norm and renewal_date = v_date and order_id is null) then
    update public.plaque_items set kind = p_kind where icar_id_norm = v_rec.icar_id_norm and renewal_date = v_date and order_id is null returning id into v_id;
  else
    insert into public.plaque_items (recognition_id, icar_id, icar_id_norm, kind, aluminum, language, renewal_date, shop_name, raw_name,
                                     address, city, province, postal_code, reason, created_by)
    values (v_rec.id, v_rec.icar_id, v_rec.icar_id_norm, p_kind, v_rec.aluminum, public.store_language(v_rec.province), v_date,
            v_rec.display_name, v_rec.raw_name, v_rec.address, v_rec.city, v_rec.province, v_rec.postal_code, 'Added by hand', (select auth.uid()))
    on conflict (icar_id_norm, renewal_date) do update set kind = excluded.kind
    returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- STAFF: change or drop a queued item before it is ordered
create or replace function public.update_plaque_item(p_id bigint, p_kind text default null, p_language text default null, p_remove boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if p_remove then delete from public.plaque_items where id = p_id and order_id is null;
  else update public.plaque_items set kind = coalesce(p_kind, kind), language = coalesce(p_language, language) where id = p_id and order_id is null; end if;
  return jsonb_build_object('ok', true);
end $$;

-- STAFF: mark queued items as sent to St. Joseph
create or replace function public.mark_plaque_order(p_item_ids bigint[], p_label text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_order bigint; v_n integer;
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  insert into public.plaque_orders (label, created_by) values (left(coalesce(nullif(trim(p_label), ''), 'Plaque order'), 120), (select auth.uid())) returning id into v_order;
  update public.plaque_items set order_id = v_order where id = any(p_item_ids) and order_id is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Nothing left to order' using errcode = '22023'; end if;
  update public.plaque_orders set item_count = v_n where id = v_order;
  return jsonb_build_object('ok', true, 'order_id', v_order, 'items', v_n);
end $$;

revoke execute on function public.store_language, public.replace_recognition_list, public.request_letter, public.save_recognition,
  public.get_customer_list, public.get_dashboard_stats, public.add_plaque_item, public.update_plaque_item, public.mark_plaque_order from public, anon, authenticated;
grant execute on function public.request_letter to anon, authenticated;
grant execute on function public.replace_recognition_list, public.save_recognition, public.get_customer_list, public.get_dashboard_stats,
  public.add_plaque_item, public.update_plaque_item, public.mark_plaque_order to authenticated;
