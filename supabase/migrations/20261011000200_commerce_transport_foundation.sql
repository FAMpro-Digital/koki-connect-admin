-- GÉNÉRÉ par scripts/build-local-migrations.mjs — NE PAS MODIFIER À LA MAIN.
-- Source : supabase/proposals/commerce-transport-foundation.sql · sha256 d76658e96fddde506e4b087fb8f0be68ac321eff4c73666ceada552606d46d5c
-- Usage : Supabase LOCAL uniquement (supabase start / supabase db reset). Jamais « supabase db push ».
-- PROPOSITION A REVOIR : jamais exécutée sur le projet Supabase réel.
-- Fondation uniquement. Les écritures publiques restent interdites jusqu'aux RPC métier.
-- Réutilise koki_records, koki_admin_members, koki_private.allowed et le journal existants.

alter table public.koki_records
 add column owner_id uuid references auth.users(id) on delete restrict,
 add column client_id uuid references auth.users(id) on delete restrict,
 add column parent_id uuid references public.koki_records(id) on delete restrict,
 add column provider_id uuid references public.koki_records(id) on delete restrict,
 add column driver_id uuid references public.koki_records(id) on delete restrict,
 add column source_id uuid references public.koki_records(id) on delete restrict;
-- Pas de backfill implicite depuis les chaînes JSON : validation des propriétaires requise.
create index koki_records_owner on public.koki_records(owner_id,kind,updated_at desc);
create index koki_records_client on public.koki_records(client_id,kind,updated_at desc);
create index koki_records_parent on public.koki_records(parent_id);
create index koki_records_provider on public.koki_records(provider_id);
create index koki_records_driver on public.koki_records(driver_id);
create index koki_records_source on public.koki_records(source_id);

-- Booléen limité au propriétaire courant ; aucune identité tierce retournée.
create function koki_private.owns_business(record_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records r where r.id=record_id
   and r.owner_id=(select auth.uid())
   and ((r.kind='professionnels' and r.statut='Actif')
     or (r.kind='chauffeurs' and r.statut in ('Disponible','Indisponible'))))
$$;
revoke all on function koki_private.owns_business(uuid) from public,anon;
grant execute on function koki_private.owns_business(uuid) to authenticated;
create policy records_participants_read on public.koki_records for select to authenticated using(
 (owner_id=(select auth.uid()) and kind in ('professionnels','boutiques','produits','services','chauffeurs','vehicules'))
 or (client_id=(select auth.uid()) and kind in ('commandes','demandes_services','courses'))
 or (kind in ('commandes','demandes_services') and koki_private.owns_business(provider_id))
 or (kind='courses' and koki_private.owns_business(driver_id))
);
-- Aucun INSERT/UPDATE/DELETE pour clients ou professionnels. RPC contrôlées à ajouter.

create table public.koki_order_items(
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.koki_records(id) on delete restrict,
 product_id uuid not null references public.koki_records(id) on delete restrict,
 quantity integer not null check(quantity between 1 and 10000),
 unit_price bigint not null check(unit_price between 0 and 1000000000),
 product_name text not null check(length(trim(product_name)) between 1 and 180),
 unique(order_id,product_id)
);
create index koki_order_items_product on public.koki_order_items(product_id);
alter table public.koki_order_items enable row level security;
revoke all on public.koki_order_items from anon,authenticated;
grant select on public.koki_order_items to authenticated;
create policy order_items_participant_read on public.koki_order_items for select to authenticated using(
 exists(select 1 from public.koki_records r where r.id=order_id and r.kind='commandes')
);
-- Les tarifs ne contiennent aucune donnée personnelle et sont publiables après validation.
create table public.koki_transport_rates(
 category text primary key check(category in ('Moto','Taxi','Voiture','Minicar')),
 base_fcfa integer not null check(base_fcfa between 0 and 1000000),
 per_km_fcfa integer not null check(per_km_fcfa between 0 and 1000000),
 active boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.koki_transport_rates enable row level security;
revoke all on public.koki_transport_rates from anon,authenticated;
grant select on public.koki_transport_rates to anon,authenticated;
grant insert,update,delete on public.koki_transport_rates to authenticated;
create policy rates_public_read on public.koki_transport_rates for select to anon,authenticated using(active);
create policy rates_admin_read on public.koki_transport_rates for select to authenticated using(koki_private.allowed('read'));
create policy rates_admin_insert on public.koki_transport_rates for insert to authenticated with check(koki_private.allowed('transport'));
create policy rates_admin_update on public.koki_transport_rates for update to authenticated using(koki_private.allowed('transport')) with check(koki_private.allowed('transport'));
create policy rates_admin_delete on public.koki_transport_rates for delete to authenticated using(koki_private.allowed('transport'));
-- Aucun tarif fictif inséré. L'absence de tarif actif bloque les futures réservations réelles.
