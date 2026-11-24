-- PROPOSITION (NON appliquée) — fin de la transition : plus aucune émission sur le canal PUBLIC « koki-foot ».
-- À appliquer seulement quand tous les clients utilisent le canal privé (foot-direct.js, option prive:true).
begin;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='koki_foot_ecoute') then raise exception 'GARDE : 20261201000700 absente'; end if;
end $$;
create or replace function koki_foot.diffuser(p_evenement text, p_charge jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then return; end if;
 begin
  execute 'select realtime.send($1,$2,$3,true)' using p_charge, p_evenement, 'koki-foot';
 exception when others then
  raise warning 'koki_foot : diffusion impossible (%)', sqlerrm;
 end;
end $$;
revoke all on function koki_foot.diffuser(text,jsonb) from public, anon, authenticated;
commit;
