-- Espace Clubs & Académies — 4 : notifications (décision D2).
-- EN ATTENTE : non appliquée en production.
--  * public.koki_notifications : colonne facultative sport_ref (→ koki_sport.clubs) et contrainte « une seule cible »
--    élargie à trois cibles. Les applications lisent id/title/body/created_at/read_at : inchangées.
--  * public.koki_notification_claim : SEULE modification d'une fonction existante — les notifications du module
--    partent en push uniquement (jamais en SMS payant). Le retour arrière restaure la définition d'origine.
--  * Déclencheurs du module : membres (validation, refus, suspension, nouveau membre, masquage),
--    administrateurs (académie à valider, signalement), abonnés (actualité, match programmé ou reporté, résultat).

begin;

do $$ begin
 if to_regclass('koki_sport.clubs') is null then raise exception 'GARDE : migrations koki_sport 1 à 3 absentes'; end if;
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name='koki_notifications' and column_name='sport_ref') then
  raise exception 'GARDE : déjà appliquée'; end if;
 if (select md5(pg_get_functiondef('public.koki_notification_claim(boolean,boolean)'::regprocedure)))<>'f1574a357b3e29240317d16960129245' then
  raise exception 'GARDE : koki_notification_claim a changé depuis la référence'; end if;
 if (select pg_get_constraintdef(oid) from pg_constraint where conname='koki_notifications_cible' and conrelid='public.koki_notifications'::regclass)
    <>'CHECK (((record_id IS NULL) <> (content_id IS NULL)))' then raise exception 'GARDE : contrainte koki_notifications_cible inattendue'; end if;
end $$;

alter table public.koki_notifications add column sport_ref uuid references koki_sport.clubs(id) on delete cascade;
alter table public.koki_notifications drop constraint koki_notifications_cible;
alter table public.koki_notifications add constraint koki_notifications_cible check (num_nonnulls(record_id,content_id,sport_ref)=1);
create index koki_notifications_sport on public.koki_notifications(sport_ref,category,created_at) where sport_ref is not null;

CREATE OR REPLACE FUNCTION public.koki_notification_claim(p_push boolean, p_sms boolean)
 RETURNS SETOF koki_notification_deliveries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 -- Une invocation globale à la fois, y compris le calcul du plafond SMS.
 perform pg_advisory_xact_lock(hashtextextended('koki_notification_claim',0));
 update public.koki_notification_deliveries set state='failed',failure_code='delivery_unknown',completed_at=now() where state='processing' and processing_started_at<now()-interval '10 minutes';
 update public.koki_notification_deliveries set state='skipped',failure_code='expired',completed_at=now() where state='pending' and created_at<=now()-interval '1 day';
 if p_push then
  insert into public.koki_notification_deliveries(notification_id,channel,destination)
  select n.id,'push',s.id::text from public.koki_notifications n join public.koki_push_subscriptions s on s.user_id=n.recipient_id
  where n.created_at>now()-interval '1 day' and s.created_at<=n.created_at
  on conflict do nothing;
 end if;
 if p_sms then
  insert into public.koki_notification_deliveries(notification_id,channel,destination)
  select n.id,'sms',n.recipient_id::text from public.koki_notifications n join public.koki_notification_preferences p on p.user_id=n.recipient_id
  join auth.users u on u.id=n.recipient_id
  where n.created_at>now()-interval '1 day' and n.content_id is null and n.sport_ref is null and p.sms and p.updated_at<=n.created_at and u.phone_confirmed_at is not null and u.phone is not null
  on conflict do nothing;
 end if;
 -- Maximum 5 SMS/jour/compte. Les erreurs et résultats incertains comptent dans ce plafond.
 update public.koki_notification_deliveries d set state='skipped',completed_at=now()
 where d.id in (select id from (select id,row_number() over(partition by destination order by created_at,id) rank
 from public.koki_notification_deliveries where channel='sms' and created_at>=date_trunc('day',now())) x where rank>5) and d.state='pending';
 return query with batch as (
  select id from public.koki_notification_deliveries where state='pending' and created_at>now()-interval '1 day'
   and ((channel='push' and p_push) or (channel='sms' and p_sms)) order by created_at limit 20 for update skip locked
 ) update public.koki_notification_deliveries d set state='processing',processing_started_at=now() from batch where d.id=batch.id returning d.*;
end $function$;

-- ───── Envoi interne ─────
create function koki_sport.notify(p_club uuid, p_recipients uuid[], p_title text, p_body text, p_category text) returns void
language sql security definer set search_path='' as $$
 insert into public.koki_notifications(recipient_id,sport_ref,revision,title,body,category)
 select distinct u,p_club,1,left(p_title,120),left(p_body,300),p_category from unnest(p_recipients) u where u is not null
