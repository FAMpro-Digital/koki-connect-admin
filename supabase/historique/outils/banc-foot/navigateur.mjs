// Tests NAVIGATEUR du module Football (Chrome réel, piloté par Playwright) sur le banc LOCAL :
//  - Supabase simulé (serveur-supabase.mjs) devant la base koki_foot_banc (preparer.sh) ;
//  - site public koki-connect servi avec sa CSP réelle (vercel.json), adresse Supabase remplacée par 127.0.0.1:54321 ;
//  - écrans d'administration montés dans tests/navigateur/foot-admin.html (CSP stricte).
// Usage : node navigateur.mjs  (variables : KOKI_PUBLIC_DIR, PLAYWRIGHT_CORE, CHROME, CAPTURES)
import {createServer} from 'node:http';import {readFile,stat,mkdir} from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';
import {spawn,execFileSync} from 'node:child_process';
const ICI=path.dirname(fileURLToPath(import.meta.url)),ADMIN=path.resolve(ICI,'../../../..'),PUBLIC=path.resolve(process.env.KOKI_PUBLIC_DIR||path.join(ADMIN,'../koki-connect'));
const pw=await import(process.env.PLAYWRIGHT_CORE||'/opt/node-tools/node_modules/playwright-core/index.js');const {chromium}=pw.default||pw;
const CAPTURES=process.env.CAPTURES||path.join(ICI,'captures');await mkdir(CAPTURES,{recursive:true});
const SUPA='http://127.0.0.1:54321';
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml','.ico':'image/x-icon','.webmanifest':'application/manifest+json'};

// ───── Serveurs ─────
let drapeauFootball=true;
async function csPublique(){const v=JSON.parse(await readFile(path.join(PUBLIC,'vercel.json'),'utf8'));
 return v.headers.flatMap(h=>h.headers).find(h=>h.key==='Content-Security-Policy').value.replaceAll('https://qsbmzzbiztfqysstepxm.supabase.co',SUPA).replaceAll('wss://qsbmzzbiztfqysstepxm.supabase.co','ws://127.0.0.1:54321');}
function statique(racine,{port,csp,remplacements=()=>({})}){
 return new Promise(ok=>{const s=createServer(async(req,res)=>{try{
  const p=decodeURIComponent(new URL(req.url,'http://x').pathname),voulu=p==='/'?'/index.html':p,r=remplacements();
  if(r[voulu]){res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(r[voulu]));return;}
  const f=path.normalize(path.join(racine,voulu));if(!f.startsWith(racine)||!(await stat(f)).isFile())throw 0;
  res.writeHead(200,{'Content-Type':types[path.extname(f)]||'application/octet-stream','Cache-Control':'no-store',...(csp?{'Content-Security-Policy':await csp()}:{})});res.end(await readFile(f));
 }catch{res.writeHead(404);res.end();}}).listen(port,'127.0.0.1',()=>ok(s));});
}
const supabase=spawn(process.execPath,[path.join(ICI,'serveur-supabase.mjs')],{stdio:['ignore','pipe','inherit']});
await new Promise(ok=>supabase.stdout.once('data',ok));
process.on('exit',()=>supabase.kill());process.on('uncaughtException',e=>{console.error(e);supabase.kill();process.exit(1);});
const sitePublic=await statique(PUBLIC,{port:8091,csp:csPublique,remplacements:()=>({
 '/assets/portail/backend.json':{url:SUPA,publishableKey:'sb_publishable_banc_local',local:true},
 '/assets/business/config.json':{enabled:false,schemaVersion:2,modules:{commerce:false,transport:false,clubs:false,football:drapeauFootball}},
 '/assets/portail/environment.json':{preproduction:true,local:true}})});
const siteAdmin=await statique(ADMIN,{port:8092,csp:async()=>"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' "+SUPA+"; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"});
const panne=mode=>fetch(SUPA+'/__banc/panne',{method:'POST',body:JSON.stringify({mode})});
const sql=q=>execFileSync('sudo',['-n','-u','postgres','psql','-X','-At','-d','koki_foot_banc','-c',q],{encoding:'utf8'}).trim();

