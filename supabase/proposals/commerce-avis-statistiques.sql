-- PROPOSITION — Commerces & Services : avis des clients, suivi d'activité et statistiques du commerçant.
-- NON APPLIQUÉE : à relire, puis à tester sur Supabase LOCAL (supabase start) avant toute installation distante.
-- Additive : aucune table existante n'est modifiée, aucune donnée n'est supprimée ni réécrite.
-- À installer après commerce-modernisation.sql (elle utilise koki_records et ses statuts publiables).
-- L'application publique (assets/business/client.mjs) détecte l'absence de ces fonctions (PGRST202) et masque simplement
-- les avis et les statistiques tant qu'elles ne sont pas installées : l'ordre de mise en ligne est donc libre.
--
-- Règles :
--  * seules les fiches visibles dans le catalogue public peuvent recevoir un avis ou une activité ;
--  * un client (compte permanent) = un avis par fiche, modifiable ; jamais sur sa propre fiche ; 20 avis par jour maximum ;
--  * un avis masqué par l'administration ne peut pas être republié par son auteur ;
--  * le suivi d'activité est anonyme (compteurs par fiche, type et jour : aucune identité, aucune adresse IP) ;
--  * un commerçant ne voit que les chiffres de ses propres fiches.
begin;

-- 0. Préflight : le socle commerce doit exister.
do $$ begin
 if to_regclass('public.koki_records') is null or to_regprocedure('koki_private.commerce_catalog()') is null then
  raise exception 'Préflight avis : installer d''abord le socle commerce (commerce-modernisation.sql)';
 end if;
end $$;

-- 1. Fiche publique = même règle que koki_private.commerce_catalog().
create function koki_private.is_public_listing(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records l where l.id=p_id and (
  (l.kind='professionnels' and l.statut='Actif')
  or (l.kind='boutiques' and l.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=l.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
  or (l.kind='services' and l.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=l.parent_id and prof.statut='Actif'))
  or (l.kind='produits' and l.statut in ('Disponible','Épuisé') and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=l.parent_id and b.statut='Actif' and prof.statut='Actif'))))
$$;
revoke all on function koki_private.is_public_listing(uuid) from public,anon,authenticated;

