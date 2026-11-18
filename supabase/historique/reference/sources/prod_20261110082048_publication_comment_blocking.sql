-- Apply after publication-moderation.sql. Private per-account comment filtering.
begin;
create table if not exists koki_social_private.blocks (
 blocker_id uuid not null references auth.users(id) on delete cascade,
 blocked_id uuid not null references auth.users(id) on delete cascade,
 primary key(blocker_id,blocked_id), check(blocker_id<>blocked_id)
);
alter table koki_social_private.blocks enable row level security;
revoke all on koki_social_private.blocks from public,anon,authenticated;
CREATE OR REPLACE FUNCTION koki_social_private.interact(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if p_action is null or p_action not in ('read','like','comment','delete','report','block','unblock_all') then raise exception 'Action invalide'; end if;
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
 elsif p_action='block' then
  if not exists(select 1 from koki_social_private.comments where id=p_comment and content_id=p_content and not hidden and user_id<>uid) then raise exception 'Commentaire indisponible';end if;
  insert into koki_social_private.blocks(blocker_id,blocked_id) select uid,user_id from koki_social_private.comments where id=p_comment and content_id=p_content on conflict do nothing;
 elsif p_action='unblock_all' then
  delete from koki_social_private.blocks where blocker_id=uid;
 elsif p_action='delete' then
  delete from koki_social_private.comments where id=p_comment and content_id=p_content and user_id=uid;
 end if;
 select jsonb_build_object('blocking_available',true,'blocked_count',(select count(*) from koki_social_private.blocks where blocker_id=uid),'likes',(select count(*) from koki_social_private.likes where content_id=p_content),
 'liked',exists(select 1 from koki_social_private.likes where content_id=p_content and user_id=uid),
 'total',(select count(*) from koki_social_private.comments where not hidden and content_id=p_content and not exists(select 1 from koki_social_private.blocks b where b.blocker_id=uid and b.blocked_id=comments.user_id)),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'created_at',c.created_at,'mine',coalesce(c.user_id=uid,false)) order by c.created_at desc,c.id) from (select * from koki_social_private.comments where not hidden and content_id=p_content and not exists(select 1 from koki_social_private.blocks b where b.blocker_id=uid and b.blocked_id=comments.user_id) order by created_at desc,id limit 30 offset p_offset)c),'[]'::jsonb)) into result;
 return result;
end $function$
;

commit;


