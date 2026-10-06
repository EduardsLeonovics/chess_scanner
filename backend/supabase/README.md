# ChessGeek community backend

Accounts, puzzle posts, comments, follows, blocks and reports live in a
[Supabase](https://supabase.com) project. The app talks to it directly; the
database's row-level security (in `schema.sql`) decides who may read and
write what. The one piece of server code is the `sign-in-with-username`
Edge Function (`functions/`).

## Setting up a project

1. Create a project at supabase.com (the free tier is enough to start).
2. **SQL Editor → New query**: paste all of `schema.sql`, run it.
3. **Authentication → URL Configuration → Redirect URLs**: add
   `chessgeek://login-callback` (sign-up confirmation and password-reset
   links open the app through it).
4. **Authentication → Sign In / Providers → Email**: leave "Confirm email"
   on. Supabase's built-in mailer only sends a few emails per hour, which
   is fine for testing; before a public launch, set up your own SMTP
   (Authentication → Emails → SMTP Settings, e.g. Resend or Brevo, both have
   free tiers).
5. **Project Settings → API Keys**: copy the project URL and the
   *publishable* key (`sb_publishable_…`; older projects call it the
   `anon` key). Never put the *secret* / `service_role` key in the app.
6. Put both into the app build, either in
   `app/lib/src/community/community_config.dart` as the default values, or
   at build time:

   ```
   flutter build apk --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_KEY=sb_publishable_…
   ```

Without them the app works as before and the Community tab says it's
unavailable.

7. **Edge Functions → Deploy a new function → Via Editor**: name it
   `sign-in-with-username`, paste `functions/sign-in-with-username/index.ts`,
   deploy. (Or with the Supabase CLI: `supabase functions deploy
   sign-in-with-username`.) Signing in by username needs it; signing in by
   email works without it. It uses the built-in `SUPABASE_URL` and
   `SUPABASE_SERVICE_ROLE_KEY` secrets, so there is nothing to configure.

Re-run `schema.sql` whenever it changes; it upgrades an existing project in
place.

## Costs

The free plan covers a launch: 500,000 Edge Function calls a month (only
username sign-ins use one), 50,000 monthly active users, a 500 MB database
and 5 GB of downloads. Free projects pause after a week with no requests.
The Pro plan ($25 a month) adds daily backups, no pausing, 2 million
function calls and 100,000 users; move to it once real people depend on
the app.

## Moderation

Reports land in the `moderation_queue` view (Table Editor): open reports,
child-safety reports first, with a copy of what was reported (kept even if
it's deleted) and how often that user has been reported.

A routine that meets Google Play's and the EU Digital Services Act's
expectations for a small app:

- Check the queue at least every day or two; child-safety reports at once.
- For each report decide, then set the report's `status` in the `reports`
  table to `actioned` or `dismissed`, with a line in `moderator_note`.
- To remove a post or comment, delete its row. To ban someone, delete
  their user under Authentication → Users (profile, posts and comments go
  with it).
- Tell the person whose content you removed, and why (the DSA's
  "statement of reasons"): an email to their account address is enough.
- Content that sexualises children must be reported to the police /
  national hotline (in Latvia: drossinternets.lv) — don't just delete it.
- Keep the support email (see CLAUDE.md) monitored: it is the DSA contact
  point for users and authorities.

Free projects are paused after a week without any requests; once people use
the app daily that doesn't happen, and a paused project can be resumed from
the dashboard.
