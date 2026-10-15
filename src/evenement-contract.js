// Contrat commun « événement » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/evenement-contract.js, public : assets/portail/evenement-contract.js).
// Stockage : public.koki_contents, type=Événements ; début = colonne evenement, lieu = colonne lieu ; texte = JSON versionné.
// Aucune migration. Les anciens événements (texte libre) restent affichés. Un événement terminé disparaît de l'application.
(function(root){'use strict';
const marker='koki.evenement.fiche',version=1,type='Événements';
const genres=[{nom:'Religieux',icone:'🕌'},{nom:'Culture',icone:'🎭'},{nom:'Sport',icone:'⚽'},{nom:'Famille',icone:'💍'},{nom:'Réunion',icone:'🤝'},{nom:'Éducation',icone:'🎓'},{nom:'Santé',icone:'🏥'},{nom:'Économie',icone:'🛍️'},{nom:'Autre',icone:'📅'}];
const noms=genres.map(g=>g.nom);
const telRe=/^\+?[0-9 ()-]{6,24}$/;
const DUREE_PAR_DEFAUT=4*3600000; // sans heure de fin : l'événement est considéré en cours pendant 4 h
const txt=(v,max)=>typeof v==='string'&&v.length<=max;
const dateValide=v=>v===''||(typeof v==='string'&&!Number.isNaN(Date.parse(v)));
function check(v){
 if(!v||v.schema!==marker||v.version!==version||!noms.includes(v.genre))return false;
 if(!txt(v.organisateur,120)||!txt(v.contact,24)||!txt(v.entree,80)||!txt(v.programme,4000)||!dateValide(v.fin))return false;
 if(v.contact&&!telRe.test(v.contact))return false;
 for(const k of ['latitude','longitude'])if(v[k]!==null&&!Number.isFinite(v[k]))return false;
 if((v.latitude===null)!==(v.longitude===null))return false;
 if(v.latitude!==null&&(Math.abs(v.latitude)>90||Math.abs(v.longitude)>180))return false;
 return typeof v.archive==='boolean';
}
function decode(row){if(row?.type!==type)return null;try{const v=JSON.parse(row.texte);return check(v)?v:null;}catch{return null;}}
const nombre=x=>x===''||x===null||x===undefined?null:Number(String(x).replace(',','.'));
function encode(v){
 const s={schema:marker,version,genre:v.genre||'Autre',fin:v.fin?new Date(v.fin).toISOString():'',organisateur:String(v.organisateur||'').trim(),contact:String(v.contact||'').trim(),
  entree:String(v.entree||'').trim(),programme:String(v.programme||'').trim(),latitude:nombre(v.latitude),longitude:nombre(v.longitude),archive:v.archive===true};
 if(!check(s)){
  if(!noms.includes(s.genre))throw Error('Choisissez le type d’événement.');
  if(s.contact&&!telRe.test(s.contact))throw Error('Téléphone de contact invalide.');
  if((s.latitude===null)!==(s.longitude===null)||Number.isNaN(s.latitude)||Number.isNaN(s.longitude))throw Error('Position GPS incomplète ou invalide.');
  if(s.programme.length>4000)throw Error('Programme trop long (4 000 caractères maximum).');
  throw Error('Fiche événement invalide.');
 }
 return JSON.stringify(s);
}
// Début et fin (ms). Sans fin : début + 4 h. Fin avant le début : ignorée.
function bornes(row,v){const debut=Date.parse(row?.evenement);if(Number.isNaN(debut))return null;let fin=v?.fin?Date.parse(v.fin):NaN;if(Number.isNaN(fin)||fin<debut)fin=debut+DUREE_PAR_DEFAUT;return {debut,fin};}
function etat(row,v,now=Date.now()){const b=bornes(row,v);if(!b)return 'Sans date';if(now>b.fin)return 'Terminé';if(now>=b.debut)return 'En cours';return 'À venir';}
const termine=(row,v,now=Date.now())=>etat(row,v,now)==='Terminé';
// Jour à Koki (Africa/Dakar = UTC) : AAAA-MM-JJ.
const jourDe=ms=>new Date(ms).toISOString().slice(0,10);
// « Aujourd'hui · 18:00 », « Demain · 17:00 », « Dans 5 jours », « En cours ».
function quand(row,v,now=Date.now()){
 const b=bornes(row,v);if(!b)return '';const e=etat(row,v,now);if(e==='En cours')return 'En cours';if(e==='Terminé')return 'Terminé';
 const h=new Date(b.debut).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit',timeZone:'Africa/Dakar'});
 const jours=Math.round((Date.parse(jourDe(b.debut))-Date.parse(jourDe(now)))/86400000);
 if(jours===0)return 'Aujourd’hui · '+h;if(jours===1)return 'Demain · '+h;if(jours<=7)return new Date(b.debut).toLocaleDateString('fr-FR',{weekday:'long',timeZone:'Africa/Dakar'}).replace(/^./,c=>c.toUpperCase())+' · '+h;
 return new Date(b.debut).toLocaleDateString('fr-FR',{weekday:'short',day:'numeric',month:'short',timeZone:'Africa/Dakar'})+' · '+h;
}
// Périodes de l'agenda.
function periode(nom,row,v,now=Date.now()){
 const b=bornes(row,v);if(!b)return nom==='Tout';const j=jourDe(now),d=new Date(Date.parse(j+'T00:00:00Z'));const dow=(d.getUTCDay()+6)%7;// 0 = lundi
 const deb=jourDe(b.debut),fin=jourDe(b.fin);const chevauche=(a,z)=>deb<=z&&fin>=a;const plus=n=>jourDe(Date.parse(j+'T00:00:00Z')+n*86400000);
 if(nom==='Aujourd’hui')return chevauche(j,j);
 if(nom==='Ce week-end'){const sam=plus(dow<=5?5-dow:-1),dim=plus(dow<=5?6-dow:0);return chevauche(sam,dim);}
 if(nom==='Cette semaine')return chevauche(j,plus(6-dow));
 if(nom==='Ce mois')return chevauche(j,j.slice(0,8)+'31');
 return true;
}
const periodes=['Tout','Aujourd’hui','Ce week-end','Cette semaine','Ce mois'];
// Fichier agenda (.ics) pour « Ajouter à mon agenda ».
function ics(row,v,url=''){
 const b=bornes(row,v);if(!b)return '';const f=ms=>new Date(ms).toISOString().replace(/[-:]/g,'').replace(/\.\d{3}/,'');
 const e=s=>String(s||'').replace(/\\/g,'\\\\').replace(/;/g,'\\;').replace(/,/g,'\\,').replace(/\r?\n/g,'\\n');
 return ['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Koki Connect//Agenda//FR','CALSCALE:GREGORIAN','BEGIN:VEVENT','UID:'+e(row.id||'evenement')+'@koki-connect','DTSTAMP:'+f(Date.now()),'DTSTART:'+f(b.debut),'DTEND:'+f(b.fin),
  'SUMMARY:'+e(row.titre),'LOCATION:'+e(row.lieu),'DESCRIPTION:'+e([row.resume,v?.organisateur?'Organisateur : '+v.organisateur:'',v?.contact?'Contact : '+v.contact:'',url].filter(Boolean).join('\n')),
  ...(v?.latitude!=null?['GEO:'+v.latitude+';'+v.longitude]:[]),'BEGIN:VALARM','TRIGGER:-PT2H','ACTION:DISPLAY','DESCRIPTION:'+e(row.titre),'END:VALARM','END:VEVENT','END:VCALENDAR'].join('\r\n');
}
const genre=nom=>genres.find(g=>g.nom===nom)||genres.at(-1);
root.KokiEvenementContract=Object.freeze({marker,version,type,genres:Object.freeze(genres.map(g=>Object.freeze({...g}))),periodes:Object.freeze(periodes),check,decode,encode,bornes,etat,termine,quand,periode,ics,genre});
})(typeof globalThis!=='undefined'?globalThis:this);
