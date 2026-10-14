// Contrat commun « Sports & ASC » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/sport-contract.js, public : assets/portail/sport-contract.js).
// Stockage : public.koki_contents, type=Sports & ASC, texte = JSON versionné. Aucune migration.
//  - categorie « Équipe » : une ASC ou équipe (logo = image de la fiche) ;
//  - categorie « Match »  : un match (date = evenement, terrain = lieu) avec son score et son statut.
// Le classement n'est pas saisi : il est calculé à partir des matchs terminés (3 points victoire, 1 nul, 0 défaite).
(function(root){'use strict';
const type='Sports & ASC',version=1;
const EQUIPE='koki.sport.equipe',MATCH='koki.sport.match';
const disciplines=['Football','Basket-ball','Lutte','Handball','Volley-ball','Athlétisme','Autre'];
const statuts=['À venir','En direct','Terminé','Reporté'];
const telRe=/^\+?[0-9 ()-]{6,24}$/,couleurRe=/^#[0-9a-f]{6}$/,uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const txt=(v,max)=>typeof v==='string'&&v.length<=max;
const score=v=>v===null||(Number.isInteger(v)&&v>=0&&v<=999);
function joueurValide(j){return j&&txt(j.nom,80)&&j.nom.trim().length>0&&txt(j.poste,40)&&(j.numero===null||(Number.isInteger(j.numero)&&j.numero>=0&&j.numero<=99));}
function checkEquipe(v){
 if(!v||v.schema!==EQUIPE||v.version!==version||!disciplines.includes(v.discipline))return false;
 if(!txt(v.quartier,80)||!txt(v.president,80)||!txt(v.poule,40)||!txt(v.description,2000)||!txt(v.telephone,24))return false;
 if(v.telephone&&!telRe.test(v.telephone))return false;
 if(!Array.isArray(v.couleurs)||v.couleurs.length<1||v.couleurs.length>2||!v.couleurs.every(c=>couleurRe.test(c)))return false;
 if(!Array.isArray(v.joueurs)||v.joueurs.length>60||!v.joueurs.every(joueurValide))return false;
 return typeof v.archive==='boolean';
}
function checkMatch(v){
 if(!v||v.schema!==MATCH||v.version!==version||!statuts.includes(v.statut)||!disciplines.includes(v.discipline))return false;
 if(!txt(v.competition,80)||!v.competition.trim()||!txt(v.poule,40)||!txt(v.journee,40)||!txt(v.commentaire,500))return false;
 if(!uuidRe.test(v.domicile)||!uuidRe.test(v.exterieur)||v.domicile===v.exterieur)return false;
 if(!score(v.score_domicile)||!score(v.score_exterieur)||(v.score_domicile===null)!==(v.score_exterieur===null))return false;
 if(v.statut==='Terminé'&&v.score_domicile===null)return false;
 return typeof v.archive==='boolean';
}
function lire(row,cat,marker,check){if(row?.type!==type||row.categorie!==cat)return null;try{const v=JSON.parse(row.texte);return v&&v.schema===marker&&check(v)?v:null;}catch{return null;}}
const decodeEquipe=row=>lire(row,'Équipe',EQUIPE,checkEquipe);
const decodeMatch=row=>lire(row,'Match',MATCH,checkMatch);
const entier=x=>x===''||x===null||x===undefined?null:Number(x);
// Joueurs saisis une ligne par joueur : « 10 - Moussa Diop - Attaquant » (numéro et poste facultatifs).
function lireJoueurs(texte){
 if(Array.isArray(texte))return texte;
 return String(texte||'').split(/\r?\n/).map(l=>l.trim()).filter(Boolean).map(l=>{const p=l.split(/\s+[-–—|]\s+/);let numero=null;if(/^\d{1,2}$/.test(p[0]||'')){numero=Number(p.shift());}return {numero,nom:(p[0]||'').trim(),poste:(p[1]||'').trim()};});
}
function encodeEquipe(v){
 const s={schema:EQUIPE,version,discipline:v.discipline||'Football',quartier:String(v.quartier||'').trim(),president:String(v.president||'').trim(),telephone:String(v.telephone||'').trim(),
  poule:String(v.poule||'').trim(),couleurs:(Array.isArray(v.couleurs)?v.couleurs:[v.couleurs]).filter(Boolean).map(c=>String(c).toLowerCase()).slice(0,2),
  description:String(v.description||'').trim(),joueurs:lireJoueurs(v.joueurs).map(j=>({numero:j.numero===null||j.numero===undefined||j.numero===''?null:Number(j.numero),nom:String(j.nom||'').trim(),poste:String(j.poste||'').trim()})),archive:v.archive===true};
 if(!s.couleurs.length)s.couleurs=['#087a3d'];
 if(!checkEquipe(s)){
  if(!disciplines.includes(s.discipline))throw Error('Choisissez la discipline.');
  if(s.telephone&&!telRe.test(s.telephone))throw Error('Téléphone invalide.');
  if(s.joueurs.length>60)throw Error('60 joueurs au maximum.');
  if(!s.joueurs.every(joueurValide))throw Error('Liste des joueurs invalide : une ligne par joueur, « numéro - nom - poste » (numéro de 0 à 99).');
  throw Error('Fiche équipe invalide.');
 }
 return JSON.stringify(s);
}
function encodeMatch(v){
 const s={schema:MATCH,version,discipline:v.discipline||'Football',competition:String(v.competition||'').trim(),poule:String(v.poule||'').trim(),journee:String(v.journee||'').trim(),
  domicile:String(v.domicile||''),exterieur:String(v.exterieur||''),statut:v.statut||'À venir',score_domicile:entier(v.score_domicile),score_exterieur:entier(v.score_exterieur),
  commentaire:String(v.commentaire||'').trim(),archive:v.archive===true};
 if(s.statut==='À venir'||s.statut==='Reporté'){if(v.score_domicile===''||v.score_domicile===undefined)s.score_domicile=null;if(v.score_exterieur===''||v.score_exterieur===undefined)s.score_exterieur=null;}
 if(s.statut==='En direct'){if(s.score_domicile===null)s.score_domicile=0;if(s.score_exterieur===null)s.score_exterieur=0;}
 if(!checkMatch(s)){
  if(!s.competition)throw Error('Indiquez la compétition (ex. Navétanes 2026).');
  if(!uuidRe.test(s.domicile)||!uuidRe.test(s.exterieur))throw Error('Choisissez les deux équipes.');
  if(s.domicile===s.exterieur)throw Error('Une équipe ne peut pas jouer contre elle-même.');
  if(s.statut==='Terminé'&&(s.score_domicile===null||s.score_exterieur===null))throw Error('Score requis pour un match terminé.');
  if(!score(s.score_domicile)||!score(s.score_exterieur)||(s.score_domicile===null)!==(s.score_exterieur===null))throw Error('Score invalide.');
  throw Error('Match invalide.');
 }
 return JSON.stringify(s);
}
// Classement d'une compétition (et d'une poule) : matchs terminés seulement, équipes connues seulement.
// Départage : points, différence de buts, buts marqués, puis nom.
function classement(matchs,equipes,{competition,poule=''}={}){
 const table=new Map();
 const ligne=id=>{if(!table.has(id)){const e=equipes.get(id);table.set(id,{id,nom:e?e.nom:'Équipe',j:0,g:0,n:0,p:0,bp:0,bc:0,diff:0,pts:0,forme:[]});}return table.get(id);};
 const retenus=matchs.filter(m=>!m.archive&&m.competition===competition&&(!poule||m.poule===poule)&&equipes.has(m.domicile)&&equipes.has(m.exterieur));
 for(const m of retenus){ligne(m.domicile);ligne(m.exterieur);}
 for(const m of [...retenus].sort((a,b)=>(a.date||'').localeCompare(b.date||''))){if(m.statut!=='Terminé')continue;
  const d=ligne(m.domicile),e=ligne(m.exterieur),sd=m.score_domicile,se=m.score_exterieur;
  d.j++;e.j++;d.bp+=sd;d.bc+=se;e.bp+=se;e.bc+=sd;
  if(sd>se){d.g++;e.p++;d.pts+=3;d.forme.push('V');e.forme.push('D');}else if(sd<se){e.g++;d.p++;e.pts+=3;e.forme.push('V');d.forme.push('D');}else{d.n++;e.n++;d.pts++;e.pts++;d.forme.push('N');e.forme.push('N');}}
 const rows=[...table.values()].map(x=>({...x,diff:x.bp-x.bc,forme:x.forme.slice(-5)}));
 rows.sort((a,b)=>b.pts-a.pts||b.diff-a.diff||b.bp-a.bp||a.nom.localeCompare(b.nom,'fr'));
 return rows.map((x,i)=>({rang:i+1,...x}));
}
// Compétitions et poules présentes dans les matchs (les plus récentes d'abord).
function competitions(matchs){const vus=new Map();for(const m of matchs){if(m.archive)continue;const k=m.competition;if(!vus.has(k))vus.set(k,{nom:k,poules:new Set(),date:''});const c=vus.get(k);if(m.poule)c.poules.add(m.poule);if((m.date||'')>c.date)c.date=m.date||'';}
 return [...vus.values()].sort((a,b)=>b.date.localeCompare(a.date)||a.nom.localeCompare(b.nom,'fr')).map(c=>({nom:c.nom,poules:[...c.poules].sort((a,b)=>a.localeCompare(b,'fr'))}));}
function initiales(nom){const m=String(nom||'').replace(/^(ASC|AS|US|FC|ES)\s+/i,'').trim().split(/\s+/).filter(Boolean);return ((m[0]||'?')[0]+(m[1]?m[1][0]:(m[0]||'')[1]||'')).toUpperCase();}
root.KokiSportContract=Object.freeze({type,version,EQUIPE,MATCH,disciplines,statuts,decodeEquipe,decodeMatch,encodeEquipe,encodeMatch,lireJoueurs,classement,competitions,initiales});
})(typeof globalThis!=='undefined'?globalThis:this);
