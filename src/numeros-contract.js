// Contrat commun « Numéro utile » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (comme education-contract.js).
//
// Un numéro est un contenu koki_contents :
//   type = 'Informations utiles', categorie = 'Numéros utiles',
//   titre = nom du service, resume = description courte, source = origine de l'information,
//   texte = JSON versionné { schema:'koki.numero.utile', version:1, groupe, telephone, description, verifie_le, archive }.
(function(root){'use strict';
const marker='koki.numero.utile',version=1,type='Informations utiles',categorie='Numéros utiles';
const groupes=['Urgences nationales','Santé','Sécurité','Administration','Eau et électricité','Transport','Autre'];
const telephoneValide=v=>typeof v==='string'&&/^\+?[0-9][0-9 ().-]{1,22}$/.test(v);
const dateValide=v=>{if(v==='')return true;if(!/^\d{4}-\d{2}-\d{2}$/.test(v))return false;const d=new Date(v+'T12:00:00Z');return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===v;};
function decode(row){if(row?.type!==type||row.categorie!==categorie)return null;try{const v=JSON.parse(row.texte);if(v.schema!==marker||v.version!==version||!groupes.includes(v.groupe)||!telephoneValide(v.telephone)||typeof v.description!=='string'||typeof v.verifie_le!=='string'||!dateValide(v.verifie_le)||typeof v.archive!=='boolean')return null;return v;}catch{return null;}}
function encode(v){const s={schema:marker,version,groupe:v.groupe,telephone:String(v.telephone||'').trim(),description:String(v.description||'').trim(),verifie_le:String(v.verifie_le||'').trim(),archive:v.archive===true};if(!groupes.includes(s.groupe))throw Error('Groupe invalide.');if(!telephoneValide(s.telephone))throw Error('Téléphone invalide (ex. +221 33 000 00 00, ou 17 pour un numéro court).');if(s.description.length>300)throw Error('Description trop longue (300 caractères maximum).');if(!dateValide(s.verifie_le))throw Error('Date de vérification invalide (AAAA-MM-JJ).');return JSON.stringify(s);}
// Lien d'appel : chiffres et « + » uniquement.
const lienAppel=telephone=>'tel:'+String(telephone).replace(/[^+0-9]/g,'');
root.KokiNumeroContract=Object.freeze({marker,version,type,categorie,groupes,decode,encode,lienAppel,telephoneValide});
if(typeof module!=='undefined'&&module.exports)module.exports=root.KokiNumeroContract;
})(globalThis);
