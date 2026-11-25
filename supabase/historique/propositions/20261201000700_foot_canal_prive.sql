-- PROPOSITION (NON appliquée, hors de la suite de migrations) — Canal Realtime PRIVÉ pour le module Football.
-- Modifie un réglage Realtime de production : application soumise à l'AUTORISATION ÉCRITE du propriétaire.
--
-- Effet :
--  * koki_foot.diffuser émet sur le canal PRIVÉ « koki-foot » ET, pendant la transition, sur le canal public
--    (les écrans déjà ouverts continuent de recevoir les signaux) ;
--  * politique RLS sur realtime.messages : anon et authenticated peuvent ÉCOUTER le sujet « koki-foot »
--    (Broadcast seulement) ; AUCUNE politique d'insertion : aucun client ne peut émettre sur ce canal privé.
--    Seule la base (realtime.send, exécuté par koki_foot.diffuser en SECURITY DEFINER) peut émettre.
-- Étape suivante, après bascule des clients (foot-direct.js, option prive:true) : 20261201000710 (fin du public).
begin;
do $$ begin
 if to_regprocedure('koki_foot.diffuser(text,jsonb)') is null then raise exception 'GARDE : migration 20261201000600 absente'; end if;
 if to_regclass('realtime.messages') is null then raise exception 'GARDE : schéma Realtime absent'; end if;
 if exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='koki_foot_ecoute') then raise exception 'GARDE : déjà appliquée'; end if;
end $$;

create or replace function koki_foot.diffuser(p_evenement text, p_charge jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then return; end if;
 begin
  execute 'select realtime.send($1,$2,$3,true)' using p_charge, p_evenement, 'koki-foot';   -- canal privé
  execute 'select realtime.send($1,$2,$3,false)' using p_charge, p_evenement, 'koki-foot';  -- transition : canal public
 exception when others then
  raise warning 'koki_foot : diffusion impossible (%)', sqlerrm;
 end;
end $$;
revoke all on function koki_foot.diffuser(text,jsonb) from public, anon, authenticated;

-- Écoute seule du sujet koki-foot (Broadcast), pour les visiteurs et les comptes connectés.
create policy koki_foot_ecoute on realtime.messages for select to anon, authenticated
 using ((select realtime.topic())='koki-foot' and realtime.messages.extension='broadcast');
commit;
