-- Éducation · Bibliothèque : fichiers des livres (PDF, EPUB, audio MP3/M4A).
-- Proposition relue, à appliquer d'abord sur Supabase LOCAL puis préproduction, jamais directement en production.
-- Bucket privé « koki-livres », séparé de « koki-media » (photos 1 Mo).
-- 50 Mo maximum par fichier : limite d'envoi du forfait Supabase Free.
-- Le public ne peut lire QUE le fichier d'un livre GRATUIT, publié, non archivé et visible à la date courante.
-- Un livre payant n'a jamais de fichier publié (contrat koki.education.book) : rien n'est lisible par le public.
begin;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('koki-livres','koki-livres',false,52428800,array['application/pdf','application/epub+zip','audio/mpeg','audio/mp4','audio/x-m4a']);

-- Vrai si « path » est le fichier d'un livre gratuit publié. Les textes non JSON sont ignorés sans erreur.
create function koki_private.livre_gratuit_publie(path text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare r record;v jsonb;
begin
 if path is null or path !~ '^[a-f0-9-]+/[a-f0-9-]+\.(pdf|epub|mp3|m4a)$' then return false;end if;
 for r in select c.texte from public.koki_contents c
   where c.type='Informations utiles' and c.categorie='Éducation' and c.statut='publié' and c.publication<=now() and strpos(c.texte,path)>0
 loop
  begin v:=r.texte::jsonb;exception when others then continue;end;
  if v->>'schema'='koki.education.book' and v->>'acces'='Gratuit' and coalesce(v->>'archive','false')='false' and v->>'fichier'=path then return true;end if;
 end loop;
 return false;
end $$;
revoke all on function koki_private.livre_gratuit_publie(text) from public;
grant execute on function koki_private.livre_gratuit_publie(text) to anon,authenticated;

-- Éditeurs (MFA exigée par koki_private.allowed) : envoi dans leur propre dossier.
create policy livres_insert on storage.objects for insert to authenticated
 with check(bucket_id='koki-livres' and (storage.foldername(name))[1]=(select auth.uid())::text and koki_private.allowed('content'));
-- Administration : lecture pour vérifier les fichiers.
create policy livres_admin_read on storage.objects for select to authenticated
 using(bucket_id='koki-livres' and koki_private.allowed('read'));
-- Public : uniquement les livres gratuits publiés.
create policy livres_public_read on storage.objects for select to anon,authenticated
 using(bucket_id='koki-livres' and koki_private.livre_gratuit_publie(name));
-- Suppression : par son auteur, seulement si plus aucune fiche ne référence le fichier.
create policy livres_delete on storage.objects for delete to authenticated
 using(bucket_id='koki-livres' and koki_private.allowed('content') and (storage.foldername(name))[1]=(select auth.uid())::text
  and not exists(select 1 from public.koki_contents c where strpos(c.texte,name)>0));

commit;
