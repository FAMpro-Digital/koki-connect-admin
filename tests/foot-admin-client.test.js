// Module Football — client d'administration : contrôles avant envoi + intégration RÉELLE avec PostgreSQL local
// (migrations koki_foot appliquées sur une copie de la référence de production). L'intégration est sautée,
// avec un message, si la base locale de référence (koki_historique, outils/verifier.sh) n'est pas disponible.
import test from 'node:test';import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';
import {creerClientFoot,evenement,score,programmation,deverrouiller,motifRequis,versISO} from '../src/foot-admin-client.js';

const A='11111111-1111-4111-8111-111111111111',B='22222222-2222-4222-8222-222222222222';
const manuel={id:'m',revision:3,source:'manuel',statut:'En direct',competition:{type:'Coupe'},domicile:{id:A},exterieur:{id:B},score_domicile:0,score_exterieur:0};
const api={...manuel,source:'api'};

test('événement : période obligatoire et compatible avec le type',()=>{
 assert.throws(()=>evenement(manuel,{type:'but',equipe_id:A}),/période/);
 assert.throws(()=>evenement(manuel,{type:'but',periode:'tirs_au_but',equipe_id:A}),/incompatible/);
 assert.throws(()=>evenement(manuel,{type:'tab_reussi',periode:'mi_temps_2',equipe_id:A}),/incompatible/);
 assert.throws(()=>evenement({...manuel,competition:{type:'Championnat'}},{type:'but',periode:'prolongation_1',equipe_id:A}),/championnat/);
 assert.deepEqual(evenement(manuel,{type:'but',periode:'mi_temps_2',minute:'90',minute_add:'3',equipe_id:A,joueur:' Fall '}),
  {match_id:'m',revision:3,type:'but',periode:'mi_temps_2',equipe_id:A,joueur:'Fall',joueur2:'',maj_score:true,minute:90,minute_add:3});
 assert.equal('minute' in evenement(manuel,{type:'tab_reussi',periode:'tirs_au_but',minute:5,equipe_id:A}),false,'pas de minute pendant la séance');
 assert.throws(()=>evenement(api,{type:'but',periode:'mi_temps_1',equipe_id:A}),/Motif/);
});
test('score, programmation, déverrouillage : règles de motif identiques au serveur',()=>{
 assert.throws(()=>score(manuel,{statut:'En direct',score_domicile:1}),/deux équipes/);
 assert.doesNotThrow(()=>score(manuel,{statut:'En direct',minute:20,score_domicile:1,score_exterieur:0}));
 assert.throws(()=>score({...manuel,statut:'Terminé'},{statut:'Terminé',score_domicile:2,score_exterieur:0}),/Motif/);
 assert.throws(()=>score(api,{statut:'En direct',score_domicile:1,score_exterieur:0}),/Motif/);
 assert.equal(motifRequis(api,{programmationChange:true}),true);assert.equal(motifRequis(manuel,{programmationChange:true}),false);
 assert.throws(()=>programmation(api,{date_local:'2026-12-10T17:00'}),/Motif/);
 assert.equal(programmation(manuel,{date_local:'2026-12-10T17:00'}).date_match,'2026-12-10T17:00:00.000Z');
 assert.throws(()=>deverrouiller(api,{verrous:[],motif:'abc'}),/au moins un/);
 assert.throws(()=>deverrouiller(api,{verrous:['tout'],motif:'abc'}),/au moins un/);
 assert.throws(()=>versISO('demain'),/requises/);
});

// ───── Intégration avec PostgreSQL local ─────
const BASE='koki_foot_client_test';
function psql(args,input){return execFileSync('sudo',['-n','-u','postgres','psql','-X','-q','-At','-v','ON_ERROR_STOP=1',...args],{input,encoding:'utf8',stdio:['pipe','pipe','pipe'],cwd:new URL('..',import.meta.url).pathname});}
let disponible=false;
try{disponible=psql(['-d','postgres','-c',"select count(*) from pg_database where datname='koki_historique'"]).trim()==='1';}catch{disponible=false;}
const ADM='f1000000-0000-4000-8000-000000000001';
function appel(command,input){
 const json=JSON.stringify(input).replace(/'/g,"''");
 try{return JSON.parse(psql(['-d',BASE],`select set_config('request.jwt.claims','{"sub":"${ADM}","aal":"aal2","role":"authenticated"}',false);\nset role authenticated;\nselect public.koki_foot_admin('${command}','${json}'::jsonb);`).trim().split('\n').pop()||'null');}
 catch(e){throw Error(String(e.stderr||e.message).replace(/^.*ERROR:\s*/s,'').split('\n')[0]);}
}
test('intégration PostgreSQL : client → koki_foot_admin réel',{skip:disponible?false:'base locale de référence absente (lancer supabase/historique/outils/verifier.sh)'},()=>{
 psql(['-d','postgres','-c',`drop database if exists ${BASE}`,'-c',`create database ${BASE} template koki_historique`]);
 try{
  for(const f of ['supabase/historique/migrations/20261201000500_foot_schema.sql','supabase/historique/migrations/20261201000600_foot_acces.sql'])psql(['-d',BASE,'-f',f]);
  psql(['-d',BASE],`insert into auth.users(id,email) values('${ADM}','client@test.local');insert into public.koki_admin_members(user_id,role) values('${ADM}','editor');`);
  const c=creerClientFoot(appel);
  const comp=appel('enregistrer_competition',{nom:'Coupe test',type:'Coupe',publie:true});
  const e1=appel('enregistrer_equipe',{nom:'Alpha'}),e2=appel('enregistrer_equipe',{nom:'Beta'});
  let m=appel('enregistrer_match',{competition_id:comp.id,domicile_id:e1.id,exterieur_id:e2.id,date_match:versISO('2026-12-10T17:00'),publie:true});
  m=c.score(m,{statut:'En direct',minute:10});
  m=c.ajouterEvenement(m,{type:'but',periode:'mi_temps_2',minute:90,minute_add:3,equipe_id:e1.id,joueur:'Fall'}).match;
  assert.equal(m.score_domicile,1,'but en 2e mi-temps (90+3) : score réglementaire');
  m=c.score(m,{statut:'Prolongations',minute:91});
  m=c.ajouterEvenement(m,{type:'but',periode:'prolongation_1',minute:95,equipe_id:e2.id,joueur:'Sow'}).match;
  assert.deepEqual([m.score_domicile,m.score_exterieur,m.pro_domicile,m.pro_exterieur],[1,0,0,1]);
  m=c.ajouterEvenement(m,{type:'tab_reussi',periode:'tirs_au_but',equipe_id:e1.id}).match;
  assert.deepEqual([m.statut,m.tab_domicile,m.tab_exterieur,m.score_domicile],['Tirs au but',1,0,1],'séance : tab séparés du score');
  assert.equal(m.coherence.etat,'coherent');
  assert.throws(()=>c.score({...m,revision:1},{statut:'Terminé',score_domicile:1,score_exterieur:0,motif:'test'}),/Modifié entre-temps/,'révision périmée refusée par le serveur');
  const ev=c.evenements(m.id);assert.deepEqual(ev.map(x=>x.periode),['mi_temps_2','prolongation_1','tirs_au_but']);
  assert.equal(c.verifierJournal().premiere_alteration,null,'journal chaîné intact');
 }finally{psql(['-d','postgres','-c',`drop database if exists ${BASE}`]);}
});
