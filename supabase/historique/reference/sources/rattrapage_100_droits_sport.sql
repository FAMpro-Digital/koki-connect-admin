-- Droits relevés en production après l'application des migrations Clubs & Académies (20/11/2026).
-- En production, service_role n'a pas l'exécution des deux points d'entrée du module (comme pour les autres
-- fonctions koki_* exposées) ; la simulation locale l'accorde par défaut. Ce rattrapage aligne la référence.
revoke execute on function public.koki_sport(text,jsonb), public.koki_sport_public(text,jsonb) from service_role;
