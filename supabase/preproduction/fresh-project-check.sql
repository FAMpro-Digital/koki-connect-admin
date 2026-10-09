-- À exécuter uniquement dans le NOUVEAU projet, après vérification de sa référence.
-- Contrôle conservateur : aucun clonage ni remplacement d'un projet existant.
do $$ begin
 if current_setting('server_version_num')::integer<170000 then raise exception 'PostgreSQL 17 ou supérieur requis';end if;
 if to_regclass('auth.users') is null or to_regclass('storage.objects') is null then raise exception 'Interfaces Supabase Auth/Storage manquantes';end if;
 if exists(select 1 from pg_tables where schemaname='public') or exists(select 1 from auth.users) or exists(select 1 from storage.buckets) then raise exception 'Projet non vide : installation refusée';end if;
end $$;
