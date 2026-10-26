-- Gold Class only (Platinum retired). Monthly "Active Gold Stores" export from the I-CAR system:
-- store number + business postal code verification, expiry dates, new/renewed detection,
-- name corrections that survive uploads, and the official letter templates (standard and Aluminum).
-- Applied to the live project as migrations gold_class_system_export + replace_list_temp_tables_fix;
-- functions below are their final versions.

-- Tolerant postal code matching: fixes O/0 and I/1 mix-ups by position (Canadian format A1A 1A1)
create or replace function public.norm_postal(t text) returns text
language plpgsql immutable set search_path = '' as $$
declare s text := upper(regexp_replace(coalesce(t, ''), '[^A-Za-z0-9]', '', 'g')); r text := ''; c text; i int;
begin
  if length(s) <> 6 then return s; end if;
  for i in 1..6 loop
    c := substr(s, i, 1);
    if i in (1, 3, 5) then c := translate(c, '01', 'OI'); else c := translate(c, 'OIL', '011'); end if;
    r := r || c;
  end loop;
  return r;
end $$;

alter table public.recognitions
  add column expires_on date,
  add column raw_name text,
  add column change_status text,
  add column prev_expires_on date;

-- Name corrections the team makes once and keeps across uploads
create table public.store_name_overrides (
  program public.program_type not null,
  icar_id_norm text not null,
  display_name text not null,
  updated_by uuid references public.staff(user_id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (program, icar_id_norm)
);
create index store_name_overrides_updated_by_idx on public.store_name_overrides (updated_by);
alter table public.store_name_overrides enable row level security;
create policy overrides_select on public.store_name_overrides for select to authenticated using ((select public.is_staff()));
revoke all on public.store_name_overrides from anon;
revoke insert, update, delete on public.store_name_overrides from authenticated;

-- Letter templates per variant: standard Gold Class and Gold Class – Aluminum
alter table public.letter_templates add column variant text not null default 'standard' check (variant in ('standard', 'aluminum'));
alter table public.letter_templates drop constraint letter_templates_pkey;
alter table public.letter_templates add primary key (program, language, variant);
delete from public.letter_templates where program = 'platinum';

-- Official Gold Class letter wording (SharePoint: Plaques > Letter templates > Final Version)
update public.letter_templates set heading = '', body = $t$Dear {{name}},

Thank you for your continuing commitment to I-CAR training and congratulations on achieving your full Gold Class status for the coming year.

The Gold Class status verifies that your business is staffed by Platinum recognized professionals. Whether you are a collision repair shop, insurance company, glass business or recycler, the Gold Class emblem denotes the highest level of collision repair training.

To maintain your Gold Class status, each technician, estimator or appraiser must be designated in a role, and acquire at least six hours of I-CAR training or I-CAR recognized training (through the Industry Training Alliance) annually. For further details, please visit i-car.ca. Logging into the website allows you to view your training records, upcoming training schedules, as well as register and pay for training.

I-CAR is an international organization dedicated to providing the information required to perform complete, safe, and quality auto repairs. I-CAR Canada is a training and recognition program run by the Automotive Industries Association of Canada (AIA Canada), a not-for-profit organization representing, supporting and leading innovation in Canada’s $37.8 billion auto care sector. Aimed at up-skilling tradespeople in the collision industry, I-CAR training has been available in Canada since 1979 and has been operated by AIA Canada since 2010.

Congratulations on your achievement!

Sincerely,$t$
where program = 'gold_class' and language = 'en' and variant = 'standard';

update public.letter_templates set heading = '', body = $t${{name}},

Nous vous remercions pour votre engagement renouvelé envers les formations d’I-CAR et nous vous félicitons d’avoir atteint la reconnaissance catégorie Or pour l’année à venir.

La reconnaissance catégorie Or garantit que votre entreprise emploie du personnel ayant la reconnaissance Platine. Que vous soyez un atelier de réparation de carrosserie, un recycleur, une compagnie d’assurance ou de remplacement de pare-brise, l’emblème de la catégorie Or indique le niveau de formation le plus élevé dans l’industrie de la réparation de carrosserie.

Pour conserver votre reconnaissance catégorie Or, chaque technicien, estimateur ou évaluateur doit se voir désigner un rôle et suivre annuellement au moins six heures de formation I-CAR ou de formation reconnue par I-CAR via l’Alliance de formation dans l’industrie. Pour de plus amples informations, veuillez visiter i-car.ca. Ouvrir une séance sur le site Internet vous permet de consulter votre dossier de formation, les horaires des formations à venir, ainsi que de vous inscrire et payer des formations.

I-CAR est une organisation internationale dédiée à fournir les informations nécessaires pour effectuer des réparations automobiles complètes, sûres et de qualité. I-CAR Canada est un programme de formation et de reconnaissance géré par l’Association des industries de l’automobile du Canada (AIA Canada), un organisme sans but lucratif qui représente, appuie et dirige l’innovation dans le secteur canadien de l’entretien et de la réparation automobile, dont la valeur s’élève à 37,8 milliards de dollars. L’objectif de la formation I-CAR est le relèvement des compétences des gens de métier dans l’industrie de la carrosserie. La formation est offerte au Canada depuis 1979 et dirigée par l’AIA Canada depuis 2010.

Félicitations pour votre réussite!

Cordialement,$t$
where program = 'gold_class' and language = 'fr' and variant = 'standard';

insert into public.letter_templates (program, language, variant, heading, body) values
('gold_class', 'en', 'aluminum', '', $t$Dear {{name}},

Thank you for your continuing commitment to I-CAR training and congratulations on achieving your Gold Class - Aluminum status for the coming year.

The Gold Class Aluminum status verifies that your business is staffed by Platinum recognized professionals. For collision repair shops, the Gold Class - Aluminum emblem denotes the highest level of collision repair training.

To maintain your Gold Class Aluminum status, each technician, estimator, or appraiser must be designated in a role, and acquire at least six hours of I-CAR training or I-CAR recognized training (through the Industry Training Alliance) annually. For further details, please visit i-car.ca. Logging in to the website allows you to view your training records, upcoming training schedules, as well as register and pay for training.

I-CAR is an international organization dedicated to providing the information required to perform complete, safe, and quality auto repairs. I-CAR Canada is a training and recognition program run by the Automotive Industries Association of Canada (AIA Canada), a not-for-profit organization representing, supporting and leading innovation in Canada’s $37.8 billion auto care sector. Aimed at up-skilling tradespeople in the collision industry, I-CAR training has been available in Canada since 1979 and has been operated by AIA Canada since 2010.

Congratulations on your achievement!

Sincerely,$t$),
('gold_class', 'fr', 'aluminum', '', $t${{name}},

Nous vous remercions pour votre engagement renouvelé envers les formations d’I-CAR et nous vous félicitons d’avoir atteint la reconnaissance catégorie Or-Aluminium pour l’année à venir.

La reconnaissance catégorie Or-Aluminium garantit que votre entreprise emploie du personnel ayant la reconnaissance Platine. Pour les ateliers de réparation de carrosserie, l’emblème de la catégorie Or-Aluminium indique le niveau de formation le plus élevé dans l’industrie de la réparation de carrosserie.

Pour conserver votre reconnaissance catégorie Or-Aluminium, chaque technicien, estimateur ou évaluateur doit se voir désigner un rôle et suivre annuellement au moins six heures de formation I-CAR ou de formation reconnue par I-CAR via l’Alliance de formation dans l’industrie. Pour de plus amples informations, veuillez visiter i-car.ca. Ouvrir une séance sur le site Internet vous permet de consulter votre dossier de formation, les horaires des formations à venir, ainsi que de vous inscrire et payer des formations.

I-CAR est une organisation internationale dédiée à fournir les informations nécessaires pour effectuer des réparations automobiles complètes, sûres et de qualité. I-CAR Canada est un programme de formation et de reconnaissance géré par l’Association des industries de l’automobile du Canada (AIA Canada), un organisme sans but lucratif qui représente, appuie et dirige l’innovation dans le secteur canadien de l’entretien et de la réparation automobile, dont la valeur s’élève à 37,8 milliards de dollars. L’objectif de la formation I-CAR est le relèvement des compétences des gens de métier dans l’industrie de la carrosserie. La formation est offerte au Canada depuis 1979 et dirigée par l’AIA Canada depuis 2010.

Félicitations pour votre réussite!

Cordialement,$t$);

update public.letter_settings set
  signatory_name = 'Scott Sinclair', signatory_title_en = 'Director, I-CAR Canada', signatory_title_fr = 'Directeur, I-CAR Canada',
  footer_text = 'I-CAR Canada  |  T 613 728.5821  |  1 (800) 808.2920  |  collisiontraining@aiacanada.com',
  support_email = 'collisiontraining@aiacanada.com',
  notify_subject_en = 'Your I-CAR® {{program}} recognition certificate is ready',
  notify_subject_fr = 'Votre certificat de reconnaissance {{program}} d''I-CAR® est prêt',
  notify_body_en = replace(notify_body_en, 'You''ll need your I-CAR ID ({{icar_id}}) and {{check}}.', 'You''ll need your store number ({{icar_id}}) and your business postal code.'),
  notify_body_fr = replace(notify_body_fr, 'Vous aurez besoin de votre numéro I-CAR ({{icar_id}}) et {{check}}.', 'Vous aurez besoin de votre numéro d’atelier ({{icar_id}}) et du code postal de votre entreprise.')
where id = 1;

create or replace function public.get_letter_content() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'settings', (select to_jsonb(s) - 'updated_by' - 'updated_at' - 'id' from public.letter_settings s where s.id = 1),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('program', t.program, 'language', t.language, 'variant', t.variant,
                                     'heading', t.heading, 'body', t.body))
                           from public.letter_templates t), '[]'::jsonb));
