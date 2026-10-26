-- Installation additive des interactions ; tables privées, aucun identifiant de compte exposé.
create schema if not exists koki_social_private;
revoke all on schema koki_social_private from public;
grant usage on schema koki_social_private to anon, authenticated;
create table koki_social_private.likes (
 content_id uuid not null references public.koki_contents(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 primary key(content_id,user_id)
);
create table koki_social_private.comments (
 id uuid primary key default gen_random_uuid(),
 content_id uuid not null references public.koki_contents(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default now()
);
create index on koki_social_private.comments(content_id,created_at desc,id);
create index on koki_social_private.comments(user_id,created_at desc);
alter table koki_social_private.likes enable row level security;
alter table koki_social_private.comments enable row level security;
revoke all on all tables in schema koki_social_private from public,anon,authenticated;
create function koki_social_private.interact(p_content uuid,p_action text,p_text text,p_comment uuid,p_liked boolean,p_offset integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if p_action is null or p_action not in ('read','like','comment','delete') then raise exception 'Action invalide'; end if;
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
  if (select count(*) from koki_social_private.comments where user_id=uid and created_at>now()-interval '1 minute')>=5 or (select count(*) from koki_social_private.comments where user_id=uid and created_at>now()-interval '1 day')>=30 then raise exception 'Trop de commentaires. Réessayez plus tard.'; end if;
  insert into koki_social_private.comments(content_id,user_id,body) values(p_content,uid,trim(p_text));
 elsif p_action='delete' then
  delete from koki_social_private.comments where id=p_comment and content_id=p_content and user_id=uid;
 end if;
 select jsonb_build_object('likes',(select count(*) from koki_social_private.likes where content_id=p_content),
 'liked',exists(select 1 from koki_social_private.likes where content_id=p_content and user_id=uid),
 'total',(select count(*) from koki_social_private.comments where content_id=p_content),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'created_at',c.created_at,'mine',coalesce(c.user_id=uid,false)) order by c.created_at desc,c.id) from (select * from koki_social_private.comments where content_id=p_content order by created_at desc,id limit 30 offset p_offset)c),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function koki_social_private.interact(uuid,text,text,uuid,boolean,integer) from public;
grant execute on function koki_social_private.interact(uuid,text,text,uuid,boolean,integer) to anon,authenticated;
create function public.koki_content_social(p_content uuid,p_action text default 'read',p_text text default null,p_comment uuid default null,p_liked boolean default null,p_offset integer default 0)
returns jsonb language sql security invoker set search_path='' as $$
 select koki_social_private.interact(p_content,p_action,p_text,p_comment,p_liked,p_offset)
$$;
revoke all on function public.koki_content_social(uuid,text,text,uuid,boolean,integer) from public;
grant execute on function public.koki_content_social(uuid,text,text,uuid,boolean,integer) to anon,authenticated;
