insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('koki-videos','koki-videos',false,31457280,array['video/mp4','video/webm']) on conflict(id) do nothing;
create policy koki_videos_admin_insert on storage.objects for insert to authenticated with check (bucket_id='koki-videos' and exists(select 1 from public.koki_admin_members m where m.user_id=auth.uid() and m.enabled and m.role in ('superadmin','editor')));
create policy koki_videos_admin_delete on storage.objects for delete to authenticated using (bucket_id='koki-videos' and exists(select 1 from public.koki_admin_members m where m.user_id=auth.uid() and m.enabled and m.role in ('superadmin','editor')));


