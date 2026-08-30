-- Realmgate Battle Roll — shared battle ledger.
-- Run this in the Supabase SQL editor (Dashboard → SQL Editor → New query).
-- It is safe to re-run: every statement is idempotent.
--
-- Who can do what
-- ---------------
--   anyone (no login)  read the roll, log a battle, amend an existing battle
--   admins             all of the above, plus retire a battle from the roll
--   automation         writes with the service_role key, bypassing all of this
--
-- Nobody reachable from the page can destroy a row. The admin "delete" is a
-- soft delete that sets deleted_at; the record stays in the table and only a
-- real SQL statement run by you can remove it for good.

-- ---------------------------------------------------------------------------
-- battles
-- ---------------------------------------------------------------------------
create table if not exists public.battles (
  -- The page generates its own short id (e.g. "b1a2b3c4d") so a record keeps
  -- the same identity across the local-storage fallback and the shared roll.
  id            text        primary key,

  date          date        not null,
  points        integer     not null default 2000
                            check (points in (1000, 1500, 2000, 2500, 3000)),
  plan          text        not null default '' check (length(plan) <= 200),
  season        text        not null default ''
                            check (season in ('', '2026-27', '2025-26')),

  a_name        text        not null default '' check (length(a_name) <= 120),
  a_faction     text        not null default '' check (length(a_faction) <= 120),
  a_vp          smallint             check (a_vp between 0 and 99),
  a_list        text        not null default '' check (length(a_list) <= 20000),

  b_name        text        not null default '' check (length(b_name) <= 120),
  b_faction     text        not null default '' check (length(b_faction) <= 120),
  b_vp          smallint             check (b_vp between 0 and 99),
  b_list        text        not null default '' check (length(b_list) <= 20000),

  result        text        not null default 'draw'
                            check (result in ('a', 'b', 'draw')),
  -- Which battle round the losing side conceded in; null when the game was
  -- played out to its result.
  concede_round smallint             check (concede_round between 1 and 5),

  -- Naming the attacker implies the other side is the defender.
  attacker      text        not null default '' check (attacker in ('', 'a', 'b')),
  first_turn    text        not null default '' check (first_turn in ('', 'a', 'b')),

  -- Epoch milliseconds from the client, used only to break ties between two
  -- battles logged on the same date.
  created_at    bigint      not null default 0,

  -- Set when an admin retires a record. The row survives; the page hides it.
  deleted_at    timestamptz
);

-- For anyone upgrading from the first version of this schema.
alter table public.battles add column if not exists deleted_at timestamptz;

create index if not exists battles_live_idx
  on public.battles (date desc, created_at desc) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- admins
-- ---------------------------------------------------------------------------
-- Membership is granted by you, in the SQL editor — there is deliberately no
-- way to add yourself through the API. See the README for the insert to run
-- after creating your account.
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  note    text
);

alter table public.admins enable row level security;

drop policy if exists "an admin can see their own row" on public.admins;
create policy "an admin can see their own row"
  on public.admins for select to authenticated
  using (user_id = auth.uid());

-- security definer so that checking this from inside a battles policy does not
-- itself get filtered by the admins policy above.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
-- The publishable key ships inside the page, so these policies — not the key —
-- are what decide who can do what.
alter table public.battles enable row level security;

drop policy if exists "the roll is public to read"      on public.battles;
drop policy if exists "anyone may log a battle"         on public.battles;
drop policy if exists "anyone may amend a live battle"  on public.battles;
drop policy if exists "admins may do anything"          on public.battles;
-- Names used by the first version of this schema.
drop policy if exists "battles are public to read"      on public.battles;
drop policy if exists "battles are public to write"     on public.battles;

create policy "the roll is public to read"
  on public.battles for select to anon, authenticated
  using (deleted_at is null);

create policy "anyone may log a battle"
  on public.battles for insert to anon, authenticated
  with check (deleted_at is null);

create policy "anyone may amend a live battle"
  on public.battles for update to anon, authenticated
  using (deleted_at is null) with check (deleted_at is null);

-- Permissive policies are OR-ed together, so this is what lets an admin read
-- retired records, set deleted_at, and hard-delete.
create policy "admins may do anything"
  on public.battles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Column privileges
-- ---------------------------------------------------------------------------
-- Row-level security cannot say "you may edit this row but not that column",
-- and without that an anonymous visitor could satisfy the amend policy while
-- setting deleted_at on every row — mass deletion wearing a different hat.
-- Column-level grants are the mechanism that actually prevents it.
revoke all on public.battles from anon, authenticated;

grant select, insert on public.battles to anon, authenticated;

-- Note the absence of deleted_at, id and created_at: a visitor may correct the
-- details of a battle, but cannot retire it, re-key it, or reorder the roll.
grant update (
  date, points, plan, season,
  a_name, a_faction, a_vp, a_list,
  b_name, b_faction, b_vp, b_list,
  result, concede_round, attacker, first_turn
) on public.battles to anon;

-- Signed-in accounts exist only for admins (public sign-up is disabled), and
-- the policies above still gate the rows.
grant update, delete on public.battles to authenticated;

grant select on public.admins to authenticated;

-- ---------------------------------------------------------------------------
-- Live updates
-- ---------------------------------------------------------------------------
-- With this, an open page refreshes itself when someone else logs a battle.
-- The roll works without it — other devices just pick up changes on reload.
do $$
begin
  alter publication supabase_realtime add table public.battles;
exception
  when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- Recovering a retired battle
-- ---------------------------------------------------------------------------
--   select id, date, a_name, b_name, deleted_at
--     from public.battles where deleted_at is not null;
--
--   update public.battles set deleted_at = null where id = '<id>';
