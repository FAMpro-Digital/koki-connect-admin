// Contrat commun « lieu de la carte » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/lieu-contract.js, public : assets/portail/lieu-contract.js).
// Stockage : public.koki_contents, type=Informations utiles, categorie=Lieux de la carte, texte = JSON versionné.
// Aucune migration. Un lieu ajouté par l'administration complète la carte intégrée (OpenStreetMap) ;
// « remplace » corrige un lieu de cette carte (même identifiant), « masque » le retire de l'application.
(function(root){'use strict';
const marker='koki.carte.lieu',version=1,categorie='Lieux de la carte';
// Catégories de la carte publique (la Santé se gère dans l'écran Santé, avec horaires et téléphone).
const genres=['Villages et quartiers','Services publics','Éducation','Commerces','Lieux religieux','Sports','Eau'];
const idOSM=/^(node|way|relation)\/[0-9]{1,15}$/;
// Commune de Koki et ses environs immédiats : une position hors de ce cadre est une erreur de saisie.
const cadre={sud:15.30,nord:15.75,ouest:-16.25,est:-15.75};
const dansCadre=(lat,lon)=>Number.isFinite(lat)&&Number.isFinite(lon)&&lat>=cadre.sud&&lat<=cadre.nord&&lon>=cadre.ouest&&lon<=cadre.est;
function check(v){
 if(!v||v.schema!==marker||v.version!==version||!genres.includes(v.genre))return false;
 if(typeof v.masque!=='boolean'||typeof v.archive!=='boolean')return false;
 if(typeof v.remplace!=='string'||(v.remplace&&!idOSM.test(v.remplace)))return false;
 if(v.masque&&!v.remplace)return false;
 if(typeof v.description!=='string'||v.description.length>500)return false;
 return dansCadre(v.latitude,v.longitude);
}
function decode(row){if(row?.type!=='Informations utiles'||row.categorie!==categorie)return null;try{const v=JSON.parse(row.texte);return check(v)?v:null;}catch{return null;}}
const nombre=x=>x===''||x===null||x===undefined?NaN:Number(String(x).replace(',','.'));
function encode(v){
 const s={schema:marker,version,genre:String(v.genre||''),latitude:Math.round(nombre(v.latitude)*1e6)/1e6,longitude:Math.round(nombre(v.longitude)*1e6)/1e6,
  description:String(v.description||'').trim(),remplace:String(v.remplace||'').trim(),masque:v.masque===true,archive:v.archive===true};
 if(!check(s)){
  if(!genres.includes(s.genre))throw Error('Choisissez la catégorie du lieu.');
  if(!dansCadre(s.latitude,s.longitude))throw Error('Position GPS requise, dans la commune de Koki.');
  if(s.description.length>500)throw Error('Description trop longue (500 caractères maximum).');
  if(s.remplace&&!idOSM.test(s.remplace))throw Error('Lieu de la carte à corriger introuvable.');
  throw Error('Lieu invalide.');
 }
 return JSON.stringify(s);
}
// Lieux affichés par l'application : la carte intégrée, corrigée ou masquée par l'administration, puis les lieux ajoutés.
// « rows » : contenus publiés (déjà filtrés par date et statut). Les lieux archivés ou invalides sont ignorés.
function fusionner(reference,rows){
 const publies=[];const corrections=new Map();
 for(const row of Array.isArray(rows)?rows:[]){const v=decode(row);if(!v||v.archive)continue;
  const lieu={id:v.remplace||'koki-'+row.id,nom:String(row.titre||'').trim(),categorie:v.genre,latitude:v.latitude,longitude:v.longitude,
   description:v.description,village:String(row.lieu||'').trim(),position:'Lieu publié par Koki Connect',source:'Koki Connect'};
  if(!lieu.nom)continue;if(v.remplace)corrections.set(v.remplace,v.masque?null:lieu);else publies.push(lieu);}
 const base=(Array.isArray(reference)?reference:[]).flatMap(l=>!corrections.has(l.id)?[l]:corrections.get(l.id)?[{...l,...corrections.get(l.id)}]:[]);
 return [...base,...publies];
}
root.KokiLieuContract=Object.freeze({marker,version,categorie,genres:Object.freeze([...genres]),cadre:Object.freeze({...cadre}),dansCadre,check,decode,encode,fusionner});
})(typeof globalThis!=='undefined'?globalThis:this);
