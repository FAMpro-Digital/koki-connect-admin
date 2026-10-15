// Contrat commun « Rubriques » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/rubriques-contract.js,
// public : assets/portail/rubriques-contract.js). Les tests vérifient son empreinte.
// L'accueil public est la référence : mêmes rubriques, même ordre, mêmes noms, icônes et couleurs
// dans le menu de l'administration. Chaque type de contenu et chaque écran métier appartient à une seule entrée.
(function(root){'use strict';
const gele=x=>Object.freeze(x);
// Les 8 rubriques de l'accueil public, dans l'ordre d'affichage.
const rubriques=gele([
 gele({cle:'transport',nom:'Transport',icone:'🚕',couleur:'#245d88',
  numeros:gele(['Transport']),ecrans:gele([gele(['courses','Courses']),gele(['chauffeurs','Chauffeurs']),gele(['vehicules','Véhicules']),gele(['tarifs','Tarifs Transport']),gele(['signalements','Signalements'])])}),
 gele({cle:'commerce',nom:'Commerces & Services',icone:'🛍️',couleur:'#c76a00',lieux:'Commerces',
  ecrans:gele([gele(['boutique-en-ligne','Boutique en ligne']),gele(['validations','Validations']),gele(['professionnels','Fiches professionnelles']),gele(['boutiques','Boutiques']),gele(['produits','Produits']),
   gele(['services','Services']),gele(['commandes','Commandes']),gele(['demandes_services','Demandes de services'])])}),
 gele({cle:'education',nom:'Éducation',icone:'🎓',couleur:'#087dff',lieux:'Éducation',ecrans:gele([gele(['education-apercu','Vue d’ensemble']),gele(['education','Établissements scolaires']),gele(['livres','Bibliothèque (livres)'])])}),
 gele({cle:'opportunites',nom:'Emplois & Opportunités',icone:'💼',couleur:'#008397',type:'Opportunités',ecrans:gele([gele(['offres','Offres et opportunités'])])}),
 gele({cle:'sports',nom:'Sport',icone:'⚽',couleur:'#008444',type:'Sports & ASC',lieux:'Sports',ecrans:gele([gele(['sport-matchs','Matchs et résultats']),gele(['sport-equipes','Équipes / ASC'])])}),
 gele({cle:'sante',nom:'Santé',icone:'🏥',couleur:'#d8004f',lieux:'Santé',categorie:'Santé',numeros:gele(['Santé']),ecrans:gele([gele(['sante','Structures de santé'])])}),
 gele({cle:'evenements',nom:'Événements',icone:'📅',couleur:'#ef153b',type:'Événements',ecrans:gele([gele(['evenements','Agenda des événements'])])}),
 gele({cle:'services_publics',nom:'Services publics',icone:'🏛️',couleur:'#820ed8',lieux:'Services publics',numeros:gele(['Administration','Eau et électricité','Sécurité']),ecrans:gele([gele(['services-publics','Annuaire des services']),gele(['demarches','Guides des démarches']),gele(['avis-officiels','Avis officiels'])])})
]);
// Les publications de l'accueil public (blocs « Actualités de Koki », « Annonces »…), puis les numéros utiles et les lieux de la carte.
const publications=gele([
 gele({cle:'actualites',nom:'Actualités',icone:'📰',type:'Actualités'}),
 gele({cle:'annonces',nom:'Annonces',icone:'📢',type:'Annonces'}),
 gele({cle:'publicites',nom:'Publicités',icone:'📣',type:'Publicités'}),
 gele({cle:'informations',nom:'Informations utiles',icone:'ℹ️',type:'Informations utiles'}),
 gele({cle:'numeros',nom:'Numéros utiles',icone:'📞',ecran:'numeros'}),
 // Lieux de la carte publique (Carte, « Autour de moi », Transport, Services publics) : ajouts et corrections.
 gele({cle:'lieux',nom:'Lieux de la carte',icone:'📍',ecran:'lieux'})
]);
// Sous-rubriques « Opportunités jeunes » de l'application publique et catégories de contenu correspondantes.
const sousRubriques=gele({'Opportunités':gele([
 gele({nom:'Emplois',icone:'💼',categories:gele(['Emploi'])}),
 gele({nom:'Stages',icone:'🤝',categories:gele(['Stage'])}),
 gele({nom:'Formations',icone:'🎓',categories:gele(['Formation'])}),
 gele({nom:'Concours',icone:'🏆',categories:gele(['Concours'])}),
 gele({nom:'Bourses',icone:'📚',categories:gele(['Bourse'])}),
 gele({nom:'Financements',icone:'🌱',categories:gele(['Financement','Appel à projets'])})
])});
// Rubrique (ou publication) d'un écran d'administration, d'un type de contenu ou d'une route « contenus:<type> ».
function rubriqueDe(cle){
 if(!cle)return null;
 const type=String(cle).startsWith('contenus:')?String(cle).split(':')[1]:cle;
 for(const r of rubriques){if(r.cle===cle||r.type===type||r.ecrans.some(([e])=>e===cle)||('rubrique:'+r.cle)===cle)return r;}
 for(const p of publications){if(p.cle===cle||p.type===type||p.ecran===cle)return p;}
 return null;
}
// Fiche « Renseignements » d'une rubrique : présentation, responsable, contact, affichage sur l'accueil.
// Stockage : koki_contents, type=Informations utiles, categorie=Rubriques, titre = nom de la rubrique, texte = JSON versionné.
const FICHE='koki.rubrique.fiche',categorieFiche='Rubriques',telRe=/^\+?[0-9 ()-]{6,24}$/;
const txt=(v,max)=>typeof v==='string'&&v.length<=max;
function checkFiche(v){return !!v&&v.schema===FICHE&&v.version===1&&rubriques.some(r=>r.cle===v.cle)&&txt(v.presentation,600)&&txt(v.responsable,120)&&txt(v.telephone,24)&&(!v.telephone||telRe.test(v.telephone))&&txt(v.horaires,120)&&typeof v.visible==='boolean';}
function decodeFiche(row){if(row?.type!=='Informations utiles'||row.categorie!==categorieFiche)return null;try{const v=JSON.parse(row.texte);return checkFiche(v)?v:null;}catch{return null;}}
function encodeFiche(v){const s={schema:FICHE,version:1,cle:String(v.cle||''),presentation:String(v.presentation||'').trim(),responsable:String(v.responsable||'').trim(),telephone:String(v.telephone||'').trim(),horaires:String(v.horaires||'').trim(),visible:v.visible!==false};
 if(!checkFiche(s)){if(!rubriques.some(r=>r.cle===s.cle))throw Error('Rubrique inconnue.');if(s.telephone&&!telRe.test(s.telephone))throw Error('Téléphone du responsable invalide.');if(s.presentation.length>600)throw Error('Présentation trop longue (600 caractères maximum).');throw Error('Renseignements invalides.');}
 return JSON.stringify(s);}
// Fiche la plus récente de chaque rubrique (publiée uniquement côté application).
function fiches(rows){const out={};for(const row of rows||[]){const v=decodeFiche(row);if(!v)continue;const t=Date.parse(row.updated_at||row.publication)||0;if(!out[v.cle]||t>out[v.cle].t)out[v.cle]={row,v,t};}return out;}
function libelle(r){return r?r.icone+' '+r.nom:'';}
function categoriesSousRubrique(type,nom){const s=(sousRubriques[type]||[]).find(x=>x.nom===nom);return s?s.categories:null;}
root.KokiRubriquesContract=gele({rubriques,publications,sousRubriques,rubriqueDe,libelle,categoriesSousRubrique,categorieFiche,decodeFiche,encodeFiche,fiches});
if(typeof module!=='undefined'&&module.exports)module.exports=root.KokiRubriquesContract;
})(globalThis);