$$;

-- PUBLIC: store number + business postal code; expired stores are refused
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
   where r.is_active and r.program = 'gold_class' and r.icar_id_norm = v_id
     and r.postal_norm <> '' and r.postal_norm = public.norm_postal(p_check)
   order by r.expires_on desc nulls last limit 1;
  if not found then
    insert into public.lookup_failures (program, icar_id_norm) values ('gold_class', v_id);
    return jsonb_build_object('ok', false, 'error', 'not_found');
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

-- STAFF: monthly upload. Applies name corrections, flags new / renewed stores, counts stores that dropped off.
create or replace function public.replace_recognition_list(p_program public.program_type, p_filename text, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_upload bigint; v_count integer; v_merged integer; v_dropped integer; v_new integer; v_renewed integer;
  v_total integer := coalesce(jsonb_array_length(p_rows), 0);
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  drop table if exists pg_temp._prev; drop table if exists pg_temp._incoming;
  create temp table _prev on commit drop as
    select icar_id_norm, expires_on from public.recognitions where program = p_program and source = 'list';
  create temp table _incoming on commit drop as
    select distinct on (public.norm_id(r->>'icar_id')) r
      from jsonb_array_elements(p_rows) r
     where coalesce(trim(r->>'icar_id'), '') <> '' and coalesce(trim(r->>'name'), '') <> ''
     order by public.norm_id(r->>'icar_id'), (r->>'expires_on') desc nulls last;

  select count(*) into v_dropped from _prev p
   where not exists (select 1 from _incoming i where public.norm_id(i.r->>'icar_id') = p.icar_id_norm);

  delete from public.recognitions where program = p_program and source = 'list';
  update public.list_uploads set is_active = false where program = p_program and is_active;
  insert into public.list_uploads (program, filename, uploaded_by) values (p_program, left(p_filename, 255), (select auth.uid())) returning id into v_upload;

  insert into public.recognitions
    (upload_id, program, icar_id, display_name, raw_name, last_name, shop_name, address, city, province, postal_code, recognition_date, expires_on,
     contact_name, contact_email, contact_phone, aluminum, role, icar_id_norm, postal_norm, last_name_norm, name_norm, is_active, source,
     change_status, prev_expires_on)
  select v_upload, p_program, left(trim(i.r->>'icar_id'), 64),
         coalesce(o.display_name, left(trim(i.r->>'name'), 300)),
         nullif(left(trim(i.r->>'raw_name'), 400), ''),
         nullif(trim(i.r->>'last_name'), ''), nullif(trim(i.r->>'shop_name'), ''),
         nullif(trim(i.r->>'address'), ''), nullif(trim(i.r->>'city'), ''), nullif(trim(i.r->>'province'), ''), nullif(trim(i.r->>'postal_code'), ''),
         case when coalesce(i.r->>'recognition_date', '') ~ '^\d{4}-\d{2}-\d{2}$' then (i.r->>'recognition_date')::date end,
         case when coalesce(i.r->>'expires_on', '') ~ '^\d{4}-\d{2}-\d{2}$' then (i.r->>'expires_on')::date end,
         nullif(left(trim(i.r->>'contact_name'), 200), ''), nullif(lower(left(trim(i.r->>'contact_email'), 320)), ''), nullif(left(trim(i.r->>'contact_phone'), 60), ''),
         p_program = 'gold_class' and lower(trim(coalesce(i.r->>'aluminum', ''))) in ('true', 'yes', 'y', 'oui', 'o', 'x', '1', 'aluminum', 'aluminium'),
         nullif(left(trim(i.r->>'role'), 120), ''),
         public.norm_id(i.r->>'icar_id'), public.norm_postal(i.r->>'postal_code'),
         public.norm_name(i.r->>'last_name'), public.norm_name(coalesce(o.display_name, i.r->>'name')), true, 'list',
         case when not exists (select 1 from _prev) then null
              when p.icar_id_norm is null then 'new'
              when coalesce(i.r->>'expires_on', '') ~ '^\d{4}-\d{2}-\d{2}$' and (i.r->>'expires_on')::date > coalesce(p.expires_on, '1900-01-01') then 'renewed'
              else null end,
         p.expires_on
    from _incoming i
    left join _prev p on p.icar_id_norm = public.norm_id(i.r->>'icar_id')
    left join public.store_name_overrides o on o.program = p_program and o.icar_id_norm = public.norm_id(i.r->>'icar_id');
  get diagnostics v_count = row_count;
  if v_count = 0 then raise exception 'No valid rows found. The current list was left unchanged.' using errcode = '22023'; end if;

  delete from public.recognitions m
   where m.program = p_program and m.source = 'manual'
     and exists (select 1 from public.recognitions l where l.program = p_program and l.source = 'list' and l.icar_id_norm = m.icar_id_norm);
  get diagnostics v_merged = row_count;
  select count(*) filter (where change_status = 'new'), count(*) filter (where change_status = 'renewed')
    into v_new, v_renewed from public.recognitions where upload_id = v_upload;
  update public.list_uploads set row_count = v_count where id = v_upload;
  drop table if exists pg_temp._prev; drop table if exists pg_temp._incoming;
  return jsonb_build_object('upload_id', v_upload, 'inserted', v_count, 'skipped', v_total - v_count, 'merged_manual', v_merged,
    'new', v_new, 'renewed', v_renewed, 'dropped', v_dropped);
end $$;

-- STAFF: add a store, or edit one. A changed name on a list store is saved as a correction for future uploads.
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
   where r.program = p_program and r.icar_id_norm = v_norm and r.is_active and (p_id is null or r.id <> p_id) limit 1;
  if found then
    raise exception 'Store % is already on the list as %.', v_icar, v_existing.display_name using errcode = '23505';
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
       contact_name, contact_email, contact_phone, aluminum, icar_id_norm, postal_norm, last_name_norm, name_norm, is_active, source, added_by, added_at, change_status)
    values
      (p_program, v_icar, v_name, nullif(trim(p_data->>'address'), ''), nullif(trim(p_data->>'city'), ''), nullif(trim(p_data->>'province'), ''),
       nullif(trim(p_data->>'postal_code'), ''), v_exp,
       nullif(left(trim(p_data->>'contact_name'), 200), ''), nullif(lower(left(trim(p_data->>'contact_email'), 320)), ''), nullif(left(trim(p_data->>'contact_phone'), 60), ''),
       coalesce((p_data->>'aluminum')::boolean, false), v_norm, public.norm_postal(p_data->>'postal_code'), '', public.norm_name(v_name),
       true, 'manual', (select auth.uid()), now(), 'new')
    returning * into v_row;
  end if;
  return to_jsonb(v_row) - 'icar_id_norm' - 'postal_norm' - 'last_name_norm' - 'name_norm';
