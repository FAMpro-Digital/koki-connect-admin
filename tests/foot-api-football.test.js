// Connecteur API-Football : conversion, quota, erreurs, sécurité de la clé, fonction serveur.
// Données : objets au format v3 d'API-Football construits pour les tests (aucun appel réseau).
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';
import {statut,scores,evenements,typeEvenement,convertirMatchs,convertirClassement,convertirCompetition,couverture,classerErreurs,creerClient,expurger,
 refCompetition,lireRefCompetition,journee,nomCompetition,ErreurFournisseur} from '../server/foot/api-football.js';
import {planifier,passage,decouvrir,verifier,minutesDirectRestantes,lireConfig,CONFIG_DEFAUT} from '../server/foot/synchronisation.js';
import {footSyncHandler} from '../api/foot-sync.js';

const CLE='cle-secrete-api-football-0123456789';
const LIGUE={id:9001,name:'Ligue 1',country:'Senegal',season:2024,round:'Regular Season - 12'};
function f({id=1,st='NS',el=null,gH=null,gA=null,ft=null,et=null,pen=null,events,date='2025-03-01T16:30:00+00:00',h=11,a=12,league=LIGUE}={}){
 return {fixture:{id,date,venue:{name:'Stade Lat Dior',city:'Thiès'},status:{short:st,elapsed:el}},league,
  teams:{home:{id:h,name:'ASC Jaraaf'},away:{id:a,name:'Génération Foot'}},goals:{home:gH,away:gA},
  score:{fulltime:{home:ft?.[0]??null,away:ft?.[1]??null},extratime:{home:et?.[0]??null,away:et?.[1]??null},penalty:{home:pen?.[0]??null,away:pen?.[1]??null}},...(events?{events}:{})};
}
const ev=(elapsed,type,detail,team=11,player='Joueur A',extra=null,comments=null)=>({time:{elapsed,extra},team:{id:team},player:{id:null,name:player},assist:{name:''},type,detail,comments});
function reponseHttp(corps,{status=200,entetes={}}={}){return {ok:status>=200&&status<300,status,headers:{get:n=>entetes[n.toLowerCase()]??null},json:async()=>corps};}
function res(){return {h:{},setHeader(k,v){this.h[k]=v;},status(n){this.code=n;return this;},json(v){this.body=v;return this;}};}