// ───── Outils de test ─────
const resultats=[];let courant='';
async function cas(nom,fn){courant=nom;const t0=Date.now();try{await fn();await panne('aucune');resultats.push({nom,ok:true,ms:Date.now()-t0});console.log('ok      '+nom);}
 catch(e){await panne('aucune');resultats.push({nom,ok:false,erreur:e.message.split('\n')[0]});console.log('ÉCHEC   '+nom+' : '+e.message.split('\n')[0]);}}
function vrai(c,m){if(!c)throw Error(m);}
const navigateur=await chromium.launch({executablePath:process.env.CHROME||'/usr/bin/google-chrome',args:['--no-sandbox']});
const MOBILE={viewport:{width:390,height:844},deviceScaleFactor:2,isMobile:true,hasTouch:true,locale:'fr-FR',timezoneId:'Africa/Dakar'};
const PETIT={...MOBILE,viewport:{width:360,height:740}};
const BUREAU={viewport:{width:1280,height:800},locale:'fr-FR',timezoneId:'America/New_York'};
async function page(ctx,{faux=true}={}){
 const c=await navigateur.newContext(ctx);c.setDefaultTimeout(8000);const p=await c.newPage();p.erreurs=[];p.csp=[];
 p.on('pageerror',e=>p.erreurs.push(e.message));p.on('console',m=>{if(m.type()==='error'){const t=m.text();(/Content Security Policy|Refused to/.test(t)?p.csp:p.erreurs).push(t);}});
 await p.addInitScript(()=>{try{localStorage.setItem('koki.bienvenue.v1','vu');}catch(_){}});
 if(faux)await p.addInitScript(()=>{
  // Realtime simulé : canal contrôlable depuis le test (le WebSocket Supabase réel n'existe pas sur le banc).
  window.__KOKI_FOOT_DEMARRAGE_MANUEL__=true;try{localStorage.setItem('koki.bienvenue.v1','vu');}catch(_){}
  window.__realtime={canaux:[],statut(s){for(const c of this.canaux)c.cb?.(s);},emettre(ev,payload){for(const c of this.canaux)c.ec[ev]?.({payload});}};
  window.__fabrique=()=>({channel:nom=>{const c={nom,ec:{},on(t,f,cb){this.ec[f.event]=cb;return this;},subscribe(cb){this.cb=cb;setTimeout(()=>cb('SUBSCRIBED'),10);return this;},unsubscribe(){}};window.__realtime.canaux.push(c);return c;}});
 });
 return p;
}
async function demarrerFoot(p){await p.waitForFunction(()=>window.KokiFoot);await p.evaluate(async()=>{KokiFoot.configurer({clientRealtime:window.__fabrique});await KokiFoot.demarrer();});}
async function sansDebordement(p,ou){const r=await p.evaluate(()=>({sw:document.documentElement.scrollWidth,w:window.innerWidth}));vrai(r.sw<=r.w+1,ou+' : débordement horizontal ('+r.sw+' > '+r.w+')');}
async function capture(p,nom){await p.screenshot({path:path.join(CAPTURES,nom+'.png'),fullPage:false});}
async function ouvrirSport(p){await p.evaluate(()=>KokiSport.accueil());await p.waitForSelector('.ft-racine');}

