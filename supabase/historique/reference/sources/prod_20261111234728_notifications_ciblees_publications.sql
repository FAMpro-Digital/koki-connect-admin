do $p$ begin
 if to_regclass('public.koki_user_interests') is not null or to_regclass('public.koki_content_notified') is not null then raise exception 'Préflight : déjà appliqué'; end if;
end $p$;
create table public.koki_user_interests(user_id uuid primary key references auth.users(id) on delete cascade, types jsonb not null default '{}'::jsonb, categories jsonb not null default '{}'::jsonb, actif boolean not null default true, updated_at timestamptz not null default now());
alter table public.koki_user_interests enable row level security;
revoke all on public.koki_user_interests from anon, authenticated;
grant select on public.koki_user_interests to authenticated;
create policy interests_self_read on public.koki_user_interests for select to authenticated using (user_id=(select auth.uid()));
create function koki_private.interests_clean(o jsonb) returns jsonb language plpgsql immutable set search_path to '' as $f$
declare k text; v jsonb; out jsonb:='{}'::jsonb; c int:=0;
begin
 if o is null or jsonb_typeof(o)<>'object' then return '{}'::jsonb;end if;
 for k,v in select key,value from jsonb_each(o) loop
  if char_length(k) between 1 and 80 and jsonb_typeof(v)='number' and (v#>>'{}')::numeric>0 then out:=out||jsonb_build_object(k,round(least((v#>>'{}')::numeric,50),2));c:=c+1;end if;
  exit when c>=60;
 end loop;
 return out;
end $f$;
create function public.koki_interests_sync(p_types jsonb, p_categories jsonb, p_actif boolean default true) returns void language plpgsql security definer set search_path to '' as $f$
declare actor uuid:=auth.uid();
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Connexion requise' using errcode='42501';end if;
 if octet_length(coalesce(p_types,'{}'::jsonb)::text)+octet_length(coalesce(p_categories,'{}'::jsonb)::text)>16000 then raise exception 'Données trop volumineuses';end if;
 insert into public.koki_user_interests(user_id,types,categories,actif,updated_at)
 values(actor,case when coalesce(p_actif,true) then koki_private.interests_clean(p_types) else '{}'::jsonb end,case when coalesce(p_actif,true) then koki_private.interests_clean(p_categories) else '{}'::jsonb end,coalesce(p_actif,true),now())
 on conflict(user_id) do update set types=excluded.types,categories=excluded.categories,actif=excluded.actif,updated_at=now();
end $f$;
revoke all on function public.koki_interests_sync(jsonb,jsonb,boolean) from public, anon;
grant execute on function public.koki_interests_sync(jsonb,jsonb,boolean) to authenticated;
revoke all on function koki_private.interests_clean(jsonb) from public, anon, authenticated;
alter table public.koki_notifications alter column record_id drop not null;
alter table public.koki_notifications add column content_id uuid references public.koki_contents(id) on delete cascade;
alter table public.koki_notifications add constraint koki_notifications_cible check ((record_id is null) <> (content_id is null));
create unique index koki_notifications_recipient_content on public.koki_notifications(recipient_id,content_id) where content_id is not null;
create table public.koki_content_notified(content_id uuid primary key references public.koki_contents(id) on delete cascade, notified_at timestamptz not null default now(), destinataires integer not null default 0);
alter table public.koki_content_notified enable row level security;
revoke all on public.koki_content_notified from anon, authenticated;
insert into public.koki_content_notified(content_id) select id from public.koki_contents where statut='publié' and publication<=now();
create function koki_private.notify_contents() returns integer language plpgsql security definer set search_path to '' as $f$
declare c record; n integer; total integer:=0;
begin
 perform pg_advisory_xact_lock(hashtextextended('koki_notify_contents',0));
 for c in select id,type,categorie,titre,resume,une from public.koki_contents x where statut='publié' and publication<=now() and publication>now()-interval '2 days' and type<>'Publicités'
  and not exists(select 1 from public.koki_content_notified d where d.content_id=x.id) order by publication limit 20 loop
  insert into public.koki_notifications(recipient_id,content_id,revision,title,body,category)
  select distinct s.user_id,c.id,0,left(c.titre,120),left(coalesce(nullif(c.resume,''),c.type),240),c.type
  from public.koki_push_subscriptions s left join public.koki_user_interests i on i.user_id=s.user_id
  where c.une or (i.actif and (coalesce((i.types->>c.type)::numeric,0)>=2 or coalesce((i.categories->>c.categorie)::numeric,0)>=2))
  on conflict do nothing;
  get diagnostics n=row_count;
  insert into public.koki_content_notified(content_id,destinataires) values(c.id,n) on conflict do nothing;
  total:=total+n;
 end loop;
 return total;
end $f$;
revoke all on function koki_private.notify_contents() from public, anon, authenticated;
do $c$
declare d text; n int;
begin
 d:=pg_get_functiondef('public.koki_notification_claim'::regproc);
 n:=(length(d)-length(replace(d,$a$where n.created_at>now()-interval '1 day' and p.sms and$a$,'')))/length($a$where n.created_at>now()-interval '1 day' and p.sms and$a$);
 if n<>1 then raise exception 'Préflight claim : % occurrence(s)',n;end if;
 execute replace(d,$a$where n.created_at>now()-interval '1 day' and p.sms and$a$,$b$where n.created_at>now()-interval '1 day' and n.content_id is null and p.sms and$b$);
end $c$;
select cron.schedule('koki-notify-contents','*/5 * * * *','select koki_private.notify_contents()');