end $$;

-- STAFF: issue a certificate on a store's behalf
create or replace function public.staff_issue_letter(p_recognition_id bigint, p_language text default 'en')
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_rec public.recognitions; v_staff public.staff; v_raw text; v_code text;
  v_lang text := case when p_language in ('en', 'fr') then p_language else 'en' end; v_now timestamptz := now();
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select * into v_staff from public.staff where user_id = (select auth.uid());
  select * into v_rec from public.recognitions where id = p_recognition_id and is_active;
  if not found then raise exception 'Record not found' using errcode = '22023'; end if;
  loop
    v_raw := upper(encode(extensions.gen_random_bytes(5), 'hex'));
    exit when not exists (select 1 from public.letter_requests l where l.code_norm = v_raw);
  end loop;
  v_code := substr(v_raw, 1, 5) || '-' || substr(v_raw, 6, 5);
  insert into public.letter_requests
    (recognition_id, program, icar_id, recipient_name, requester_name, requester_email, marketing_consent, language, verification_code, code_norm, created_at, issued_by)
  values (v_rec.id, v_rec.program, v_rec.icar_id, v_rec.display_name, coalesce(v_staff.full_name, v_staff.email), v_staff.email,
          false, v_lang, v_code, v_raw, v_now, v_staff.user_id);
  return jsonb_build_object('ok', true, 'code', v_code, 'program', v_rec.program, 'language', v_lang,
    'name', v_rec.display_name, 'icar_id', v_rec.icar_id, 'address', v_rec.address, 'city', v_rec.city,
    'province', v_rec.province, 'postal_code', v_rec.postal_code, 'recognition_date', v_rec.recognition_date,
    'expires_on', v_rec.expires_on, 'aluminum', v_rec.aluminum, 'issued_at', v_now);
