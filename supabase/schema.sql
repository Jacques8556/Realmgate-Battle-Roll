-- Realmgate Battle Roll — shared battle ledger.
-- Run this once in the Supabase SQL editor (Dashboard → SQL Editor → New query).

create table if not exists public.battles (
  -- The page generates its own short id (e.g. "b1a2b3c4d") so a record keeps
  -- the same identity across the local-storage fallback and the shared roll.
  id            text        primary key,

  date          date        not null,
  points        integer     not null default 2000
                            check (points in (1000, 1500, 2000, 2500, 3000)),
  plan          text        not null default '',
  season        text        not null default ''
                            check (season in ('', '2026-27', '2025-26')),

  a_name        text        not null default '',
  a_faction     text        not null default '',
  a_vp          smallint             check (a_vp between 0 and 99),
  a_list        text        not null default '',

  b_name        text        not null default '',
  b_faction     text        not null default '',
  b_vp          smallint             check (b_vp between 0 and 99),
  b_list        text        not null default '',

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
  created_at    bigint      not null default 0
);

create index if not exists battles_date_idx on public.battles (date desc, created_at desc);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
-- The publishable key ships inside the page, so these policies — not the key —
-- are what actually decide who can do what. The policies below make the roll a
-- fully public ledger: anyone who opens the GitHub Pages URL can read it AND
-- log, amend or delete battles. That matches how the group uses the page, but
-- it does mean a stranger who finds the URL can edit the roll too.
alter table public.battles enable row level security;

drop policy if exists "battles are public to read"  on public.battles;
drop policy if exists "battles are public to write" on public.battles;

create policy "battles are public to read"
  on public.battles for select
  to anon, authenticated
  using (true);

create policy "battles are public to write"
  on public.battles for all
  to anon, authenticated
  using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Read-only alternative
-- ---------------------------------------------------------------------------
-- To publish the roll but keep writing to signed-in accounts, drop the write
-- policy above and use this instead. The page will then show its "does not
-- accept new records from here" message when someone tries to log a battle.
--
--   drop policy if exists "battles are public to write" on public.battles;
--
--   create policy "signed-in warlords may write"
--     on public.battles for all
--     to authenticated
--     using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Live updates (optional)
-- ---------------------------------------------------------------------------
-- With this, an open page refreshes itself when someone else logs a battle.
-- The roll works without it — other devices just pick up changes on reload.
alter publication supabase_realtime add table public.battles;
