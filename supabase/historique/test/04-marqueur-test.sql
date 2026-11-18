-- KOKI CONNECT TEST — MARQUEUR « KOKI TEST », posé APRÈS la référence (le paquet des
-- phases 2 à 6 refuse de s'exécuter sur une base déjà marquée). Empêche ensuite tout
-- paquet réservé à la production de s'appliquer par erreur sur cette base.
create table koki_private.test_environment(label text primary key check(label='KOKI TEST'));
alter table koki_private.test_environment enable row level security;
revoke all on koki_private.test_environment from public,anon,authenticated;
insert into koki_private.test_environment values('KOKI TEST');
-- La tâche d'envoi des notifications vers l'administration NE DOIT PAS exister ici.
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') and exists(select 1 from cron.job where jobname='koki-notifications-dispatch' or command ilike '%http%') then
  raise exception 'CONTRÔLE : une tâche planifiée appelle un service extérieur'; end if;
end $$;
