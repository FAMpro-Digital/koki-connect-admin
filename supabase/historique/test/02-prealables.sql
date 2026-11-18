-- KOKI CONNECT TEST — PRÉALABLE : planificateur pg_cron (utilisé par la tâche interne
-- « koki-notify-contents », qui n'appelle aucun service extérieur).
-- NÉCESSITE UNE AUTORISATION EXPLICITE. Ni pg_net, ni secret du coffre : inutiles en test.
create extension if not exists pg_cron with schema pg_catalog;
