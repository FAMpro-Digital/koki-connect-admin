-- Retour arrière de 20261201000200_sport_storage.sql
begin;
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='koki-sport') then
  raise exception 'RETOUR BLOQUÉ : le bucket koki-sport contient des fichiers. Exportez-les et videz-le d’abord.';
 end if;
end $$;
drop policy if exists koki_sport_insert on storage.objects;
drop policy if exists koki_sport_member_read on storage.objects;
drop policy if exists koki_sport_public_read on storage.objects;
drop policy if exists koki_sport_delete on storage.objects;
delete from storage.buckets where id='koki-sport';
commit;
