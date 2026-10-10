(function(root){'use strict';
const marker='koki.education.school',version=1;
const levels=['Préscolaire','Élémentaire','Moyen','Secondaire','Enseignement religieux','Formation professionnelle','Supérieur','Autre'];
function decode(row){if(row?.type!=='Informations utiles'||row.categorie!=='Éducation')return null;try{const v=JSON.parse(row.texte);if(v.schema!==marker||v.version!==version||!levels.includes(v.niveau)||!['Public','Privé','Communautaire','Autre'].includes(v.secteur)||!['telephone','horaires','description'].every(k=>typeof v[k]==='string')||typeof v.archive!=='boolean')return null;return v;}catch{return null;}}
function encode(v){const s={schema:marker,version,niveau:v.niveau,secteur:v.secteur,telephone:String(v.telephone||'').trim(),horaires:String(v.horaires||'').trim(),description:String(v.description||'').trim(),archive:v.archive===true};if(!levels.includes(s.niveau)||!['Public','Privé','Communautaire','Autre'].includes(s.secteur))throw Error('Type d’établissement invalide.');if(s.telephone&&!/^\+?[0-9 ()-]{6,24}$/.test(s.telephone))throw Error('Téléphone invalide.');if(s.description.length>10000||s.horaires.length>500)throw Error('Description ou horaires trop longs.');return JSON.stringify(s);}
root.KokiEducationContract=Object.freeze({marker,version,levels,decode,encode});
})(globalThis);