test('statuts : codes du fournisseur → statuts koki_foot',()=>{
 const attendus={NS:'À venir',TBD:'À venir','1H':'En direct','2H':'En direct',HT:'Mi-temps',ET:'Prolongations',BT:'Prolongations',P:'Tirs au but',FT:'Terminé',AET:'Terminé',PEN:'Terminé',AWD:'Terminé',WO:'Terminé',SUSP:'Suspendu',INT:'Interrompu',PST:'Reporté',CANC:'Annulé',ABD:'Annulé'};
 for(const [k,v] of Object.entries(attendus))assert.equal(statut(k),v,k);
 assert.equal(statut('XYZ'),null);
});
test('scores : réglementaire, prolongation séparée, tirs au but, direct sans buts',()=>{
 assert.deepEqual(scores(f({st:'FT',gH:2,gA:1,ft:[2,1]})),{score_domicile:2,score_exterieur:1,pro_domicile:null,pro_exterieur:null,tab_domicile:null,tab_exterieur:null});
 assert.deepEqual(scores(f({st:'AET',gH:3,gA:2,ft:[2,2],et:[1,0]})),{score_domicile:2,score_exterieur:2,pro_domicile:1,pro_exterieur:0,tab_domicile:null,tab_exterieur:null});
 const p=scores(f({st:'PEN',gH:1,gA:1,ft:[1,1],et:[0,0],pen:[4,3]}));assert.deepEqual([p.score_domicile,p.pro_domicile,p.tab_domicile,p.tab_exterieur],[1,0,4,3]);
 const live=scores(f({st:'1H',el:3}));assert.deepEqual([live.score_domicile,live.score_exterieur],[0,0]);
 assert.equal(scores(f({st:'NS'})).score_domicile,null);assert.equal(scores(f({st:'PST'})).score_domicile,null);
 const etLive=scores(f({st:'ET',el:100,gH:2,gA:1,ft:[1,1]}));assert.deepEqual([etLive.score_domicile,etLive.pro_domicile,etLive.pro_exterieur],[1,1,0],'prolongation en cours : écart buts/90 min');
});
test('événements : types, périodes, clés stables et distinctes, VAR ignoré, tirs au but',()=>{
 assert.equal(typeEvenement(ev(10,'Goal','Normal Goal')),'but');assert.equal(typeEvenement(ev(10,'Goal','Own Goal')),'but_csc');
 assert.equal(typeEvenement(ev(10,'Goal','Penalty')),'penalty');assert.equal(typeEvenement(ev(10,'Goal','Missed Penalty')),'penalty_manque');
 assert.equal(typeEvenement(ev(10,'Card','Yellow Card')),'carton_jaune');assert.equal(typeEvenement(ev(10,'Card','Second Yellow card')),'carton_rouge');
 assert.equal(typeEvenement(ev(10,'Card','Red Card')),'carton_rouge');assert.equal(typeEvenement(ev(10,'subst','Substitution 1')),'remplacement');
 assert.equal(typeEvenement(ev(10,'Var','Goal cancelled')),null);
 assert.equal(typeEvenement(ev(120,'Goal','Penalty',11,'X',null,'Penalty Shootout')),'tab_reussi');assert.equal(typeEvenement(ev(120,'Goal','Missed Penalty',11,'X',null,'Penalty Shootout')),'tab_manque');
 const m=f({st:'FT',gH:1,gA:0,ft:[1,0],events:[ev(45,'Goal','Normal Goal',11,'A',2),ev(90,'Card','Yellow Card',12,'B',4),ev(100,'Goal','Normal Goal',11,'C'),ev(30,'Var','Goal cancelled'),ev(60,'Card','Yellow Card',12,'B'),ev(60,'Card','Yellow Card',12,'B')]});
 const a=evenements(m),b=evenements(m);
 assert.deepEqual(a,b,'mêmes clés à chaque passage');assert.equal(a.length,5);
 assert.deepEqual(a.map(x=>x.periode),['mi_temps_1','mi_temps_2','prolongation_1','mi_temps_2','mi_temps_2']);
 assert.equal(a[0].minute_add,2);assert.equal(new Set(a.map(x=>x.cle)).size,5,'deux cartons identiques : clés distinctes');
 assert.ok(a.every(x=>x.cle.length<=200&&x.match_ref==='1'&&x.equipe_ref));
});
test('conversion des matchs : références, rejet des lignes incomplètes, minute en jeu seulement, journée',()=>{
 const r=convertirMatchs([f({id:1,st:'2H',el:67,gH:1,gA:0}),f({id:2,st:'FT',gH:null,gA:null}),f({id:3,st:'NS'}),{fixture:{id:4}},f({id:5,st:'FT',gH:0,gA:0,ft:[0,0]})]);
 assert.deepEqual(r.matchs.map(m=>m.ref),['1','3','5']);assert.deepEqual(r.rejetes.sort(),['2','4']);
 const m1=r.matchs[0];assert.equal(m1.competition_ref,'9001:2024');assert.equal(m1.minute,67);assert.equal(m1.statut,'En direct');assert.equal(m1.journee,'Journée 12');assert.equal(m1.lieu,'Stade Lat Dior, Thiès');
 assert.equal(r.matchs[1].minute,null);assert.equal(r.equipes.length,2);assert.ok(r.equipes.every(e=>e.portee==='Sénégal'));
 assert.equal(r.evenements.length,0,'sans liste complète : aucun événement ni retrait');assert.equal(r.evenements_complets.length,0);
 const d=convertirMatchs([f({id:7,st:'FT',gH:1,gA:0,ft:[1,0],events:[]})],{avecEvenements:true});assert.deepEqual(d.evenements_complets,['7'],'liste vide fournie : retrait des événements annulés possible');
 assert.equal(journee('Group A - 2'),'Groupe A - 2');assert.equal(nomCompetition({name:'Ligue 1',country:'Senegal'}),'Ligue 1 Sénégal');assert.equal(nomCompetition({name:'Ligue 1',country:'France'}),'Ligue 1 (France)');
 assert.equal(refCompetition(403,2025),'403:2025');assert.deepEqual(lireRefCompetition('403:2025'),{ligue:403,saison:2025});assert.equal(lireRefCompetition('403'),null);
});
test('classement : forme V/N/D, poules, lignes invalides ignorées',()=>{
 const rep=[{league:{id:9001,season:2024,country:'Senegal',standings:[[{rank:1,team:{id:11,name:'ASC Jaraaf'},points:40,form:'WWDLW',group:'Ligue 1',all:{played:20,win:12,draw:4,lose:4,goals:{for:30,against:15}}},{rank:null,team:{id:99}}]]}}];
 const c=convertirClassement(rep);assert.equal(c.classements.length,1);assert.deepEqual(c.classements[0],{competition_ref:'9001:2024',poule:'',equipe_ref:'11',rang:1,joues:20,gagnes:12,nuls:4,perdus:4,buts_pour:30,buts_contre:15,points:40,forme:'VVNDV'});
 const g=convertirClassement([{league:{id:5,season:2024,country:'World',standings:[[{rank:1,team:{id:1,name:'A'},group:'Group A',all:{}}],[{rank:1,team:{id:2,name:'B'},group:'Group B',all:{}}]]}}]);
 assert.deepEqual(g.classements.map(x=>x.poule),['Groupe A','Groupe B']);assert.deepEqual(convertirClassement([]),{equipes:[],inscriptions:[],classements:[]});
});
test('compétition et couverture : saison absente refusée, type Coupe, saison étalée',()=>{
 const ent={league:{id:9001,name:'Ligue 1',type:'League'},country:{name:'Senegal'},seasons:[{year:2024,start:'2024-11-01',end:'2025-06-30',current:false,coverage:{fixtures:{events:true,lineups:false,statistics_fixtures:false},standings:true,players:false,top_scorers:false}}]};
 assert.deepEqual(convertirCompetition(ent,2024),{ref:'9001:2024',nom:'Ligue 1 Sénégal',saison:'2024/25',portee:'Sénégal',type:'Championnat'});
 assert.equal(convertirCompetition(ent,2025),null);
 assert.equal(convertirCompetition({...ent,league:{...ent.league,type:'Cup'}},2024).type,'Coupe');
 const c=couverture(ent,2024);assert.equal(c.evenements,true);assert.equal(c.classement,true);assert.equal(c.compositions,false);assert.equal(couverture(ent,2025).disponible,false);
});
test('erreurs du fournisseur : réponse 200 avec « errors » classée (clé, quota, formule)',()=>{
 assert.equal(classerErreurs({}),null);assert.equal(classerErreurs([]),null);
 assert.equal(classerErreurs({token:'Error/Missing application key.'}).code,'authentification');
 assert.equal(classerErreurs({requests:'You have reached the request limit for the day'}).code,'quota');
 assert.equal(classerErreurs({rateLimit:'Too many requests'}).code,'quota');
 const p=classerErreurs({plan:'Free plans do not have access to this season, try from 2022 to 2024.'});assert.equal(p.code,'donnees');assert.equal(p.plan,true);
});
test('client : clé en en-tête uniquement, redirection interdite, quota lu, erreurs classées, clé jamais renvoyée',async()=>{
 const vus=[];const api=creerClient({cle:CLE,request:async(url,o)=>{vus.push({url,o});return reponseHttp({errors:[],response:[{ok:1}]},{entetes:{'x-ratelimit-requests-remaining':'87','x-ratelimit-requests-limit':'100','x-ratelimit-remaining':'9'}});}});
 await api.matchsLigue(9001,2024);
 assert.equal(vus[0].o.headers['x-apisports-key'],CLE);assert.ok(!vus[0].url.includes(CLE),'clé absente de l’adresse');assert.equal(vus[0].o.redirect,'error');
 assert.equal(new URL(vus[0].url).host,'v3.football.api-sports.io');assert.equal(new URL(vus[0].url).searchParams.get('league'),'9001');
 assert.deepEqual(api.quota,{restant:87,jour:100,minute:9});assert.equal(api.requetes,1);
 const cas=[[reponseHttp({},{status:429}),'quota'],[reponseHttp({},{status:403}),'authentification'],[reponseHttp({},{status:502}),'indisponible'],[reponseHttp({errors:{token:'bad key '+CLE},response:[]}),'authentification']];
 for(const [r,code] of cas){const c=creerClient({cle:CLE,request:async()=>r});await assert.rejects(c.statut(),e=>{assert.equal(e.code,code);assert.ok(!e.message.includes(CLE),'clé expurgée');return true;});}
 const t=creerClient({cle:CLE,request:async()=>{const e=new Error('timeout');e.name='TimeoutError';throw e;}});await assert.rejects(t.statut(),e=>e.code==='delai');
 assert.throws(()=>creerClient({cle:''}),e=>e.code==='authentification');
 assert.equal(expurger('x-apisports-key: '+CLE+' et '+CLE,CLE).includes(CLE),false);
});

