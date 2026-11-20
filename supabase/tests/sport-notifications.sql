-- Tests des notifications Clubs & Académies (migration 20261201000300). Base LOCALE uniquement.
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = warning;
create schema t;
grant usage on schema t to anon, authenticated;
create table t.journal(n serial, ok text);
grant insert, select on t.journal to anon, authenticated; grant usage on sequence t.journal_n_seq to anon, authenticated;
create function t.as_user(uid text, aal text default 'aal1') returns void language sql as $$
 select set_config('request.jwt.claim.sub',coalesce(uid,''),false), set_config('request.jwt.claims',json_build_object('sub',uid,'aal',aal,'role','authenticated')::text,false), null::void $$;
create function t.ok(cond boolean, msg text) returns void language plpgsql as $$
begin if cond is not true then raise exception 'ÉCHEC : %', msg; end if; insert into t.journal(ok) values(msg); end $$;
create function t.call(cmd text, input jsonb default '{}') returns jsonb language sql as $$ select public.koki_sport(cmd,input) $$;
grant execute on all functions in schema t to anon, authenticated;
create function t.nb(uid text, motif text default '%') returns integer language sql security definer as $$
 select count(*)::int from public.koki_notifications where recipient_id=uid::uuid and sport_ref is not null and (title||' '||body) like motif $$;

insert into auth.users(id,phone,phone_confirmed_at) values
 ('e0000000-0000-4000-8000-000000000001',null,null),('e0000000-0000-4000-8000-000000000002',null,null),
 ('e0000000-0000-4000-8000-000000000003','221770000003',now()),('e0000000-0000-4000-8000-000000000004','221770000004',now()),
 ('e0000000-0000-4000-8000-000000000005',null,null),('e0000000-0000-4000-8000-000000000006',null,null),('e0000000-0000-4000-8000-000000000007',null,null);
insert into public.koki_admin_members(user_id,role) values('e0000000-0000-4000-8000-000000000005','superadmin'),('e0000000-0000-4000-8000-000000000006','editor');
\set resp 'e0000000-0000-4000-8000-000000000001'
\set coach 'e0000000-0000-4000-8000-000000000002'
\set fan 'e0000000-0000-4000-8000-000000000003'
\set muet 'e0000000-0000-4000-8000-000000000004'
\set admin 'e0000000-0000-4000-8000-000000000005'
\set editor 'e0000000-0000-4000-8000-000000000006'
\set autre 'e0000000-0000-4000-8000-000000000007'
-- L'abonné a activé SMS et push AVANT les notifications (conditions d'envoi SMS du système existant réunies).
insert into public.koki_notification_preferences(user_id,sms,updated_at) values(:'fan',true,now()-interval '1 minute');
insert into public.koki_push_subscriptions(user_id,endpoint,p256dh,auth,created_at) values(:'fan','https://fcm.googleapis.com/fcm/send/test-koki','B'||repeat('A',86),repeat('A',22),now()-interval '1 minute');

set role authenticated; select t.as_user(:'resp');
select (t.call('create_club','{"nom":"Académie Notif"}'))->>'id' as club \gset
select t.ok(t.nb(:'admin','Académie à valider%')=1,'administrateur prévenu d’une académie à valider');
select t.ok(t.nb(:'editor')=0,'editor non concerné par la validation');
select t.as_user(:'admin','aal2');
select t.call('admin_review',jsonb_build_object('id',:'club','revision',1,'decision','approve'));
select t.ok(t.nb(:'resp','%validée%')=1,'responsable prévenu de la validation');
select t.as_user(:'resp');
select (t.call('category_save',jsonb_build_object('club_id',:'club','nom','U15')))->>'id' as cat \gset
select (t.call('invite',jsonb_build_object('club_id',:'club','role','entraineur')))->>'code' as code \gset
select t.as_user(:'coach'); select t.call('accept_invitation',jsonb_build_object('code',:'code'));
select t.ok(t.nb(:'resp','%Nouveau membre%')=1,'responsable prévenu d’un nouveau membre');
select t.as_user(:'fan'); select t.call('follow',jsonb_build_object('club_id',:'club'));
select t.as_user(:'muet'); select t.call('follow',jsonb_build_object('club_id',:'club','notifications',false));

