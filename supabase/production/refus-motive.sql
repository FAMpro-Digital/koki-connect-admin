-- PRODUCTION : à lancer UNIQUEMENT après autorisation de Mourtada (éditeur SQL Supabase, une seule fois).
-- Refus motivé obligatoire côté serveur (Commerces & Services).
-- Jusqu'ici, seul l'écran d'administration exigeait un motif ; le serveur acceptait un refus sans motif.
-- Ce garde-fou refuse toute décision « reject » / « reject_changes » sans motif d'au moins 3 caractères.
-- Aucune donnée existante n'est modifiée. Réversible : drop trigger koki_refus_motive on public.koki_records;
create or replace function koki_private.refus_motive() returns trigger language plpgsql set search_path='' as $$
begin
 if new.kind in ('professionnels','boutiques','produits','services')
  and new.payload->'moderation' is distinct from old.payload->'moderation'
  and new.payload->'moderation'->>'decision' in ('reject','reject_changes')
  and length(btrim(coalesce(new.payload->'moderation'->>'note','')))<3
 then raise exception 'Motif de refus obligatoire (3 caractères minimum), visible par le professionnel';end if;
 return new;
end $$;
revoke all on function koki_private.refus_motive() from public,anon,authenticated;
drop trigger if exists koki_refus_motive on public.koki_records;
create trigger koki_refus_motive before update on public.koki_records for each row execute function koki_private.refus_motive();
