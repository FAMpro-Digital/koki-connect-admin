-- Lecture bornée par page ; le texte des fiches structurées reste intact.
create function public.koki_public_feed(p_offset integer) returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'Page invalide';end if;
 return (with page as (select id,type,titre,resume,case when type in ('Actualités','Annonces','Publicités') then null else texte end as texte,type in ('Actualités','Annonces','Publicités') as detail_required,categorie,statut,publication,source,lieu,evenement,image_path,une,actif,emplacement,fin from public.koki_contents where statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now()))) order by publication desc,id desc limit 101 offset p_offset),items as (select * from page order by publication desc,id desc limit 100) select jsonb_build_object('version',1,'more',(select count(*)>100 from page),'contenus',coalesce((select jsonb_agg(to_jsonb(items) order by publication desc,id desc) from items),'[]'::jsonb)));
end $$;
revoke all on function public.koki_public_feed(integer) from public;
grant execute on function public.koki_public_feed(integer) to anon,authenticated;
create function public.koki_public_content(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',id,'texte',texte,'image_path',image_path) from public.koki_contents where id=p_id and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))
$$;
revoke all on function public.koki_public_content(uuid) from public;
grant execute on function public.koki_public_content(uuid) to anon,authenticated;
