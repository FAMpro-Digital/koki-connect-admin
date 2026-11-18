do $p$ begin
 if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='koki_videos_published') then raise exception 'Préflight : politique déjà présente'; end if;
end $p$;
alter policy koki_content_media_admin_write on public.koki_content_media to authenticated;
create policy koki_videos_published on storage.objects for select to anon, authenticated using (bucket_id='koki-videos' and exists(select 1 from public.koki_content_media m join public.koki_contents c on c.id=m.content_id where m.storage_path=objects.name and c.statut='publié' and c.publication<=now() and (c.type<>'Publicités' or (c.actif and (c.fin is null or c.fin>now())))));

