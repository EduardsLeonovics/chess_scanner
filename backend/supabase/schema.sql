-- ChessHive community: accounts, puzzle posts, comments, follows.
--
-- Run once in the Supabase dashboard (SQL Editor -> New query -> paste ->
-- Run) on a fresh project. Safe to re-run: everything is created only if
-- missing and policies are replaced.
--
-- Everything is readable by signed-in users only; each user can only write
-- their own rows. Row-level security enforces this on the server, so the
-- public "anon" key shipped in the app can't be used to read or change
-- anyone else's data.

create extension if not exists citext;

-- ---------------------------------------------------------------------------
-- Profiles: one per account, created with it (see handle_new_user).

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique
    check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  bio text not null default '' check (char_length(bio) <= 160),
  created_at timestamptz not null default now()
);

-- Profile picture: a public URL in the "avatars" bucket (see Storage below).
alter table public.profiles add column if not exists avatar_url text
  check (avatar_url is null or char_length(avatar_url) <= 500);

-- Copies the username chosen at sign-up (auth metadata) into a profile.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (new.id, new.raw_user_meta_data ->> 'username');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Sign-up checks this first, so a taken name gets a clear message instead
-- of the trigger failing.
create or replace function public.username_available(name text)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select name ~ '^[A-Za-z0-9_]{3,20}$'
     and not exists (select 1 from public.profiles where username = name::citext);
$$;

-- Signing in with a username: Supabase Auth only takes an email, so the
-- app first trades username + password for the account's email. It does
-- that through the sign-in-with-username Edge Function
-- (backend/supabase/functions/), which passes the caller's network address
-- as Supabase's proxy saw it; only that function may call this, so the
-- address can't be faked. The email is returned only when the password is
-- right, so this can't be used to collect addresses.
--
-- Wrong passwords are limited, and checked before any password hashing so
-- floods stay cheap:
--   * 10 per username from one address and 30 per address, per 15 minutes;
--   * 50 per username from all addresses per hour, against guessing spread
--     over many addresses. That only blocks signing in by username: the
--     owner can still sign in with their email meanwhile.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.sign_in_failures (
  username citext not null,
  at timestamptz not null default now()
);
alter table public.sign_in_failures add column if not exists ip text not null default '';
drop index if exists public.sign_in_failures_idx;
create index if not exists sign_in_failures_ip_idx on public.sign_in_failures (ip, at);
create index if not exists sign_in_failures_name_idx on public.sign_in_failures (username, at);

-- The earlier version took the address from a header the caller controls.
drop function if exists public.email_for_sign_in(text, text);

create or replace function public.email_for_sign_in(name text, password text, caller_ip text)
returns text
language plpgsql
volatile
security definer set search_path = public, extensions
as $$
declare
  found_email text;
  hash text;
begin
  if name is null or password is null or coalesce(caller_ip, '') = '' then
    return null;
  end if;
  delete from public.sign_in_failures where at < now() - interval '1 hour';
  if (select count(*) from public.sign_in_failures
      where ip = caller_ip and at > now() - interval '15 minutes') >= 30
     or (select count(*) from public.sign_in_failures
         where ip = caller_ip and username = name::citext
           and at > now() - interval '15 minutes') >= 10
     or (select count(*) from public.sign_in_failures where username = name::citext) >= 50 then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;
  select u.email, u.encrypted_password into found_email, hash
    from public.profiles p join auth.users u on u.id = p.id
    where p.username = name::citext;
  -- No such user: nothing to guess, nothing to record.
  if hash is null then
    return null;
  end if;
  if hash = extensions.crypt(password, hash) then
    delete from public.sign_in_failures where ip = caller_ip and username = name::citext;
    return found_email;
  end if;
  insert into public.sign_in_failures (username, ip) values (name::citext, caller_ip);
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Posts: a position to solve and the author's text.

create table if not exists public.posts (
  id bigint generated always as identity primary key,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null default '' check (char_length(body) <= 280),
  -- Position before last_move (if any); the solver plays the side to move
  -- after it.
  fen text not null check (char_length(fen) <= 100),
  last_move text check (last_move ~ '^[a-h][1-8][a-h][1-8][qrbn]?$'),
  -- UCI moves, solver's first: solver, reply, solver, ...
  solution text[] not null check (cardinality(solution) between 1 and 9),
  -- Engine score of the solution in centipawns for the solver (mates as
  -- +-100000-ish); equally good alternatives are accepted.
  best_score integer not null,
  created_at timestamptz not null default now()
);