end $$;

-- STAFF: store list with outreach status, expiry and new/renewed flags
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
      l.n as letters, l.last_at as last_letter_at
    from public.recognitions r
    left join lateral (select * from public.customer_contacts c where c.program = r.program and c.icar_id_norm = r.icar_id_norm order by c.contacted_at desc limit 1) c on true
    left join public.staff s on s.user_id = c.contacted_by
    left join lateral (select count(*) n, max(created_at) last_at from public.letter_requests l where l.program = r.program and l.icar_id_norm = r.icar_id_norm) l on true
    where r.is_active and r.program = p_program
      and (v_q is null or r.display_name ilike '%' || v_q || '%' or r.raw_name ilike '%' || v_q || '%' or r.icar_id ilike '%' || v_q || '%'
           or r.contact_email ilike '%' || v_q || '%' or r.contact_name ilike '%' || v_q || '%' or r.city ilike '%' || v_q || '%'
           or r.contact_phone ilike '%' || v_q || '%')
  ), filtered as (
    select * from base where case p_status
      when 'new' then change_status in ('new', 'renewed') and not expired
      when 'not_contacted' then last_contact_at is null and letters = 0 and not expired
      when 'contacted' then last_contact_at is not null and letters = 0 and not expired
      when 'downloaded' then letters > 0
      when 'expired' then expired
      else true end
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'rows', coalesce((select jsonb_agg(to_jsonb(f) - 'icar_id_norm' - 'postal_norm' - 'last_name_norm' - 'name_norm' - 'upload_id' - 'is_active')
                      from (select * from filtered order by (change_status is null), (letters > 0), (last_contact_at is not null), display_name
                            limit greatest(1, least(p_limit, 500)) offset greatest(0, p_offset)) f), '[]'::jsonb),
    'summary', (select jsonb_build_object(
        'total', count(*),
        'new', count(*) filter (where change_status in ('new', 'renewed') and not expired),
        'not_contacted', count(*) filter (where last_contact_at is null and letters = 0 and not expired),
        'contacted', count(*) filter (where last_contact_at is not null and letters = 0 and not expired),
        'downloaded', count(*) filter (where letters > 0),
        'expired', count(*) filter (where expired)) from base))
  into v_res;
  return v_res;
