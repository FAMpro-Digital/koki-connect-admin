// Contrat commun « offre » (Emplois & Opportunités) entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/offre-contract.js, public : assets/portail/offre-contract.js).
// Stockage : public.koki_contents, type=Opportunités, categorie = Emploi, Stage, Formation…, texte = JSON versionné.
// Aucune migration. Les offres plus anciennes (texte libre) restent affichées, sans date limite.
// Une offre dont la date limite est passée n'est plus affichée dans l'application (retrait automatique).
(function(root){'use strict';
const marker='koki.opportunite.offre',version=1,type='Opportunités';
// Familles affichées (mêmes noms et catégories que les sous-rubriques du contrat Rubriques).
const familles=[
 {nom:'Emplois',icone:'💼',categories:['Emploi']},{nom:'Stages',icone:'🤝',categories:['Stage']},{nom:'Formations',icone:'🎓',categories:['Formation']},
 {nom:'Concours',icone:'🏆',categories:['Concours']},{nom:'Bourses',icone:'📚',categories:['Bourse']},{nom:'Financements',icone:'🌱',categories:['Financement','Appel à projets']}];
const categories=familles.flatMap(f=>f.categories);
const contrats=['','CDI','CDD','Stage','Apprentissage','Journalier / saisonnier','Bénévolat','Indépendant','Autre'];
const dateRe=/^\d{4}-\d{2}-\d{2}$/;
const txt=(v,max)=>typeof v==='string'&&v.length<=max;
function check(v){
 if(!v||v.schema!==marker||v.version!==version||!contrats.includes(v.contrat))return false;
 if(!txt(v.organisme,120)||!txt(v.comment_postuler,1000)||!txt(v.description,10000)||!txt(v.date_limite,10)||!txt(v.remuneration,80))return false;
 if(v.date_limite&&(!dateRe.test(v.date_limite)||Number.isNaN(Date.parse(v.date_limite+'T00:00:00Z'))))return false;
 return typeof v.archive==='boolean';
}
function decode(row){if(row?.type!==type)return null;try{const v=JSON.parse(row.texte);return check(v)?v:null;}catch{return null;}}
function encode(v){
 const s={schema:marker,version,organisme:String(v.organisme||'').trim(),contrat:String(v.contrat||''),remuneration:String(v.remuneration||'').trim(),
  date_limite:String(v.date_limite||'').trim(),comment_postuler:String(v.comment_postuler||'').trim(),description:String(v.description||'').trim(),archive:v.archive===true};
 if(!check(s)){
  if(!contrats.includes(s.contrat))throw Error('Type de contrat inconnu.');
  if(s.date_limite&&!dateRe.test(s.date_limite))throw Error('Date limite invalide (AAAA-MM-JJ).');
  if(s.organisme.length>120)throw Error('Nom de l’organisme trop long (120 caractères maximum).');
  if(s.comment_postuler.length>1000)throw Error('« Comment postuler » trop long (1 000 caractères maximum).');
  throw Error('Offre invalide.');
 }
 return JSON.stringify(s);
}
// Jour courant à Koki (Africa/Dakar = UTC toute l'année), au format AAAA-MM-JJ.
const aujourdhui=(now=new Date())=>new Date(now).toISOString().slice(0,10);
// Jours restants avant la date limite (0 = dernier jour, négatif = expirée, null = pas de date limite).
function joursRestants(v,now=new Date()){if(!v?.date_limite)return null;return Math.round((Date.parse(v.date_limite+'T00:00:00Z')-Date.parse(aujourdhui(now)+'T00:00:00Z'))/86400000);}
const expiree=(v,now=new Date())=>{const j=joursRestants(v,now);return j!==null&&j<0;};
// Libellé de l'échéance pour l'application : « Dernier jour », « Plus que 3 jours », « Jusqu'au 30 octobre ».
function echeance(v,now=new Date()){
 const j=joursRestants(v,now);if(j===null)return null;
 if(j<0)return {texte:'Expirée',urgent:false,expiree:true};
 if(j===0)return {texte:'Dernier jour',urgent:true,expiree:false};
 if(j===1)return {texte:'Plus qu’1 jour',urgent:true,expiree:false};
 if(j<=7)return {texte:'Plus que '+j+' jours',urgent:true,expiree:false};
 return {texte:'Jusqu’au '+new Date(v.date_limite+'T12:00:00Z').toLocaleDateString('fr-FR',{day:'numeric',month:'long',timeZone:'Africa/Dakar'}),urgent:false,expiree:false};
}
const famille=categorie=>familles.find(f=>f.categories.includes(categorie))||null;
root.KokiOffreContract=Object.freeze({marker,version,type,familles:Object.freeze(familles.map(f=>Object.freeze({...f,categories:Object.freeze([...f.categories])}))),categories:Object.freeze(categories),contrats:Object.freeze(contrats),check,decode,encode,aujourdhui,joursRestants,expiree,echeance,famille});
})(typeof globalThis!=='undefined'?globalThis:this);
