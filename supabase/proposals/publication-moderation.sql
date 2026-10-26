-- Quota indépendant de la suppression et modération privée.
alter table koki_social_private.comments add column hidden boolean not null default false;
create table koki_social_private.comment_events(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create index on koki_social_private.comment_events(user_id,created_at);
insert into koki_social_private.comment_events(user_id,created_at) select user_id,created_at from koki_social_private.comments where created_at>now()-interval '1 day';
create table koki_social_private.reports(id uuid primary key default gen_random_uuid(),comment_id uuid not null references koki_social_private.comments(id) on delete cascade,reporter_id uuid not null references auth.users(id) on delete cascade,reason text not null check(char_length(reason) between 3 and 500),created_at timestamptz not null default now(),resolved boolean not null default false,unique(comment_id,reporter_id));
create index on koki_social_private.reports(reporter_id,created_at);
create table koki_social_private.moderation_log(id bigint generated always as identity primary key,comment_id uuid,actor uuid,hidden boolean not null,reason text not null,created_at timestamptz not null default now());
alter table koki_social_private.comment_events enable row level security;
alter table koki_social_private.reports enable row level security;
alter table koki_social_private.moderation_log enable row level security;
revoke all on all tables in schema koki_social_private from public,anon,authenticated;
CREATE OR REPLACE FUNCTION koki_social_private.interact(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if p_action is null or p_action not in ('read','like','comment','delete','report') then raise exception 'Action invalide'; end if;
 if p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'Page invalide'; end if;
 if not exists(select 1 from public.koki_contents where id=p_content and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))) then raise exception 'Publication indisponible'; end if;
 if p_action<>'read' then
  if uid is null or not exists(select 1 from auth.users where id=uid and not coalesce(is_anonymous,false)) then raise exception 'Connectez-vous pour participer' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,372));
 end if;
 if p_action='like' then
  if p_liked is null then raise exception 'Choix invalide'; end if;
  if p_liked then insert into koki_social_private.likes values(p_content,uid) on conflict do nothing;
  else delete from koki_social_private.likes where content_id=p_content and user_id=uid; end if;
 elsif p_action='comment' then
  if p_text is null or char_length(trim(p_text)) not between 1 and 2000 then raise exception 'Commentaire requis (2 000 caractères maximum)'; end if;
  if (select count(*) from koki_social_private.comment_events where user_id=uid and created_at>now()-interval '1 minute')>=5 or (select count(*) from koki_social_private.comment_events where user_id=uid and created_at>now()-interval '1 day')>=30 then raise exception 'Trop de commentaires. Réessayez plus tard.'; end if;
  delete from koki_social_private.comment_events where user_id=uid and created_at<now()-interval '1 day';
  insert into koki_social_private.comment_events(user_id) values(uid);
  insert into koki_social_private.comments(content_id,user_id,body) values(p_content,uid,trim(p_text));
 elsif p_action='report' then
  if not exists(select 1 from koki_social_private.comments where id=p_comment and content_id=p_content and not hidden) then raise exception 'Commentaire indisponible';end if;
  if p_text is null or char_length(trim(p_text)) not between 3 and 500 then raise exception 'Motif requis';end if;
  if (select count(*) from koki_social_private.reports where reporter_id=uid and created_at>now()-interval '1 day')>=20 then raise exception 'Trop de signalements';end if;
  insert into koki_social_private.reports(comment_id,reporter_id,reason) values(p_comment,uid,trim(p_text)) on conflict(comment_id,reporter_id) do nothing;
 elsif p_action='delete' then
  delete from koki_social_private.comments where id=p_comment and content_id=p_content and user_id=uid;
 end if;
 select jsonb_build_object('likes',(select count(*) from koki_social_private.likes where content_id=p_content),
 'liked',exists(select 1 from koki_social_private.likes where content_id=p_content and user_id=uid),
 'total',(select count(*) from koki_social_private.comments where not hidden and content_id=p_content),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'created_at',c.created_at,'mine',coalesce(c.user_id=uid,false)) order by c.created_at desc,c.id) from (select * from koki_social_private.comments where not hidden and content_id=p_content order by created_at desc,id limit 30 offset p_offset)c),'[]'::jsonb)) into result;
 return result;
end $function$
;

create function koki_social_private.moderate(p_comment uuid,p_hidden boolean,p_reason text,p_offset integer) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(koki_private.allowed('content'),false) then raise exception 'Accès refusé' using errcode='42501';end if;
 if p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'Page invalide';end if;
 if p_comment is not null then
  if p_hidden is null or p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'Motif requis (3 à 500 caractères)';end if;
  update koki_social_private.comments set hidden=p_hidden where id=p_comment;
  if not found then raise exception 'Commentaire indisponible';end if;
  insert into koki_social_private.moderation_log(comment_id,actor,hidden,reason) values(p_comment,auth.uid(),p_hidden,trim(p_reason));
  update koki_social_private.reports set resolved=true where comment_id=p_comment;
 end if;
 return coalesce((select jsonb_agg(to_jsonb(c)) from (select c.id,c.content_id,c.body,c.created_at,c.hidden,(select count(*) from koki_social_private.reports r where r.comment_id=c.id and not r.resolved) as reports,(select jsonb_agg(r.reason) from koki_social_private.reports r where r.comment_id=c.id and not r.resolved) as reasons from koki_social_private.comments c order by reports desc,c.created_at desc,c.id limit 50 offset p_offset)c),'[]'::jsonb);
end $$;
revoke all on function koki_social_private.moderate(uuid,boolean,text,integer) from public,anon;
grant execute on function koki_social_private.moderate(uuid,boolean,text,integer) to authenticated;
create function public.koki_comment_moderation(p_comment uuid default null,p_hidden boolean default null,p_reason text default null,p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select koki_social_private.moderate(p_comment,p_hidden,p_reason,p_offset)$$;
revoke all on function public.koki_comment_moderation(uuid,boolean,text,integer) from public,anon;
grant execute on function public.koki_comment_moderation(uuid,boolean,text,integer) to authenticated;
-- Résumé des compteurs par lot, sans charger les commentaires.
create function koki_social_private.summaries(p_ids uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if coalesce(cardinality(p_ids),0)>50 then raise exception 'Lot trop grand';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'likes',(select count(*) from koki_social_private.likes l where l.content_id=c.id),'liked',exists(select 1 from koki_social_private.likes l where l.content_id=c.id and l.user_id=auth.uid()))) from public.koki_contents c where c.id=any(p_ids) and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))),'[]'::jsonb);
end $$;
revoke all on function koki_social_private.summaries(uuid[]) from public;
grant execute on function koki_social_private.summaries(uuid[]) to anon,authenticated;
create function public.koki_social_summaries(p_ids uuid[]) returns jsonb language sql security invoker set search_path='' as $$select koki_social_private.summaries(p_ids)$$;
revoke all on function public.koki_social_summaries(uuid[]) from public;
grant execute on function public.koki_social_summaries(uuid[]) to anon,authenticated;