// ───── Planification du quota ─────
const NOW=new Date('2026-12-06T16:00:00Z');
const base=(o={})=>({quota_restant:null,derniere_tentative:null,pause_jusqu_a:null,competitions:[{ref:'9001:2025',saison:'2025/26'}],matchs_a_suivre:[],coups_d_envoi:[],competitions_du_jour:[],operations:{},...o});
test('planification : pause, rien à suivre, besoins quotidiens, plafond par minute',()=>{
 assert.equal(planifier({maintenant:NOW,planning:base({pause_jusqu_a:'2026-12-06T17:00:00Z'})}).actions.length,0);
 const p=planifier({maintenant:NOW,planning:base()});assert.deepEqual(p.actions.map(a=>a.type),['calendrier','classement']);
 const recent=planifier({maintenant:NOW,planning:base({operations:{'calendrier:9001:2025':'2026-12-06T10:00:00Z','classement:9001:2025':'2026-12-06T01:00:00Z'}})});assert.equal(recent.actions.length,0);assert.equal(recent.raison,'rien à faire');
 const many=planifier({maintenant:NOW,planning:base({competitions:Array.from({length:12},(_,i)=>({ref:`${100+i}:2025`}))})});assert.ok(many.actions.length<=CONFIG_DEFAUT.parMinute-1,'≤ 9 requêtes par minute');
 const vide=planifier({maintenant:NOW,planning:base({quota_restant:10,derniere_tentative:'2026-12-06T15:00:00Z'})});assert.equal(vide.actions.length,0);assert.equal(vide.raison,'quota du jour épuisé');
 const lendemain=planifier({maintenant:NOW,planning:base({quota_restant:0,derniere_tentative:'2026-12-05T23:00:00Z'})});assert.equal(lendemain.budget.restant,100,'nouveau jour UTC : quota renouvelé');
});
test('planification du direct : intervalle réparti sur les fenêtres de match du jour',()=>{
 assert.equal(minutesDirectRestantes(['2026-12-06T16:00:00Z','2026-12-06T16:30:00Z'],NOW,130),160);
 assert.equal(minutesDirectRestantes(['2026-12-06T23:30:00Z'],NOW,130),30,'coupé à minuit UTC');
 const ops={'calendrier:9001:2025':NOW.toISOString(),'classement:9001:2025':NOW.toISOString()};
 const p=planifier({maintenant:NOW,planning:base({matchs_a_suivre:['77','78'],coups_d_envoi:['2026-12-06T16:00:00Z'],competitions_du_jour:['9001:2025'],operations:ops})});
 assert.deepEqual(p.actions,[{type:'direct',refs:['77','78']}]);
 // 89 requêtes pour le direct (100 − 10 de réserve − 1 classement final) sur 130 min → toutes les 88 s environ.
 assert.equal(p.budget.pour_direct,89);assert.ok(p.budget.intervalle_direct_s>=60&&p.budget.intervalle_direct_s<=120,String(p.budget.intervalle_direct_s));
 const trop=planifier({maintenant:NOW,planning:base({matchs_a_suivre:['77'],coups_d_envoi:['2026-12-06T16:00:00Z'],operations:{...ops,direct:new Date(+NOW-30000).toISOString()}})});assert.equal(trop.actions.length,0,'pas avant l’intervalle');
 const peu=planifier({maintenant:NOW,planning:base({quota_restant:11,competitions_du_jour:['9001:2025'],derniere_tentative:NOW.toISOString(),matchs_a_suivre:['77'],coups_d_envoi:['2026-12-06T16:00:00Z'],operations:ops})});
 assert.equal(peu.actions.length,0);assert.match(peu.raison,/quota insuffisant/);
 const cfg=lireConfig({API_FOOTBALL_LIMITE_JOUR:'7500',API_FOOTBALL_PAR_MINUTE:'300'});const pro=planifier({maintenant:NOW,config:cfg,planning:base({matchs_a_suivre:['77'],coups_d_envoi:['2026-12-06T16:00:00Z'],operations:ops})});
 assert.equal(pro.budget.intervalle_direct_s,60,'formule payante : chaque minute');
 assert.deepEqual(lireConfig({API_FOOTBALL_LIMITE_JOUR:'abc'}),{...CONFIG_DEFAUT},'valeur invalide : défaut');
});

