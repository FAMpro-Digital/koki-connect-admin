-- Retour arrière de 20261201000600_foot_acces.sql : retire les fonctions d'accès et la diffusion.
-- Les données du module (tables koki_foot) ne sont PAS touchées.
begin;
drop function if exists public.koki_foot_public(text,jsonb);
drop function if exists public.koki_foot_admin(text,jsonb);
drop function if exists public.koki_foot_sync(text,jsonb);
drop trigger if exists matchs_diffusion on koki_foot.matchs;
drop trigger if exists evenements_diffusion on koki_foot.evenements;
-- Toutes les fonctions koki_foot créées par cette migration (celles de la migration 1/2 sont conservées).
do $$ declare r record; begin
 for r in select p.oid::regprocedure f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='koki_foot' and p.proname not in ('texte_ok','url_ok','evenement_equipe','corrections_ajout_seul','corrections_sans_vidage')
   order by p.proname desc loop
  execute format('drop function if exists %s cascade', r.f);
 end loop;
end $$;
commit;
