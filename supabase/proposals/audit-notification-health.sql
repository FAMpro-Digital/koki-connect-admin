-- Aucun renvoi automatique des envois dont le résultat est incertain.
alter table public.koki_notification_deliveries add column processing_started_at timestamptz,add column failure_code text;
update public.koki_notification_deliveries set processing_started_at=now() where state='processing';
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
  where n.created_at>now()-interval '1 day' and p.sms and p.updated_at<=n.created_at and u.phone_confirmed_at is not null and u.phone is not null
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
end $function$
;

create function koki_private.notification_health() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(koki_private.allowed('audit'),false) then raise exception 'Accès refusé' using errcode='42501';end if;
 return jsonb_build_object('counts',(select coalesce(jsonb_object_agg(state,n),'{}'::jsonb) from (select state,count(*) as n from public.koki_notification_deliveries where created_at>now()-interval '7 days' group by state)x),'oldest_pending',(select min(created_at) from public.koki_notification_deliveries where state='pending'),'recent',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select id,channel,state,created_at,completed_at,failure_code from public.koki_notification_deliveries order by created_at desc limit 50)x));
end $$;
revoke all on function koki_private.notification_health() from public,anon;
grant execute on function koki_private.notification_health() to authenticated;
create function public.koki_notification_health() returns jsonb language sql security invoker set search_path='' as $$select koki_private.notification_health()$$;
revoke all on function public.koki_notification_health() from public,anon;
grant execute on function public.koki_notification_health() to authenticated;
