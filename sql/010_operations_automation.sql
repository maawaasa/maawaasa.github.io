-- مأوى: نواة تشغيل الطلبات والتوزيع الذكي والتذكيرات
-- آمن لإعادة التشغيل، وجميع العمليات الخارجية تُمنع من التكرار بمفتاح فريد.

create table if not exists public.contract_workflows (
  contract_id uuid primary key references public.contracts(id) on delete cascade,
  stage text not null default 'new' check (stage in (
    'new','awaiting_deposit','confirmed','assignment_pending','assigned',
    'shoot_scheduled','shot','editing','ready','delivered','awaiting_balance','completed','cancelled'
  )),
  paid_amount numeric(12,2) not null default 0 check (paid_amount >= 0),
  assigned_employee_id uuid references public.employees(id) on delete set null,
  notion_page_id text,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.assignment_offers (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','expired','cancelled')),
  score numeric(14,2) not null default 0,
  response_token_hash text not null unique,
  sent_to text,
  expires_at timestamptz not null,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists assignment_offers_one_pending_per_contract
  on public.assignment_offers(contract_id) where status = 'pending';

create table if not exists public.automation_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  contract_id uuid references public.contracts(id) on delete cascade,
  event_type text not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','done','failed','cancelled')),
  scheduled_for timestamptz,
  payload jsonb not null default '{}'::jsonb,
  attempts integer not null default 0,
  last_error text,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists automation_events_due_idx
  on public.automation_events(status, scheduled_for);
create index if not exists assignment_offers_contract_idx
  on public.assignment_offers(contract_id, created_at desc);

alter table public.contract_workflows enable row level security;
alter table public.assignment_offers enable row level security;
alter table public.automation_events enable row level security;

revoke all on public.contract_workflows from anon, authenticated;
revoke all on public.assignment_offers from anon, authenticated;
revoke all on public.automation_events from anon, authenticated;

create or replace function public.recommend_photographers(p_contract_id uuid)
returns table (
  employee_id uuid,
  employee_name text,
  monthly_revenue numeric,
  active_jobs bigint,
  last_assignment timestamptz,
  score numeric
)
language sql
security definer
set search_path = ''
as $$
  with stats as (
    select
      e.id,
      e.name,
      e.sort_order,
      coalesce(sum(c.total_amount * coalesce(a.share_pct,70) / 100.0)
        filter (where a.created_at >= date_trunc('month', now() at time zone 'Asia/Riyadh')),0) as revenue,
      count(*) filter (where c.status in ('deposit_paid','awaiting_signature','in_progress')) as jobs,
      max(a.created_at) as last_at
    from public.employees e
    left join public.assignments a on a.employee_id = e.id
    left join public.contracts c on c.id = a.contract_id
    where e.role = 'photographer' and coalesce(e.is_active,true)
      and not exists (
        select 1 from public.assignment_offers o
        where o.contract_id = p_contract_id and o.employee_id = e.id
          and o.status in ('rejected','expired','cancelled')
      )
    group by e.id,e.name,e.sort_order
  )
  select id,name,revenue,jobs,last_at,
    (revenue + jobs * 500 + coalesce(extract(epoch from last_at)/1000000000.0,0))::numeric as score
  from stats
  order by revenue asc, jobs asc, last_at asc nulls first, sort_order asc, name asc;
$$;

revoke all on function public.recommend_photographers(uuid) from public, anon, authenticated;
