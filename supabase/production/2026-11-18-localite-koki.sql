-- Script de production (hors migrations locales générées, qui gardent les données fictives « Coki »).
-- Orthographe de la localité principale : « Koki » (nom de la commune et de l'application) au lieu de « Coki »
-- (graphie OpenStreetMap). Appliqué en production le 18 novembre 2026. Les fiches qui portaient « Coki » sont renommées.
update public.koki_localites set nom = 'Koki' where nom = 'Coki';
update public.koki_records set payload = jsonb_set(payload, '{village}', '"Koki"')
 where payload->>'village' = 'Coki' and kind in ('professionnels', 'boutiques');
-- Retour arrière : mêmes requêtes en inversant 'Koki' et 'Coki' (uniquement pour les fiches renommées ici).
