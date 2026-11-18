-- Signaler une fiche (produit, service, boutique, professionnel) — Apple, règle 1.2 (contenus publiés par les utilisateurs).
-- À appliquer en production uniquement avec accord. Ne modifie aucune table ni fonction existante.
--  1. koki_private.record_reports : un signalement par fiche et par compte (un nouveau signalement remplace l'ancien
--     et le repasse « Nouveau »). Effacé avec la fiche ou avec le compte qui l'a envoyé. Aucun accès direct.
--  2. public.koki_record_report : envoi par un compte permanent connecté, sur une fiche publique qui n'est pas la sienne,
--     20 signalements par jour au plus.
--  3. public.koki_record_reports_admin : liste (100 plus récents) et traitement Nouveau / En cours / Traité, réservés
--     au droit Commerce avec double authentification, chaque changement inscrit au journal des opérations.
-- Retour arrière : en fin de fichier.

create table koki_private.record_reports(
  id uuid primary key default gen_random_uuid(),
  record_id uuid not null references public.koki_records(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  motif text not null check (motif in ('Arnaque ou fraude','Contenu choquant','Produit interdit','Fausses informations','Autre')),
  details text check (details is null or char_length(details) between 3 and 500),
  statut text not null default 'Nouveau' check (statut in ('Nouveau','En cours','Traité')),
  note_admin text check (note_admin is null or char_length(note_admin) between 3 and 500),
  traite_le timestamptz,
  traite_par uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (record_id, reporter_id)
);
create index record_reports_recents on koki_private.record_reports(created_at desc);
create index record_reports_auteur on koki_private.record_reports(reporter_id, created_at);
alter table koki_private.record_reports enable row level security;
revoke all on koki_private.record_reports from public, anon, authenticated;

create function public.koki_record_report(p_target uuid, p_motif text, p_details text default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare actor uuid := (select auth.uid()); texte text := nullif(btrim(coalesce(p_details,'')),''); proprio uuid;
begin
  if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
    raise exception 'Connectez-vous avec votre compte pour signaler une fiche.' using errcode='42501'; end if;
  if p_motif is null or p_motif not in ('Arnaque ou fraude','Contenu choquant','Produit interdit','Fausses informations','Autre') then
    raise exception 'Choisissez un motif.'; end if;
  if texte is not null and char_length(texte) not between 3 and 500 then raise exception 'Le détail doit contenir de 3 à 500 caractères.'; end if;
  if p_motif = 'Autre' and texte is null then raise exception 'Précisez le problème.'; end if;
  if p_target is null or not koki_private.is_public_listing(p_target) then raise exception 'Cette fiche n''est plus disponible.'; end if;
  select owner_id into proprio from public.koki_records where id = p_target;
  if proprio = actor then raise exception 'Vous ne pouvez pas signaler votre propre fiche.'; end if;
  if (select count(*) from koki_private.record_reports where reporter_id = actor and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Trop de signalements aujourd''hui. Réessayez demain.'; end if;
  insert into koki_private.record_reports(record_id, reporter_id, motif, details) values (p_target, actor, p_motif, texte)
    on conflict (record_id, reporter_id) do update set motif = excluded.motif, details = excluded.details, statut = 'Nouveau', created_at = now();
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.koki_record_report(uuid, text, text) from public, anon;
grant execute on function public.koki_record_report(uuid, text, text) to authenticated;

create function public.koki_record_reports_admin(p_action text, p_id uuid default null, p_statut text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare actor uuid := (select auth.uid()); x koki_private.record_reports; note text := nullif(btrim(coalesce(p_note,'')),''); avant text;
begin
  if actor is null or not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501'; end if;
  if p_action = 'liste' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'record_id',r.record_id,'motif',r.motif,'details',r.details,'statut',r.statut,
        'note_admin',r.note_admin,'traite_le',r.traite_le,'created_at',r.created_at,'fiche',coalesce(k.payload->>'nom',k.payload->>'titre','Fiche'),
        'kind',k.kind,'fiche_statut',k.statut,'total',(select count(*) from koki_private.record_reports t where t.record_id=r.record_id)) order by r.created_at desc)
      from (select * from koki_private.record_reports order by created_at desc limit 100) r join public.koki_records k on k.id = r.record_id), '[]'::jsonb);
  end if;
  if p_action <> 'statut' then raise exception 'Action inconnue'; end if;
  if p_statut is null or p_statut not in ('Nouveau','En cours','Traité') then raise exception 'Statut de signalement invalide'; end if;
  if note is not null and char_length(note) not between 3 and 500 then raise exception 'Note de 3 à 500 caractères'; end if;
  if p_statut = 'Traité' and note is null then raise exception 'Indiquez ce qui a été fait (note obligatoire pour « Traité »)'; end if;
  select * into x from koki_private.record_reports where id = p_id for update;
  if x.id is null then raise exception 'Signalement introuvable'; end if;
  avant := x.statut;
  update koki_private.record_reports set statut = p_statut, note_admin = coalesce(note, note_admin), traite_le = now(), traite_par = actor
    where id = x.id returning * into x;
  insert into public.koki_audit(actor_id, operation, table_name, record_id, details)
    values (actor, 'SIGNALEMENT', 'record_reports', x.id, jsonb_strip_nulls(jsonb_build_object('avant',avant,'apres',x.statut,'note',note,'fiche',x.record_id)));
  return jsonb_build_object('id',x.id,'statut',x.statut,'note_admin',x.note_admin,'traite_le',x.traite_le);
end $$;
revoke all on function public.koki_record_reports_admin(text, uuid, text, text) from public, anon;
grant execute on function public.koki_record_reports_admin(text, uuid, text, text) to authenticated;

-- Retour arrière :
-- drop function public.koki_record_reports_admin(text, uuid, text, text);
-- drop function public.koki_record_report(uuid, text, text);
-- drop table koki_private.record_reports;
