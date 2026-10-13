// Contrat commun « structure de santé » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/sante-contract.js, public : assets/portail/sante-contract.js).
// Stockage : public.koki_contents, type=Informations utiles, categorie=Santé, texte = JSON versionné. Aucune migration.
// Ne renseigner que des coordonnées professionnelles publiques (jamais de données de patients).
(function(root){'use strict';
const marker='koki.sante.structure',version=1;
const genres=['Centre de santé','Poste de santé','Case de santé','Hôpital','Clinique','Maternité','Pharmacie','Dépôt de pharmacie','Cabinet médical','Autre'];
const familles={'Centre de santé':'centre','Poste de santé':'centre','Case de santé':'centre','Hôpital':'centre','Clinique':'centre','Cabinet médical':'centre','Maternité':'maternite','Pharmacie':'pharmacie','Dépôt de pharmacie':'pharmacie','Autre':'autre'};
const jours=['Lun','Mar','Mer','Jeu','Ven','Sam','Dim'];
const telRe=/^\+?[0-9 ()-]{6,24}$/,heureRe=/^([01][0-9]|2[0-3]):[0-5][0-9]$/,dateRe=/^\d{4}-\d{2}-\d{2}$/;
const txt=(v,max)=>typeof v==='string'&&v.length<=max;
function plageValide(p){return p&&Array.isArray(p.jours)&&p.jours.length>=1&&p.jours.length<=7&&p.jours.every(j=>Number.isInteger(j)&&j>=0&&j<=6)&&new Set(p.jours).size===p.jours.length&&heureRe.test(p.de)&&heureRe.test(p.a)&&p.de!==p.a;}
function check(v){
 if(!v||v.schema!==marker||v.version!==version||!genres.includes(v.genre))return false;
 if(!txt(v.telephone,24)||!txt(v.whatsapp,24)||!txt(v.horaires_note,200)||!txt(v.description,10000)||!txt(v.garde_fin,10))return false;
 if((v.telephone&&!telRe.test(v.telephone))||(v.whatsapp&&!telRe.test(v.whatsapp)))return false;
 if(typeof v.h24!=='boolean'||typeof v.garde!=='boolean'||typeof v.archive!=='boolean')return false;
 if(v.garde_fin&&!dateRe.test(v.garde_fin))return false;
 if(!Array.isArray(v.plages)||v.plages.length>6||!v.plages.every(plageValide))return false;
 if(!Array.isArray(v.services)||v.services.length>12||!v.services.every(s=>typeof s==='string'&&s.trim()&&s.length<=60))return false;
 for(const k of ['latitude','longitude'])if(v[k]!==null&&!Number.isFinite(v[k]))return false;
 if((v.latitude===null)!==(v.longitude===null))return false;
 if(v.latitude!==null&&(Math.abs(v.latitude)>90||Math.abs(v.longitude)>180))return false;
 return true;
}
function decode(row){if(row?.type!=='Informations utiles'||row.categorie!=='Santé')return null;try{const v=JSON.parse(row.texte);return check(v)?v:null;}catch{return null;}}
function nombre(x){if(x===null||x===undefined||x==='')return null;const n=Number(String(x).replace(',','.'));return Number.isFinite(n)?n:NaN;}
function encode(v){
 const s={schema:marker,version,genre:v.genre,telephone:String(v.telephone||'').trim(),whatsapp:String(v.whatsapp||'').trim(),
  h24:v.h24===true,plages:Array.isArray(v.plages)?v.plages.map(p=>({jours:[...new Set((p.jours||[]).map(Number))].sort((a,b)=>a-b),de:String(p.de||''),a:String(p.a||'')})):[],
  horaires_note:String(v.horaires_note||'').trim(),services:(Array.isArray(v.services)?v.services:String(v.services||'').split(',')).map(x=>String(x).trim()).filter(Boolean),
  garde:v.garde===true,garde_fin:v.garde===true?String(v.garde_fin||'').trim():'',latitude:nombre(v.latitude),longitude:nombre(v.longitude),
  description:String(v.description||'').trim(),archive:v.archive===true};
 if(s.h24)s.plages=[];
 if(!check(s)){
  if(!genres.includes(s.genre))throw Error('Choisissez le type de structure.');
  if((s.telephone&&!telRe.test(s.telephone))||(s.whatsapp&&!telRe.test(s.whatsapp)))throw Error('Numéro de téléphone ou WhatsApp invalide.');
  if(!s.plages.every(plageValide))throw Error('Horaires invalides : choisissez au moins un jour, et une heure d’ouverture différente de la fermeture (HH:MM).');
  if(s.plages.length>6)throw Error('Six plages horaires au maximum.');
  if(s.services.length>12||s.services.some(x=>x.length>60))throw Error('Douze services au maximum, 60 caractères chacun.');
  if((s.latitude===null)!==(s.longitude===null)||Number.isNaN(s.latitude)||Number.isNaN(s.longitude))throw Error('Position GPS incomplète ou invalide.');
  if(s.garde_fin&&!dateRe.test(s.garde_fin))throw Error('Date de fin de garde invalide.');
  throw Error('Fiche santé invalide.');
 }
 return JSON.stringify(s);
}
// Heure et jour à Koki (Africa/Dakar), 0 = lundi.
function maintenant(now=new Date()){
 const parts=Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Dakar',weekday:'short',hour:'2-digit',minute:'2-digit',year:'numeric',month:'2-digit',day:'2-digit',hourCycle:'h23'}).formatToParts(now).map(p=>[p.type,p.value]));
 const jour=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].indexOf(parts.weekday);
 return {jour,minutes:Number(parts.hour)*60+Number(parts.minute),date:parts.year+'-'+parts.month+'-'+parts.day};
}
const enMinutes=h=>Number(h.slice(0,2))*60+Number(h.slice(3,5));
// true / false selon les horaires ; null si aucun horaire n'est renseigné (statut inconnu, jamais deviné).
function ouvert(v,now=new Date()){
 if(v.h24)return true;if(!v.plages.length)return null;
 const t=maintenant(now),hier=(t.jour+6)%7;
 return v.plages.some(p=>{const de=enMinutes(p.de),a=enMinutes(p.a);
  if(de<a)return p.jours.includes(t.jour)&&t.minutes>=de&&t.minutes<a;
  return (p.jours.includes(t.jour)&&t.minutes>=de)||(p.jours.includes(hier)&&t.minutes<a);});
}
function enGarde(v,now=new Date()){return v.garde===true&&(!v.garde_fin||v.garde_fin>=maintenant(now).date);}
function joursTexte(js){const s=[...js].sort((a,b)=>a-b);if(s.length===7)return 'Tous les jours';const suite=s.every((j,i)=>i===0||j===s[i-1]+1);return suite&&s.length>2?jours[s[0]]+'–'+jours[s[s.length-1]]:s.map(j=>jours[j]).join(', ');}
function horairesTexte(v){if(v.h24)return '24 h/24';if(v.plages.length)return v.plages.map(p=>joursTexte(p.jours)+' '+p.de.replace(':','h')+'–'+p.a.replace(':','h')).join(' · ')+(v.horaires_note?' · '+v.horaires_note:'');return v.horaires_note||'Horaires non renseignés';}
const famille=g=>familles[g]||'autre';
const api=Object.freeze({marker,version,genres,jours,decode,encode,ouvert,enGarde,horairesTexte,famille,maintenant});
root.KokiSanteContract=api;if(typeof module!=='undefined'&&module.exports)module.exports=api;
})(globalThis);