$$;
create function koki_sport.members_of(p_club uuid, p_roles text[] default array['responsable','entraineur','communication']) returns uuid[]
language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(user_id),'{}') from koki_sport.club_members where club_id=p_club and statut='actif' and role=any(p_roles)
$$;
create function koki_sport.admins_for(p_roles text[]) returns uuid[] language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(user_id),'{}') from public.koki_admin_members where enabled and role=any(p_roles)
$$;
-- Abonnés, avec anti-saturation : au plus 3 envois « abonnés » par académie et par heure.
create function koki_sport.notify_followers(p_club uuid, p_title text, p_body text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if (select statut from koki_sport.clubs where id=p_club)<>'Actif' then return; end if;
 if (select count(distinct body) from public.koki_notifications where sport_ref=p_club and category='sport_abonnes' and created_at>now()-interval '1 hour')>=3 then return; end if;
 perform koki_sport.notify(p_club,(select coalesce(array_agg(user_id),'{}') from koki_sport.follows where club_id=p_club and notifications),p_title,p_body,'sport_abonnes');
end $$;

create function koki_sport.on_club() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  if new.statut='À valider' then perform koki_sport.notify(new.id,koki_sport.admins_for(array['superadmin','manager']),'Académie à valider','« '||new.nom||' » attend une validation.','sport_admin'); end if;
  return new;
 end if;
 if new.statut is not distinct from old.statut then return new; end if;
 perform koki_sport.notify(new.id,koki_sport.members_of(new.id),new.nom,
  case new.statut when 'Actif' then case when old.statut='Suspendu' then 'Votre académie est de nouveau active.' else 'Votre académie est validée : elle est visible dans Koki Connect.' end
   when 'Refusé' then 'Demande refusée : '||coalesce(new.motif,'')
   when 'Suspendu' then 'Académie suspendue : '||coalesce(new.motif,'')
   when 'Archivé' then 'Académie archivée.' else 'Statut : '||new.statut end,'sport_membres');
 return new;
end $$;
create trigger clubs_notify after insert or update of statut on koki_sport.clubs for each row execute function koki_sport.on_club();

create function koki_sport.on_member() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' or (old.statut='retiré' and new.statut='actif') then
  perform koki_sport.notify(new.club_id,array(select x from unnest(koki_sport.members_of(new.club_id,array['responsable'])) x where x<>new.user_id),
   (select nom from koki_sport.clubs where id=new.club_id),'Nouveau membre : '||case new.role when 'responsable' then 'responsable' when 'entraineur' then 'entraîneur' else 'communication' end||'.','sport_membres');
 end if;
 return new;
end $$;
create trigger club_members_notify after insert or update of statut on koki_sport.club_members for each row execute function koki_sport.on_member();

create function koki_sport.on_post() returns trigger language plpgsql security definer set search_path='' as $$
declare club text:=(select nom from koki_sport.clubs where id=new.club_id);
begin
 if new.statut='publié' and old.statut<>'publié' and new.publication<=now()+interval '5 minutes' then
  perform koki_sport.notify_followers(new.club_id,club,'Nouvelle publication : '||new.titre);
 elsif new.statut='masqué' and old.statut<>'masqué' then
  perform koki_sport.notify(new.club_id,koki_sport.members_of(new.club_id,array['responsable','communication']),club,
   'Publication masquée par la modération : « '||new.titre||' ». Motif : '||coalesce(new.motif,''),'sport_membres');
 end if;
 return new;
end $$;
create trigger posts_notify after update of statut on koki_sport.posts for each row execute function koki_sport.on_post();

create function koki_sport.on_match() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb:=koki_sport.match_json(new); club text:=(select nom from koki_sport.clubs where id=new.club_id);
begin
 if new.statut='Terminé' and (tg_op='INSERT' or old.statut<>'Terminé') then
  perform koki_sport.notify_followers(new.club_id,club,'Résultat ('||(j->>'categorie')||') : '||(j->>'domicile')||' '||new.score_home||' – '||new.score_away||' '||(j->>'exterieur'));
 elsif tg_op='INSERT' and new.statut='À venir' and new.date_match>now() then
  perform koki_sport.notify_followers(new.club_id,club,'Match programmé ('||(j->>'categorie')||') : '||(j->>'domicile')||' – '||(j->>'exterieur')||', '||to_char(new.date_match at time zone 'Africa/Dakar','DD/MM à HH24"h"MI'));
 elsif tg_op='UPDATE' and new.statut='Reporté' and old.statut<>'Reporté' then
  perform koki_sport.notify_followers(new.club_id,club,'Match reporté ('||(j->>'categorie')||') : '||(j->>'domicile')||' – '||(j->>'exterieur'));
 end if;
 return new;
end $$;
create trigger matches_notify after insert or update of statut on koki_sport.matches for each row execute function koki_sport.on_match();

create function koki_sport.on_report() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform koki_sport.notify(new.club_id,koki_sport.admins_for(array['superadmin','editor']),'Signalement Clubs & Académies',
  new.motif||' · '||(select nom from koki_sport.clubs where id=new.club_id),'sport_admin');
 return new;
end $$;
create trigger reports_notify after insert on koki_sport.reports for each row execute function koki_sport.on_report();

revoke all on function koki_sport.notify(uuid,uuid[],text,text,text), koki_sport.members_of(uuid,text[]), koki_sport.admins_for(text[]),
 koki_sport.notify_followers(uuid,text,text), koki_sport.on_club(), koki_sport.on_member(), koki_sport.on_post(), koki_sport.on_match(), koki_sport.on_report()
 from public, anon, authenticated;

commit;
