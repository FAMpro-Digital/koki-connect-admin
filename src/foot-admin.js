// Module Football — écrans d'administration (téléphone d'abord). Toutes les opérations passent par
// public.koki_foot_admin via creerClientFoot ; aucun accès direct aux tables. PAS ENCORE BRANCHÉ sur la
// navigation de l'administration (voir docs/football-interfaces.md pour le branchement proposé).
// Styles : src/foot-admin.css (CSP style-src 'self' : aucun style en ligne, seulement les couleurs d'équipe via CSSOM).
import {creerClientFoot,PERIODES,LIBELLES_PERIODES,TYPES_JEU,TYPES_SEANCE,STATUTS,VERROUS,motifRequis,versISO} from './foot-admin-client.js';

const TZ='Africa/Dakar';
const EN_JEU=['En direct','Mi-temps','Prolongations','Tirs au but','Interrompu'];
const LIB_TYPES={but:'⚽ But',but_csc:'⚽ But c.s.c.',penalty:'⚽ Penalty',penalty_manque:'❌ Penalty manqué',carton_jaune:'🟨 Jaune',carton_rouge:'🟥 Rouge',remplacement:'🔁 Remplacement',tab_reussi:'✅ T.a.b. réussi',tab_manque:'❌ T.a.b. manqué'};
const heure=iso=>new Date(iso).toLocaleString('fr-FR',{timeZone:TZ,weekday:'short',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'});
const versChamp=iso=>iso?new Date(iso).toISOString().slice(0,16):''; // Africa/Dakar = UTC

// Période proposée par défaut selon le statut du match (toujours modifiable par l'administrateur).
export function periodeParDefaut(m){if(m.statut==='Prolongations')return 'prolongation_1';if(m.statut==='Tirs au but')return 'tirs_au_but';return (m.minute??0)>45||m.statut==='Mi-temps'?'mi_temps_2':'mi_temps_1';}
// Valeur d'un conflit en clair : score [réglementaire, prolongation, tirs au but], statut, programmation, événement.
export function valeurConflit(champ,v){
 if(champ==='score'&&Array.isArray(v)){const [a,b,c,d,e,f]=v;if(a===null)return 'pas de score';return a+'–'+b+(c!==null?' · prolongation '+c+'–'+d:'')+(e!==null?' · tirs au but '+e+'–'+f:'');}
 if(champ==='programmation'&&v&&typeof v==='object')return [v.date_match?new Date(v.date_match).toLocaleString('fr-FR',{timeZone:TZ,weekday:'short',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}):'date inconnue',v.lieu||'lieu non précisé'].join(' · ');
 if(champ==='evenements'&&v&&typeof v==='object'&&v.type)return (LIB_TYPES[v.type]||v.type)+(v.minute!=null?' '+v.minute+'’':'')+(v.joueur?' · '+v.joueur:'');
 return typeof v==='string'?v:JSON.stringify(v);
}
// Message lisible pour les erreurs du serveur.
export function messageErreur(e){const t=String(e?.message||e||'Erreur inconnue');
 if(/Modifié entre-temps/.test(t))return {type:'revision',texte:'Ce match a été modifié sur un autre appareil. Rechargez avant de recommencer.'};
 if(/double authentification|permission denied/i.test(t))return {type:'droits',texte:'Action non autorisée : vérifiez votre rôle et votre double authentification.'};
 if(/Failed to fetch|NetworkError|Connexion|réseau|fetch|ECONN|503|502|504|indisponible/i.test(t))return {type:'reseau',texte:'Connexion impossible. Vérifiez le réseau puis réessayez.'};
 return {type:'erreur',texte:t};}

export function monterFootAdmin(racine,{appel,role='editor',maintenant=()=>Date.now()}){
 const api=creerClientFoot(appel);
 const etat={donnees:null,vue:'matchs',matchId:null,enCours:new Set(),message:null};
 const n=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined&&text!==null)e.textContent=text;if(cls)e.className=cls;return e;};
 const champ=(label,el)=>{const l=n('label',undefined,'fa-champ');l.append(n('span',label),el);return l;};
 const entree=(type,valeur='',attrs={})=>{const e=n('input');e.type=type;e.value=valeur??'';for(const [k,v] of Object.entries(attrs))e.setAttribute(k,v);return e;};
 const choix=(options,valeur)=>{const s=n('select');for(const o of options){const [v,l]=Array.isArray(o)?o:[o,o];const x=n('option',l);x.value=v;s.append(x);}if(valeur!==undefined)s.value=valeur;return s;};
 // Bouton protégé : une seule exécution à la fois (anti double soumission), état « en cours » visible.
 function action(libelle,cle,fn,cls='fa-bouton'){const x=n('button',libelle,cls);x.type='button';x.dataset.action=cle;
  x.onclick=async()=>{if(etat.enCours.has(cle))return;etat.enCours.add(cle);x.disabled=true;x.setAttribute('aria-busy','true');
   try{await fn();}catch(e){afficherErreur(e);}finally{etat.enCours.delete(cle);if(x.isConnected){x.disabled=false;x.removeAttribute('aria-busy');}}};return x;}
 function avis(type,texte){etat.message={type,texte};const z=racine.querySelector('.fa-avis');if(z)remplirAvis(z);}
 function remplirAvis(z){z.replaceChildren();const m=etat.message;if(!m){z.hidden=true;return;}z.hidden=false;z.className='fa-avis fa-avis-'+m.type;z.setAttribute('role',m.type==='succes'?'status':'alert');
  z.append(n('span',m.texte));if(m.type==='revision')z.append(action('Recharger','recharger',async()=>{etat.message=null;await charger();}));}
 function afficherErreur(e){const m=messageErreur(e);avis(m.type,m.texte);}
 async function charger(){rendreChargement();try{etat.donnees=await api.etat();rendre();}catch(e){etat.donnees=null;rendre();afficherErreur(e);}}
 function rendreChargement(){racine.replaceChildren(n('p','Chargement…','fa-chargement'));racine.firstChild.setAttribute('role','status');}
 const match=id=>etat.donnees?.matchs.find(m=>m.id===id);
 async function rafraichir(id){etat.donnees=await api.etat();if(id)etat.matchId=id;rendre();}

 function entete(){
  const h=n('div',undefined,'fa-entete');h.append(n('h1','⚽ Football'));
  const nav=n('nav',undefined,'fa-onglets');
  for(const [k,l] of [['matchs','Matchs'],['nouveau','Programmer'],['competitions','Compétitions'],['equipes','Équipes'],['conflits','Conflits'+(etat.donnees?.conflits_ouverts?' ('+etat.donnees.conflits_ouverts+')':'')],['sources','Sources']]){
   const x=n('button',l,'fa-onglet');x.type='button';x.setAttribute('aria-current',String(etat.vue===k&&!etat.matchId));x.onclick=()=>{etat.vue=k;etat.matchId=null;etat.message=null;rendre();};nav.append(x);}
  if(!navigator.onLine){const o=n('p','Hors ligne : les modifications seront refusées jusqu’au retour du réseau.','fa-hors-ligne');o.setAttribute('role','status');h.append(o);}
  h.append(nav);return h;
 }
 function rendre(){
  const avisZone=n('div',undefined,'fa-avis');avisZone.hidden=true;
  const corps=n('main',undefined,'fa-corps');racine.replaceChildren(entete(),avisZone,corps);remplirAvis(avisZone);
  if(!etat.donnees){corps.append(n('p','Données indisponibles.','fa-vide'),action('Réessayer','recharger',charger));return;}
  if(etat.matchId&&match(etat.matchId)){ecranMatch(corps,match(etat.matchId));return;}
  ({matchs:ecranListe,nouveau:ecranProgrammer,competitions:ecranCompetitions,equipes:ecranEquipes,conflits:ecranConflits,sources:ecranSources}[etat.vue]||ecranListe)(corps);
 }

 // ───── Liste des matchs ─────
 function badges(m){const z=n('span',undefined,'fa-badges');
  if(m.source==='api')z.append(n('span','Importé','fa-badge'));
  const v=m.verrous||{};const actifs=Object.entries(v).filter(([k,x])=>x&&k!=='global').map(([k])=>k);if(actifs.length||v.global)z.append(n('span','🔒 '+(actifs.join(', ')||'global'),'fa-badge fa-badge-verrou'));
  if(m.conflits)z.append(n('span','⚠ '+m.conflits+' conflit'+(m.conflits>1?'s':''),'fa-badge fa-badge-alerte'));
  if(m.coherence?.etat==='incoherent')z.append(n('span','Buts ≠ score','fa-badge fa-badge-alerte'));
  if(m.fraicheur?.etat==='ancien')z.append(n('span','Données anciennes','fa-badge fa-badge-alerte'));
  if(!m.publie)z.append(n('span','Non publié','fa-badge'));return z;}
 function ligneMatch(m){const x=n('button',undefined,'fa-ligne'+(EN_JEU.includes(m.statut)?' fa-ligne-direct':''));x.type='button';x.dataset.match=m.id;
  const sc=Number.isInteger(m.score_domicile)?m.score_domicile+(m.pro_domicile??0)+' – '+(m.score_exterieur+(m.pro_exterieur??0)):'–';
  x.append(n('strong',m.domicile.nom+'  '+sc+'  '+m.exterieur.nom),n('span',[m.statut+(Number.isInteger(m.minute)?' '+m.minute+'’':''),m.competition.nom,heure(m.date_match)].join(' · '),'fa-sous'),badges(m));
  x.onclick=()=>{etat.matchId=m.id;etat.message=null;rendre();};return x;}
 function ecranListe(corps){
  const ms=etat.donnees.matchs,now=maintenant(),jour=d=>new Date(d).toLocaleDateString('en-CA',{timeZone:TZ});const auj=jour(now);
  const groupes=[['● En jeu',ms.filter(m=>EN_JEU.includes(m.statut))],["Aujourd’hui",ms.filter(m=>!EN_JEU.includes(m.statut)&&jour(m.date_match)===auj)],
   ['À venir',ms.filter(m=>!EN_JEU.includes(m.statut)&&Date.parse(m.date_match)>now&&jour(m.date_match)!==auj)],['Récents',ms.filter(m=>!EN_JEU.includes(m.statut)&&Date.parse(m.date_match)<=now&&jour(m.date_match)!==auj).reverse()]];
  corps.append(action('↻ Actualiser','actualiser',()=>rafraichir()));
  let total=0;for(const [t,xs] of groupes){if(!xs.length)continue;total+=xs.length;corps.append(n('h2',t,'fa-titre'));const l=n('div',undefined,'fa-liste');l.append(...xs.map(ligneMatch));corps.append(l);}
  if(!total)corps.append(n('p','Aucun match sur la période. Programmez-en un dans « Programmer ».','fa-vide'));
 }

 // ───── Écran d'un match : saisie rapide ─────
 function ecranMatch(corps,m){
  const retour=n('button','← Matchs','fa-lien');retour.type='button';retour.onclick=()=>{etat.matchId=null;etat.message=null;rendre();};corps.append(retour);
  const tete=n('section',undefined,'fa-tableau');tete.append(n('p',m.competition.nom+' · '+heure(m.date_match)+(m.lieu?' · '+m.lieu:''),'fa-sous'));
  const face=n('div',undefined,'fa-face');const sc=(a,b)=>Number.isInteger(a)?String(a+(b??0)):'–';
  face.append(n('strong',m.domicile.nom),n('span',sc(m.score_domicile,m.pro_domicile)+' – '+sc(m.score_exterieur,m.pro_exterieur),'fa-score'),n('strong',m.exterieur.nom));tete.append(face);
  const det=[m.statut+(Number.isInteger(m.minute)?' · '+m.minute+'’':''),Number.isInteger(m.pro_domicile)?'Réglementaire '+m.score_domicile+'–'+m.score_exterieur+' · Prolongation '+m.pro_domicile+'–'+m.pro_exterieur:null,Number.isInteger(m.tab_domicile)?'Tirs au but '+m.tab_domicile+'–'+m.tab_exterieur:null].filter(Boolean).join(' · ');
  tete.append(n('p',det,'fa-sous'),badges(m));
  const f=m.fraicheur||{};tete.append(n('p',m.source==='manuel'?'Saisie Koki Connect':'Source '+(f.fournisseur||'API')+' · état '+(f.etat_source||'?')+(f.derniere_actualisation?' · actualisé '+heure(f.derniere_actualisation):''),'fa-sous'));
  corps.append(tete);
  const motif=entree('text','',{maxlength:'300',placeholder:'Motif (obligatoire pour une correction)','aria-label':'Motif'});motif.className='fa-motif';
  const besoinMotif=m.source==='api'||m.statut==='Terminé';
  const m2=()=>motif.value.trim()||undefined;
  // Statut et minute.
  const st=n('section',undefined,'fa-bloc');st.append(n('h2','Statut','fa-titre'));
  const minute=entree('number',m.minute??'',{min:'0',max:'150',inputmode:'numeric','aria-label':'Minute'});
  const grille=n('div',undefined,'fa-grille');
  for(const [lib,s] of [['Coup d’envoi','En direct'],['Mi-temps','Mi-temps'],['2e période','En direct'],['Prolongations','Prolongations'],['Tirs au but','Tirs au but'],['Fin','Terminé'],['Interrompu','Interrompu'],['Reporté','Reporté']]){
   if(['Prolongations','Tirs au but'].includes(s)&&m.competition.type==='Championnat')continue;
   grille.append(action(lib,'statut-'+lib,async()=>{const minuteVal=lib==='2e période'?46:lib==='Prolongations'?91:minute.value;
    const r=await api.score(m,{statut:s,minute:EN_JEU.includes(s)?minuteVal:undefined,score_domicile:m.score_domicile,score_exterieur:m.score_exterieur,pro_domicile:m.pro_domicile??undefined,pro_exterieur:m.pro_exterieur??undefined,tab_domicile:m.tab_domicile??undefined,tab_exterieur:m.tab_exterieur??undefined,motif:m2()});
    await rafraichir(m.id);avis('succes','Statut enregistré : '+r.statut);},'fa-bouton fa-bouton-statut'+(m.statut===s?' fa-actif':'')));}
  st.append(grille,champ('Minute',minute),action('Enregistrer la minute','minute',async()=>{await api.score(m,{statut:m.statut,minute:minute.value,motif:m2()});await rafraichir(m.id);avis('succes','Minute enregistrée');}));
  corps.append(st);
  // Ajout rapide d'un événement : période explicite, équipe, joueur.
  const ev=n('section',undefined,'fa-bloc');ev.append(n('h2','Ajouter un événement','fa-titre'));
  const periode=choix(PERIODES.filter(p=>m.competition.type!=='Championnat'||p.startsWith('mi_temps')).map(p=>[p,LIBELLES_PERIODES[p]]),periodeParDefaut(m));
  const type=choix([],undefined);const majTypes=()=>{const ts=periode.value==='tirs_au_but'?TYPES_SEANCE:TYPES_JEU;type.replaceChildren(...ts.map(t=>{const o=n('option',LIB_TYPES[t]);o.value=t;return o;}));};majTypes();periode.onchange=majTypes;
  const evMin=entree('number',m.minute??'',{min:'0',max:'150',inputmode:'numeric'}),evAdd=entree('number','',{min:'0',max:'30',inputmode:'numeric',placeholder:'+'});
  const joueur=entree('text','',{maxlength:'80',autocomplete:'off'});
  ev.append(champ('Période',periode),champ('Type',type),champ('Minute',evMin),champ('Temps additionnel',evAdd),champ('Joueur',joueur));
  const eqs=n('div',undefined,'fa-grille fa-grille-2');
  for(const e of [m.domicile,m.exterieur])eqs.append(action('+ '+e.nom,'evenement-'+e.id,async()=>{
   const r=await api.ajouterEvenement(m,{type:type.value,periode:periode.value,minute:evMin.value,minute_add:evAdd.value,equipe_id:e.id,joueur:joueur.value,motif:m2()});
   await rafraichir(m.id);avis('succes',LIB_TYPES[type.value]+' enregistré'+(r.match.coherence?.etat==='incoherent'?' — attention : buts et score différents':''));},'fa-bouton fa-bouton-equipe'));
  ev.append(eqs);corps.append(ev);
  // Correction directe du score (réglementaire, prolongation, tirs au but distincts).
  const cs=n('section',undefined,'fa-bloc');cs.append(n('h2','Corriger le score','fa-titre'));
  const z={};const ligne=(lib,cle)=>{const l=n('div',undefined,'fa-score-ligne');l.append(n('span',lib));for(const c of ['domicile','exterieur']){z[cle+'_'+c]=entree('number',m[cle+'_'+c]??'',{min:'0',max:'99',inputmode:'numeric','aria-label':lib+' '+(c==='domicile'?m.domicile.nom:m.exterieur.nom)});l.append(z[cle+'_'+c]);}cs.append(l);};
  ligne('Réglementaire','score');if(m.competition.type!=='Championnat'){ligne('Prolongation','pro');ligne('Tirs au but','tab');}
  cs.append(action('Enregistrer le score','score',async()=>{const v={statut:m.statut,motif:m2()};for(const [k,e] of Object.entries(z))if(e.value!=='')v[k]=e.value;
   if(motifRequis(m,{scoreChange:true})&&!m2())throw Error('Motif de la correction requis.');await api.score(m,v);await rafraichir(m.id);avis('succes','Score enregistré');}));
  corps.append(cs);
  corps.append(champ(besoinMotif?'Motif (obligatoire : match importé ou terminé)':'Motif (facultatif)',motif));
  // Événements par période, annulation avec motif.
  const liste=n('section',undefined,'fa-bloc');liste.append(n('h2','Événements','fa-titre'));corps.append(liste);
  api.evenements(m.id).then(evs=>{if(!evs.length){liste.append(n('p','Aucun événement.','fa-vide'));return;}
   for(const p of PERIODES){const xs=evs.filter(e=>e.periode===p);if(!xs.length)continue;liste.append(n('h3',LIBELLES_PERIODES[p],'fa-periode'));
    for(const e of xs){const l=n('div',undefined,'fa-evt');l.dataset.evenement=e.id;l.append(n('span',(e.minute??'')+(e.minute_add?'+'+e.minute_add:'')+(e.minute!==null?'’':'')),n('span',LIB_TYPES[e.type]||e.type),n('span',(e.equipe_id===m.domicile.id?m.domicile.nom:m.exterieur.nom)+(e.joueur?' · '+e.joueur:'')),n('span',e.source==='api'?'API':'','fa-badge'));
     l.append(action('Annuler','annuler-'+e.id,async()=>{if(!m2())throw Error('Indiquez le motif de l’annulation (champ « Motif »).');await api.retirerEvenement(e.id,m2());await rafraichir(m.id);avis('succes','Événement annulé');},'fa-bouton fa-bouton-danger'));liste.append(l);}}
  }).catch(afficherErreur);
  // Programmation et publication.
  const pg=n('section',undefined,'fa-bloc');pg.append(n('h2','Programmation','fa-titre'));
  const date=entree('datetime-local',versChamp(m.date_match)),lieu=entree('text',m.lieu||'',{maxlength:'120'});
  pg.append(champ('Date et heure (heure de Koki)',date),champ('Lieu',lieu),action('Enregistrer la programmation','programmation',async()=>{
   await api.corrigerProgrammation(m,{date_local:date.value,lieu:lieu.value,motif:m2()});await rafraichir(m.id);avis('succes','Programmation enregistrée');}));
  pg.append(action(m.publie?'Dépublier':'Publier','publier',async()=>{await appel('enregistrer_match',{id:m.id,revision:m.revision,publie:!m.publie});await rafraichir(m.id);avis('succes',m.publie?'Match dépublié':'Match publié');}));
  if(m.source==='api'&&Object.values(m.verrous||{}).some(Boolean)){
   const dv=n('div',undefined,'fa-grille');for(const v of VERROUS)if(m.verrous[v])dv.append(action('Déverrouiller '+v,'deverrou-'+v,async()=>{await api.deverrouiller(m,{verrous:[v],motif:motif.value});await rafraichir(m.id);avis('succes','Verrou '+v+' levé');},'fa-bouton fa-bouton-clair'));
   pg.append(n('p','Verrous : la synchronisation ne modifie pas les champs verrouillés.','fa-sous'),dv);}
  corps.append(pg);
 }

 // ───── Programmer un match ─────
 function ecranProgrammer(corps){
  const comps=etat.donnees.competitions.filter(c=>c.source==='manuel'&&c.statut==='active'),eqs=etat.donnees.equipes.filter(e=>e.source==='manuel'&&e.statut==='active');
  if(!comps.length||eqs.length<2){corps.append(n('p','Créez d’abord une compétition locale et au moins deux équipes.','fa-vide'));return;}
  const f=n('form',undefined,'fa-form');f.noValidate=true;
  const comp=choix(comps.map(c=>[c.id,c.nom]));const dom=choix(eqs.map(e=>[e.id,e.nom]));const ext=choix(eqs.map(e=>[e.id,e.nom]),eqs[1].id);
  const date=entree('datetime-local','',{required:''}),lieu=entree('text','',{maxlength:'120'}),journee=entree('text','',{maxlength:'40'}),poule=entree('text','',{maxlength:'40'});
  const pub=entree('checkbox');pub.checked=true;
  f.append(champ('Compétition',comp),champ('Équipe à domicile',dom),champ('Équipe à l’extérieur',ext),champ('Date et heure (heure de Koki)',date),champ('Lieu',lieu),champ('Journée',journee),champ('Poule',poule),champ('Publier',pub));
  f.append(action('Programmer le match','programmer',async()=>{
   if(dom.value===ext.value)throw Error('Choisissez deux équipes différentes.');
   const r=await appel('enregistrer_match',{competition_id:comp.value,domicile_id:dom.value,exterieur_id:ext.value,date_match:versISO(date.value),lieu:lieu.value.trim(),journee:journee.value.trim(),poule:poule.value.trim(),publie:pub.checked});
   etat.vue='matchs';await rafraichir(r.id);avis('succes','Match programmé');},'fa-bouton fa-bouton-principal'));
  corps.append(n('h2','Programmer un match','fa-titre'),f);
 }
 // ───── Compétitions ─────
 function ecranCompetitions(corps){
  const f=n('form',undefined,'fa-form');const nom=entree('text','',{maxlength:'120',required:''}),saison=entree('text',String(new Date(maintenant()).getFullYear()),{maxlength:'20'});
  const type=choix(['Championnat','Coupe','Tournoi','Amical']),portee=choix(['Koki','Sénégal','International']);const pub=entree('checkbox');
  f.append(champ('Nom',nom),champ('Saison',saison),champ('Type',type),champ('Portée',portee),champ('Publier',pub),action('Créer la compétition','competition',async()=>{
   if(nom.value.trim().length<2)throw Error('Nom de la compétition requis.');
   await appel('enregistrer_competition',{nom:nom.value.trim(),saison:saison.value.trim(),type:type.value,portee:portee.value,publie:pub.checked});await rafraichir();avis('succes','Compétition créée');},'fa-bouton fa-bouton-principal'));
  corps.append(n('h2','Nouvelle compétition','fa-titre'),f,n('h2','Compétitions','fa-titre'));
  const l=n('div',undefined,'fa-liste');
  for(const c of etat.donnees.competitions){const x=n('div',undefined,'fa-ligne fa-ligne-fixe');x.append(n('strong',c.nom),n('span',[c.portee,c.type,c.saison,c.source==='api'?'importée':'locale',c.publie?'publiée':'non publiée'].filter(Boolean).join(' · '),'fa-sous'),
   action(c.publie?'Dépublier':'Publier','pub-'+c.id,async()=>{await appel('enregistrer_competition',{id:c.id,revision:c.revision,publie:!c.publie});await rafraichir();avis('succes','Compétition mise à jour');},'fa-bouton fa-bouton-clair'));l.append(x);}
  corps.append(l);
 }
 // ───── Équipes ─────
 function ecranEquipes(corps){
  const f=n('form',undefined,'fa-form');const nom=entree('text','',{maxlength:'80',required:''}),quartier=entree('text','',{maxlength:'80'}),c1=entree('color','#087a3d'),c2=entree('color','#ffffff');
  f.append(champ('Nom',nom),champ('Quartier',quartier),champ('Couleur 1',c1),champ('Couleur 2',c2),action('Créer l’équipe','equipe',async()=>{
   if(!nom.value.trim())throw Error('Nom de l’équipe requis.');
   await appel('enregistrer_equipe',{nom:nom.value.trim(),quartier:quartier.value.trim(),couleurs:[c1.value,c2.value]});await rafraichir();avis('succes','Équipe créée');},'fa-bouton fa-bouton-principal'));
  const ins=n('form',undefined,'fa-form');const comps=etat.donnees.competitions.filter(c=>c.source==='manuel');const eqs=etat.donnees.equipes.filter(e=>e.source==='manuel');
  if(comps.length&&eqs.length){const comp=choix(comps.map(c=>[c.id,c.nom])),eq=choix(eqs.map(e=>[e.id,e.nom])),poule=entree('text','',{maxlength:'40'});
   ins.append(champ('Compétition',comp),champ('Équipe',eq),champ('Poule',poule),action('Inscrire','inscrire',async()=>{await appel('inscrire_equipe',{competition_id:comp.value,equipe_id:eq.value,poule:poule.value.trim()});await rafraichir();avis('succes','Équipe inscrite');}));}
  corps.append(n('h2','Nouvelle équipe','fa-titre'),f,n('h2','Inscrire une équipe','fa-titre'),ins,n('h2','Équipes locales','fa-titre'));
  const l=n('div',undefined,'fa-liste');for(const e of eqs){const x=n('div',undefined,'fa-ligne fa-ligne-fixe');const p=n('span',undefined,'fa-pastille');const [a,b]=e.couleurs;p.style.background=b?`linear-gradient(135deg,${a} 0 55%,${b} 55% 100%)`:a;x.append(p,n('strong',e.nom),n('span',e.quartier||'','fa-sous'));l.append(x);}corps.append(l);
 }
 // ───── Conflits API ─────
 function ecranConflits(corps){
  corps.append(n('h2','Conflits ouverts','fa-titre'));const zone=n('div',undefined,'fa-liste');corps.append(zone);zone.append(n('p','Chargement…','fa-chargement'));
  api.conflits().then(cs=>{zone.replaceChildren();if(!cs.length){zone.append(n('p','Aucun conflit : les corrections locales et le fournisseur concordent.','fa-vide'));return;}
   for(const k of cs){const c=n('article',undefined,'fa-conflit');c.dataset.conflit=k.id;
    c.append(n('strong',k.match.domicile.nom+' – '+k.match.exterieur.nom),n('p','Champ : '+k.champ+' · vu '+k.occurrences+' fois · dernier '+heure(k.dernier_vu),'fa-sous'),
     n('p','Valeur locale (publiée) : '+valeurConflit(k.champ,k.valeur_locale)),n('p','Valeur du fournisseur : '+valeurConflit(k.champ,k.valeur_api)));
    const motif=entree('text','',{maxlength:'300',placeholder:'Motif de la décision','aria-label':'Motif'});c.append(motif);
    const g=n('div',undefined,'fa-grille fa-grille-2');
    g.append(action('Garder la valeur locale','garder-'+k.id,async()=>{await api.resoudreConflit(k,{decision:'garder',motif:motif.value});await rafraichir();avis('succes','Valeur locale conservée');etat.vue='conflits';rendre();}),
     action('Accepter le fournisseur','accepter-'+k.id,async()=>{await api.resoudreConflit(k,{decision:'accepter_api',motif:motif.value});await rafraichir();avis('succes','Le fournisseur reprend la main sur ce champ');etat.vue='conflits';rendre();},'fa-bouton fa-bouton-clair'));
    c.append(g);zone.append(c);}
  }).catch(afficherErreur);
 }
 // ───── Sources (fournisseurs) et réglages ─────
 function ecranSources(corps){
  corps.append(n('h2','Fournisseurs','fa-titre'));const fs=etat.donnees.fournisseurs||[];
  if(!fs.length)corps.append(n('p','Aucun fournisseur appelé pour le moment.','fa-vide'));
  for(const f of fs){const c=n('article',undefined,'fa-conflit');c.append(n('strong',f.fournisseur+' · '+f.etat),n('p',['Dernière réussite : '+(f.derniere_reussite?heure(f.derniere_reussite):'jamais'),'Dernière tentative : '+(f.derniere_tentative?heure(f.derniere_tentative):'jamais'),
   f.derniere_erreur_code?'Dernière erreur : '+f.derniere_erreur_code:null,f.pause_jusqu_a?'En pause jusqu’à '+heure(f.pause_jusqu_a):null,f.quota_restant!==null?'Quota restant : '+f.quota_restant:null].filter(Boolean).join(' · '),'fa-sous'));
   if(role==='superadmin'){const seuil=entree('number',f.seuil_ancien_s,{min:'60',max:'86400'});c.append(champ('Seuil « données anciennes » (secondes)',seuil),action('Enregistrer le seuil','seuil-'+f.fournisseur,async()=>{await appel('regler_source',{fournisseur:f.fournisseur,seuil_ancien_s:Number(seuil.value)});await rafraichir();avis('succes','Seuil enregistré');etat.vue='sources';rendre();}));}
   corps.append(c);}
  corps.append(n('p','Mode des verrous : '+(etat.donnees.mode_verrous==='independant'?'indépendants':'global (lancement)'),'fa-sous'));
  const s=etat.donnees.synchronisations||[];corps.append(n('h2','Dernières synchronisations','fa-titre'));
  if(!s.length)corps.append(n('p','Aucune synchronisation.','fa-vide'));
  for(const x of s.slice(0,10))corps.append(n('p',heure(x.created_at)+' · '+x.fournisseur+' · '+x.operation+' · '+x.statut+(x.code?' ('+x.code+')':'')+' · '+x.crees+' créés, '+x.mis_a_jour+' mis à jour, '+x.ignores_verrou+' divergences, '+x.rejetes+' rejetés','fa-sous'));
 }

 window.addEventListener('online',()=>{if(racine.isConnected)rendre();});window.addEventListener('offline',()=>{if(racine.isConnected)rendre();});
 charger();
 return {recharger:charger,etat};
}
