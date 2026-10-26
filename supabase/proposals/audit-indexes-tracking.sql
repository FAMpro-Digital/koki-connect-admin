-- Index des clés étrangères utilisées pour les suppressions et les jointures.
create index if not exists audit_ride_quotes_category on koki_private.ride_quotes(category);
create index if not exists audit_ride_quotes_client on koki_private.ride_quotes(client_id);
create index if not exists audit_ride_quotes_ride on koki_private.ride_quotes(ride_id);
create index if not exists audit_ride_ratings_client on koki_private.ride_ratings(client_id);
create index if not exists audit_ride_reports_reporter on koki_private.ride_reports(reporter_id);
create index if not exists audit_ride_reports_ride on koki_private.ride_reports(ride_id);
create index if not exists audit_ride_reports_moderator on koki_private.ride_reports(traite_par);
create index if not exists audit_social_likes_user on koki_social_private.likes(user_id);
create index if not exists audit_notifications_record on public.koki_notifications(record_id);
create index if not exists audit_push_user on public.koki_push_subscriptions(user_id);
alter table koki_private.nearby_lookups add column id bigint generated always as identity primary key;
-- Compteurs indicatifs : une action par compte/cible/type/jour. Aucun suivi anonyme ni IP.
create table koki_private.activity_dedup(actor_id uuid not null references auth.users(id) on delete cascade,target_id uuid not null references public.koki_records(id) on delete cascade,kind text not null,day date not null,primary key(actor_id,target_id,kind,day));
create index on koki_private.activity_dedup(target_id);
alter table koki_private.activity_dedup enable row level security;
revoke all on koki_private.activity_dedup from public,anon,authenticated;
create function koki_private.track(p_target uuid,p_kind text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and not coalesce(is_anonymous,false)) then return;end if;
 if p_target is null or p_kind is null or p_kind not in ('vue','appel','whatsapp','commander','partage','panier','devis') or not koki_private.is_public_listing(p_target) then return;end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,916));
 delete from koki_private.activity_dedup where actor_id=uid and day<current_date;
 if (select count(*) from koki_private.activity_dedup where actor_id=uid and day=current_date)>=200 then return;end if;
 insert into koki_private.activity_dedup values(uid,p_target,p_kind,current_date) on conflict do nothing;
 if not found then return;end if;
 insert into public.koki_activity(target_id,kind,day,n) values(p_target,p_kind,current_date,1) on conflict(target_id,kind,day) do update set n=least(public.koki_activity.n+1,1000000);
end $$;
revoke all on function koki_private.track(uuid,text) from public;
grant execute on function koki_private.track(uuid,text) to anon,authenticated;
create or replace function public.koki_track(p_target uuid,p_kind text) returns void language sql security invoker set search_path='' as $$select koki_private.track(p_target,p_kind)$$;
