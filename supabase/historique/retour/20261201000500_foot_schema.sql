-- Retour arrière de 20261201000500_foot_schema.sql
-- Refuse de détruire des données réelles : exporter d'abord, puis exécuter avec
--   set koki.retour_force = 'oui';   (dans la même session)
begin;
do $$ begin
 if to_regprocedure('public.koki_foot_admin(text,jsonb)') is not null then
  raise exception 'RETOUR BLOQUÉ : exécutez d’abord le retour de 20261201000600_foot_acces.sql';
 end if;
 if (exists(select 1 from koki_foot.matchs) or exists(select 1 from koki_foot.competitions) or exists(select 1 from koki_foot.corrections))
    and coalesce(current_setting('koki.retour_force',true),'')<>'oui' then
  raise exception 'RETOUR BLOQUÉ : le module contient des données. Exportez-les puis relancez avec set koki.retour_force = ''oui''';
 end if;
end $$;
-- Lignes du journal public.koki_audit conservées (historique).
drop schema koki_foot cascade;
commit;
