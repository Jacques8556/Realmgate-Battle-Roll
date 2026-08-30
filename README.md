# Realmgate-Battle-Roll

A shared Age of Sigmar battle ledger: standings, per-warlord records, and a log
of every engagement. The whole app is one self-contained `index.html`, served
as a static page from GitHub Pages, with the shared roll kept in Supabase.

## Who can do what

| | read the roll | log a battle | amend a battle | retire a battle |
|---|---|---|---|---|
| **anyone, no login** | yes | yes | yes | no |
| **admin** (signed in) | yes | yes | yes | yes |
| **automation** (service key) | yes | yes | yes | yes |

Retiring a battle is a soft delete: it stamps `deleted_at` and the page stops
showing the record, but the row stays in the table. Nothing reachable from the
page can destroy data — a permanent delete takes a SQL statement that you run
yourself. `supabase/schema.sql` has the query to list and restore retired
records at the bottom.

This is enforced by row-level security **and** column-level grants, not by
keeping the key in the page secret. Row-level security alone can't express
"you may edit this row but not that column", and without that an anonymous
visitor could set `deleted_at` on every row through the amend path — mass
deletion wearing a different hat. The grants in `schema.sql` are what stop it.

## Setting it up

### 1. Create the tables

Supabase dashboard → **SQL Editor → New query**, paste
[`supabase/schema.sql`](supabase/schema.sql), run it. Safe to re-run later.

### 2. Create your admin account

**Authentication → Users → Add user**, with an email and password. Tick
*Auto Confirm User* so no email needs to be delivered.

Then turn off public sign-up, so nobody else can make an account:
**Authentication → Sign In / Providers → Email** → disable *Allow new users to
sign up*.

Finally, mark yourself as an admin in the SQL editor:

```sql
insert into public.admins (user_id, note)
select id, 'me' from auth.users where email = 'you@example.com'
on conflict (user_id) do nothing;
```

There is no API path that grants admin — it can only be done here.

### 3. Point the page at the project

`index.html` carries the project URL and publishable key near the top of its
script. Both are meant to ship in the page.

### 4. Turn on Pages

**Settings → Pages → Source: GitHub Actions.**
[`.github/workflows/pages.yml`](.github/workflows/pages.yml) publishes the
repository root on every push to `main`. There is no build step.

### 5. Turn on backups

Add two repository secrets under **Settings → Secrets and variables → Actions**:

- `SUPABASE_URL` — the project URL
- `SUPABASE_SERVICE_ROLE_KEY` — **Project Settings → API Keys → service_role**

[`.github/workflows/backup.yml`](.github/workflows/backup.yml) then exports the
whole table nightly as a build artifact, retired records included.

> The service_role key bypasses row-level security completely. It belongs in
> GitHub Secrets and nowhere else — never in `index.html`, never committed.

## Automated data entry

Workflows write over the REST API. Which key you use depends on what the
workflow needs to do:

**Logging battles** needs no secret at all — the same publishable key that is
already in the page can insert:

```bash
curl -X POST "$SUPABASE_URL/rest/v1/battles" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"id":"b-2026-05-05-01","date":"2026-05-05","points":2000,
       "plan":"Into the Fire","season":"2026-27",
       "a_name":"Ravik","a_faction":"Stormcast Eternals","a_vp":20,
       "b_name":"Terrik","b_faction":"Skaven","b_vp":12,
       "result":"a","created_at":1767571200000}'
```

`id` must be unique and is yours to choose; `created_at` is epoch milliseconds
and only breaks ties between battles on the same date.

**Retiring records or backfilling `created_at`** needs the service_role key, as
in the backup workflow.

## Working on it

Open `index.html` in a browser, or serve the folder (`python3 -m http.server`)
and visit it. If Supabase can't be reached — no network, or the tables not
created yet — the page says so and keeps records in that browser's local
storage instead, so it stays usable offline.
