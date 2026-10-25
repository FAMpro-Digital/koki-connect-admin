-- Notifications transactionnelles. Additif : aucun envoi historique ni changement des parcours existants.
begin;
create table public.koki_notifications (
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id) on delete cascade,
 record_id uuid not null references public.koki_records(id) on delete cascade,
 revision bigint not null, title text not null, body text not null, category text not null,
 created_at timestamptz not null default now(), read_at timestamptz,
 unique(recipient_id,record_id,revision)
);
create index koki_notifications_inbox on public.koki_notifications(recipient_id,created_at desc);
alter table public.koki_notifications enable row level security;
revoke all on public.koki_notifications from public,anon,authenticated;
grant select,update(read_at) on public.koki_notifications to authenticated;
create policy notifications_read on public.koki_notifications for select to authenticated using(recipient_id=(select auth.uid()));
create policy notifications_seen on public.koki_notifications for update to authenticated using(recipient_id=(select auth.uid())) with check(recipient_id=(select auth.uid()));
create table public.koki_notification_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 sms boolean not null default false, updated_at timestamptz not null default now()
);
alter table public.koki_notification_preferences enable row level security;
revoke all on public.koki_notification_preferences from public,anon,authenticated;
grant select,insert,update on public.koki_notification_preferences to authenticated;
create policy notification_preferences_own on public.koki_notification_preferences for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false));
create table public.koki_push_subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text unique not null check(length(endpoint)<2048), p256dh text not null, auth text not null,
 created_at timestamptz not null default now(),
 check(endpoint ~ '^https://(fcm.googleapis.com|updates.push.services.mozilla.com|web.push.apple.com)/[^[:space:]]+$'),
 check(p256dh ~ '^[A-Za-z0-9_-]{87}=?$'), check(auth ~ '^[A-Za-z0-9_-]{22}={0,2}$')
);
alter table public.koki_push_subscriptions enable row level security;
revoke all on public.koki_push_subscriptions from public,anon,authenticated;
grant select,delete on public.koki_push_subscriptions to authenticated;
create policy push_own on public.koki_push_subscriptions for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create function public.koki_push_register(p_endpoint text,p_p256dh text,p_auth text) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Connexion requise' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 if exists(select 1 from public.koki_push_subscriptions where endpoint=p_endpoint and user_id<>actor) then raise exception 'Désactivez puis réactivez les notifications sur cet appareil.';end if;
 if (select count(*) from public.koki_push_subscriptions where user_id=actor)>=5 and not exists(select 1 from public.koki_push_subscriptions where endpoint=p_endpoint and user_id=actor) then raise exception 'Cinq appareils maximum.';end if;
 insert into public.koki_push_subscriptions(user_id,endpoint,p256dh,auth) values(actor,p_endpoint,p_p256dh,p_auth)
 on conflict(endpoint) do update set p256dh=excluded.p256dh,auth=excluded.auth where koki_push_subscriptions.user_id=actor;
end $$;
revoke all on function public.koki_push_register(text,text,text) from public,anon;
grant execute on function public.koki_push_register(text,text,text) to authenticated;

-- Destinataires dérivés exclusivement des données métier, jamais d'un numéro fourni par l'appelant.
create function koki_private.notify_record() returns trigger language plpgsql security definer set search_path='' as $$
declare recipients uuid[]:='{}'; target uuid; label text; text_body text; admin_permission text;
begin
 if tg_op='UPDATE' then
  if new.statut is not distinct from old.statut and new.driver_id is not distinct from old.driver_id then return new;end if;
 end if;
 if new.kind in ('commandes','courses','demandes_services') then
  recipients:=array_append(recipients,new.client_id);
  select owner_id into target from public.koki_records where id=case when new.kind='courses' then new.driver_id else new.provider_id end;
  recipients:=array_append(recipients,target);
  label:=case new.kind when 'courses' then 'Votre course' when 'commandes' then 'Votre commande' else 'Votre demande de service' end;
  text_body:=new.statut||' · Référence '||left(new.id::text,8);
 elsif new.kind in ('professionnels','chauffeurs','boutiques','produits','services','vehicules') then
  recipients:=array_append(recipients,new.owner_id);
  label:='Suivi de votre activité';text_body:=new.statut||' · Consultez votre espace professionnel.';
  if new.statut='À valider' then
   admin_permission:=case when new.kind in ('chauffeurs','vehicules') then 'transport' else 'commerce' end;
   recipients:=recipients||coalesce((select array_agg(user_id) from public.koki_admin_members where enabled and role in ('superadmin','manager')),'{}'::uuid[]);
   label:='Dossier à valider';text_body:='Un dossier professionnel attend une validation.';
  end if;
 else return new;
 end if;
 insert into public.koki_notifications(recipient_id,record_id,revision,title,body,category)
 select distinct u,new.id,new.revision,label,text_body,new.kind from unnest(recipients) u where u is not null
 on conflict(recipient_id,record_id,revision) do nothing;
 return new;
end $$;
revoke all on function koki_private.notify_record() from public,anon,authenticated;
create trigger koki_notify_record after insert or update on public.koki_records for each row execute function koki_private.notify_record();

-- File serveur : aucun accès utilisateur. Une livraison réservée n'est jamais renvoyée automatiquement
-- après une interruption : cela évite les doubles SMS facturés en cas de résultat réseau incertain.
create table public.koki_notification_deliveries (
 id uuid primary key default gen_random_uuid(), notification_id uuid not null references public.koki_notifications(id) on delete cascade,
 channel text not null check(channel in ('push','sms')), destination text not null,
 state text not null default 'pending' check(state in ('pending','processing','sent','failed','skipped')),
 created_at timestamptz not null default now(), completed_at timestamptz, provider_id text,
 unique(notification_id,channel,destination)
);
alter table public.koki_notification_deliveries enable row level security;
revoke all on public.koki_notification_deliveries from public,anon,authenticated;
grant all on public.koki_notifications,public.koki_notification_deliveries,public.koki_push_subscriptions,public.koki_notification_preferences to service_role;
create function public.koki_notification_claim(p_push boolean,p_sms boolean) returns setof public.koki_notification_deliveries language plpgsql security definer set search_path='' as $$
begin
 -- Une invocation globale à la fois, y compris le calcul du plafond SMS.
 perform pg_advisory_xact_lock(hashtextextended('koki_notification_claim',0));
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
 ) update public.koki_notification_deliveries d set state='processing' from batch where d.id=batch.id returning d.*;
end $$;
revoke all on function public.koki_notification_claim(boolean,boolean) from public,anon,authenticated;
grant execute on function public.koki_notification_claim(boolean,boolean) to service_role;
commit;
