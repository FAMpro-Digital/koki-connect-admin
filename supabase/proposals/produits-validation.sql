-- Proposition : appliquer après commerce-modernisation et refus-motive-complet, après validation.
-- Les produits existants restent inchangés. Les nouveaux produits attendent une décision.
begin;
create or replace function koki_private.product_review_required() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.kind='produits' then
  new.statut:='Masqué';
  new.payload:=new.payload||jsonb_build_object('moderation_lock',true,'moderation',jsonb_build_object('decision','pending_review','at',now()));
 end if;
 return new;
end $$;
revoke all on function koki_private.product_review_required() from public,anon,authenticated;
create trigger koki_product_review_required before insert on public.koki_records
for each row execute function koki_private.product_review_required();

-- Conserver tous les contrôles existants ; enrichir seulement la file et les compteurs.
alter function koki_private.commerce_admin(text,jsonb) rename to commerce_admin_before_product_review;
create function koki_private.commerce_admin(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare answer jsonb; pending jsonb; pending_count bigint;
begin
 answer:=koki_private.commerce_admin_before_product_review(command,input);
 if command='admin_queue' then
  select coalesce(jsonb_agg(koki_private.commerce_admin_view(r)||jsonb_build_object('demande','produit') order by r.created_at),'[]'::jsonb)
  into pending from public.koki_records r where r.kind='produits' and r.statut='Masqué' and r.payload->'moderation'->>'decision'='pending_review';
  return answer||pending;
 elsif command='admin_stats' then
  select count(*) into pending_count from public.koki_records r where r.kind='produits' and r.statut='Masqué' and r.payload->'moderation'->>'decision'='pending_review';
  return answer||jsonb_build_object('produits_en_attente',pending_count,'suspendus',greatest(0,(answer->>'suspendus')::bigint-pending_count));
 end if;
 return answer;
end $$;
revoke all on function koki_private.commerce_admin(text,jsonb) from public,anon,authenticated;
revoke all on function koki_private.commerce_admin_before_product_review(text,jsonb) from public,anon,authenticated;
grant execute on function koki_private.commerce_admin(text,jsonb) to anon,authenticated;
commit;
