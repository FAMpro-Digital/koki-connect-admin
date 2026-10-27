-- Une première boutique issue de la fiche : gestion immédiate, publication liée à la validation du professionnel.
create or replace function koki_private.ensure_initial_shop(p public.koki_records) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p.kind<>'professionnels' or p.owner_id is null or p.statut not in ('Actif','En attente','À valider') or coalesce(p.payload->>'type','') not in ('Commerçant','Les deux') then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));
 -- Même une boutique archivée compte : ne jamais la recréer après une suppression volontaire.
 if exists(select 1 from public.koki_records b where b.kind='boutiques' and b.parent_id=p.id) then return;end if;
 insert into public.koki_records(kind,statut,owner_id,parent_id,payload)
 values('boutiques','Actif',p.owner_id,p.id,jsonb_strip_nulls(jsonb_build_object(
 'nom',p.payload->>'nom','categorie',p.payload->>'categorie','adresse',p.payload->>'adresse',
 'village',p.payload->>'village','description',p.payload->>'description','horaires',p.payload->>'horaires',
 'whatsapp',p.payload->>'whatsapp','photos',coalesce(p.payload->'photos','[]'::jsonb),
 'image_path',p.payload->>'image_path','localisation',p.payload->'localisation','initial_shop',true)));
end $$;
revoke all on function koki_private.ensure_initial_shop(public.koki_records) from public,anon,authenticated;
create or replace function koki_private.initial_shop_after_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin perform koki_private.ensure_initial_shop(new);return new;end $$;
revoke all on function koki_private.initial_shop_after_profile() from public,anon,authenticated;
create trigger initial_shop_after_profile after insert or update on public.koki_records
for each row when (new.kind='professionnels') execute function koki_private.initial_shop_after_profile();
-- Préparation des offres avant validation, sans modifier les contrôles de publication, de commande ou de propriété.
do $patch$
declare definition text;old_guard text;new_guard text;
begin
 definition:=pg_get_functiondef('koki_private.commerce_business(text,jsonb)'::regprocedure);
 old_guard:='p.kind<>''professionnels'' or p.statut<>''Actif''';
 new_guard:='p.kind<>''professionnels'' or p.statut not in (''Actif'',''En attente'',''À valider'')';
 if position(old_guard in definition)=0 then old_guard:='p.kind<>''professionnels'' or p.statut not in (''En attente'',''Actif'')';end if;
 if position(old_guard in definition)=0 then raise exception 'Garde profil inattendue';end if;
 definition:=replace(definition,old_guard,new_guard);
 old_guard:='p.kind<>''boutiques'' or p.statut<>''Actif'' or d.statut<>''Actif''';
 new_guard:='p.kind<>''boutiques'' or p.statut not in (''Actif'',''À valider'') or d.id is null or d.owner_id is distinct from actor or d.statut not in (''Actif'',''En attente'',''À valider'')';
 if position(old_guard in definition)=0 then raise exception 'Garde produit inattendue';end if;
 definition:=replace(definition,old_guard,new_guard);
 execute definition;
end $patch$;
-- Reprise des comptes existants sans boutique, sans doublon ni changement des boutiques existantes.
select koki_private.ensure_initial_shop(p) from public.koki_records p where p.kind='professionnels';