// ───── Passage complet (fournisseur et base simulés) ─────
function apiSimulee(rep,{echec}={}){let n=0;const q={restant:80};return {get quota(){return q;},get requetes(){return n;},
 async matchsIds(ids){n++;if(echec==='ids')throw new ErreurFournisseur('donnees','ids non autorisés');if(echec==='quota')throw new ErreurFournisseur('quota','limite');return rep.direct.filter(x=>ids.includes(String(x.fixture.id)));},
 async matchId(id){n++;return rep.direct.filter(x=>String(x.fixture.id)===String(id));},
 async matchsLigue(){n++;return rep.calendrier||[];},async classement(){n++;return rep.classement||[];},
 async ligues(){n++;return rep.ligues||[];},async statut(){return rep.statut;}};}
function baseSimulee(planning){const appels=[];return {appels,planning:async()=>planning,rpc:async(c,i)=>{appels.push([c,i]);return c==='importer'?{statut:'ok',lus:1,crees:0,mis_a_jour:1,ignores_verrou:0,rejetes:0}:{};}};}
test('passage : direct avec événements complets, puis classement après un match terminé',async()=>{
 const L={...LIGUE,id:9001,season:2025};
 const rep={direct:[f({id:77,st:'FT',gH:2,gA:0,ft:[2,0],league:L,events:[ev(12,'Goal','Normal Goal')]}),f({id:78,st:'2H',el:70,gH:0,gA:0,league:L,events:[]})],classement:[{league:{id:9001,season:2025,standings:[[{rank:1,team:{id:11,name:'A'},all:{}}]]}}]};
 const db=baseSimulee(base({matchs_a_suivre:['77','78'],coups_d_envoi:[NOW.toISOString()],operations:{'calendrier:9001:2025':NOW.toISOString(),'classement:9001:2025':NOW.toISOString()}}));
 const api=apiSimulee(rep);const b=await passage({api,rpc:db.rpc,planning:db.planning,maintenant:NOW});
 assert.deepEqual(b.operations.map(o=>o.operation),['direct','classement:9001:2025']);assert.equal(api.requetes,2);
 const imp=db.appels[0][1];assert.equal(imp.fournisseur,'api-football');assert.equal(imp.operation,'direct');assert.equal(imp.quota_restant,80);
 assert.deepEqual(imp.evenements_complets,['77','78']);assert.equal(imp.evenements.length,1);assert.equal(imp.matchs.find(m=>m.ref==='77').statut,'Terminé');
 assert.ok(!('competitions' in imp)&&!('inscriptions' in imp),'le direct ne réécrit ni compétition ni poule');
});
test('passage : quota dépassé → erreur journalisée (pause par la base), arrêt du passage',async()=>{
 const db=baseSimulee(base({matchs_a_suivre:['77'],coups_d_envoi:[NOW.toISOString()]}));
 const b=await passage({api:apiSimulee({direct:[]},{echec:'quota'}),rpc:db.rpc,planning:db.planning,maintenant:NOW,cle:CLE});
 assert.deepEqual(db.appels.map(a=>a[0]),['erreur']);assert.equal(db.appels[0][1].code,'quota');assert.equal(b.operations.length,1,'aucune autre requête après un dépassement');
});
test('passage : requête groupée refusée par la formule → repli match par match (2 au plus)',async()=>{
 const rep={direct:[f({id:77,st:'1H',el:5,gH:0,gA:0}),f({id:78,st:'1H',el:5,gH:0,gA:0}),f({id:79,st:'1H',el:5,gH:0,gA:0})]};
 const db=baseSimulee(base({matchs_a_suivre:['77','78','79'],coups_d_envoi:[NOW.toISOString()],operations:{'calendrier:9001:2025':NOW.toISOString(),'classement:9001:2025':NOW.toISOString()}}));
 const api=apiSimulee(rep,{echec:'ids'});await passage({api,rpc:db.rpc,planning:db.planning,maintenant:NOW});
 assert.equal(api.requetes,3);assert.deepEqual(db.appels[0][1].matchs.map(m=>m.ref),['77','78']);
});
test('découverte : compétition créée avec couverture vérifiée ; saison refusée sans requête de matchs',async()=>{
 const ent={league:{id:9001,name:'Ligue 1',type:'League'},country:{name:'Senegal'},seasons:[{year:2024,start:'2024-11-01',end:'2025-06-30',coverage:{fixtures:{events:true},standings:true}}]};
 const db=baseSimulee(base());const api=apiSimulee({ligues:[ent],calendrier:[f({id:1,st:'FT',gH:1,gA:1,ft:[1,1]})],classement:[{league:{id:9001,season:2024,standings:[[{rank:1,team:{id:11,name:'ASC Jaraaf'},all:{}}]]}}]});
 const r=await decouvrir({api,rpc:db.rpc,ligue:9001,saison:2024});
 assert.equal(api.requetes,3);assert.equal(r.competition.saison,'2024/25');assert.equal(db.appels[0][1].competitions[0].ref,'9001:2024');assert.equal(db.appels[0][1].classements.length,1);
 const api2=apiSimulee({ligues:[ent]});await assert.rejects(decouvrir({api:api2,rpc:db.rpc,ligue:9001,saison:2025}),/absente/);assert.equal(api2.requetes,1);
});
test('vérification : Ligue 1 et Ligue 2 du Sénégal repérées avec leur couverture, compte sans données personnelles',async()=>{
 const mk=(id,name,y)=>({league:{id,name,type:'League'},country:{name:'Senegal'},seasons:[{year:y,coverage:{fixtures:{events:false},standings:true}}]});
 const v=await verifier({api:apiSimulee({ligues:[mk(1,'Ligue 1',2024),mk(2,'Ligue 2',2023),mk(3,'Coupe de la Ligue',2024)],statut:{account:{email:'x@y.z',firstname:'A'},subscription:{plan:'Free',active:true},requests:{current:3,limit_day:100}}})});
 assert.equal(v.ligue1.id,1);assert.equal(v.ligue2.id,2);assert.equal(v.ligues.length,3);assert.equal(v.compte.formule,'Free');
 assert.ok(!JSON.stringify(v).includes('x@y.z'),'aucune donnée personnelle du compte');
});

