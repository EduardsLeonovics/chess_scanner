# ChessGeek community backend

Accounts, puzzle posts, comments, follows, blocks and reports live in a
[Supabase](https://supabase.com) project. The app talks to it directly; the
database's row-level security (in `schema.sql`) decides who may read and
write what, so there is no server code of our own.

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

## Moderation

Reports land in the `reports` table (Table Editor). To remove a post or a
comment, delete its row; to ban someone, delete their user under
Authentication → Users (their profile, posts and comments go with it).

Free projects are paused after a week without any requests; once people use
the app daily that doesn't happen, and a paused project can be resumed from
the dashboard.