// ═════════════ SITE PUBLIC ═════════════
await cas('public · drapeau désactivé : aucun changement visible (Accueil, Sport)',async()=>{
 drapeauFootball=false;const p=await page(MOBILE,{faux:false});await p.goto('http://127.0.0.1:8091/');await p.waitForFunction(()=>window.KokiSport&&window.KokiFoot);
 await p.waitForTimeout(800);vrai(await p.locator('#koki-foot-direct').isHidden(),'carte Accueil affichée alors que le module est désactivé');
 vrai(!(await p.evaluate(()=>KokiFoot.visible)),'module visible sans drapeau');
 await p.evaluate(()=>KokiSport.accueil());await p.waitForSelector('.sp-onglets');const onglets=await p.locator('.sp-onglet').allTextContents();
 vrai(!onglets.some(t=>/Football/.test(t)),'onglet Football présent sans drapeau');vrai(onglets.some(t=>/Matchs/.test(t)),'onglets existants absents');
 vrai(!(await p.locator('link[href="assets/portail/foot.css"]').count()),'feuille de style chargée sans drapeau');
 await capture(p,'public-01-drapeau-desactive-sport');vrai(!p.erreurs.some(e=>/foot/i.test(e)),'erreurs : '+p.erreurs.join(' | '));
 await p.context().close();drapeauFootball=true;
});
let pub;
await cas('public · Accueil : carte « Match en direct », 2 matchs au plus, Koki d’abord',async()=>{
 pub=await page(MOBILE);await pub.goto('http://127.0.0.1:8091/');await demarrerFoot(pub);
 await pub.waitForSelector('#koki-foot-direct:not([hidden]) .ft-accueil-ligne');
 const lignes=await pub.locator('#koki-foot-direct .ft-accueil-ligne').allTextContents();
 vrai(lignes.length===2,'2 lignes attendues, '+lignes.length);vrai(/ASC Koki Ndiaye/.test(lignes[0])&&/Navétanes/.test(lignes[0]),'Koki en premier : '+lignes[0]);vrai(/Ligue 1 Sénégal/.test(lignes[1]),'Sénégal ensuite : '+lignes[1]);
 vrai(await pub.locator('#koki-direct').count()===1,'bloc « Koki en direct » d’origine toujours présent');
 await sansDebordement(pub,'Accueil 390');await pub.locator('#koki-foot-direct').scrollIntoViewIfNeeded();await capture(pub,'public-02-accueil-carte-direct');
});
await cas('public · Realtime : score mis à jour sans rechargement ; message ancien ignoré',async()=>{
 const id=sql("select id from koki_foot.matchs where lieu='Stade de Koki' and statut='En direct'");
 // Le serveur enregistre le but (révision +1) puis diffuse ; le test rejoue le message tel que la base le produit.
 sql(`update koki_foot.matchs set score_domicile=2, minute=71 where id='${id}'`);const rev=Number(sql(`select revision from koki_foot.matchs where id='${id}'`))-1;
 await pub.evaluate(([id,rev])=>window.__realtime.emettre('match',{id,revision:rev+1,statut:'En direct',minute:71,score_domicile:2,score_exterieur:0}),[id,rev]);
 await pub.waitForFunction(()=>/2\s+–\s+0/.test(document.querySelector('#koki-foot-direct .ft-accueil-ligne')?.textContent||''),null,{timeout:3000});
 await pub.evaluate(([id,rev])=>window.__realtime.emettre('match',{id,revision:rev,statut:'En direct',minute:60,score_domicile:1,score_exterieur:0}),[id,rev]);
 await pub.waitForTimeout(300);vrai(/2\s+–\s+0/.test(await pub.locator('#koki-foot-direct .ft-accueil-ligne').first().textContent()),'message ancien appliqué');
 vrai(/71/.test(await pub.locator('#koki-foot-direct .ft-accueil-ligne').first().textContent()),'minute non mise à jour');
 await capture(pub,'public-03-accueil-realtime');
});
await cas('public · sécurité Realtime : un faux message (score 9–9, révision énorme) n’impose rien ; la vraie mise à jour suivante passe',async()=>{
 const id=sql("select id from koki_foot.matchs where lieu='Stade de Koki' and statut='En direct'");
 const lu=()=>pub.locator('#koki-foot-direct .ft-accueil-ligne').first().textContent();
 await pub.evaluate(id=>window.__realtime.emettre('match',{id,revision:999999,statut:'Terminé',minute:90,score_domicile:9,score_exterieur:9}),id);
 await pub.waitForTimeout(2600);const t=await lu();
 vrai(/2\s+–\s+0/.test(t)&&!/9\s+–\s+9/.test(t),'faux score affiché : '+t);
 // Vrai but enregistré en base (révision réelle +1) puis diffusé : il doit s'afficher malgré la fausse révision.
 sql(`update koki_foot.matchs set score_domicile=3, minute=72 where id='${id}'`);const rev=Number(sql(`select revision from koki_foot.matchs where id='${id}'`));
 await pub.evaluate(([id,rev])=>window.__realtime.emettre('match',{id,revision:rev}),[id,rev]);
 await pub.waitForFunction(()=>/3\s+–\s+0/.test(document.querySelector('#koki-foot-direct .ft-accueil-ligne')?.textContent||''),null,{timeout:5000});
 sql(`update koki_foot.matchs set score_domicile=2, minute=71 where id='${id}'`);
 await pub.evaluate(([id,rev])=>window.__realtime.emettre('match',{id,revision:rev+1}),[id,rev]);
 await pub.waitForFunction(()=>/2\s+–\s+0/.test(document.querySelector('#koki-foot-direct .ft-accueil-ligne')?.textContent||''),null,{timeout:5000});
 await capture(pub,'public-03b-faux-message-realtime');
});
await cas('public · Realtime : coupure → bandeau, reconnexion → état rechargé depuis le serveur',async()=>{
 await ouvrirSport(pub);await pub.evaluate(()=>window.__realtime.statut('CHANNEL_ERROR'));
 await pub.waitForSelector('.ft-hors-ligne');await capture(pub,'public-04-sport-coupure-realtime');
 // Pendant la coupure, le score change en base (message perdu) ; la reconnexion doit le récupérer.
 sql("update koki_foot.matchs set score_exterieur=1, minute=75 where lieu='Stade de Koki' and statut='En direct'");
 // Le module se réabonne seul (attente 1 s) ; le canal simulé confirme l'abonnement.
 await pub.waitForFunction(()=>[...document.querySelectorAll('.ft-match')].some(x=>/Koki Ndiaye/.test(x.textContent)&&/75/.test(x.textContent)),null,{timeout:8000});
 vrai(!(await pub.locator('.ft-hors-ligne').count()),'bandeau de coupure resté affiché');
});
await cas('public · Sport : onglet Football par défaut, six vues, filtres de portée',async()=>{
 await ouvrirSport(pub);const onglets=await pub.locator('.sp-onglet').allTextContents();vrai(/Football/.test(onglets[0]),'Football en premier : '+onglets.join(','));
 vrai((await pub.locator('.sp-onglet[aria-selected="true"]').textContent()).includes('Football'),'Football non sélectionné');
 const vues=await pub.locator('.ft-vue').allTextContents();vrai(vues.length===6,'6 vues attendues : '+vues.join(','));
 await capture(pub,'public-05-sport-en-direct');
 await pub.locator('.ft-filtre',{hasText:'Sénégal'}).click();await pub.waitForTimeout(150);
 const comps=await pub.locator('.ft-match .ft-comp').allTextContents();vrai(comps.length>0&&comps.every(c=>/Ligue 1 Sénégal/.test(c)),'filtre Sénégal : '+comps.join(','));
 await pub.locator('.ft-filtre',{hasText:'Tout'}).click();
 for(const [v,attendu] of [['Aujourd’hui',/Aujourd’hui à Koki/],['Résultats',/Résultats des 7 derniers jours/]]){await pub.locator('.ft-vue',{hasText:v}).click();await pub.waitForFunction(r=>new RegExp(r).test(document.querySelector('.ft-contenu')?.textContent),attendu.source);await capture(pub,'public-06-sport-'+(v==='Résultats'?'resultats':'aujourdhui'));}
 vrai(/a\.p\.\s·\st\.a\.b\.\s1–2/.test(await pub.locator('.ft-contenu').textContent()),'résultat de coupe : a.p. et t.a.b. affichés séparément');
 await pub.locator('.ft-vue',{hasText:'Calendrier'}).click();await pub.waitForSelector('.ft-select');vrai(!(await pub.locator('.ft-select').textContent()).includes('2026 2026'),'saison répétée dans le nom');await pub.waitForSelector('.ft-jour');await capture(pub,'public-07-sport-calendrier');
 await pub.locator('.ft-vue',{hasText:'Compétitions'}).click();await pub.waitForSelector('.ft-competition');vrai((await pub.locator('.ft-competition').count())===4,'4 compétitions publiées');await capture(pub,'public-08-sport-competitions');
 await pub.locator('.ft-vue',{hasText:'Classements'}).click();await pub.waitForSelector('.ft-table tbody tr');
 const t1=await pub.locator('.ft-table tbody tr').allTextContents();vrai(t1.length===4&&/ASC Darou/.test(t1[0]),'classement calculé Navétanes : '+t1[0]);
 await pub.locator('.ft-select').selectOption({label:'Ligue 1 Sénégal 2025'});await pub.waitForFunction(()=>/ASC Jaraaf/.test(document.querySelector('.ft-table tbody tr')?.textContent));
 vrai(/23/.test(await pub.locator('.ft-table tbody tr').first().textContent()),'classement officiel importé');vrai(/Classement officiel fourni par la source/.test(await pub.locator('.ft-note').textContent()),'source du classement');
 await capture(pub,'public-09-sport-classement');await sansDebordement(pub,'Sport 390');
});
await cas('public · fiche de match : événements par période, scores distincts, source',async()=>{
 await pub.locator('.ft-vue',{hasText:'Résultats'}).click();await pub.locator('.ft-match',{hasText:'Santhiou'}).click();await pub.waitForSelector('.ft-evenements');
 const per=await pub.locator('.ft-periode').allTextContents();vrai(per.join('|')==='2e mi-temps|2e prolongation|Tirs au but','périodes : '+per.join('|'));
 const scores=await pub.locator('.ft-scores').textContent();vrai(/Temps réglementaire\s*1 – 1/.test(scores)&&/Prolongation\s*1 – 1/.test(scores)&&/Tirs au but\s*1 – 2/.test(scores),'scores distincts : '+scores);
 vrai(/90\+4/.test(await pub.locator('.ft-evts').first().textContent()),'temps additionnel affiché');
 vrai(/Résultat saisi par Koki Connect/.test(await pub.locator('.ft-fraicheur').first().textContent()),'source affichée');
 await capture(pub,'public-10-fiche-match-tab');await pub.evaluate(()=>window.scrollTo(0,document.body.scrollHeight));await capture(pub,'public-11-fiche-match-evenements');
 await sansDebordement(pub,'Fiche 390');
});
await cas('public · données anciennes signalées (source du fournisseur en panne)',async()=>{
 sql("update koki_foot.vus_api set vu_le=now()-interval '20 minutes'; update koki_foot.etat_fournisseurs set derniere_erreur=now(), derniere_tentative=now(), pause_jusqu_a=now()+interval '5 minutes'");
 await pub.evaluate(()=>KokiFoot.detail(document.querySelector('[data-match]')?.dataset.match));
 const idApi=sql("select id from koki_foot.matchs where ref_fournisseur='F1'");await pub.evaluate(id=>KokiFoot.detail(id),idApi);await pub.waitForSelector('.ft-fraicheur');
 const t=await pub.locator('.ft-fraicheur').textContent();vrai(/données possiblement anciennes/.test(t)&&/API-Football/.test(t),'avertissement : '+t);
 await capture(pub,'public-12-fiche-donnees-anciennes');
});
await cas('public · erreurs réseau : 503 puis coupure → message et « Réessayer » ; retour → données',async()=>{
 await ouvrirSport(pub);await pub.locator('.ft-vue',{hasText:'Compétitions'}).click();await pub.waitForSelector('.ft-competition');
 await panne('503');await pub.evaluate(()=>KokiFoot.detail('00000000-0000-4000-8000-000000000000'));await pub.waitForSelector('.ft-erreur');
 vrai(/Connexion indisponible/.test(await pub.locator('.ft-erreur').textContent()),'message 503');await capture(pub,'public-13-erreur-reseau');
 await panne('coupure');await pub.locator('.ft-erreur button').click();await pub.waitForSelector('.ft-erreur');
 await panne('aucune');const id=sql("select id from koki_foot.matchs where ref_fournisseur='F1'");await pub.evaluate(id=>KokiFoot.detail(id),id);await pub.waitForSelector('.ft-tableau');
 vrai(!pub.erreurs.some(e=>/Uncaught|TypeError/.test(e)),'exception JavaScript : '+pub.erreurs.join(' | '));
});
await cas('public · CSP réelle respectée (aucune violation)',async()=>{vrai(pub.csp.length===0,'violations CSP : '+pub.csp.join(' | '));});
await cas('public · responsive 360 px et bureau (fuseau de l’appareil différent)',async()=>{
 const p=await page(PETIT);await p.goto('http://127.0.0.1:8091/');await demarrerFoot(p);await p.waitForSelector('#koki-foot-direct:not([hidden])');await sansDebordement(p,'Accueil 360');
 await ouvrirSport(p);await sansDebordement(p,'Sport 360');await p.locator('.ft-vue',{hasText:'Classements'}).click();await p.waitForSelector('.ft-table');await sansDebordement(p,'Classement 360');await capture(p,'public-14-classement-360px');await p.context().close();
 const d=await page(BUREAU);await d.goto('http://127.0.0.1:8091/');await demarrerFoot(d);await ouvrirSport(d);await d.locator('.ft-vue',{hasText:'Aujourd’hui'}).click();
 await d.waitForSelector('.ft-match');const txt=await d.locator('.ft-contenu').textContent();vrai(/22:00/.test(txt),'heure de Koki (22:00) affichée même sur un appareil à New York : '+txt.slice(0,200));
 await capture(d,'public-15-bureau-new-york');await d.context().close();
});

