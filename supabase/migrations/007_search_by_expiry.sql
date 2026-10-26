-- Notify customers: search also matches the expiry date ("Oct 31", "October 31, 2026", "2026-10-31", "31 octobre"),
-- and a new optional filter limits the list to one expiry month (p_expires = 'YYYY-MM').
drop function if exists public.get_customer_list(public.program_type, text, text, integer, integer);

create or replace function public.get_customer_list(
  p_program public.program_type, p_q text default '', p_status text default 'all', p_limit integer default 50, p_offset integer default 0,
  p_expires text default null
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_q text := nullif(trim(coalesce(p_q, '')), ''); v_today date := (now() at time zone 'America/Toronto')::date; v_res jsonb;
  v_month date := case when coalesce(p_expires, '') ~ '^\d{4}-\d{2}$' then (p_expires || '-01')::date end;
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
      and (v_month is null or (r.expires_on >= v_month and r.expires_on < v_month + interval '1 month'))
      and (v_q is null or r.display_name ilike '%' || v_q || '%' or r.raw_name ilike '%' || v_q || '%' or r.icar_id ilike '%' || v_q || '%'
           or r.contact_email ilike '%' || v_q || '%' or r.contact_name ilike '%' || v_q || '%' or r.city ilike '%' || v_q || '%'
           or r.contact_phone ilike '%' || v_q || '%'
           or (r.expires_on is not null and (
                to_char(r.expires_on, 'YYYY-MM-DD') ilike '%' || v_q || '%'
             or to_char(r.expires_on, 'FMMonth FMDD, YYYY') ilike '%' || v_q || '%'
             or to_char(r.expires_on, 'Mon FMDD, YYYY') ilike '%' || v_q || '%'
             or to_char(r.expires_on, 'FMDD/FMMM/YYYY') ilike '%' || v_q || '%'
             or to_char(r.expires_on, 'FMMM/FMDD/YYYY') ilike '%' || v_q || '%'
             or (to_char(r.expires_on, 'FMDD') || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from r.expires_on)::int] || ' ' || to_char(r.expires_on, 'YYYY')) ilike '%' || v_q || '%')))
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
        'off', count(*) filter (where not is_active)) from base),
    'months', (select coalesce(jsonb_agg(jsonb_build_object('m', m, 'n', n) order by m), '[]'::jsonb) from
        (select to_char(expires_on, 'YYYY-MM') m, count(*) n from public.recognitions where program = p_program and is_active and expires_on is not null group by 1) x))
  into v_res;
  return v_res;
end $$;

revoke execute on function public.get_customer_list from public, anon, authenticated;
grant execute on function public.get_customer_list to authenticated;
