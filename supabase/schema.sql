-- I-CAR Recognition Letters: complete database setup
-- Matches the live Supabase project "I-CAR Recognition Letters" (ref fwtzwkdcxkcnscqkyxhf).
-- Run once in the SQL editor of an empty project to rebuild the back end.

create extension if not exists unaccent with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.program_type as enum ('gold_class', 'platinum');
create type public.staff_role as enum ('admin', 'staff');

-- Staff accounts (Tanja's team)
create table public.staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  role public.staff_role not null default 'staff',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.staff s where s.user_id = (select auth.uid()) and s.active);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.staff s where s.user_id = (select auth.uid()) and s.active and s.role = 'admin');
$$;

create or replace function public.norm_id(t text) returns text
language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(t, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function public.norm_name(t text) returns text
language sql stable set search_path = '' as $$
  select regexp_replace(lower(extensions.unaccent(coalesce(t, ''))), '[^a-z]', '', 'g');
$$;

-- Uploaded recognition lists
create table public.list_uploads (
  id bigint generated always as identity primary key,
  program public.program_type not null,
  filename text,
  row_count integer not null default 0,
  uploaded_by uuid references public.staff(user_id) on delete set null,
  uploaded_at timestamptz not null default now(),
  is_active boolean not null default true
);
create index list_uploads_uploaded_by_idx on public.list_uploads (uploaded_by);
create index list_uploads_active_idx on public.list_uploads (program) where is_active;

create table public.recognitions (
  id bigint generated always as identity primary key,
  upload_id bigint not null references public.list_uploads(id) on delete cascade,
  program public.program_type not null,
  icar_id text not null,
  display_name text not null,
  last_name text,
  shop_name text,
  address text,
  city text,
  province text,
  postal_code text,
  recognition_date date,
  icar_id_norm text not null,
  postal_norm text not null default '',
  last_name_norm text not null default '',
  name_norm text not null default '',
  is_active boolean not null default true
);
create index recognitions_upload_id_idx on public.recognitions (upload_id);
create index recognitions_lookup_idx on public.recognitions (program, icar_id_norm) where is_active;

-- Letters issued (the download log)
create table public.letter_requests (
  id bigint generated always as identity primary key,
  recognition_id bigint references public.recognitions(id) on delete set null,
  program public.program_type not null,
  icar_id text not null,
  recipient_name text not null,
  requester_name text not null,
  requester_email text not null,
  marketing_consent boolean not null default false,
  language text not null default 'en' check (language in ('en', 'fr')),
  verification_code text not null,
  code_norm text not null unique,
  created_at timestamptz not null default now()
);
create index letter_requests_recognition_id_idx on public.letter_requests (recognition_id);
create index letter_requests_created_at_idx on public.letter_requests (created_at desc);

-- Failed lookups, used to throttle guessing (10 per I-CAR ID per hour)
create table public.lookup_failures (
  id bigint generated always as identity primary key,
  program public.program_type not null,
  icar_id_norm text not null,
  created_at timestamptz not null default now()
);
create index lookup_failures_idx on public.lookup_failures (icar_id_norm, created_at);

-- Letter wording and branding
create table public.letter_templates (
  program public.program_type not null,
  language text not null check (language in ('en', 'fr')),
  heading text not null,
  body text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.staff(user_id) on delete set null,
  primary key (program, language)
);
create index letter_templates_updated_by_idx on public.letter_templates (updated_by);

create table public.letter_settings (
  id smallint primary key default 1 check (id = 1),
  org_name text not null default 'I-CAR Canada',
  signatory_name text not null default '',
  signatory_title_en text not null default '',
  signatory_title_fr text not null default '',
  footer_text text not null default '',
  accent_color text not null default '#C8102E',
  logo_data text,
  signature_data text,
  support_email text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.staff(user_id) on delete set null
);
create index letter_settings_updated_by_idx on public.letter_settings (updated_by);

-- Row level security: staff read/manage; the public reaches data only through the functions below
alter table public.staff enable row level security;
alter table public.list_uploads enable row level security;
alter table public.recognitions enable row level security;
alter table public.letter_requests enable row level security;
alter table public.lookup_failures enable row level security;
alter table public.letter_templates enable row level security;
alter table public.letter_settings enable row level security;

create policy staff_select on public.staff for select to authenticated using ((select public.is_staff()));
create policy staff_admin_update on public.staff for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy uploads_select on public.list_uploads for select to authenticated using ((select public.is_staff()));
create policy recognitions_select on public.recognitions for select to authenticated using ((select public.is_staff()));
create policy requests_select on public.letter_requests for select to authenticated using ((select public.is_staff()));
create policy templates_select on public.letter_templates for select to authenticated using ((select public.is_staff()));
create policy templates_update on public.letter_templates for update to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));
create policy settings_select on public.letter_settings for select to authenticated using ((select public.is_staff()));
create policy settings_update on public.letter_settings for update to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));

