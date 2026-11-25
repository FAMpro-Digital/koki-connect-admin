-- PROPOSITION (NON appliquée) — planification de la synchronisation API-Football selon le quota.
-- Ajout seul : une fonction de LECTURE réservée au serveur (service_role). Aucune table, aucune donnée,
-- aucune fonction existante modifiée. Les écritures restent faites par public.koki_foot_sync('importer'|'erreur').
-- Retour : retour-20261201000800_foot_planification_api.sql
begin;
do $$ begin
 if to_regprocedure('public.koki_foot_sync(text,jsonb)') is null then raise exception 'GARDE : 20261201000600 absente'; end if;
 if to_regprocedure('public.koki_foot_sync_planning(text)') is not null then raise exception 'GARDE : 20261201000800 déjà appliquée'; end if;
end $$;

create function public.koki_foot_sync_planning(p_fournisseur text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ef koki_foot.etat_fournisseurs; fin_jour timestamptz:=(date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC';
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Réservé à la synchronisation serveur' using errcode='42501'; end if;
 if p_fournisseur is null or p_fournisseur not in ('api-football','sportmonks') then raise exception 'Fournisseur invalide' using errcode='22023'; end if;
 select * into ef from koki_foot.etat_fournisseurs where fournisseur=p_fournisseur;
 return jsonb_build_object(
  'pause_jusqu_a',case when ef.pause_jusqu_a>now() then ef.pause_jusqu_a end,
  'erreurs_consecutives',coalesce(ef.erreurs_consecutives,0),
  'quota_restant',ef.quota_restant,
  'derniere_tentative',ef.derniere_tentative,
  -- Compétitions suivies : publiées et actives (même règle que koki_foot_sync('references')).
  'competitions',coalesce((select jsonb_agg(jsonb_build_object('ref',c.ref_fournisseur,'saison',c.saison) order by c.ref_fournisseur) from koki_foot.competitions c
    where c.fournisseur=p_fournisseur and c.publie and c.statut='active'),'[]'),
  'matchs_a_suivre',coalesce((select jsonb_agg(m.ref_fournisseur order by m.date_match) from koki_foot.matchs m join koki_foot.competitions c on c.id=m.competition_id
    where m.fournisseur=p_fournisseur and c.publie and c.statut='active'
      and (koki_foot.en_jeu(m.statut) or (m.statut='À venir' and m.date_match between now()-interval '3 hours' and now()+interval '15 minutes'))),'[]'),
  -- Coups d'envoi restants aujourd'hui (UTC) : répartition du quota sur les fenêtres de direct.
  'coups_d_envoi',coalesce((select jsonb_agg(m.date_match order by m.date_match) from koki_foot.matchs m join koki_foot.competitions c on c.id=m.competition_id
    where m.fournisseur=p_fournisseur and c.publie and c.statut='active' and m.statut not in ('Terminé','Reporté','Annulé')
      and m.date_match between now()-interval '150 minutes' and fin_jour),'[]'),
  'competitions_du_jour',coalesce((select jsonb_agg(distinct c.ref_fournisseur) from koki_foot.matchs m join koki_foot.competitions c on c.id=m.competition_id
    where m.fournisseur=p_fournisseur and c.publie and c.statut='active' and m.statut not in ('Terminé','Reporté','Annulé')
      and m.date_match between now()-interval '150 minutes' and fin_jour),'[]'),
  -- Dernier passage réussi (ou partiel) de chaque opération sur trois jours.
  'operations',coalesce((select jsonb_object_agg(s.operation,s.derniere) from (select operation,max(created_at) derniere from koki_foot.synchronisations
    where fournisseur=p_fournisseur and statut in ('ok','partiel') and created_at>now()-interval '3 days' group by operation) s),'{}'));
end $$;
revoke all on function public.koki_foot_sync_planning(text) from public, anon, authenticated, service_role;
grant execute on function public.koki_foot_sync_planning(text) to service_role;
commit;
