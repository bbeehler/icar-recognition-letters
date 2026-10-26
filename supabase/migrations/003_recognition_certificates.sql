-- Recognition certificates: Gold Class – Aluminum designation and Platinum role, from the uploaded lists.
-- The download is now one PDF: the recognition certificate (modelled on the I-CAR plaques) followed by Scott's letter.

alter table public.recognitions
  add column aluminum boolean not null default false,
  add column role text;

-- request_letter now also returns aluminum and role
create or replace function public.request_letter(
  p_program public.program_type, p_icar_id text, p_check text, p_requester_name text, p_requester_email text,
  p_language text default 'en', p_marketing_consent boolean default false
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
              else length(v_ln) >= 2 and ((r.last_name_norm <> '' and r.last_name_norm = v_ln) or right(r.name_norm, length(v_ln)) = v_ln)
         end
   order by r.recognition_date desc nulls last limit 1;
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
    (recognition_id, program, icar_id, recipient_name, requester_name, requester_email, marketing_consent, language, verification_code, code_norm, created_at)
  values
    (v_rec.id, v_rec.program, v_rec.icar_id, v_rec.display_name, left(trim(p_requester_name), 200),
     lower(left(trim(p_requester_email), 320)), coalesce(p_marketing_consent, false), v_lang, v_code, v_raw, v_now);
  return jsonb_build_object(
    'ok', true, 'code', v_code, 'program', v_rec.program, 'language', v_lang,
    'name', v_rec.display_name, 'icar_id', v_rec.icar_id, 'shop_name', v_rec.shop_name,
    'address', v_rec.address, 'city', v_rec.city, 'province', v_rec.province,
    'postal_code', v_rec.postal_code, 'recognition_date', v_rec.recognition_date,
    'aluminum', v_rec.aluminum, 'role', v_rec.role, 'issued_at', v_now);
end $$;

-- replace_recognition_list now reads the aluminum and role columns
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
  values (p_program, left(p_filename, 255), (select auth.uid())) returning id into v_upload;
  insert into public.recognitions
    (upload_id, program, icar_id, display_name, last_name, shop_name, address, city, province,
     postal_code, recognition_date, contact_name, contact_email, contact_phone, aluminum, role,
     icar_id_norm, postal_norm, last_name_norm, name_norm, is_active)
  select v_upload, p_program,
         left(trim(r->>'icar_id'), 64), left(trim(r->>'name'), 300),
         nullif(trim(r->>'last_name'), ''), nullif(trim(r->>'shop_name'), ''),
         nullif(trim(r->>'address'), ''), nullif(trim(r->>'city'), ''),
         nullif(trim(r->>'province'), ''), nullif(trim(r->>'postal_code'), ''),
         case when coalesce(r->>'recognition_date', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'recognition_date')::date end,
         nullif(left(trim(r->>'contact_name'), 200), ''), nullif(lower(left(trim(r->>'contact_email'), 320)), ''),
         nullif(left(trim(r->>'contact_phone'), 60), ''),
         p_program = 'gold_class' and lower(trim(coalesce(r->>'aluminum', ''))) in ('true', 'yes', 'y', 'oui', 'o', 'x', '1', 'aluminum', 'aluminium'),
         nullif(left(trim(r->>'role'), 120), ''),
         public.norm_id(r->>'icar_id'), public.norm_id(r->>'postal_code'),
         public.norm_name(r->>'last_name'), public.norm_name(r->>'name'), true
    from jsonb_array_elements(p_rows) r
   where coalesce(trim(r->>'icar_id'), '') <> '' and coalesce(trim(r->>'name'), '') <> '';
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'No valid rows found. The current list was left unchanged.' using errcode = '22023';
  end if;
  update public.list_uploads set row_count = v_count where id = v_upload;
  return jsonb_build_object('upload_id', v_upload, 'inserted', v_count, 'skipped', v_total - v_count);
end $$;

revoke execute on function public.request_letter, public.replace_recognition_list from public, anon, authenticated;
grant execute on function public.request_letter to anon, authenticated;
grant execute on function public.replace_recognition_list to authenticated;

-- Letter: a line for Aluminum shops (blank for everyone else)
update public.letter_templates
   set body = regexp_replace(body, '(en date de la présente lettre\.|as of the date of this letter\.)', '\1' || E'\n\n{{aluminum_note}}')
 where program = 'gold_class' and body not like '%{{aluminum_note}}%';

-- Notification email: certificate and letter
update public.letter_settings set
  notify_subject_en = replace(notify_subject_en, 'recognition letter is ready', 'recognition certificate is ready'),
  notify_subject_fr = replace(notify_subject_fr, 'Votre lettre de reconnaissance {{program}} d''I-CAR® est prête', 'Votre certificat de reconnaissance {{program}} d''I-CAR® est prêt'),
  notify_body_en = replace(notify_body_en, 'You can now download your official recognition letter, in English or French, whenever you need it:', 'You can now download your official recognition certificate, along with a confirmation letter, in English or French, whenever you need them:'),
  notify_body_fr = replace(notify_body_fr, 'Vous pouvez maintenant télécharger votre lettre de reconnaissance officielle, en français ou en anglais, au moment qui vous convient :', 'Vous pouvez maintenant télécharger votre certificat de reconnaissance officiel, accompagné d''une lettre de confirmation, en français ou en anglais, au moment qui vous convient :')
where id = 1;
