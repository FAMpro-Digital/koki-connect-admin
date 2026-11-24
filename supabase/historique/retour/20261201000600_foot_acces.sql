-- Retour arrière de 20261201000600_foot_acces.sql : retire les fonctions d'accès et la diffusion.
-- Les données du module (tables koki_foot) ne sont PAS touchées.
begin;
drop function if exists public.koki_foot_public(text,jsonb);
drop function if exists public.koki_foot_admin(text,jsonb);
drop function if exists public.koki_foot_sync(text,jsonb);
drop trigger if exists matchs_diffusion on koki_foot.matchs;
drop trigger if exists evenements_diffusion on koki_foot.evenements;
drop function if exists koki_foot.match_diffuse(), koki_foot.evenement_diffuse(), koki_foot.diffuser(text,jsonb),
 koki_foot.appliquer_score(koki_foot.matchs,uuid,text,integer,integer,integer,integer,integer,text), koki_foot.corriger(uuid,uuid,text,jsonb,jsonb,text),
 koki_foot.classement(uuid,text), koki_foot.visible(koki_foot.matchs), koki_foot.evenement_json(koki_foot.evenements), koki_foot.match_json(koki_foot.matchs),
 koki_foot.equipe_json(koki_foot.equipes), koki_foot.exiger(text), koki_foot.revision(integer,integer), koki_foot.ts(jsonb,text), koki_foot.b(jsonb,text,boolean),
 koki_foot.i(jsonb,text), koki_foot.u(jsonb,text), koki_foot.t(jsonb,text), koki_foot.cles(jsonb,text[]), koki_foot.echec(text);
commit;
