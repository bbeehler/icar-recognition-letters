-- Customer notifications: the team emails or phones customers with a personal link and logs it.
-- Also retires the public QR verification page and brings letter wording in line with the I-CAR brand standards.

-- Contact details from the I-CAR export (optional columns)
alter table public.recognitions
  add column contact_name text,
  add column contact_email text,
  add column contact_phone text;

alter table public.letter_requests
  add column icar_id_norm text generated always as (public.norm_id(icar_id)) stored;
create index letter_requests_lookup_idx on public.letter_requests (program, icar_id_norm);

-- Outreach log
create type public.contact_method as enum ('email', 'phone');
create table public.customer_contacts (
  id bigint generated always as identity primary key,
  program public.program_type not null,
  icar_id text not null,
  icar_id_norm text not null,
  recipient_name text not null,
  method public.contact_method not null,
  contact_detail text,
  note text,
  contacted_by uuid references public.staff(user_id) on delete set null,
  contacted_at timestamptz not null default now()
);
create index customer_contacts_lookup_idx on public.customer_contacts (program, icar_id_norm, contacted_at desc);
create index customer_contacts_by_idx on public.customer_contacts (contacted_by);
alter table public.customer_contacts enable row level security;
create policy contacts_select on public.customer_contacts for select to authenticated using ((select public.is_staff()));
revoke all on public.customer_contacts from anon;
revoke insert, update, delete on public.customer_contacts from authenticated;

-- Editable notification email wording
alter table public.letter_settings
  add column notify_subject_en text not null default 'Your I-CAR® {{program}} recognition letter is ready',
  add column notify_subject_fr text not null default 'Votre lettre de reconnaissance {{program}} d''I-CAR® est prête',
  add column notify_body_en text not null default $t$Hello {{contact}},

Congratulations on {{name}}'s I-CAR® {{program}} recognition. You can now download your official recognition letter, in English or French, whenever you need it:

{{link}}

You'll need your I-CAR ID ({{icar_id}}) and {{check}}.

If you have any questions, reply to this email and we'll be happy to help.

Thank you for your commitment to complete, safe and quality repairs.

{{sender}}
I-CAR Canada$t$,
  add column notify_body_fr text not null default $t$Bonjour {{contact}},

Félicitations pour la reconnaissance {{program}} d'I-CAR® de {{name}}. Vous pouvez maintenant télécharger votre lettre de reconnaissance officielle, en français ou en anglais, au moment qui vous convient :

{{link}}

Vous aurez besoin de votre numéro I-CAR ({{icar_id}}) et {{check}}.

Pour toute question, répondez simplement à ce courriel et nous vous aiderons avec plaisir.

Merci de votre engagement envers des réparations complètes, sécuritaires et de qualité.

{{sender}}
I-CAR Canada$t$;

-- The public verification page is retired
drop function if exists public.verify_letter(text);