// ═════════════ ADMINISTRATION ═════════════
let adm;
const urlAdmin=(r='editor')=>'http://127.0.0.1:8092/tests/navigateur/foot-admin.html?role='+r;
await cas('admin · liste des matchs (téléphone) : en jeu, badges verrou/conflit',async()=>{
 adm=await page(MOBILE,{faux:false});await adm.goto(urlAdmin());await adm.waitForSelector('.fa-ligne');
 const titres=await adm.locator('.fa-titre').allTextContents();vrai(titres[0]==='● En jeu','groupe En jeu en premier');
 vrai(await adm.locator('.fa-badge-alerte',{hasText:'conflit'}).count()>=1,'badge de conflit');vrai(await adm.locator('.fa-badge-verrou').count()>=1,'badge de verrou');
 await sansDebordement(adm,'Admin liste');await capture(adm,'admin-01-liste-matchs');
});
await cas('admin · créer compétition, deux équipes, programmer un match',async()=>{
 await adm.locator('.fa-onglet',{hasText:'Compétitions'}).click();await adm.getByLabel('Nom').fill('Tournoi de la Tabaski');await adm.getByLabel('Type').selectOption('Tournoi');
 await adm.locator('[data-action="competition"]').click();await adm.waitForSelector('.fa-avis-succes');await capture(adm,'admin-02-competition');
 await adm.locator('.fa-onglet',{hasText:'Équipes'}).click();
 for(const nom of ['ASC Keur Mbaye','ASC Ndiambour']){await adm.getByLabel('Nom').fill(nom);await adm.locator('[data-action="equipe"]').click();await adm.waitForFunction(n=>[...document.querySelectorAll('.fa-ligne-fixe')].some(x=>x.textContent.includes(n)),nom);}
 await capture(adm,'admin-03-equipes');
 await adm.locator('.fa-onglet',{hasText:'Programmer'}).click();await adm.getByLabel('Compétition').selectOption({label:'Tournoi de la Tabaski'});
 await adm.getByLabel('Équipe à domicile').selectOption({label:'ASC Keur Mbaye'});await adm.getByLabel('Équipe à l’extérieur').selectOption({label:'ASC Ndiambour'});
 const demain=new Date(Date.now()+864e5).toISOString().slice(0,10);await adm.getByLabel('Date et heure (heure de Koki)').fill(demain+'T17:30');await adm.getByLabel('Lieu').fill('Terrain municipal');
 await capture(adm,'admin-04-programmer');await adm.locator('[data-action="programmer"]').click();
 await adm.waitForFunction(()=>/Keur Mbaye/.test(document.querySelector('.fa-tableau')?.textContent||''));
 vrai(sql("select to_char(date_match at time zone 'Africa/Dakar','HH24:MI')||'|'||lieu from koki_foot.matchs m join koki_foot.equipes e on e.id=m.domicile_id where e.nom='ASC Keur Mbaye'")==='17:30|Terrain municipal','heure de Koki et lieu enregistrés');
});
await cas('admin · saisie rapide : coup d’envoi, but par période, double appui = un seul événement',async()=>{
 await adm.locator('[data-action^="statut-Coup"]').click();await adm.waitForFunction(()=>/En direct/.test(document.querySelector('.fa-tableau')?.textContent||''));
 await adm.getByLabel('Période').selectOption('mi_temps_1');await adm.getByLabel('Minute',{exact:true}).first().fill('12');await adm.getByLabel('Joueur').fill('Pape Ndiaye');
 const btn=adm.locator('[data-action^="evenement-"]').first();await btn.dblclick();await adm.waitForSelector('.fa-avis-succes');await adm.waitForTimeout(400);
 const n=sql("select count(*) from koki_foot.evenements v join koki_foot.matchs m on m.id=v.match_id join koki_foot.equipes e on e.id=m.domicile_id where e.nom='ASC Keur Mbaye'");
 vrai(n==='1','double appui : '+n+' événement(s)');vrai(/1 – 0/.test(await adm.locator('.fa-score').textContent()),'score 1–0');
 await adm.waitForSelector('.fa-evt');vrai(/1re mi-temps/i.test(await adm.locator('.fa-periode').first().textContent()),'événement rangé par période');
 await capture(adm,'admin-05-saisie-rapide');await sansDebordement(adm,'Admin match');
});
await cas('admin · conflit de révision : modification depuis un autre appareil → message et « Recharger »',async()=>{
 const id=await adm.evaluate(()=>window.__banc.app.etat.matchId);
 await fetch(SUPA+'/rest/v1/rpc/koki_foot_admin',{method:'POST',headers:{'Content-Type':'application/json','X-Banc-Role':'editor'},body:JSON.stringify({command:'score',input:{id,revision:Number(sql(`select revision from koki_foot.matchs where id='${id}'`)),statut:'En direct',minute:30}})});
 await adm.locator('[data-action="statut-Mi-temps"]').click();await adm.waitForSelector('.fa-avis-revision');await capture(adm,'admin-06-conflit-revision');
 await adm.locator('.fa-avis-revision [data-action="recharger"]').click();await adm.waitForFunction(()=>/30’/.test(document.querySelector('.fa-tableau')?.textContent||''));
});
await cas('admin · correction d’un match terminé : motif obligatoire, puis enregistrée et journalisée',async()=>{
 if(await adm.locator('.fa-lien').count())await adm.locator('.fa-lien').click();await adm.locator('.fa-ligne',{hasText:'ASC Darou'}).filter({hasText:'Terminé'}).first().click();await adm.waitForSelector('.fa-tableau');
 await adm.getByLabel('Réglementaire ASC Darou').fill('3');await adm.locator('[data-action="score"]').click();await adm.waitForSelector('.fa-avis-erreur');
 vrai(/Motif/.test(await adm.locator('.fa-avis').textContent()),'motif exigé');await capture(adm,'admin-07-motif-exige');
 await adm.getByLabel('Motif').fill('Feuille de match officielle');await adm.locator('[data-action="score"]').click();await adm.waitForSelector('.fa-avis-succes');
 vrai(sql("select count(*) from koki_foot.corrections where motif='Feuille de match officielle'")==='1','correction journalisée');
});
await cas('admin · annulation d’un événement avec motif',async()=>{
 await adm.locator('.fa-lien').click();await adm.locator('.fa-ligne',{hasText:'Keur Mbaye'}).click();await adm.waitForSelector('.fa-evt');
 await adm.getByLabel('Motif').fill('But refusé : hors-jeu');await adm.locator('.fa-evt [data-action^="annuler-"]').first().click();await adm.waitForSelector('.fa-avis-succes');
 vrai(/0 – 0/.test(await adm.locator('.fa-score').textContent()),'score revenu à 0–0');await capture(adm,'admin-08-annulation-evenement');
});
await cas('admin · conflits API : affichés puis résolus avec motif',async()=>{
 await adm.locator('.fa-lien').click();await adm.locator('.fa-onglet',{hasText:'Conflits'}).click();await adm.waitForSelector('.fa-conflit');await capture(adm,'admin-09-conflits');
 const txt=await adm.locator('.fa-conflit').first().textContent();vrai(/Valeur locale \(publiée\) : 2–1/.test(txt)&&/fournisseur : 1–1/.test(txt)&&!/null/.test(txt),'valeurs lisibles : '+txt);
 const c=adm.locator('.fa-conflit').first();await c.locator('[data-action^="garder-"]').click();await adm.waitForSelector('.fa-avis-erreur');
 await c.getByLabel('Motif').fill('Feuille officielle confirmée par la ligue');await c.locator('[data-action^="garder-"]').click();await adm.waitForSelector('.fa-avis-succes');
 vrai(sql("select count(*) from koki_foot.conflits where not resolu")==='0','conflit résolu');
});
await cas('admin · sources : état du fournisseur ; réglage du seuil réservé au superadmin',async()=>{
 await adm.locator('.fa-onglet',{hasText:'Sources'}).click();await adm.waitForSelector('.fa-conflit');vrai(!(await adm.locator('[data-action^="seuil-"]').count()),'éditeur : réglage visible');
 const s=await page(MOBILE,{faux:false});await s.goto(urlAdmin('superadmin'));await s.locator('.fa-onglet',{hasText:'Sources'}).click();await s.waitForSelector('[data-action^="seuil-"]');
 await s.getByLabel('Seuil « données anciennes » (secondes)').fill('600');await s.locator('[data-action^="seuil-"]').click();await s.waitForSelector('.fa-avis-succes');
 vrai(sql("select seuil_ancien_s from koki_foot.etat_fournisseurs where fournisseur='api-football'")==='600','seuil enregistré');await capture(s,'admin-10-sources-superadmin');await s.context().close();
});
await cas('admin · erreurs réseau (503, coupure) : message clair, aucune donnée perdue',async()=>{
 await adm.locator('.fa-onglet',{hasText:'Matchs'}).click();await panne('503');await adm.locator('[data-action="actualiser"]').click();await adm.waitForSelector('.fa-avis:not([hidden])');
 vrai(/Connexion impossible|indisponible/i.test(await adm.locator('.fa-avis').textContent()),'message réseau : '+await adm.locator('.fa-avis').textContent());await capture(adm,'admin-11-erreur-reseau');
 await panne('coupure');await adm.locator('[data-action="actualiser"]').click();await adm.waitForSelector('.fa-avis-reseau');await panne('aucune');
 await adm.locator('[data-action="actualiser"]').click();await adm.waitForSelector('.fa-ligne');
});
await cas('admin · utilisateur non habilité : refus clair',async()=>{
 const h=await page(MOBILE,{faux:false});await h.goto(urlAdmin('habitant'));await h.waitForSelector('.fa-avis:not([hidden])');vrai(/non autorisée/.test(await h.locator('.fa-avis').textContent()),'refus : '+await h.locator('.fa-avis').textContent());
 await capture(h,'admin-12-non-habilite');await h.context().close();
});
await cas('admin · CSP stricte respectée, aucune exception',async()=>{vrai(adm.csp.length===0,'CSP : '+adm.csp.join(' | '));vrai(!adm.erreurs.some(e=>/Uncaught|TypeError|ReferenceError/.test(e)),'exceptions : '+adm.erreurs.join(' | '));});

await navigateur.close();sitePublic.close();siteAdmin.close();supabase.kill();
const ko=resultats.filter(r=>!r.ok);console.log(`\nNavigateur : ${resultats.length-ko.length}/${resultats.length} réussis · captures : ${CAPTURES}`);
process.exit(ko.length?1:0);
