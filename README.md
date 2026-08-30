# Realmgate-Battle-Roll

A shared Age of Sigmar battle ledger: standings, per-warlord records, and a log
of every engagement. The whole app is one self-contained `index.html`, served
as a static page from GitHub Pages, with the shared roll kept in Supabase.

## Setting it up

### 1. Create the table

In the Supabase dashboard, open **SQL Editor → New query**, paste
[`supabase/schema.sql`](supabase/schema.sql), and run it. That creates the
`battles` table, its row-level security policies, and (optionally) enables
realtime so an open page refreshes when someone else logs a battle.

### 2. Point the page at the project

`index.html` carries the project URL and publishable key near the top of its
script:

```js
const SUPABASE_URL = "https://<project>.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_...";
```

Both are meant to ship in the page. What a visitor can actually do is decided
by the row-level security policies in `schema.sql`, not by keeping this string
secret — so read that file before publishing the site, and pick the policy set
that matches how open you want the roll to be.

### 3. Turn on Pages

In **Settings → Pages**, set **Source** to **GitHub Actions**. The workflow in
[`.github/workflows/pages.yml`](.github/workflows/pages.yml) publishes the
repository root on every push to `main`; there is no build step.

## Working on it

Open `index.html` in a browser, or serve the folder (`python3 -m http.server`)
and visit it. If Supabase can't be reached — no network, policies that refuse
the read, or the table not created yet — the page says so and keeps records in
that browser's local storage instead, so it stays usable offline.