create index if not exists posts_created_idx on public.posts (created_at desc, id desc);
create index if not exists posts_author_idx on public.posts (author_id, created_at desc);

create table if not exists public.comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);

create index if not exists comments_post_idx on public.comments (post_id, created_at);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);

create index if not exists follows_followee_idx on public.follows (followee_id);

-- Blocking hides someone's posts and comments from you. Required by the
-- app stores for apps with user-generated content, as is reporting.
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- Whether the signed-in user and [other] have blocked each other, in either
-- direction. Security definer, because users can only read their own
-- blocks; this answers yes or no without showing who blocked whom.
create or replace function public.blocked_between(other uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = other)
       or (b.blocker_id = other and b.blocked_id = auth.uid())
  );
$$;

-- Blocking ends follows and post alerts both ways.
create or replace function public.after_block()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from public.follows
    where (follower_id = new.blocker_id and followee_id = new.blocked_id)
       or (follower_id = new.blocked_id and followee_id = new.blocker_id);
  delete from public.post_alerts
    where (subscriber_id = new.blocker_id and author_id = new.blocked_id)
       or (subscriber_id = new.blocked_id and author_id = new.blocker_id);
  return new;
end;
$$;

drop trigger if exists after_block on public.blocks;
create trigger after_block
  after insert on public.blocks
  for each row execute function public.after_block();

-- Reports go to the project owner (the moderation_queue view, see
-- README.md); nobody can read them through the app. A report is about a
-- post, a comment or a profile. prepare_report fills in who was reported
-- and a copy of what they wrote, so the evidence survives the content (or
-- the account) being deleted.
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  post_id bigint references public.posts (id) on delete set null,
  comment_id bigint references public.comments (id) on delete set null,
  reason text not null default '' check (char_length(reason) <= 500),
  created_at timestamptz not null default now()
);
-- Upgrades from the first version of this table.
alter table public.reports add column if not exists reported_user_id uuid
  references public.profiles (id) on delete set null;
alter table public.reports add column if not exists reported_username text;
alter table public.reports add column if not exists content_snapshot text;
alter table public.reports add column if not exists category text not null default 'other';
alter table public.reports add column if not exists status text not null default 'open';
alter table public.reports add column if not exists moderator_note text;
alter table public.reports alter column reason set default '';
alter table public.reports drop constraint if exists reports_check;
alter table public.reports drop constraint if exists reports_post_id_fkey;
alter table public.reports add constraint reports_post_id_fkey
  foreign key (post_id) references public.posts (id) on delete set null;
alter table public.reports drop constraint if exists reports_comment_id_fkey;
alter table public.reports add constraint reports_comment_id_fkey
  foreign key (comment_id) references public.comments (id) on delete set null;
alter table public.reports drop constraint if exists reports_category_check;
alter table public.reports add constraint reports_category_check check (category in (
  'spam', 'toxic', 'harassment', 'hate', 'violence', 'sexual', 'child_safety', 'self_harm',
  'illegal', 'scam', 'impersonation', 'private_info', 'copyright', 'cheating', 'other'));
alter table public.reports drop constraint if exists reports_status_check;
alter table public.reports add constraint reports_status_check
  check (status in ('open', 'actioned', 'dismissed'));
-- One report per reporter per thing.
create unique index if not exists reports_once on public.reports
  (reporter_id, post_id, comment_id, reported_user_id) nulls not distinct;
create index if not exists reports_open_idx on public.reports (status, created_at);

