-- Retour arrière de 20261201000300_sport_notifications.sql
-- Les notifications du module sont supprimées (elles n'ont pas de cible valable sans la colonne sport_ref).
begin;
do $$ begin
 if exists(select 1 from public.koki_notifications where sport_ref is not null) and coalesce(current_setting('koki.retour_force',true),'')<>'oui' then
  raise exception 'RETOUR BLOQUÉ : des notifications Clubs & Académies existent. Relancez avec set koki.retour_force = ''oui'' pour les supprimer.';
 end if;
end $$;
drop trigger if exists clubs_notify on koki_sport.clubs;
drop trigger if exists club_members_notify on koki_sport.club_members;
drop trigger if exists posts_notify on koki_sport.posts;
drop trigger if exists matches_notify on koki_sport.matches;
drop trigger if exists reports_notify on koki_sport.reports;
drop function if exists koki_sport.on_club(), koki_sport.on_member(), koki_sport.on_post(), koki_sport.on_match(), koki_sport.on_report(),
 koki_sport.notify_followers(uuid,text,text), koki_sport.notify(uuid,uuid[],text,text,text), koki_sport.members_of(uuid,text[]), koki_sport.admins_for(text[]);
delete from public.koki_notifications where sport_ref is not null;
drop index if exists public.koki_notifications_sport;
alter table public.koki_notifications drop constraint koki_notifications_cible;
alter table public.koki_notifications drop column sport_ref;
alter table public.koki_notifications add constraint koki_notifications_cible check (((record_id IS NULL) <> (content_id IS NULL)));
-- Définition d'origine (référence du 18/11/2026), restaurée à l'identique :
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
  where n.created_at>now()-interval '1 day' and n.content_id is null and p.sms and p.updated_at<=n.created_at and u.phone_confirmed_at is not null and u.phone is not null
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
commit;
