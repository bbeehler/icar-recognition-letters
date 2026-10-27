-- Bulk email: the team emails every store matching the Notify filters in one go (sent by the send-bulk-email
-- Edge Function through Resend). Each send is recorded here, and each store emailed gets a contact-history entry.
create table public.bulk_sends (
  id bigint generated always as identity primary key,
  created_by uuid references public.staff(user_id) on delete set null,
  created_at timestamptz not null default now(),
  filters jsonb not null default '{}'::jsonb,
  subject_en text,
  subject_fr text,
  recipients integer not null default 0,
  sent integer not null default 0,
  failed integer not null default 0,
  is_test boolean not null default false,
  error text
);
create index bulk_sends_created_by_idx on public.bulk_sends (created_by);
alter table public.bulk_sends enable row level security;
create policy bulk_sends_select on public.bulk_sends for select to authenticated using ((select public.is_staff()));
revoke all on public.bulk_sends from anon;
revoke insert, update, delete on public.bulk_sends from authenticated;
