#!/usr/bin/env node
// Essai d'intégration LOCAL du connecteur API-Football avec la VRAIE fonction public.koki_foot_sync :
// fournisseur simulé (réponses au format v3), base PostgreSQL locale (référence de production koki_historique + migrations Football).
// Vérifie : découverte non publiée, aucun appel tant que rien n'est publié, direct + événements,
// verrou manuel respecté et conflit signalé, but annulé retiré, quota dépassé → pause, classement final.
// Lancement (utilisateur postgres) : node supabase/historique/outils/tester-foot-api.mjs
// Ne se connecte JAMAIS à Supabase : refuse tout hôte non local.
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {passage,decouvrir} from '../../../server/foot/synchronisation.js';
import {ErreurFournisseur} from '../../../server/foot/api-football.js';

const H=process.env.PGHOST||'/var/run/postgresql';
if(!/^(\/|localhost$|127\.0\.0\.1$|::1$)/.test(H)){console.error('REFUS : hôte non local');process.exit(2);}
const B='koki_foot_api';
// SQL sur l'entrée standard : les variables psql (:'nom') y sont substituées et échappées.
const psql=(db,sql,vars={})=>execFileSync('psql',['-X','-q','-At','-v','ON_ERROR_STOP=1','-d',db,...Object.entries(vars).flatMap(([k,v])=>['-v',`${k}=${v}`])],{input:sql+'\n',encoding:'utf8',env:{...process.env,PGHOST:H}}).trim();
const sqlFile=(db,f)=>execFileSync('psql',['-X','-q','-v','ON_ERROR_STOP=1','-d',db,'-f',f],{encoding:'utf8',env:{...process.env,PGHOST:H}});
const q=(sql)=>psql(B,sql);
const SERVICE=`select set_config('request.jwt.claims','{"role":"service_role"}',false); set role service_role;`;
const rpc=async(command,input)=>JSON.parse(psql(B,`${SERVICE} select public.koki_foot_sync(:'c',:'i'::jsonb)`,{c:command,i:JSON.stringify(input)}).split('\n').pop());
const planning=async()=>JSON.parse(psql(B,`${SERVICE} select public.koki_foot_sync_planning('api-football')`).split('\n').pop());
const EDITEUR='d0000000-0000-4000-8000-000000000002';
const admin=(command,input)=>JSON.parse(psql(B,`select set_config('request.jwt.claims',json_build_object('sub','${EDITEUR}','aal','aal2','role','authenticated')::text,false),set_config('request.jwt.claim.sub','${EDITEUR}',false); set role authenticated; select public.koki_foot_admin(:'c',:'i'::jsonb)`,{c:command,i:JSON.stringify(input)}).split('\n').pop());
let ok=0;const verifie=(c,m)=>{assert.ok(c,m);ok++;console.log('ok      '+m);};

// ───── Fournisseur simulé (format v3) ─────
const NOW=new Date();const K=+NOW-20*60000; // coup d'envoi du match suivi (constant)
const iso=d=>new Date(d).toISOString();
const LIGUE={id:9001,name:'Ligue 1',country:'Senegal',season:2025};
const eq={11:'ASC Jaraaf',12:'Génération Foot',13:'Teungueth FC',14:'AS Pikine'};
function fx(id,h,a,date,st,{el=null,g=[null,null],ft=null,events}={}){return {fixture:{id,date:iso(date),venue:{name:'Stade Lat Dior',city:'Thiès'},status:{short:st,elapsed:el}},
 league:{...LIGUE,round:'Regular Season - 7'},teams:{home:{id:h,name:eq[h]},away:{id:a,name:eq[a]}},goals:{home:g[0],away:g[1]},
 score:{fulltime:{home:ft?.[0]??null,away:ft?.[1]??null},extratime:{home:null,away:null},penalty:{home:null,away:null}},...(events?{events}:{})};}
const but=(min,team,nom)=>({time:{elapsed:min,extra:null},team:{id:team},player:{id:null,name:nom},assist:{name:''},type:'Goal',detail:'Normal Goal'});
const etat={matchs:[fx(501,11,12,+NOW+60*60000,'NS'),fx(502,13,14,+NOW-3*86400000,'FT',{g:[1,0],ft:[1,0]})],quota:95,echec:null};
const standings=()=>[{league:{...LIGUE,standings:[[11,12,13,14].map((t,i)=>({rank:i+1,team:{id:t,name:eq[t]},points:10-i,form:'WDL',all:{played:5,win:3-Math.min(i,3),draw:1,lose:1,goals:{for:8,against:5}}}))]}}];
let requetes=0;
const api={get quota(){return {restant:etat.quota};},get requetes(){return requetes;},
 async ligues(){requetes++;etat.quota--;return [{league:{id:9001,name:'Ligue 1',type:'League'},country:{name:'Senegal'},seasons:[{year:2025,start:'2025-11-01',end:'2026-06-30',current:true,coverage:{fixtures:{events:true},standings:true}}]}];},
 async matchsLigue(){requetes++;etat.quota--;return etat.matchs.map(m=>{const {events,...x}=m;return x;});},
 async matchsIds(ids){requetes++;if(etat.echec)throw etat.echec;etat.quota--;return etat.matchs.filter(m=>ids.includes(String(m.fixture.id)));},
 async matchId(id){return this.matchsIds([String(id)]);},
 async classement(){requetes++;etat.quota--;return standings();}};