-- PUBLIC: look up a recognition and issue a letter
create or replace function public.request_letter(
  p_program public.program_type,
  p_icar_id text,
  p_check text,
  p_requester_name text,
  p_requester_email text,
  p_language text default 'en',
  p_marketing_consent boolean default false
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id text := public.norm_id(p_icar_id);
  v_ln text := public.norm_name(p_check);
  v_rec public.recognitions;
  v_fail integer;
  v_raw text;
  v_code text;
  v_lang text := case when p_language in ('en', 'fr') then p_language else 'en' end;
  v_now timestamptz := now();
begin
  if v_id = '' or coalesce(trim(p_check), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_fields');
  end if;
  if coalesce(trim(p_requester_name), '') = ''
     or coalesce(trim(p_requester_email), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_contact');
  end if;

  select count(*) into v_fail from public.lookup_failures f
   where f.icar_id_norm = v_id and f.created_at > v_now - interval '1 hour';
  if v_fail >= 10 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select * into v_rec from public.recognitions r
   where r.is_active and r.program = p_program and r.icar_id_norm = v_id
     and case when p_program = 'gold_class'
              then r.postal_norm <> '' and r.postal_norm = public.norm_id(p_check)
              else length(v_ln) >= 2 and (
                     (r.last_name_norm <> '' and r.last_name_norm = v_ln)
                     or right(r.name_norm, length(v_ln)) = v_ln)
         end
   order by r.recognition_date desc nulls last
   limit 1;

  if not found then
    insert into public.lookup_failures (program, icar_id_norm) values (p_program, v_id);
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  loop
    v_raw := upper(encode(extensions.gen_random_bytes(5), 'hex'));
    exit when not exists (select 1 from public.letter_requests l where l.code_norm = v_raw);
  end loop;
  v_code := substr(v_raw, 1, 5) || '-' || substr(v_raw, 6, 5);

  insert into public.letter_requests
    (recognition_id, program, icar_id, recipient_name, requester_name, requester_email,
     marketing_consent, language, verification_code, code_norm, created_at)
  values
    (v_rec.id, v_rec.program, v_rec.icar_id, v_rec.display_name, left(trim(p_requester_name), 200),
     lower(left(trim(p_requester_email), 320)), coalesce(p_marketing_consent, false), v_lang, v_code, v_raw, v_now);

  return jsonb_build_object(
    'ok', true, 'code', v_code, 'program', v_rec.program, 'language', v_lang,
    'name', v_rec.display_name, 'icar_id', v_rec.icar_id, 'shop_name', v_rec.shop_name,
    'address', v_rec.address, 'city', v_rec.city, 'province', v_rec.province,
    'postal_code', v_rec.postal_code, 'recognition_date', v_rec.recognition_date, 'issued_at', v_now);
end $$;

-- PUBLIC: verify a letter by its code (QR code target)
create or replace function public.verify_letter(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_req public.letter_requests;
  v_current boolean;
begin
  select * into v_req from public.letter_requests l where l.code_norm = public.norm_id(p_code);
  if not found then
    return jsonb_build_object('valid', false);
  end if;
  select exists (
    select 1 from public.recognitions r
     where r.is_active and r.program = v_req.program and r.icar_id_norm = public.norm_id(v_req.icar_id)
  ) into v_current;
  return jsonb_build_object(
    'valid', true, 'name', v_req.recipient_name, 'program', v_req.program,
    'icar_id', v_req.icar_id, 'issued_at', v_req.created_at, 'code', v_req.verification_code,
    'currently_recognized', v_current);
end $$;

-- PUBLIC: letter wording and branding used to draw the PDF
create or replace function public.get_letter_content() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'settings', (select to_jsonb(s) - 'updated_by' - 'updated_at' - 'id' from public.letter_settings s where s.id = 1),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('program', t.program, 'language', t.language,
                                     'heading', t.heading, 'body', t.body))
                           from public.letter_templates t), '[]'::jsonb));
$$;

