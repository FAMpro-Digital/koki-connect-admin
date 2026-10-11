-- LECTURE SEULE — inventaire des photos historiques dont le chemin commence par l'identifiant du compte.
-- Aucune écriture, aucune migration. À exécuter d'abord sur le Supabase local, puis sur le projet TEST, avec autorisation.
with refs as (
 select r.id record_id,r.kind,r.statut,r.owner_id,p.path
 from public.koki_records r
 cross join lateral (select r.payload->>'image_path' path union select jsonb_array_elements_text(coalesce(r.payload->'photos','[]'::jsonb)) union select jsonb_array_elements_text(coalesce(r.payload->'modification'->'photos','[]'::jsonb))) p
 where p.path is not null and r.owner_id is not null and p.path like r.owner_id::text||'/%'
)
select kind,statut,count(*) as references_historiques,count(distinct path) as fichiers,count(distinct owner_id) as comptes,
 count(*) filter(where not exists(select 1 from storage.objects o where o.bucket_id='koki-media' and o.name=refs.path)) as fichiers_absents
from refs group by kind,statut order by kind,statut;