// ───── Base locale ─────
psql('postgres',`drop database if exists ${B}`);psql('postgres',`create database ${B} template koki_historique`);
for(const f of ['migrations/20261201000500_foot_schema.sql','migrations/20261201000600_foot_acces.sql'])sqlFile(B,'supabase/historique/'+f);
sqlFile(B,'supabase/historique/propositions/20261201000800_foot_planification_api.sql');
verifie((()=>{try{sqlFile(B,'supabase/historique/propositions/20261201000800_foot_planification_api.sql');return false;}catch{return true;}})(),'0800 : la garde bloque une seconde application');
q(`insert into auth.users(id,email) values('${EDITEUR}','editeur@test.local') on conflict do nothing;
   insert into public.koki_admin_members(user_id,role) values('${EDITEUR}','editor') on conflict do nothing;`);
verifie(/permission denied/.test((()=>{try{psql(B,`select set_config('request.jwt.claims','{"role":"anon"}',false); set role anon; select public.koki_foot_sync_planning('api-football')`);return '';}catch(e){return String(e.stderr||e.message);}})()),'0800 : planning refusé à anon');
verifie(/permission denied|Réservé/.test((()=>{try{psql(B,`select set_config('request.jwt.claims','{"role":"authenticated"}',false); set role authenticated; select public.koki_foot_sync_planning('api-football')`);return '';}catch(e){return String(e.stderr||e.message);}})()),'0800 : planning refusé à un utilisateur connecté');

// 1. Découverte : compétition NON publiée, matchs, équipes, classement.
const d=await decouvrir({api,rpc,ligue:9001,saison:2025});
verifie(d.import.statut==='ok'&&d.matchs===2&&d.classement===4&&requetes===3,'découverte : 3 requêtes, 2 matchs, 4 lignes de classement, import ok');
verifie(q(`select publie::text||'|'||saison||'|'||portee||'|'||nom from koki_foot.competitions where ref_fournisseur='9001:2025'`)==='false|2025/26|Sénégal|Ligue 1 Sénégal','découverte : compétition créée NON publiée, portée Sénégal, saison 2025/26');
verifie(q(`select count(*) from koki_foot.equipes where fournisseur='api-football'`)==='4','découverte : 4 équipes, aucune en double');
const pub0=JSON.parse(psql(B,`select set_config('request.jwt.claims','{"role":"anon"}',false); set role anon; select public.koki_foot_public('accueil','{}')`).split('\n').pop());
verifie(JSON.stringify(pub0).indexOf('Jaraaf')===-1,'public : rien d’affiché tant que la compétition n’est pas publiée');

// 2. Rien de publié : aucun appel au fournisseur.
requetes=0;let b=await passage({api,rpc,planning,maintenant:new Date()});
verifie(requetes===0&&b.raison==='rien à faire','non publiée : aucune requête envoyée');

// 3. Publication par un administrateur (aal2) puis premier passage : calendrier + classement.
const comp=JSON.parse(q(`select json_build_object('id',id,'revision',revision) from koki_foot.competitions where ref_fournisseur='9001:2025'`));
admin('enregistrer_competition',{id:comp.id,revision:comp.revision,publie:true});
requetes=0;b=await passage({api,rpc,planning,maintenant:new Date()});
verifie(requetes===2&&b.operations.map(o=>o.operation).join()==='calendrier:9001:2025,classement:9001:2025','publiée : calendrier puis classement (2 requêtes)');

// 4. Coup d'envoi : le match entre dans le suivi direct.
etat.matchs[0]=fx(501,11,12,K,'1H',{el:21,g:[1,0],events:[but(18,11,'M. Diop')]});
q(`update koki_foot.matchs set date_match=now()-interval '20 minutes', api_date_match=now()-interval '20 minutes' where ref_fournisseur='501'`);
requetes=0;b=await passage({api,rpc,planning,maintenant:new Date()});
verifie(requetes===1&&b.operations[0].operation==='direct','direct : une seule requête pour les matchs suivis');
verifie(q(`select statut||'|'||minute||'|'||score_domicile||'-'||score_exterieur||'|'||resultat_source from koki_foot.matchs where ref_fournisseur='501'`)==='En direct|21|1-0|api','direct : statut, minute et score à jour');
verifie(q(`select count(*) from koki_foot.evenements e join koki_foot.matchs m on m.id=e.match_id where m.ref_fournisseur='501' and e.source='api'`)==='1','direct : but importé');
requetes=0;b=await passage({api,rpc,planning,maintenant:new Date()});
verifie(requetes===0,'direct : pas de nouvelle requête avant l’intervalle calculé ('+b.budget.intervalle_direct_s+' s)');

