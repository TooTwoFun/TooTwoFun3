-- TooTwoFun: enforce a maximum uploaded video length of 60 seconds.
-- Run in Supabase SQL Editor after deploying the matching website code.
alter table public.videos
  add constraint videos_duration_max_60
  check (duration_seconds is null or duration_seconds between 1 and 60) not valid;

-- Allow the public feed to create temporary signed URLs only for approved videos.
drop policy if exists "Public can read published video files" on storage.objects;
create policy "Public can read published video files"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'videos'
  and exists (
    select 1
    from public.videos v
    where v.storage_path = name
      and v.status = 'published'
  )
);