end $$;

-- STAFF: dashboard numbers
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
    'new', (select count(*) from public.recognitions where is_active and program = 'gold_class' and change_status in ('new', 'renewed') and not coalesce(expires_on < v_today, false)),
    'letters_total', (select count(*) from public.letter_requests),
    'letters_30d', (select count(*) from public.letter_requests where created_at > now() - interval '30 days'),
    'unique_recipients', (select count(distinct (program, icar_id_norm)) from public.letter_requests),
    'contacted', (select count(distinct (program, icar_id_norm)) from public.customer_contacts),
    'not_contacted', (select count(*) from public.recognitions r where r.is_active and not coalesce(r.expires_on < v_today, false)
        and not exists (select 1 from public.customer_contacts c where c.program = r.program and c.icar_id_norm = r.icar_id_norm)
        and not exists (select 1 from public.letter_requests l where l.program = r.program and l.icar_id_norm = r.icar_id_norm)));
end $$;

revoke execute on function public.norm_postal, public.get_letter_content, public.request_letter, public.replace_recognition_list,
  public.save_recognition, public.staff_issue_letter, public.get_customer_list, public.get_dashboard_stats from public, anon, authenticated;
grant execute on function public.get_letter_content, public.request_letter to anon, authenticated;
grant execute on function public.replace_recognition_list, public.save_recognition, public.staff_issue_letter,
  public.get_customer_list, public.get_dashboard_stats to authenticated;
