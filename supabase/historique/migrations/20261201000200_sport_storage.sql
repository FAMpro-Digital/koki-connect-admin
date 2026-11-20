-- Espace Clubs & Académies — 3/3 : stockage des images (bucket privé koki-sport).
-- APPLIQUÉE EN PRODUCTION le 20/11/2026 (accord écrit de Mourtada Fam). Voir supabase/production/README.md.
-- Chemin imposé : <club_id>/<uuid>.(jpg|png|webp). Les buckets existants ne sont pas modifiés.

begin;

do $$ begin
 if to_regprocedure('koki_sport.public_object(text)') is null then raise exception 'GARDE : migration 20261201000100_sport_access_rpc absente';end if;
 if exists(select 1 from storage.buckets where id='koki-sport') then raise exception 'GARDE : bucket koki-sport déjà présent';end if;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('koki-sport','koki-sport',false,1048576,array['image/jpeg','image/png','image/webp']);

-- Écriture : membre autorisé de l'académie du dossier (responsable, communication, entraîneur), académie modifiable.
create policy koki_sport_insert on storage.objects for insert to authenticated
 with check (bucket_id='koki-sport' and koki_sport.can_write_object(name));
-- Lecture des membres : toutes les images de leur académie.
create policy koki_sport_member_read on storage.objects for select to authenticated
 using (bucket_id='koki-sport' and koki_sport.can_read_object(name));
-- Lecture publique : image référencée par un contenu public ET conforme aux autorisations parentales.
create policy koki_sport_public_read on storage.objects for select to anon, authenticated
 using (bucket_id='koki-sport' and koki_sport.public_object(name));
-- Suppression : membre autorisé, image plus référencée nulle part.
create policy koki_sport_delete on storage.objects for delete to authenticated
 using (bucket_id='koki-sport' and koki_sport.can_write_object(name) and koki_sport.object_unreferenced(name));

commit;