-- STAFF: replace the list for a program (old rows removed; upload history and issued letters kept)
create or replace function public.replace_recognition_list(
  p_program public.program_type, p_filename text, p_rows jsonb
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_upload bigint;
  v_count integer;
  v_total integer := coalesce(jsonb_array_length(p_rows), 0);
begin
  if not public.is_staff() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  delete from public.recognitions where program = p_program;
  update public.list_uploads set is_active = false where program = p_program and is_active;

  insert into public.list_uploads (program, filename, uploaded_by)
  values (p_program, left(p_filename, 255), (select auth.uid()))
  returning id into v_upload;

  insert into public.recognitions
    (upload_id, program, icar_id, display_name, last_name, shop_name, address, city, province,
     postal_code, recognition_date, icar_id_norm, postal_norm, last_name_norm, name_norm, is_active)
  select v_upload, p_program,
         left(trim(r->>'icar_id'), 64), left(trim(r->>'name'), 300),
         nullif(trim(r->>'last_name'), ''), nullif(trim(r->>'shop_name'), ''),
         nullif(trim(r->>'address'), ''), nullif(trim(r->>'city'), ''),
         nullif(trim(r->>'province'), ''), nullif(trim(r->>'postal_code'), ''),
         case when coalesce(r->>'recognition_date', '') ~ '^\d{4}-\d{2}-\d{2}$'
              then (r->>'recognition_date')::date end,
         public.norm_id(r->>'icar_id'),
         public.norm_id(r->>'postal_code'),
         public.norm_name(r->>'last_name'),
         public.norm_name(r->>'name'),
         true
    from jsonb_array_elements(p_rows) r
   where coalesce(trim(r->>'icar_id'), '') <> '' and coalesce(trim(r->>'name'), '') <> '';
  get diagnostics v_count = row_count;

  if v_count = 0 then
    raise exception 'No valid rows found. The current list was left unchanged.' using errcode = '22023';
  end if;

  update public.list_uploads set row_count = v_count where id = v_upload;
  return jsonb_build_object('upload_id', v_upload, 'inserted', v_count, 'skipped', v_total - v_count);
end $$;

-- STAFF: dashboard numbers
create or replace function public.get_dashboard_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_staff() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'lists', coalesce((select jsonb_agg(jsonb_build_object(
                'program', u.program, 'row_count', u.row_count, 'filename', u.filename,
                'uploaded_at', u.uploaded_at, 'uploaded_by', s.full_name, 'uploaded_by_email', s.email))
              from public.list_uploads u left join public.staff s on s.user_id = u.uploaded_by
             where u.is_active), '[]'::jsonb),
    'letters_total', (select count(*) from public.letter_requests),
    'letters_30d', (select count(*) from public.letter_requests where created_at > now() - interval '30 days'),
    'by_program', coalesce((select jsonb_object_agg(program, n) from
                    (select program, count(*) n from public.letter_requests group by program) x), '{}'::jsonb),
    'unique_recipients', (select count(distinct (program, public.norm_id(icar_id))) from public.letter_requests),
    'new_emails', (select count(distinct requester_email) from public.letter_requests));
end $$;

-- FIRST-TIME SETUP: the first signed-in @aiacanada.com user becomes admin
create or replace function public.claim_first_admin() returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_email text;
begin
  if exists (select 1 from public.staff) then
    return false;
  end if;
  select u.email into v_email from auth.users u where u.id = (select auth.uid());
  if v_email is null or lower(v_email) not like '%@aiacanada.com' then
    return false;
  end if;
  insert into public.staff (user_id, email, role) values ((select auth.uid()), lower(v_email), 'admin');
  return true;
end $$;

create or replace function public.setup_needed() returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from public.staff);
$$;

-- Keep the failed-lookup table small
create or replace function public.prune_lookup_failures() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if random() < 0.02 then
    delete from public.lookup_failures where created_at < now() - interval '1 day';
  end if;
  return null;
end $$;
create trigger lookup_failures_prune after insert on public.lookup_failures
  for each statement execute function public.prune_lookup_failures();

-- Permissions
revoke execute on function public.request_letter, public.verify_letter, public.get_letter_content,
  public.replace_recognition_list, public.get_dashboard_stats, public.claim_first_admin,
  public.setup_needed, public.is_staff, public.is_admin, public.prune_lookup_failures
  from public, anon, authenticated;
grant execute on function public.request_letter, public.verify_letter, public.get_letter_content,
  public.setup_needed to anon, authenticated;
grant execute on function public.replace_recognition_list, public.get_dashboard_stats,
  public.claim_first_admin, public.is_staff, public.is_admin to authenticated;

revoke all on public.lookup_failures from anon, authenticated;
revoke insert, delete on public.letter_requests, public.recognitions, public.list_uploads from anon, authenticated;
revoke all on public.staff, public.list_uploads, public.recognitions, public.letter_requests,
  public.letter_templates, public.letter_settings from anon;
