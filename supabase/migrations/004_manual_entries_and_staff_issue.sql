-- Add a shop or technician by hand (alongside the uploaded list) and issue certificates directly as staff.

alter table public.recognitions alter column upload_id drop not null;
alter table public.recognitions
  add column source text not null default 'list' check (source in ('list', 'manual')),
  add column added_by uuid references public.staff(user_id) on delete set null,
  add column added_at timestamptz;
create index recognitions_added_by_idx on public.recognitions (added_by);

alter table public.letter_requests add column issued_by uuid references public.staff(user_id) on delete set null;
create index letter_requests_issued_by_idx on public.letter_requests (issued_by);

-- Upload replaces the uploaded list but keeps manual entries, unless the new list includes that I-CAR ID
create or replace function public.replace_recognition_list(p_program public.program_type, p_filename text, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_upload bigint; v_count integer; v_merged integer; v_total integer := coalesce(jsonb_array_length(p_rows), 0);
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  delete from public.recognitions where program = p_program and source = 'list';
  update public.list_uploads set is_active = false where program = p_program and is_active;
  insert into public.list_uploads (program, filename, uploaded_by) values (p_program, left(p_filename, 255), (select auth.uid())) returning id into v_upload;
  insert into public.recognitions
    (upload_id, program, icar_id, display_name, last_name, shop_name, address, city, province, postal_code, recognition_date,
     contact_name, contact_email, contact_phone, aluminum, role, icar_id_norm, postal_norm, last_name_norm, name_norm, is_active, source)
  select v_upload, p_program, left(trim(r->>'icar_id'), 64), left(trim(r->>'name'), 300),
         nullif(trim(r->>'last_name'), ''), nullif(trim(r->>'shop_name'), ''), nullif(trim(r->>'address'), ''), nullif(trim(r->>'city'), ''),
         nullif(trim(r->>'province'), ''), nullif(trim(r->>'postal_code'), ''),
         case when coalesce(r->>'recognition_date', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'recognition_date')::date end,
         nullif(left(trim(r->>'contact_name'), 200), ''), nullif(lower(left(trim(r->>'contact_email'), 320)), ''), nullif(left(trim(r->>'contact_phone'), 60), ''),
         p_program = 'gold_class' and lower(trim(coalesce(r->>'aluminum', ''))) in ('true', 'yes', 'y', 'oui', 'o', 'x', '1', 'aluminum', 'aluminium'),
         nullif(left(trim(r->>'role'), 120), ''),
         public.norm_id(r->>'icar_id'), public.norm_id(r->>'postal_code'), public.norm_name(r->>'last_name'), public.norm_name(r->>'name'), true, 'list'
    from jsonb_array_elements(p_rows) r
   where coalesce(trim(r->>'icar_id'), '') <> '' and coalesce(trim(r->>'name'), '') <> '';
  get diagnostics v_count = row_count;
  if v_count = 0 then raise exception 'No valid rows found. The current list was left unchanged.' using errcode = '22023'; end if;
  delete from public.recognitions m
   where m.program = p_program and m.source = 'manual'
     and exists (select 1 from public.recognitions l where l.program = p_program and l.source = 'list' and l.icar_id_norm = m.icar_id_norm);
  get diagnostics v_merged = row_count;
  update public.list_uploads set row_count = v_count where id = v_upload;
  return jsonb_build_object('upload_id', v_upload, 'inserted', v_count, 'skipped', v_total - v_count, 'merged_manual', v_merged);
end $$;

-- STAFF: add (p_id null) or edit one recognition by hand
create or replace function public.save_recognition(p_program public.program_type, p_data jsonb, p_id bigint default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_icar text := left(trim(coalesce(p_data->>'icar_id', '')), 64);
  v_name text := left(trim(coalesce(p_data->>'name', '')), 300);
  v_norm text := public.norm_id(p_data->>'icar_id');
  v_existing public.recognitions; v_row public.recognitions;
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if v_icar = '' or v_name = '' then raise exception 'Enter the I-CAR ID and name.' using errcode = '22023'; end if;
  if p_program = 'gold_class' and public.norm_id(p_data->>'postal_code') = '' then
    raise exception 'Enter the business postal code. The customer confirms with it.' using errcode = '22023'; end if;
  if p_program = 'platinum' and public.norm_name(coalesce(nullif(p_data->>'last_name', ''), p_data->>'name')) = '' then
    raise exception 'Enter the last name. The customer confirms with it.' using errcode = '22023'; end if;
  select * into v_existing from public.recognitions r
   where r.program = p_program and r.icar_id_norm = v_norm and r.is_active and (p_id is null or r.id <> p_id) limit 1;
  if found then
    raise exception '% is already on the % list as %.', v_icar, case p_program when 'gold_class' then 'Gold Class' else 'Platinum' end, v_existing.display_name using errcode = '23505';
  end if;
  if p_id is not null then
    update public.recognitions set
      icar_id = v_icar, display_name = v_name,
      last_name = nullif(trim(p_data->>'last_name'), ''), shop_name = nullif(trim(p_data->>'shop_name'), ''),
      address = nullif(trim(p_data->>'address'), ''), city = nullif(trim(p_data->>'city'), ''),
      province = nullif(trim(p_data->>'province'), ''), postal_code = nullif(trim(p_data->>'postal_code'), ''),
      recognition_date = case when coalesce(p_data->>'recognition_date', '') ~ '^\d{4}-\d{2}-\d{2}$' then (p_data->>'recognition_date')::date end,
      contact_name = nullif(left(trim(p_data->>'contact_name'), 200), ''), contact_email = nullif(lower(left(trim(p_data->>'contact_email'), 320)), ''),
      contact_phone = nullif(left(trim(p_data->>'contact_phone'), 60), ''),
      aluminum = p_program = 'gold_class' and coalesce((p_data->>'aluminum')::boolean, false),
      role = nullif(left(trim(p_data->>'role'), 120), ''),
      icar_id_norm = v_norm, postal_norm = public.norm_id(p_data->>'postal_code'),
      last_name_norm = public.norm_name(p_data->>'last_name'), name_norm = public.norm_name(v_name)
    where id = p_id and program = p_program returning * into v_row;
    if not found then raise exception 'Record not found' using errcode = '22023'; end if;
  else
    insert into public.recognitions
      (program, icar_id, display_name, last_name, shop_name, address, city, province, postal_code, recognition_date,
       contact_name, contact_email, contact_phone, aluminum, role, icar_id_norm, postal_norm, last_name_norm, name_norm, is_active, source, added_by, added_at)
    values
      (p_program, v_icar, v_name, nullif(trim(p_data->>'last_name'), ''), nullif(trim(p_data->>'shop_name'), ''),
       nullif(trim(p_data->>'address'), ''), nullif(trim(p_data->>'city'), ''), nullif(trim(p_data->>'province'), ''), nullif(trim(p_data->>'postal_code'), ''),
       case when coalesce(p_data->>'recognition_date', '') ~ '^\d{4}-\d{2}-\d{2}$' then (p_data->>'recognition_date')::date end,
       nullif(left(trim(p_data->>'contact_name'), 200), ''), nullif(lower(left(trim(p_data->>'contact_email'), 320)), ''), nullif(left(trim(p_data->>'contact_phone'), 60), ''),
       p_program = 'gold_class' and coalesce((p_data->>'aluminum')::boolean, false), nullif(left(trim(p_data->>'role'), 120), ''),
       v_norm, public.norm_id(p_data->>'postal_code'), public.norm_name(p_data->>'last_name'), public.norm_name(v_name),
       true, 'manual', (select auth.uid()), now())
    returning * into v_row;
  end if;
  return to_jsonb(v_row) - 'icar_id_norm' - 'postal_norm' - 'last_name_norm' - 'name_norm';
end $$;

-- STAFF: remove a manually added recognition
create or replace function public.delete_recognition(p_id bigint) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'Not authorized' using errcode = '42501'; end if;
  delete from public.recognitions where id = p_id and source = 'manual';
  if not found then raise exception 'Only manually added records can be removed here.' using errcode = '22023'; end if;
  return true;
end $$;

-- STAFF: issue the certificate and letter directly, logged under the staff member
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
    'name', v_rec.display_name, 'icar_id', v_rec.icar_id, 'shop_name', v_rec.shop_name, 'address', v_rec.address, 'city', v_rec.city,
    'province', v_rec.province, 'postal_code', v_rec.postal_code, 'recognition_date', v_rec.recognition_date,
    'aluminum', v_rec.aluminum, 'role', v_rec.role, 'issued_at', v_now);
end $$;

revoke execute on function public.replace_recognition_list, public.save_recognition, public.delete_recognition, public.staff_issue_letter from public, anon, authenticated;
grant execute on function public.replace_recognition_list, public.save_recognition, public.delete_recognition, public.staff_issue_letter to authenticated;

-- Only admins can remove manually added customers
create or replace function public.delete_recognition(p_id bigint) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can remove customers.' using errcode = '42501'; end if;
  delete from public.recognitions where id = p_id and source = 'manual';
  if not found then raise exception 'Only manually added records can be removed here.' using errcode = '22023'; end if;
  return true;
end $$;
revoke execute on function public.delete_recognition from public, anon, authenticated;
grant execute on function public.delete_recognition to authenticated;
