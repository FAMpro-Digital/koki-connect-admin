-- GÉNÉRÉ par scripts/build-local-migrations.mjs — NE PAS MODIFIER À LA MAIN.
-- Source : supabase/proposals/feed-pagine-quotas.sql · sha256 c47999eb5c489a4092b018d692c1eb41f0505521e10ec196f95ebe9a6783d9b6
-- Usage : Supabase LOCAL uniquement (supabase start / supabase db reset). Jamais « supabase db push ».
-- Flux public paginé + quotas d'écriture par compte (ADDITIF : aucune table, colonne ni fonction existante n'est supprimée ou modifiée).
-- 1) public.koki_public_feed_page : même contenu et mêmes règles de visibilité que koki_public_feed(), par pages de 1 à 50 éléments.
--    koki_public_feed() reste en place : le site public l'utilise en repli tant que cette fonction n'est pas installée.
-- 2) koki_private.quota_ecriture : limite le nombre de créations par compte (anti-abus, volumes très supérieurs à un usage normal).
-- À installer d'abord sur l'environnement de TEST ; jamais appliqué automatiquement en production.

create or replace function public.koki_public_feed_page(p_limit integer default 20,p_before timestamptz default null,p_before_id uuid default null)
returns jsonb language sql stable security invoker set search_path='' as $$
with params as(select least(greatest(coalesce(p_limit,20),1),50) as n),
page_rows as(
 select c.*,row_number() over(order by c.publication desc,c.id desc) as rn
 from (select * from public.koki_contents c
  where c.statut='publié' and c.publication<=now() and (c.type<>'Publicités' or (c.actif and (c.fin is null or c.fin>now())))
   and (p_before is null or (c.publication,c.id)<(p_before,coalesce(p_before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
  order by c.publication desc,c.id desc
  limit (select n from params)+1) c)
select jsonb_build_object(
 'version',1,
 'contenus',coalesce((select jsonb_agg(jsonb_build_object('id',id,'type',type,'titre',titre,'resume',resume,'texte',texte,'categorie',categorie,'statut',statut,'publication',publication,'source',source,'lieu',lieu,'evenement',evenement,'image_path',image_path,'une',une,'actif',actif,'emplacement',emplacement,'fin',fin) order by publication desc,id desc) from page_rows where rn<=(select n from params)),'[]'::jsonb),
 'suivant',(select jsonb_build_object('avant',publication,'avant_id',id) from page_rows where rn=(select n from params) and exists(select 1 from page_rows where rn>(select n from params))))
$$;
revoke all on function public.koki_public_feed_page(integer,timestamptz,uuid) from public;
grant execute on function public.koki_public_feed_page(integer,timestamptz,uuid) to anon,authenticated;

create index if not exists koki_records_owner_created on public.koki_records(owner_id,created_at desc) where owner_id is not null;
create index if not exists koki_records_client_created on public.koki_records(client_id,created_at desc) where client_id is not null;

create or replace function koki_private.quota_ecriture() returns trigger language plpgsql security definer set search_path='' as $$
declare compte uuid;total integer;
begin
 if new.kind in ('commandes','demandes_services','courses') then
  -- Demandes d'un client : 60 par heure et 300 par jour.
  compte:=new.client_id;
  if compte is not null then
   select count(*) into total from public.koki_records r where r.client_id=compte and r.kind in ('commandes','demandes_services','courses') and r.created_at>now()-interval '1 hour';
   if total>=60 then raise exception 'Trop de demandes en peu de temps. Réessayez plus tard.' using errcode='P0001';end if;
   select count(*) into total from public.koki_records r where r.client_id=compte and r.kind in ('commandes','demandes_services','courses') and r.created_at>now()-interval '1 day';
   if total>=300 then raise exception 'Limite quotidienne de demandes atteinte. Réessayez demain.' using errcode='P0001';end if;
  end if;
 else
  -- Fiches d'un professionnel (boutiques, produits, services, véhicules…) : 500 créations par jour.
  compte:=new.owner_id;
  if compte is not null then
   select count(*) into total from public.koki_records r where r.owner_id=compte and r.created_at>now()-interval '1 day';
   if total>=500 then raise exception 'Limite quotidienne de créations atteinte. Réessayez demain.' using errcode='P0001';end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function koki_private.quota_ecriture() from public,anon,authenticated;
drop trigger if exists koki_quota_ecriture on public.koki_records;
create trigger koki_quota_ecriture before insert on public.koki_records for each row execute function koki_private.quota_ecriture();

