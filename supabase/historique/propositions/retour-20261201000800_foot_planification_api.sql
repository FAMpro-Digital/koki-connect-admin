-- Retour de 20261201000800 : retire la fonction de lecture ajoutée (aucune donnée concernée).
begin;
drop function if exists public.koki_foot_sync_planning(text);
commit;
