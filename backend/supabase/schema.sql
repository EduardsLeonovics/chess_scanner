-- ChessGeek community: accounts, puzzle posts, comments, follows.
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

-- Reports go to the project owner (Table Editor -> reports); nobody can
-- read them through the app.
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  post_id bigint references public.posts (id) on delete cascade,
  comment_id bigint references public.comments (id) on delete cascade,
  reason text not null check (char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  check (post_id is not null or comment_id is not null)
);

-- ---------------------------------------------------------------------------
-- Row-level security.

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

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
  for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "own comments deletable" on public.comments;
create policy "own comments deletable" on public.comments
  for delete to authenticated using (author_id = auth.uid());

drop policy if exists "follows readable" on public.follows;
create policy "follows readable" on public.follows
  for select to authenticated using (true);
drop policy if exists "own follows insertable" on public.follows;
create policy "own follows insertable" on public.follows
  for insert to authenticated with check (follower_id = auth.uid());
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

-- ---------------------------------------------------------------------------
-- What the app reads: posts and comments with their author, minus anyone
-- the reader blocked. security_invoker makes the views obey the policies
-- above for the user asking.

create or replace view public.feed_posts
with (security_invoker = true) as
  select p.*,
         a.username as author_username,
         (select count(*) from public.comments c where c.post_id = p.id) as comment_count
  from public.posts p
  join public.profiles a on a.id = p.author_id
  where not exists (
    select 1 from public.blocks b
    where b.blocker_id = auth.uid() and b.blocked_id = p.author_id
  );

create or replace view public.post_comments
with (security_invoker = true) as
  select c.*, a.username as author_username
  from public.comments c
  join public.profiles a on a.id = c.author_id
  where not exists (
    select 1 from public.blocks b
    where b.blocker_id = auth.uid() and b.blocked_id = c.author_id
  );

create or replace view public.profile_stats
with (security_invoker = true) as
  select pr.id, pr.username, pr.bio, pr.created_at,
         (select count(*) from public.follows f where f.followee_id = pr.id) as followers,
         (select count(*) from public.follows f where f.follower_id = pr.id) as following,
         (select count(*) from public.posts p where p.author_id = pr.id) as posts
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
