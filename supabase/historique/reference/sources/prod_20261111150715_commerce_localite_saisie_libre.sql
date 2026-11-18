do $p$ begin
 if position('koki_localites' in pg_get_functiondef('koki_private.commerce_village(jsonb)'::regprocedure))=0 then raise exception 'Préflight : fonction déjà modifiée'; end if;
end $p$;
create or replace function koki_private.commerce_village(input jsonb) returns text language plpgsql stable security definer set search_path to '' as $f$
declare v text:=btrim(input->>'village');
begin
 if v is null or v='' then return null;end if;
 if char_length(v)>180 then raise exception 'Localité trop longue';end if;
 return v;
end $f$;

