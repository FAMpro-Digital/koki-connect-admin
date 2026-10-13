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
  ecrans:gele([gele(['courses','Courses']),gele(['chauffeurs','Chauffeurs']),gele(['vehicules','Véhicules']),gele(['tarifs','Tarifs Transport'])])}),
 gele({cle:'commerce',nom:'Commerces & Services',icone:'🛍️',couleur:'#c76a00',
  ecrans:gele([gele(['validations','Validations']),gele(['professionnels','Fiches professionnelles']),gele(['boutiques','Boutiques']),gele(['produits','Produits']),
   gele(['services','Services']),gele(['commandes','Commandes']),gele(['demandes_services','Demandes de services'])])}),
 gele({cle:'education',nom:'Éducation',icone:'🎓',couleur:'#087dff',ecrans:gele([gele(['education-apercu','Vue d’ensemble']),gele(['education','Établissements scolaires']),gele(['livres','Bibliothèque (livres)'])])}),
 gele({cle:'opportunites',nom:'Emplois & Opportunités',icone:'💼',couleur:'#008397',type:'Opportunités',ecrans:gele([])}),
 gele({cle:'sports',nom:'Sports & ASC',icone:'⚽',couleur:'#008444',type:'Sports & ASC',ecrans:gele([])}),
 gele({cle:'sante',nom:'Santé',icone:'🏥',couleur:'#d8004f',lieux:'Santé',categorie:'Santé',numeros:gele(['Santé']),ecrans:gele([])}),
 gele({cle:'evenements',nom:'Événements',icone:'📅',couleur:'#ef153b',type:'Événements',ecrans:gele([])}),
 gele({cle:'services_publics',nom:'Services publics',icone:'🏛️',couleur:'#820ed8',lieux:'Services publics',numeros:gele(['Administration','Eau et électricité','Sécurité']),ecrans:gele([])})
]);
// Les publications de l'accueil public (blocs « Actualités de Koki », « Annonces »…), puis les numéros utiles.
const publications=gele([
 gele({cle:'actualites',nom:'Actualités',icone:'📰',type:'Actualités'}),
 gele({cle:'annonces',nom:'Annonces',icone:'📢',type:'Annonces'}),
 gele({cle:'publicites',nom:'Publicités',icone:'📣',type:'Publicités'}),
 gele({cle:'informations',nom:'Informations utiles',icone:'ℹ️',type:'Informations utiles'}),
 gele({cle:'numeros',nom:'Numéros utiles',icone:'📞',ecran:'numeros'})
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
function libelle(r){return r?r.icone+' '+r.nom:'';}
function categoriesSousRubrique(type,nom){const s=(sousRubriques[type]||[]).find(x=>x.nom===nom);return s?s.categories:null;}
root.KokiRubriquesContract=gele({rubriques,publications,sousRubriques,rubriqueDe,libelle,categoriesSousRubrique});
if(typeof module!=='undefined'&&module.exports)module.exports=root.KokiRubriquesContract;
})(globalThis);