// 5. But annulé (VAR) : retiré à l'import suivant (liste complète).
etat.matchs[0]=fx(501,11,12,K,'1H',{el:26,g:[0,0],events:[]});
q(`update koki_foot.synchronisations set created_at=created_at-interval '1 hour' where operation='direct'`);
await passage({api,rpc,planning,maintenant:new Date()});
verifie(q(`select count(*) from koki_foot.evenements e join koki_foot.matchs m on m.id=e.match_id where m.ref_fournisseur='501'`)==='0','but annulé par le fournisseur : retiré');

// 6. Correction manuelle (verrou) : jamais écrasée, conflit signalé et journalisé.
const m=JSON.parse(q(`select json_build_object('id',id,'revision',revision) from koki_foot.matchs where ref_fournisseur='501'`));
admin('score',{id:m.id,revision:m.revision,statut:'En direct',minute:26,score_domicile:1,score_exterieur:0,motif:'But confirmé par l’arbitre au stade'});
etat.matchs[0]=fx(501,11,12,K,'1H',{el:31,g:[0,1],events:[but(29,12,'A. Ndiaye')]});
q(`update koki_foot.synchronisations set created_at=created_at-interval '1 hour' where operation='direct'`);
b=await passage({api,rpc,planning,maintenant:new Date()});
verifie(q(`select score_domicile||'-'||score_exterieur||'|'||verrou_manuel from koki_foot.matchs where ref_fournisseur='501'`)==='1-0|true','verrou manuel : score corrigé conservé');
verifie(q(`select string_agg(champ,',' order by champ) from koki_foot.conflits c join koki_foot.matchs m on m.id=c.match_id where m.ref_fournisseur='501' and not resolu`)==='evenements,score','conflits ouverts : score et événement (rien ignoré en silence)');
verifie(b.operations[0].ignores_verrou>=1,'journal de synchronisation : divergence comptée');
verifie(q(`select count(*) from koki_foot.corrections c join koki_foot.matchs m on m.id=c.match_id where m.ref_fournisseur='501' and action='score'`)==='1','journal des corrections : correction inscrite');

// 7. Fin du match : statut final (verrouillé → conflit), classement actualisé dans le même passage.
etat.matchs[0]=fx(501,11,12,K,'FT',{g:[0,1],ft:[0,1],events:[but(29,12,'A. Ndiaye')]});
q(`update koki_foot.synchronisations set created_at=created_at-interval '1 hour' where operation='direct'`);
requetes=0;b=await passage({api,rpc,planning,maintenant:new Date()});
verifie(b.operations.map(o=>o.operation).join()==='direct,classement:9001:2025'&&requetes===2,'match terminé : classement actualisé dans le même passage');

// 8. Quota dépassé : erreur journalisée, pause jusqu'à minuit UTC, plus aucune requête.
admin('deverrouiller',{id:m.id,revision:JSON.parse(q(`select revision from koki_foot.matchs where ref_fournisseur='501'`)),motif:'Retour aux données du fournisseur'});
etat.matchs[0]=fx(501,11,12,K,'2H',{el:50,g:[0,1]});
q(`update koki_foot.matchs set statut='En direct', minute=50 where ref_fournisseur='501'`);
q(`update koki_foot.synchronisations set created_at=created_at-interval '1 hour' where operation='direct'`);
etat.echec=new ErreurFournisseur('quota','You have reached the request limit for the day');
await passage({api,rpc,planning,maintenant:new Date()});
verifie(q(`select derniere_erreur_code||'|'||(pause_jusqu_a=(date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC') from koki_foot.etat_fournisseurs where fournisseur='api-football'`)==='quota|true','quota dépassé : pause jusqu’à 00:00 UTC');
requetes=0;b=await passage({api,rpc,planning,maintenant:new Date()});
verifie(requetes===0&&/pause/.test(b.raison),'pendant la pause : aucune requête');
verifie(q(`select koki_foot.fraicheur(m)->>'etat_source' from koki_foot.matchs m where ref_fournisseur='501'`)==='en_pause','affichage : source signalée « en pause »');
q(`update koki_foot.vus_api set vu_le=now()-interval '10 minutes' where match_id=(select id from koki_foot.matchs where ref_fournisseur='501')`);
verifie(q(`select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where ref_fournisseur='501'`)==='ancien','affichage : match en jeu sans nouvelle donnée depuis le seuil → « ancien »');
console.log(`TERMINÉ : connecteur API-Football vérifié en local (${ok} contrôles).`);
psql('postgres',`drop database if exists ${B}`);
