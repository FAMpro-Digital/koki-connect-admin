// Contrat commun « Services publics » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/service-contract.js, public : assets/portail/service-contract.js).
// Stockage : public.koki_contents, type=Informations utiles, texte = JSON versionné. Aucune migration.
//  - Fiche service (annuaire) : categorie « Services publics », schéma koki.service.public.
//  - Guide de démarche : categorie « Démarches administratives », schéma koki.service.demarche.
//  - Avis officiels : publications Annonces « Communiqué » / « Avis important » et toute publication de catégorie « Services publics ».
// Ne renseigner que des informations publiques et vérifiées (coût et délai : tels qu'affichés par le service).
(function(root){'use strict';
const SERVICE='koki.service.public',DEMARCHE='koki.service.demarche',version=1,type='Informations utiles';
const categorieService='Services publics',categorieDemarche='Démarches administratives';
const genres=[
 {nom:'Mairie',icone:'🏛️',famille:'administration'},{nom:'Sous-préfecture',icone:'🏢',famille:'administration'},{nom:'État civil',icone:'📜',famille:'administration'},
 {nom:'Trésor et impôts',icone:'💰',famille:'administration'},{nom:'Gendarmerie',icone:'🛡️',famille:'securite'},{nom:'Police',icone:'👮',famille:'securite'},
 {nom:'Sapeurs-pompiers',icone:'🚒',famille:'securite'},{nom:'Électricité',icone:'⚡',famille:'reseaux'},{nom:'Eau',icone:'💧',famille:'reseaux'},
 {nom:'Poste',icone:'✉️',famille:'reseaux'},{nom:'Agriculture et élevage',icone:'🌾',famille:'administration'},{nom:'Autre',icone:'🏛️',famille:'autre'}];
const familles=[{cle:'tout',nom:'Tout'},{cle:'administration',nom:'Administration'},{cle:'securite',nom:'Sécurité'},{cle:'reseaux',nom:'Eau, électricité, poste'}];
const domaines=[{nom:'État civil',icone:'📜'},{nom:'Identité',icone:'🪪'},{nom:'Résidence',icone:'🏠'},{nom:'Foncier et urbanisme',icone:'📐'},{nom:'Associations et entreprises',icone:'🤝'},{nom:'Autre',icone:'📄'}];
const nomsGenres=genres.map(g=>g.nom),nomsDomaines=domaines.map(d=>d.nom);
const jours=['Lun','Mar','Mer','Jeu','Ven','Sam','Dim'];
const telRe=/^\+?[0-9 ()-]{6,24}$/,heureRe=/^([01][0-9]|2[0-3]):[0-5][0-9]$/,uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const txt=(v,max)=>typeof v==='string'&&v.length<=max;
const lignes=(v,max,long)=>Array.isArray(v)&&v.length<=max&&v.every(s=>typeof s==='string'&&s.trim()&&s.length<=long);
function plageValide(p){return p&&Array.isArray(p.jours)&&p.jours.length>=1&&p.jours.length<=7&&p.jours.every(j=>Number.isInteger(j)&&j>=0&&j<=6)&&new Set(p.jours).size===p.jours.length&&heureRe.test(p.de)&&heureRe.test(p.a)&&p.de!==p.a;}
function checkService(v){
 if(!v||v.schema!==SERVICE||v.version!==version||!nomsGenres.includes(v.genre))return false;
 if(!txt(v.telephone,24)||!txt(v.whatsapp,24)||!txt(v.horaires_note,200)||!txt(v.description,10000))return false;
 if((v.telephone&&!telRe.test(v.telephone))||(v.whatsapp&&!telRe.test(v.whatsapp)))return false;
 if(typeof v.h24!=='boolean'||typeof v.archive!=='boolean')return false;
 if(!Array.isArray(v.plages)||v.plages.length>6||!v.plages.every(plageValide)||!lignes(v.services,12,60))return false;
 for(const k of ['latitude','longitude'])if(v[k]!==null&&!Number.isFinite(v[k]))return false;
 if((v.latitude===null)!==(v.longitude===null))return false;
 return v.latitude===null||(Math.abs(v.latitude)<=90&&Math.abs(v.longitude)<=180);
}
function checkDemarche(v){
 if(!v||v.schema!==DEMARCHE||v.version!==version||!nomsDomaines.includes(v.domaine))return false;
 if(!lignes(v.pieces,20,160)||!lignes(v.etapes,12,300)||!txt(v.cout,80)||!txt(v.delai,80)||!txt(v.conseils,2000))return false;
 if(v.service!==''&&!uuidRe.test(v.service))return false;
 return typeof v.archive==='boolean';
}
function lire(row,categorie,check){if(row?.type!==type||row.categorie!==categorie)return null;try{const v=JSON.parse(row.texte);return check(v)?v:null;}catch{return null;}}
const decodeService=row=>lire(row,categorieService,checkService);
const decodeDemarche=row=>lire(row,categorieDemarche,checkDemarche);
function nombre(x){if(x===null||x===undefined||x==='')return null;const n=Number(String(x).replace(',','.'));return Number.isFinite(n)?n:NaN;}
const liste=(x,sep)=>(Array.isArray(x)?x:String(x||'').split(sep)).map(s=>String(s).trim()).filter(Boolean);
function encodeService(v){
 const s={schema:SERVICE,version,genre:v.genre,telephone:String(v.telephone||'').trim(),whatsapp:String(v.whatsapp||'').trim(),h24:v.h24===true,
  plages:Array.isArray(v.plages)?v.plages.map(p=>({jours:[...new Set((p.jours||[]).map(Number))].sort((a,b)=>a-b),de:String(p.de||''),a:String(p.a||'')})):[],
  horaires_note:String(v.horaires_note||'').trim(),services:liste(v.services,','),latitude:nombre(v.latitude),longitude:nombre(v.longitude),
  description:String(v.description||'').trim(),archive:v.archive===true};
 if(s.h24)s.plages=[];
 if(!checkService(s)){
  if(!nomsGenres.includes(s.genre))throw Error('Choisissez le type de service.');
  if((s.telephone&&!telRe.test(s.telephone))||(s.whatsapp&&!telRe.test(s.whatsapp)))throw Error('Numéro de téléphone ou WhatsApp invalide.');
  if(!s.plages.every(plageValide))throw Error('Horaires invalides : choisissez au moins un jour, et une heure d’ouverture différente de la fermeture (HH:MM).');
  if(s.services.length>12||s.services.some(x=>x.length>60))throw Error('Douze prestations au maximum, 60 caractères chacune.');
  if((s.latitude===null)!==(s.longitude===null)||Number.isNaN(s.latitude)||Number.isNaN(s.longitude))throw Error('Position GPS incomplète ou invalide.');
  throw Error('Fiche service invalide.');
 }
 return JSON.stringify(s);
}
function encodeDemarche(v){
 const s={schema:DEMARCHE,version,domaine:v.domaine,pieces:liste(v.pieces,/\r?\n/),etapes:liste(v.etapes,/\r?\n/),cout:String(v.cout||'').trim(),delai:String(v.delai||'').trim(),
  service:String(v.service||''),conseils:String(v.conseils||'').trim(),archive:v.archive===true};
 if(!checkDemarche(s)){
  if(!nomsDomaines.includes(s.domaine))throw Error('Choisissez le domaine de la démarche.');
  if(s.pieces.length>20||s.pieces.some(x=>x.length>160))throw Error('Pièces à fournir : 20 lignes au maximum, 160 caractères chacune.');
  if(s.etapes.length>12||s.etapes.some(x=>x.length>300))throw Error('Étapes : 12 lignes au maximum, 300 caractères chacune.');
  if(s.cout.length>80||s.delai.length>80)throw Error('Coût et délai : 80 caractères au maximum.');
  throw Error('Guide de démarche invalide.');
 }
 return JSON.stringify(s);
}
// Avis officiels : communiqués et avis importants, ou toute publication de la catégorie Services publics (hors fiches).
const avis=row=>!!row&&((row.type==='Annonces'&&(row.categorie==='Communiqué'||row.categorie==='Avis important'))||(row.categorie===categorieService&&!decodeService(row)));
// Heure et jour à Koki (Africa/Dakar), 0 = lundi.
function maintenant(now=new Date()){
 const parts=Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Dakar',weekday:'short',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(now).map(p=>[p.type,p.value]));
 return {jour:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].indexOf(parts.weekday),minutes:Number(parts.hour)*60+Number(parts.minute)};
}
const enMinutes=h=>Number(h.slice(0,2))*60+Number(h.slice(3,5));
// true / false selon les horaires ; null si aucun horaire n'est renseigné (jamais deviné).
function ouvert(v,now=new Date()){
 if(v.h24)return true;if(!v.plages.length)return null;const t=maintenant(now),hier=(t.jour+6)%7;
 return v.plages.some(p=>{const de=enMinutes(p.de),a=enMinutes(p.a);if(de<a)return p.jours.includes(t.jour)&&t.minutes>=de&&t.minutes<a;return (p.jours.includes(t.jour)&&t.minutes>=de)||(p.jours.includes(hier)&&t.minutes<a);});
}
function joursTexte(js){const s=[...js].sort((a,b)=>a-b);if(s.length===7)return 'Tous les jours';const suite=s.every((j,i)=>i===0||j===s[i-1]+1);return suite&&s.length>2?jours[s[0]]+'–'+jours[s[s.length-1]]:s.map(j=>jours[j]).join(', ');}
function horairesTexte(v){if(v.h24)return '24 h/24';if(v.plages.length)return v.plages.map(p=>joursTexte(p.jours)+' '+p.de.replace(':','h')+'–'+p.a.replace(':','h')).join(' · ')+(v.horaires_note?' · '+v.horaires_note:'');return v.horaires_note||'Horaires non renseignés';}
const genre=nom=>genres.find(g=>g.nom===nom)||genres.at(-1);
const domaine=nom=>domaines.find(d=>d.nom===nom)||domaines.at(-1);
const gele=a=>Object.freeze(a.map(x=>Object.freeze({...x})));
root.KokiServiceContract=Object.freeze({version,type,categorieService,categorieDemarche,genres:gele(genres),familles:gele(familles),domaines:gele(domaines),jours:Object.freeze([...jours]),
 decodeService,decodeDemarche,encodeService,encodeDemarche,avis,ouvert,horairesTexte,genre,domaine});
})(typeof globalThis!=='undefined'?globalThis:this);