create or replace function public.prepare_report()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.post_id is null and new.comment_id is null and new.reported_user_id is null then
    raise exception 'A report needs a post, a comment or a user';
  end if;
  if (select count(*) from public.reports
      where reporter_id = new.reporter_id and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'too_many_reports' using errcode = 'P0001';
  end if;
  -- Set by the server, whatever the app sent.
  new.status := 'open';
  new.moderator_note := null;
  new.created_at := now();
  if new.comment_id is not null then
    select c.author_id, c.body into new.reported_user_id, new.content_snapshot
      from public.comments c where c.id = new.comment_id;
  elsif new.post_id is not null then
    select p.author_id, 'Post: ' || p.body || ' (FEN ' || p.fen || ')'
      into new.reported_user_id, new.content_snapshot
      from public.posts p where p.id = new.post_id;
  else
    select 'Profile bio: ' || pr.bio || coalesce(' / avatar: ' || pr.avatar_url, '')
      into new.content_snapshot
      from public.profiles pr where pr.id = new.reported_user_id;
  end if;
  if new.reported_user_id = new.reporter_id then
    raise exception 'own_content' using errcode = 'P0001';
  end if;
  select username into new.reported_username from public.profiles where id = new.reported_user_id;
  return new;
end;
$$;

drop trigger if exists prepare_report on public.reports;
create trigger prepare_report
  before insert on public.reports
  for each row execute function public.prepare_report();

-- "Notify me" on a profile: the subscriber hears about each new post by
-- the author. The app shows them under the bell in the Community tab.
create table if not exists public.post_alerts (
  subscriber_id uuid not null references public.profiles (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (subscriber_id, author_id),
  check (subscriber_id <> author_id)
);

-- Crash reports the app uploads when the user taps "Send report". Anyone
-- may add one (crashes happen signed out too); nobody can read them
-- through the app. Read them in the dashboard: Table Editor -> crash_reports.
create table if not exists public.crash_reports (
  id bigint generated always as identity primary key,
  user_id uuid default auth.uid() references auth.users (id) on delete set null,
  app_version text not null check (char_length(app_version) <= 50),
  platform text not null check (char_length(platform) <= 30),
  os_version text not null check (char_length(os_version) <= 300),
  source text not null check (char_length(source) <= 200),
  error text not null check (char_length(error) <= 4000),
  stack text not null check (char_length(stack) <= 8000),
  happened_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists crash_reports_created_idx on public.crash_reports (created_at desc);

-- Each user's game library, so it comes back after a reinstall or on a new
-- phone (app/lib/src/backup/library_backup.dart): their Lichess / Chess.com
-- usernames and the analysis of their games (puzzles with their review
-- progress, which games were analyzed, skill stats, opening moves). One
-- row per user, written by the app part by part; only its owner can read
-- it. The games themselves aren't kept: the sites have them.
create table if not exists public.libraries (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  -- The app's PuzzleLibraryNotifier.dataVersion that wrote the analysis.
  data_version int not null check (data_version between 1 and 1000),
  accounts jsonb not null default '{}',
  puzzles jsonb not null default '[]',
  analyzed_games jsonb not null default '[]',
  coverage jsonb not null default '{}',
  game_stats jsonb not null default '{}',
  opening_games jsonb not null default '[]',
  updated_at timestamptz not null default now(),
  -- Thousands of analyzed games take a few MB; this only stops abuse.
  constraint libraries_size_check check (
    pg_column_size(accounts) + pg_column_size(puzzles) + pg_column_size(analyzed_games)
      + pg_column_size(coverage) + pg_column_size(game_stats)
      + pg_column_size(opening_games) < 30000000
  )
);

create or replace function public.touch_library()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists libraries_touch on public.libraries;
create trigger libraries_touch before update on public.libraries
  for each row execute function public.touch_library();

-- ---------------------------------------------------------------------------
-- Row-level security.

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.post_alerts enable row level security;
alter table public.crash_reports enable row level security;
alter table public.libraries enable row level security;
-- Only email_for_sign_in (security definer) touches this: no policies.
alter table public.sign_in_failures enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles
  for select to authenticated using (true);
drop policy if exists "own profile editable" on public.profiles;
create policy "own profile editable" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "posts readable" on public.posts;
create policy "posts readable" on public.posts
  for select to authenticated using (true);
drop policy if exists "own posts insertable" on public.posts;
create policy "own posts insertable" on public.posts
  for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "own posts deletable" on public.posts;
create policy "own posts deletable" on public.posts
  for delete to authenticated using (author_id = auth.uid());

drop policy if exists "comments readable" on public.comments;
create policy "comments readable" on public.comments
  for select to authenticated using (true);
drop policy if exists "own comments insertable" on public.comments;
create policy "own comments insertable" on public.comments
  for insert to authenticated with check (
    author_id = auth.uid()
    and not exists (
      select 1 from public.posts p where p.id = post_id and public.blocked_between(p.author_id)
    )
  );
drop policy if exists "own comments deletable" on public.comments;
create policy "own comments deletable" on public.comments
  for delete to authenticated using (author_id = auth.uid());
-- Authors can remove comments under their own posts.
drop policy if exists "comments on own posts deletable" on public.comments;
create policy "comments on own posts deletable" on public.comments
  for delete to authenticated using (
    exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
  );

drop policy if exists "follows readable" on public.follows;
create policy "follows readable" on public.follows
  for select to authenticated using (true);
drop policy if exists "own follows insertable" on public.follows;
create policy "own follows insertable" on public.follows
  for insert to authenticated
  with check (follower_id = auth.uid() and not public.blocked_between(followee_id));
drop policy if exists "own follows deletable" on public.follows;
create policy "own follows deletable" on public.follows
  for delete to authenticated using (follower_id = auth.uid());

drop policy if exists "own blocks readable" on public.blocks;
create policy "own blocks readable" on public.blocks
  for select to authenticated using (blocker_id = auth.uid());
drop policy if exists "own blocks insertable" on public.blocks;
create policy "own blocks insertable" on public.blocks
  for insert to authenticated with check (blocker_id = auth.uid());
drop policy if exists "own blocks deletable" on public.blocks;
create policy "own blocks deletable" on public.blocks
  for delete to authenticated using (blocker_id = auth.uid());

drop policy if exists "reports insertable" on public.reports;
create policy "reports insertable" on public.reports
  for insert to authenticated with check (reporter_id = auth.uid());

drop policy if exists "own alerts readable" on public.post_alerts;
create policy "own alerts readable" on public.post_alerts
  for select to authenticated using (subscriber_id = auth.uid());
drop policy if exists "own alerts insertable" on public.post_alerts;
create policy "own alerts insertable" on public.post_alerts
  for insert to authenticated
  with check (subscriber_id = auth.uid() and not public.blocked_between(author_id));
drop policy if exists "own alerts deletable" on public.post_alerts;
create policy "own alerts deletable" on public.post_alerts
  for delete to authenticated using (subscriber_id = auth.uid());

drop policy if exists "crash reports insertable" on public.crash_reports;
create policy "crash reports insertable" on public.crash_reports
  for insert to anon, authenticated
  with check (user_id is null or user_id = auth.uid());
grant insert on public.crash_reports to anon, authenticated;

drop policy if exists "own library readable" on public.libraries;
create policy "own library readable" on public.libraries
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "own library insertable" on public.libraries;
create policy "own library insertable" on public.libraries
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "own library updatable" on public.libraries;
create policy "own library updatable" on public.libraries
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- A post's position and solution must at least be well formed, so one
-- broken post can't break everyone's feed. NOT VALID: rows from before
-- this check aren't re-checked (the app skips any that don't parse).
alter table public.posts drop constraint if exists posts_fen_format;
alter table public.posts add constraint posts_fen_format check (
  fen ~ '^[1-8pnbrqkPNBRQK]{1,8}(/[1-8pnbrqkPNBRQK]{1,8}){7} [wb] (-|[KQkq]{1,4}) (-|[a-h][36]) [0-9]{1,3} [0-9]{1,4}$'
) not valid;
alter table public.posts drop constraint if exists posts_solution_format;
alter table public.posts add constraint posts_solution_format check (
  array_to_string(solution, ',') ~ '^[a-h][1-8][a-h][1-8][qrbn]?(,[a-h][1-8][a-h][1-8][qrbn]?)*$'
) not valid;

-- ---------------------------------------------------------------------------
-- Anonymous usage statistics: totals per day, event, platform and app
-- version. The app only sends them when the user allowed it (consent
-- message / Settings). Nothing here identifies anyone: no user or device
-- id, and the address a request came from is never stored.
create table if not exists public.usage_daily (
  day date not null default current_date,
  event text not null check (event ~ '^[a-z_]{1,32}$'),
  platform text not null check (platform ~ '^[a-z]{1,16}$'),
  app_version text not null check (app_version ~ '^[0-9.]{1,20}$'),
  count bigint not null default 0,
  primary key (day, event, platform, app_version)
);
alter table public.usage_daily enable row level security;
-- No policies: only record_usage writes it; read it in the dashboard.

-- Adds the app's counts ({"puzzle_solved": 3, ...}) to today's totals.
-- Unknown events are ignored and counts are capped, so a bad client can't
-- do much.
create or replace function public.record_usage(events jsonb, platform text, app_version text)
returns void
language plpgsql
volatile
security definer set search_path = public
as $$
declare
  known constant text[] := array[
    'app_open', 'scan_read', 'scan_failed', 'puzzle_solved', 'puzzle_failed', 'game_analyzed',
    'opening_studied', 'post_created', 'comment_created', 'position_shared'];
  item record;
  n bigint;
begin
  if jsonb_typeof(events) <> 'object' or (select count(*) from jsonb_object_keys(events)) > 30
     or platform !~ '^[a-z]{1,16}$' or app_version !~ '^[0-9.]{1,20}$' then
    return;
  end if;
  for item in select key, value from jsonb_each(events) loop
    continue when not (item.key = any(known)) or jsonb_typeof(item.value) <> 'number';
    n := least(greatest((item.value #>> '{}')::numeric, 0), 500)::bigint;
    continue when n = 0;
    insert into public.usage_daily (event, platform, app_version, count)
      values (item.key, platform, app_version, n)
      on conflict (day, event, platform, app_version)
      do update set count = public.usage_daily.count + excluded.count;
  end loop;
end;
$$;

revoke execute on function public.record_usage(jsonb, text, text) from public;
grant execute on function public.record_usage(jsonb, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Moderation: open reports, child-safety reports first, then newest, with
-- what was reported and how often that user has been reported. For the
-- project owner only (dashboard Table/SQL Editor); the app can't read it.
create or replace view public.moderation_queue as
  select r.id, r.created_at, r.category, r.reason as details,
         r.reported_username, r.content_snapshot,
         r.post_id, r.comment_id, r.reported_user_id,
         reporter.username as reported_by,
         (select count(*) from public.reports o
          where o.reported_user_id = r.reported_user_id) as reports_against_user
  from public.reports r
  left join public.profiles reporter on reporter.id = r.reporter_id
  where r.status = 'open'
  order by r.category = 'child_safety' desc, r.created_at desc;
revoke all on public.moderation_queue from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Storage: profile pictures, one folder per user (<user id>/avatar.jpg).
-- Public to read, so the feed can show them; only the owner can write.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars readable" on storage.objects;
create policy "avatars readable" on storage.objects
  for select using (bucket_id = 'avatars');
drop policy if exists "own avatar insertable" on storage.objects;
create policy "own avatar insertable" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "own avatar updatable" on storage.objects;
create policy "own avatar updatable" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "own avatar deletable" on storage.objects;
create policy "own avatar deletable" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- What the app reads: posts and comments with their author, minus anyone
-- the reader blocked or was blocked by. security_invoker makes the views obey the policies
-- above for the user asking.

create or replace view public.feed_posts
with (security_invoker = true) as
  select p.*,
         a.username as author_username,
         (select count(*) from public.comments c where c.post_id = p.id) as comment_count,
         a.avatar_url as author_avatar_url
  from public.posts p
  join public.profiles a on a.id = p.author_id
  where not public.blocked_between(p.author_id);

create or replace view public.post_comments
with (security_invoker = true) as
  select c.*, a.username as author_username, a.avatar_url as author_avatar_url
  from public.comments c
  join public.profiles a on a.id = c.author_id
  where not public.blocked_between(c.author_id);

create or replace view public.profile_stats
with (security_invoker = true) as
  select pr.id, pr.username, pr.bio, pr.created_at,
         (select count(*) from public.follows f where f.followee_id = pr.id) as followers,
         (select count(*) from public.follows f where f.follower_id = pr.id) as following,
         (select count(*) from public.posts p where p.author_id = pr.id) as posts,
         pr.avatar_url
  from public.profiles pr;

-- Deletes the caller's account and everything they posted (the app stores
-- require in-app account deletion).
create or replace function public.delete_account()
returns void
language sql
security definer set search_path = public
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
grant execute on function public.username_available(text) to anon, authenticated;
-- Only the sign-in-with-username Edge Function (service role) may call it.
revoke execute on function public.email_for_sign_in(text, text, text) from public, anon, authenticated;
grant execute on function public.email_for_sign_in(text, text, text) to service_role;