// ───── Fonction serveur ─────
const ENV={FOOT_SYNC_SECRET:'s'.repeat(40),FOOT_SYNC_ENABLED:'true',API_FOOTBALL_KEY:CLE,SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'cle-service-tres-secrete',KOKI_ENV:'test'};
const auth={authorization:'Bearer '+ENV.FOOT_SYNC_SECRET};
test('fonction serveur : POST + secret obligatoires ; désactivée = aucune requête',async()=>{
 let appels=0;const request=async()=>{appels++;return reponseHttp({});};
 for(const [req,code] of [[{method:'GET',headers:auth},405],[{method:'POST',headers:{}},401],[{method:'POST',headers:{authorization:'Bearer court'}},401]]){const r=res();await footSyncHandler({env:ENV,request})(req,r);assert.equal(r.code,code);}
 const r=res();await footSyncHandler({env:{...ENV,FOOT_SYNC_SECRET:'court'},request})({method:'POST',headers:{authorization:'Bearer court'}},r);assert.equal(r.code,401,'secret trop court refusé');
 const d=res();await footSyncHandler({env:{...ENV,FOOT_SYNC_ENABLED:'false'},request})({method:'POST',headers:auth},d);assert.equal(d.code,503);
 const s=res();await footSyncHandler({env:{...ENV,API_FOOTBALL_KEY:''},request})({method:'POST',headers:auth},s);assert.equal(s.code,503);
 const p=res();await footSyncHandler({env:{...ENV,SUPABASE_URL:'https://qsbmzzbiztfqysstepxm.supabase.co'},request})({method:'POST',headers:auth},p);assert.equal(p.code,503,'environnement test : production refusée');
 assert.equal(appels,0);assert.equal(r.h['Cache-Control'],'no-store');
});
test('fonction serveur : passage réel simulé, clés jamais renvoyées, paramètres validés',async()=>{
 const vus=[];const request=async(url,o)=>{vus.push({url,o});
  if(url.includes('/rpc/koki_foot_sync_planning'))return reponseHttp(base());
  if(url.includes('/rpc/koki_foot_sync'))return reponseHttp({statut:'ok',lus:2});
  return reponseHttp({errors:[],response:[]},{entetes:{'x-ratelimit-requests-remaining':'97'}});};
 const r=res();await footSyncHandler({env:ENV,request,maintenant:()=>NOW})({method:'POST',headers:auth,body:{mode:'passage'}},r);
 assert.equal(r.code,200);assert.ok(r.body.operations.length>=1);
 const txt=JSON.stringify(r.body);assert.ok(!txt.includes(CLE)&&!txt.includes(ENV.SUPABASE_SERVICE_ROLE_KEY));
 const rpc=vus.find(v=>v.url.includes('/rest/v1/rpc/koki_foot_sync'));assert.equal(rpc.o.headers.apikey,ENV.SUPABASE_SERVICE_ROLE_KEY);assert.equal(rpc.o.redirect,'error');
 assert.ok(vus.filter(v=>v.url.includes('api-sports.io')).every(v=>!v.url.includes(CLE)));
 for(const body of [{mode:'decouvrir',ligue:'x',saison:2024},{mode:'decouvrir',ligue:1,saison:1990},{mode:'inconnu'}]){const b=res();await footSyncHandler({env:ENV,request})({method:'POST',headers:auth,body},b);assert.equal(b.code,400);}
 const e=res();await footSyncHandler({env:ENV,request:async(url)=>url.includes('api-sports')?reponseHttp({errors:{token:'invalid '+CLE},response:[]}):reponseHttp(base())})({method:'POST',headers:auth,body:{mode:'verifier'}},e);
 assert.equal(e.code,502);assert.equal(e.body.code,'authentification');assert.ok(!JSON.stringify(e.body).includes(CLE));
});
test('isolement : aucun code du navigateur n’importe le connecteur ni ne lit la clé API-Football',()=>{
 const fichiers=[];const parcourir=d=>{for(const n of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,n.name);if(n.isDirectory())parcourir(p);else if(/\.(js|jsx|ts|html|css)$/.test(n.name))fichiers.push(p);}};
 parcourir('src');parcourir('public');fichiers.push('index.html');
 for(const p of fichiers.filter(fs.existsSync)){const t=fs.readFileSync(p,'utf8');assert.ok(!/server\/foot|API_FOOTBALL|api-sports\.io|apisports/i.test(t),p);}
 for(const p of ['server/foot/api-football.js','server/foot/synchronisation.js','api/foot-sync.js'])assert.ok(!/VITE_|import\.meta\.env/.test(fs.readFileSync(p,'utf8')),p);
 assert.ok(!/=\s*\S{8,}/.test(fs.readFileSync('.env.example','utf8').split('\n').filter(l=>/API_FOOTBALL_KEY|FOOT_SYNC_SECRET/.test(l)).join('\n')),'aucune valeur dans .env.example');
});
