-- طلبات تعديل مواعيد التصوير: رابط عميل موقّع وقرار مأوى لمرة واحدة.
create table if not exists public.schedule_change_requests (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts(id) on delete cascade,
  current_shoot_date date,
  proposed_start timestamptz not null,
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  decision_token_hash text not null unique,
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists schedule_change_one_pending_per_contract
  on public.schedule_change_requests(contract_id) where status = 'pending';
create index if not exists schedule_change_contract_idx
  on public.schedule_change_requests(contract_id, created_at desc);

alter table public.schedule_change_requests enable row level security;
revoke all on public.schedule_change_requests from public, anon, authenticated;
