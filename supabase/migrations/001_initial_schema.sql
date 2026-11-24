-- TooTwoFun initial production schema
-- Apply in Supabase SQL Editor. Never expose the service_role key in the browser.
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 username text unique, display_name text, avatar_url text, created_at timestamptz not null default now()
);
create table if not exists public.videos (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 storage_path text not null, caption text not null default '',
 status text not null default 'pending' check (status in ('pending','published','rejected')),
 duration_seconds integer check (duration_seconds is null or duration_seconds between 1 and 600),
 created_at timestamptz not null default now()
);
create index if not exists videos_feed_idx on public.videos(status, created_at desc);
create table if not exists public.video_interactions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 video_id uuid not null references public.videos(id) on delete cascade,
 action text not null check (action in ('like','comment','share')),
 comment_text text, created_at timestamptz not null default now(),
 check ((action='comment' and comment_text is not null and length(trim(comment_text)) between 1 and 1000) or (action<>'comment' and comment_text is null))
);
create index if not exists interactions_video_idx on public.video_interactions(video_id, created_at desc);
create unique index if not exists one_like_per_user_video on public.video_interactions(user_id,video_id) where action='like';
create table if not exists public.wallets (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 coin_balance bigint not null default 0 check (coin_balance >= 0), updated_at timestamptz not null default now()
);
create table if not exists public.reward_rules (
 action text primary key check (action in ('watch','upload','like','share','comment')),
 coins integer not null check (coins >= 0), daily_limit integer not null check (daily_limit >= 0), enabled boolean not null default false
);
insert into public.reward_rules(action,coins,daily_limit,enabled) values
 ('watch',0,30,false),('upload',0,2,false),('like',0,20,false),('share',0,10,false),('comment',0,10,false)
on conflict (action) do nothing;
create table if not exists public.reward_ledger (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 action text not null check (action in ('watch','upload','like','share','comment')),
 reference_id text not null, idempotency_key text not null unique,
 coins integer not null check (coins > 0), created_at timestamptz not null default now()
);
create index if not exists reward_ledger_user_day_idx on public.reward_ledger(user_id,created_at desc);
create table if not exists public.withdrawal_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 coins bigint not null check (coins > 0), payout_method text not null, payout_account text not null,
 status text not null default 'pending' check (status in ('pending','approved','paid','rejected')),
 created_at timestamptz not null default now()
);
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,username,display_name)
 values(new.id,coalesce(new.raw_user_meta_data->>'username','user_'||substr(new.id::text,1,8)),coalesce(new.raw_user_meta_data->>'display_name','New User'))
 on conflict(id) do nothing;
 insert into public.wallets(user_id) values(new.id) on conflict(user_id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created_tootwofun on auth.users;
create trigger on_auth_user_created_tootwofun after insert on auth.users for each row execute procedure public.handle_new_user();

-- Trusted server-side Edge Functions only. The browser must never call this RPC directly.
create or replace function public.award_reward(p_user_id uuid,p_action text,p_reference_id text,p_idempotency_key text)
returns table(awarded_coins integer,new_balance bigint,result text)
language plpgsql security definer set search_path=public as $$
declare rule public.reward_rules%rowtype; used_today integer; current_balance bigint;
begin
 if p_action not in ('watch','upload','like','share','comment') then raise exception 'Unsupported reward action'; end if;
 select * into rule from public.reward_rules where action=p_action and enabled=true;
 if not found or rule.coins<=0 then return query select 0,0::bigint,'reward_disabled'::text; return; end if;
 if exists(select 1 from public.reward_ledger where idempotency_key=p_idempotency_key) then
  select w.coin_balance into current_balance from public.wallets w where w.user_id=p_user_id;
  return query select 0,coalesce(current_balance,0),'already_processed'::text; return;
 end if;
 select count(*) into used_today from public.reward_ledger where user_id=p_user_id and action=p_action and created_at>=date_trunc('day',now());
 if used_today>=rule.daily_limit then
  select w.coin_balance into current_balance from public.wallets w where w.user_id=p_user_id;
  return query select 0,coalesce(current_balance,0),'daily_limit_reached'::text; return;
 end if;
 insert into public.reward_ledger(user_id,action,reference_id,idempotency_key,coins) values(p_user_id,p_action,p_reference_id,p_idempotency_key,rule.coins);
 insert into public.wallets(user_id,coin_balance,updated_at) values(p_user_id,rule.coins,now())
 on conflict(user_id) do update set coin_balance=public.wallets.coin_balance+excluded.coin_balance,updated_at=now();
 select w.coin_balance into current_balance from public.wallets w where w.user_id=p_user_id;
 return query select rule.coins,current_balance,'awarded'::text;
end; $$;
revoke all on function public.award_reward(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.award_reward(uuid,text,text,text) to service_role;

alter table public.profiles enable row level security;
alter table public.videos enable row level security;
alter table public.video_interactions enable row level security;
alter table public.wallets enable row level security;
alter table public.reward_rules enable row level security;
alter table public.reward_ledger enable row level security;
alter table public.withdrawal_requests enable row level security;
create policy "Profiles are viewable" on public.profiles for select using(true);
create policy "Users update own profile" on public.profiles for update using(auth.uid()=id) with check(auth.uid()=id);
create policy "Published videos are public" on public.videos for select using(status='published' or auth.uid()=user_id);
create policy "Users upload own videos" on public.videos for insert with check(auth.uid()=user_id);
create policy "Owners update own pending videos" on public.videos for update using(auth.uid()=user_id and status='pending') with check(auth.uid()=user_id);
create policy "Interactions are viewable" on public.video_interactions for select using(true);
create policy "Users create own interactions" on public.video_interactions for insert with check(auth.uid()=user_id);
create policy "Users remove own interactions" on public.video_interactions for delete using(auth.uid()=user_id);
create policy "Users view own wallet" on public.wallets for select using(auth.uid()=user_id);
create policy "Reward rules are public" on public.reward_rules for select using(true);
create policy "Users view own reward history" on public.reward_ledger for select using(auth.uid()=user_id);
create policy "Users view own withdrawals" on public.withdrawal_requests for select using(auth.uid()=user_id);
create policy "Users request own withdrawals" on public.withdrawal_requests for insert with check(auth.uid()=user_id);
