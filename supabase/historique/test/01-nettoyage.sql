-- KOKI CONNECT TEST (euvxtwmyoihnutifshay) — NETTOYAGE DES OBJETS KOKI AVANT RECONSTRUCTION.
-- NÉCESSITE UNE AUTORISATION EXPLICITE. Ne touche PAS : auth (comptes), schémas gérés par
-- Supabase, registre des migrations, crochets Auth de test (koki_test, koki_test_signup).
-- Une seule transaction : en cas d'erreur, rien n'est modifié.
begin;
-- GARDE : refuse toute base contenant des données réelles (la production en contient).
do $$ begin
 if exists(select 1 from auth.users limit 1) then raise exception 'GARDE : des comptes existent, nettoyage refusé (inventaire et décision requis)'; end if;
 if to_regclass('public.koki_records') is not null and exists(select 1 from public.koki_records limit 1) then raise exception 'GARDE : fiches existantes, nettoyage refusé'; end if;
 if to_regclass('public.koki_contents') is not null and exists(select 1 from public.koki_contents limit 1) then raise exception 'GARDE : publications existantes, nettoyage refusé'; end if;
 if exists(select 1 from storage.objects where bucket_id like 'koki-%' limit 1) then raise exception 'GARDE : fichiers présents dans le stockage Koki, nettoyage refusé'; end if;
 if to_regclass('public.koki_content_images') is not null or to_regprocedure('public.koki_business(text,jsonb)') is not null then raise exception 'GARDE : état plus avancé que prévu (2 migrations), inventaire à refaire'; end if;
end $$;
-- Déclencheur Koki sur les comptes (le schéma auth lui-même n'est pas modifié).
drop trigger if exists koki_register_user on auth.users;
-- Règles Koki sur le stockage (les règles de Supabase, s'il y en a, sont conservées).
do $$ declare r record; begin
 for r in select policyname, tablename from pg_policies where schemaname='storage' and policyname in
  ('koki_media_insert','koki_media_published','koki_media_read','koki_media_delete') loop
  execute format('drop policy %I on storage.%I', r.policyname, r.tablename);
 end loop; end $$;
-- Bucket de test vide (vérifié par la garde). Si Supabase refuse la suppression directe,
-- supprimer le bucket « koki-media » depuis Storage dans le tableau de bord, puis relancer.
delete from storage.buckets where id='koki-media';
-- Objets Koki du schéma public, puis schémas Koki.
do $$ declare r record; begin
 for r in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname like 'koki\_%' loop
  execute format('drop table if exists public.%I cascade', r.relname); end loop;
 for r in select p.oid::regprocedure::text f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'koki\_%' loop
  execute 'drop function if exists '||r.f||' cascade'; end loop;
end $$;
drop schema if exists koki_social_private cascade;
drop schema if exists koki_private cascade;
-- Contrôle : plus aucun objet Koki.
do $$ begin
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'koki\_%')
  or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'koki\_%')
  or to_regnamespace('koki_private') is not null then raise exception 'CONTRÔLE : objets Koki restants'; end if;
end $$;
commit;
