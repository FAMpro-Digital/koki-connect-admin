-- Retour arrière des propositions 0700/0710 : canal public seul, comme la migration 20261201000600.
begin;
drop policy if exists koki_foot_ecoute on realtime.messages;
create or replace function koki_foot.diffuser(p_evenement text, p_charge jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then return; end if;
 begin
  execute 'select realtime.send($1,$2,$3,false)' using p_charge, p_evenement, 'koki-foot';
 exception when others then
  raise warning 'koki_foot : diffusion impossible (%)', sqlerrm;
 end;
end $$;
revoke all on function koki_foot.diffuser(text,jsonb) from public, anon, authenticated;
commit;
