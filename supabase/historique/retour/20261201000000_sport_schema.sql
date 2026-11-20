-- Retour arrière de 20261201000000_sport_schema.sql
-- Refuse de détruire des données réelles : exporter d'abord, puis exécuter avec
--   set koki.retour_force = 'oui';   (dans la même session)
begin;
do $$ begin
 if to_regprocedure('koki_sport.can(uuid,text,uuid)') is not null then
  raise exception 'RETOUR BLOQUÉ : exécutez d’abord le retour de 20261201000100_sport_access_rpc.sql';
 end if;
 if exists(select 1 from koki_sport.clubs) and coalesce(current_setting('koki.retour_force',true),'')<>'oui' then
  raise exception 'RETOUR BLOQUÉ : des académies existent. Exportez les données puis relancez avec set koki.retour_force = ''oui''';
 end if;
end $$;
drop schema koki_sport cascade;
commit;