-- STAFF: customer list with outreach and download status
create or replace function public.get_customer_list(
  p_program public.program_type, p_q text default '', p_status text default 'all',
  p_limit integer default 50, p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_q text := nullif(trim(coalesce(p_q, '')), '');
  v_res jsonb;
begin
  if not public.is_staff() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  with base as (
    select r.*,
      c.contacted_at as last_contact_at, c.method as last_contact_method,
      coalesce(s.full_name, s.email) as last_contact_by,
      (select count(*) from public.customer_contacts c2 where c2.program = r.program and c2.icar_id_norm = r.icar_id_norm) as contacts,
      l.n as letters, l.last_at as last_letter_at
    from public.recognitions r
    left join lateral (select * from public.customer_contacts c where c.program = r.program and c.icar_id_norm = r.icar_id_norm
                       order by c.contacted_at desc limit 1) c on true
    left join public.staff s on s.user_id = c.contacted_by
    left join lateral (select count(*) n, max(created_at) last_at from public.letter_requests l
                       where l.program = r.program and l.icar_id_norm = r.icar_id_norm) l on true
    where r.is_active and r.program = p_program
      and (v_q is null or r.display_name ilike '%' || v_q || '%' or r.icar_id ilike '%' || v_q || '%'
           or r.contact_email ilike '%' || v_q || '%' or r.contact_name ilike '%' || v_q || '%'
           or r.city ilike '%' || v_q || '%' or r.shop_name ilike '%' || v_q || '%')
  ), filtered as (
    select * from base where case p_status
      when 'not_contacted' then last_contact_at is null and letters = 0
      when 'contacted' then last_contact_at is not null and letters = 0
      when 'downloaded' then letters > 0
      else true end
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'rows', coalesce((select jsonb_agg(to_jsonb(f) - 'icar_id_norm' - 'postal_norm' - 'last_name_norm' - 'name_norm' - 'upload_id' - 'is_active')
                      from (select * from filtered order by (letters > 0), (last_contact_at is not null), display_name
                            limit greatest(1, least(p_limit, 500)) offset greatest(0, p_offset)) f), '[]'::jsonb),
    'summary', (select jsonb_build_object(
        'total', count(*),
        'not_contacted', count(*) filter (where last_contact_at is null and letters = 0),
        'contacted', count(*) filter (where last_contact_at is not null and letters = 0),
        'downloaded', count(*) filter (where letters > 0)) from base))
  into v_res;
  return v_res;
end $$;

-- STAFF: log that a customer was emailed or phoned
create or replace function public.log_customer_contact(
  p_recognition_id bigint, p_method public.contact_method, p_detail text default null, p_note text default null
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_rec public.recognitions;
  v_id bigint;
begin
  if not public.is_staff() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  select * into v_rec from public.recognitions where id = p_recognition_id;
  if not found then
    raise exception 'Customer not found on the current list' using errcode = '22023';
  end if;
  insert into public.customer_contacts (program, icar_id, icar_id_norm, recipient_name, method, contact_detail, note, contacted_by)
  values (v_rec.program, v_rec.icar_id, v_rec.icar_id_norm, v_rec.display_name, p_method,
          left(nullif(trim(p_detail), ''), 320), left(nullif(trim(p_note), ''), 1000), (select auth.uid()))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- STAFF: list upload now carries optional contact details
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
     postal_code, recognition_date, contact_name, contact_email, contact_phone,
     icar_id_norm, postal_norm, last_name_norm, name_norm, is_active)
  select v_upload, p_program,
         left(trim(r->>'icar_id'), 64), left(trim(r->>'name'), 300),
         nullif(trim(r->>'last_name'), ''), nullif(trim(r->>'shop_name'), ''),
         nullif(trim(r->>'address'), ''), nullif(trim(r->>'city'), ''),
         nullif(trim(r->>'province'), ''), nullif(trim(r->>'postal_code'), ''),
         case when coalesce(r->>'recognition_date', '') ~ '^\d{4}-\d{2}-\d{2}$'
              then (r->>'recognition_date')::date end,
         nullif(left(trim(r->>'contact_name'), 200), ''), nullif(lower(left(trim(r->>'contact_email'), 320)), ''),
         nullif(left(trim(r->>'contact_phone'), 60), ''),
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

-- STAFF: dashboard numbers, now with outreach
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
    'unique_recipients', (select count(distinct (program, icar_id_norm)) from public.letter_requests),
    'contacted', (select count(distinct (program, icar_id_norm)) from public.customer_contacts),
    'contacts_30d', (select count(*) from public.customer_contacts where contacted_at > now() - interval '30 days'),
    'not_contacted', (select count(*) from public.recognitions r where r.is_active
        and not exists (select 1 from public.customer_contacts c where c.program = r.program and c.icar_id_norm = r.icar_id_norm)
        and not exists (select 1 from public.letter_requests l where l.program = r.program and l.icar_id_norm = r.icar_id_norm)));
end $$;

revoke execute on function public.get_customer_list, public.log_customer_contact,
  public.replace_recognition_list, public.get_dashboard_stats from public, anon, authenticated;
grant execute on function public.get_customer_list, public.log_customer_contact,
  public.replace_recognition_list, public.get_dashboard_stats to authenticated;

-- Letter wording: I-CAR® on first use, no QR verification
update public.letter_templates set heading = replace(heading, 'I-CAR Gold', 'I-CAR® Gold') where program = 'gold_class' and language = 'en';
update public.letter_templates set heading = replace(heading, 'I-CAR Platinum', 'I-CAR® Platinum') where program = 'platinum' and language = 'en';
update public.letter_templates set heading = replace(heading, 'd''I-CAR', 'd''I-CAR®') where language = 'fr';
update public.letter_templates set body = replace(body, 'This letter reflects recognition status on its date of issue. Current status can be confirmed at any time using the verification code or QR code below.',
  'This letter reflects recognition status on its date of issue. To confirm current status, please contact I-CAR Canada.') where language = 'en';
update public.letter_templates set body = replace(body, 'Cette lettre reflète le statut de reconnaissance à sa date d''émission. Le statut actuel peut être confirmé en tout temps à l''aide du code de vérification ou du code QR ci-dessous.',
  'Cette lettre reflète le statut de reconnaissance à sa date d''émission. Pour confirmer le statut actuel, veuillez communiquer avec I-CAR Canada.') where language = 'fr';
update public.letter_settings set footer_text = 'I-CAR Canada  |  i-car.ca', accent_color = '#006cb4' where id = 1;