-- Abonnés : match programmé, résultat
select t.as_user(:'resp');
select (t.call('match_save',jsonb_build_object('club_id',:'club','categorie_id',:'cat','adversaire','ASC Louga','a_domicile',true,'date_match',(now()+interval '3 days')::text)))->>'id' as mid \gset
select t.ok(t.nb(:'fan','%Match programmé (U15) : Académie Notif – ASC Louga%')=1,'abonné prévenu d’un match programmé');
select t.ok(t.nb(:'muet')=0,'abonné sans notifications : rien');
select t.ok(t.nb(:'autre')=0,'non-abonné : rien');
select t.call('match_save',jsonb_build_object('id',:'mid','revision',1,'categorie_id',:'cat','adversaire','ASC Louga','a_domicile',true,'date_match',(now()+interval '3 days')::text,'statut','Terminé','score_domicile',2,'score_exterieur',0));
select t.ok(t.nb(:'fan','%Résultat (U15) : Académie Notif 2 – 0 ASC Louga%')=1,'abonné prévenu du résultat');
select t.call('match_save',jsonb_build_object('id',:'mid','revision',2,'categorie_id',:'cat','adversaire','ASC Louga','a_domicile',true,'date_match',(now()+interval '3 days')::text,'statut','Terminé','score_domicile',2,'score_exterieur',1));
select t.ok(t.nb(:'fan','%Résultat%')=1,'correction de score : pas de second envoi');
-- Anti-saturation : 3 envois abonnés par heure au maximum
select (t.call('post_save',jsonb_build_object('club_id',:'club','titre','Info 1')))->>'id' as p1 \gset
select t.call('post_publish',jsonb_build_object('id',:'p1','revision',1));
select (t.call('post_save',jsonb_build_object('club_id',:'club','titre','Info 2')))->>'id' as p2 \gset
select t.call('post_publish',jsonb_build_object('id',:'p2','revision',1));
select t.ok(t.nb(:'fan','%Info 1%')=1,'abonné prévenu de la 1re publication');
select t.ok(t.nb(:'fan','%Info 2%')=0,'4e envoi dans l’heure : retenu (anti-saturation)');

-- Signalement et modération
select t.as_user(:'fan');
select t.call('report',jsonb_build_object('cible_type','post','cible_id',:'p1','motif','Mineur exposé'));
select t.ok(t.nb(:'editor','Signalement%')=1 and t.nb(:'admin','Signalement%')=1,'modérateurs prévenus d’un signalement');
select t.as_user(:'editor','aal2');
select t.call('admin_hide',jsonb_build_object('cible_type','post','id',:'p1','motif','Photo à vérifier'));
select t.ok(t.nb(:'resp','%masquée par la modération%')=1,'responsable prévenu du masquage');
select t.ok(t.nb(:'coach','%masquée%')=0,'entraîneur non concerné par la communication');
-- Suspension : membres prévenus, abonnés plus sollicités
reset role; select revision as rv from koki_sport.clubs where id=:'club' \gset
set role authenticated; select t.as_user(:'admin','aal2');
select t.call('admin_review',jsonb_build_object('id',:'club','revision',:'rv'::int,'decision','suspend','motif','Vérification en cours'));
select t.ok(t.nb(:'coach','%suspendue%')=1,'membres prévenus de la suspension');

-- Lecture : chacun ne voit que ses notifications (règles existantes inchangées)
select t.as_user(:'fan');
select t.ok((select count(*) from public.koki_notifications where sport_ref is not null)=(select t.nb(:'fan')),'un compte ne lit que ses propres notifications');
select t.ok((select count(*) from public.koki_notifications where recipient_id<>:'fan')=0,'aucune notification d’autrui visible');

-- Envoi : push oui, SMS jamais pour le module ; les autres notifications gardent le SMS
reset role;
insert into public.koki_notifications(recipient_id,record_id,revision,title,body,category)
 select :'fan',r.id,1,'Suivi','Commande','commandes' from public.koki_records r limit 1;
select count(*) as d from public.koki_notification_claim(true,true) \gset
select t.ok((select count(*) from public.koki_notification_deliveries d join public.koki_notifications n on n.id=d.notification_id where n.sport_ref is not null and d.channel='push')>=2,'notifications du module envoyées en push');
select t.ok((select count(*) from public.koki_notification_deliveries d join public.koki_notifications n on n.id=d.notification_id where n.sport_ref is not null and d.channel='sms')=0,'jamais de SMS pour le module');
select t.ok((select count(*) from public.koki_notification_deliveries d join public.koki_notifications n on n.id=d.notification_id where n.record_id is not null and d.channel='sms')=(select count(*) from public.koki_notifications where record_id is not null and recipient_id=:'fan'),'SMS des notifications existantes inchangé');
select t.ok(not exists(select 1 from public.koki_notifications where num_nonnulls(record_id,content_id,sport_ref)<>1),'contrainte : une seule cible par notification');

select count(*) as reussis from t.journal \gset
\echo 'Tests réussis :' :reussis
drop schema t cascade;
