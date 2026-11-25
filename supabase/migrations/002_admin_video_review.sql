-- TooTwoFun admin video review access
-- Run once in Supabase SQL Editor. Admin membership is assigned by trusted SQL only.
create table if not exists public.admin_users (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon, authenticated;
grant select on public.admin_users to authenticated;
drop policy if exists "Admins can read own admin membership" on public.admin_users;
create policy "Admins can read own admin membership"
 on public.admin_users for select to authenticated
 using (user_id = auth.uid());

-- Register the intended administrator account by email.
insert into public.admin_users(user_id)
select id from auth.users where lower(email)=lower('taijulsheikh862@gmail.com')
on conflict (user_id) do nothing;

-- Keep ordinary users from changing their own video status.
drop policy if exists "Owners update own pending videos" on public.videos;
create policy "Owners update own pending videos"
 on public.videos for update to authenticated
 using (auth.uid()=user_id and status='pending')
 with check (auth.uid()=user_id and status='pending');

-- Admins can view all pending submissions and publish/reject them.
drop policy if exists "Admins review videos" on public.videos;
create policy "Admins review videos"
 on public.videos for select to authenticated
 using (exists (select 1 from public.admin_users a where a.user_id=auth.uid()));
drop policy if exists "Admins update video review status" on public.videos;
create policy "Admins update video review status"
 on public.videos for update to authenticated
 using (exists (select 1 from public.admin_users a where a.user_id=auth.uid()))
 with check (exists (select 1 from public.admin_users a where a.user_id=auth.uid())
             and status in ('published','rejected'));

grant select, insert, update on public.videos to authenticated;