-- 2. Avis.
create table public.koki_reviews(
 id uuid primary key default gen_random_uuid(),
 target_id uuid not null references public.koki_records(id) on delete cascade,
 author_id uuid not null references auth.users(id) on delete cascade,
 rating smallint not null check(rating between 1 and 5),
 comment text check(comment is null or char_length(comment)<=500),
 status text not null default 'publié' check(status in ('publié','masqué')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(target_id,author_id));
create index koki_reviews_target on public.koki_reviews(target_id,status,created_at desc);
create index koki_reviews_author on public.koki_reviews(author_id,updated_at desc);
alter table public.koki_reviews enable row level security;
revoke all on public.koki_reviews from public,anon,authenticated;
-- Aucun accès direct pour le public ni les clients : tout passe par les fonctions ci-dessous.
-- Modération : l'administration (permission « commerce », aal2) lit tous les avis et peut les masquer.
grant select,update(status) on public.koki_reviews to authenticated;
create policy reviews_admin_read on public.koki_reviews for select to authenticated using(koki_private.allowed('commerce'));
create policy reviews_admin_hide on public.koki_reviews for update to authenticated using(koki_private.allowed('commerce')) with check(koki_private.allowed('commerce'));

create function public.koki_reviews_list(p_target uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare moyenne numeric; total integer; liste jsonb;
begin
 if p_target is null or not koki_private.is_public_listing(p_target) then return null;end if;
 select round(avg(rating)::numeric,1),count(*) into moyenne,total from public.koki_reviews where target_id=p_target and status='publié';
 select coalesce(jsonb_agg(jsonb_build_object('note',r.rating,'commentaire',nullif(btrim(r.comment),''),'auteur','Client','date',to_char(r.created_at at time zone 'Africa/Dakar','YYYY-MM-DD')) order by r.created_at desc),'[]'::jsonb)
  into liste from (select * from public.koki_reviews where target_id=p_target and status='publié' order by created_at desc limit 20) r;
 return jsonb_build_object('moyenne',coalesce(moyenne,0),'total',total,'avis',liste);
end $$;
revoke all on function public.koki_reviews_list(uuid) from public;
grant execute on function public.koki_reviews_list(uuid) to anon,authenticated;

create function public.koki_review_save(p_target uuid,p_rating integer,p_comment text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); texte text:=nullif(btrim(coalesce(p_comment,'')),''); existant text; proprio uuid;
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if p_rating is null or p_rating not between 1 and 5 then raise exception 'Choisissez une note de 1 à 5.';end if;
 if texte is not null and char_length(texte)>500 then raise exception 'Le commentaire est limité à 500 caractères.';end if;
 if p_target is null or not koki_private.is_public_listing(p_target) then raise exception 'Cette fiche n''est plus disponible.';end if;
 select owner_id into proprio from public.koki_records where id=p_target;
 if proprio=actor then raise exception 'Vous ne pouvez pas noter votre propre fiche.';end if;
 select status into existant from public.koki_reviews where target_id=p_target and author_id=actor;
 if existant='masqué' then raise exception 'Votre avis a été retiré par l''administration.';end if;
 if existant is null and (select count(*) from public.koki_reviews where author_id=actor and created_at>now()-interval '1 day')>=20 then
  raise exception 'Trop d''avis aujourd''hui. Réessayez demain.';end if;
 insert into public.koki_reviews(target_id,author_id,rating,comment) values(p_target,actor,p_rating,texte)
  on conflict(target_id,author_id) do update set rating=excluded.rating,comment=excluded.comment,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.koki_review_save(uuid,integer,text) from public,anon;
grant execute on function public.koki_review_save(uuid,integer,text) to authenticated;

-- 3. Suivi d'activité anonyme : un compteur par fiche, type d'événement et jour.
create table public.koki_activity(
 target_id uuid not null references public.koki_records(id) on delete cascade,
 kind text not null check(kind in ('vue','appel','whatsapp','commander','partage','panier','devis')),
 day date not null default current_date,
 n integer not null default 0 check(n>=0),
 primary key(target_id,kind,day));
create index koki_activity_day on public.koki_activity(day);
alter table public.koki_activity enable row level security;
revoke all on public.koki_activity from public,anon,authenticated;

create function public.koki_track(p_target uuid,p_kind text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_target is null or p_kind is null or p_kind not in ('vue','appel','whatsapp','commander','partage','panier','devis') then return;end if;
 if not koki_private.is_public_listing(p_target) then return;end if;
 insert into public.koki_activity(target_id,kind,day,n) values(p_target,p_kind,current_date,1)
  on conflict(target_id,kind,day) do update set n=least(public.koki_activity.n+1,1000000);
end $$;
revoke all on function public.koki_track(uuid,text) from public;
grant execute on function public.koki_track(uuid,text) to anon,authenticated;

-- 4. Statistiques du commerçant : uniquement ses propres fiches (propriétaire = compte connecté).
create function public.koki_stats_mine(p_days integer default 30) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); jours integer:=greatest(1,least(coalesce(p_days,30),365)); resultat jsonb;
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 with mine as (select id,kind,payload->>'nom' as nom from public.koki_records
   where owner_id=actor and kind in ('professionnels','boutiques','produits','services') and statut<>'Archivé' order by updated_at desc limit 300),
 agg as (select a.target_id,a.kind,sum(a.n)::integer as n from public.koki_activity a join mine on mine.id=a.target_id
   where a.day>current_date-jours group by a.target_id,a.kind)
 select jsonb_build_object('jours',jours,
  'totaux',coalesce((select jsonb_object_agg(t.kind,t.n) from (select kind,sum(n)::integer as n from agg group by kind) t),'{}'::jsonb),
  'elements',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'kind',m.kind,'nom',m.nom)||coalesce((select jsonb_object_agg(g.kind,g.n) from agg g where g.target_id=m.id),'{}'::jsonb)) from mine m),'[]'::jsonb))
 into resultat;
 return resultat;
end $$;
revoke all on function public.koki_stats_mine(integer) from public,anon;
grant execute on function public.koki_stats_mine(integer) to authenticated;

commit;

-- RETOUR ARRIÈRE (à exécuter seulement après sauvegarde, il supprime les avis et les compteurs) :
-- drop function public.koki_stats_mine(integer),public.koki_track(uuid,text),public.koki_review_save(uuid,integer,text),public.koki_reviews_list(uuid);
-- drop table public.koki_activity,public.koki_reviews;
-- drop function koki_private.is_public_listing(uuid);
