// Contrat commun « Commerces & Services » entre Koki Connect Admin et l'application publique.
// À conserver IDENTIQUE dans les deux dépôts (admin : src/commerce-contract.js,
// public : assets/business/commerce-contract.js). Les tests vérifient son empreinte.
// Le serveur (supabase/proposals/commerce-modernisation.sql) reste l'autorité : ce contrat
// sert à l'affichage, aux formulaires et aux liens ; il ne remplace aucun contrôle serveur.
(function(root){'use strict';
const version=1;
// Relations : Professionnel → Boutique → Produits ; Professionnel → Services.
const parents=Object.freeze({boutiques:'professionnels',produits:'boutiques',services:'professionnels'});
const statuts=Object.freeze({
 professionnels:Object.freeze(['À valider','En attente','Actif','Refusé','Suspendu','Archivé']),
 boutiques:Object.freeze(['À valider','Actif','Refusé','Fermé','Archivé']),
 produits:Object.freeze(['Disponible','Épuisé','Masqué','Archivé']),
 services:Object.freeze(['Disponible','Indisponible','Masqué','Archivé'])
});
// Statuts visibles dans le catalogue public (si toute la chaîne parente est active).
const publics=Object.freeze({professionnels:['Actif'],boutiques:['Actif'],produits:['Disponible','Épuisé'],services:['Disponible']});
// « À valider » (inscription prestataire historique) et « En attente » (fiche commerçant) = même file de validation.
const enValidation=Object.freeze(['À valider','En attente']);
// Décisions de l'administration : statut de départ → statut d'arrivée (identique au SQL).
const decisions=Object.freeze({
 professionnels:{approve:{from:['À valider','En attente','Refusé','Suspendu','Archivé'],to:'Actif'},reject:{from:['À valider','En attente'],to:'Refusé'},suspend:{from:['Actif'],to:'Suspendu'},archive:{from:['À valider','En attente','Actif','Refusé','Suspendu'],to:'Archivé'}},
 boutiques:{approve:{from:['À valider','Refusé','Fermé','Archivé'],to:'Actif'},reject:{from:['À valider'],to:'Refusé'},suspend:{from:['Actif'],to:'Fermé'},archive:{from:['À valider','Actif','Refusé','Fermé'],to:'Archivé'}},
 produits:{approve:{from:['Masqué','Archivé'],to:'Disponible'},suspend:{from:['Disponible','Épuisé','Masqué'],to:'Masqué'},archive:{from:['Disponible','Épuisé','Masqué'],to:'Archivé'}},
 services:{approve:{from:['Masqué','Archivé'],to:'Disponible'},suspend:{from:['Disponible','Indisponible','Masqué'],to:'Masqué'},archive:{from:['Disponible','Indisponible','Masqué'],to:'Archivé'}}
});
const libellesDecision=Object.freeze({approve:'Approuver',reject:'Refuser',suspend:'Suspendre',archive:'Archiver'});
// Disponibilités que le professionnel choisit lui-même (hors blocage par l'administration).
const disponibilites=Object.freeze({produits:['Disponible','Épuisé','Masqué'],services:['Disponible','Indisponible','Masqué']});
const tarifs=Object.freeze(['fixe','devis']);
const maxPhotos=5;
// Suggestions de saisie (le serveur accepte un texte libre de 1 à 100 caractères).
const categoriesCommerce=Object.freeze(['Alimentation','Boutique et quincaillerie','Vêtements et tissus','Beauté et coiffure','Téléphonie et électronique','Maison','Agriculture et élevage','Restauration','Santé et pharmacie','Autre']);
const metiers=Object.freeze(['Plomberie','Électricité','Maçonnerie','Menuiserie','Couture','Mécanique','Coiffure','Transport et livraison','Informatique','Cours et formation','Autre']);
// Liste de secours ; la liste de référence est la table koki_localites (modifiable dans l'admin).
// Source : OpenStreetMap (assets/koki-carte.json), type village/quartier à confirmer.
const localitesParDefaut=Object.freeze(['Bellel Ouolof','Coki','Kanène Khar','Keur Ngoura','Loumène','Ndare Wakhy','Ndiobene Belal','Ouarak','Pallene','Thiourour']);

// Numéros : format international +XXXXXXXX ; numéros sénégalais à 9 chiffres (7x ou 3x) complétés en +221.
function normaliserTelephone(value){
 let v=String(value??'').trim();if(!v)return null;
 v=v.replace(/[\s.\-()\/]/g,'');
 if(v.startsWith('00'))v='+'+v.slice(2);
 if(/^221[37]\d{8}$/.test(v))v='+'+v;
 if(/^[37]\d{8}$/.test(v))v='+221'+v;
 if(v.startsWith('+221')&&!/^\+221[37]\d{8}$/.test(v))return null;
 return /^\+[1-9]\d{7,14}$/.test(v)?v:null;
}
function afficherTelephone(value){const v=normaliserTelephone(value);if(!v)return '';const m=/^\+221(\d{2})(\d{3})(\d{2})(\d{2})$/.exec(v);return m?'+221 '+m.slice(1).join(' '):v;}
function lienAppel(value){const v=normaliserTelephone(value);return v?'tel:'+v:null;}
function lienWhatsApp(value,message){const v=normaliserTelephone(value);if(!v)return null;return 'https://wa.me/'+v.slice(1)+(message?'?text='+encodeURIComponent(message):'');}
// Prix entiers en FCFA, espaces insécables (pas de coupure de ligne au milieu d'un prix).
function formaterPrix(n){if(typeof n!=='number'||!Number.isInteger(n)||n<0)return '';return String(n).replace(/\B(?=(\d{3})+(?!\d))/g,' ')+' FCFA';}
function libellePrix(item){if(!item)return '';if(item.tarif==='devis'||item.prix===null||item.prix===undefined)return 'Sur devis';return formaterPrix(item.prix);}
function messageCommande({produit,prix,boutique,quantite=1}){
 const q=Number.isInteger(quantite)&&quantite>0?quantite:1;
 return 'Bonjour'+(boutique?' '+String(boutique).trim():'')+', je souhaite commander via Koki Connect :\n- '+String(produit||'').trim()+' × '+q+(Number.isInteger(prix)?' — '+formaterPrix(prix)+(q>1?' l’unité':''):'')+'\nEst-il disponible ?';
}
function lienCommandeWhatsApp(telephone,commande){return lienWhatsApp(telephone,messageCommande(commande));}
// Même clé que l'index anti-doublon du serveur : minuscules, espaces réduits.
function cleNom(nom){return String(nom??'').trim().replace(/\s+/g,' ').toLowerCase();}
function transition(kind,statut,decision){const d=decisions[kind]?.[decision];return d&&d.from.includes(statut)?d.to:null;}
function decisionsPossibles(kind,statut){return Object.keys(decisions[kind]||{}).filter(d=>transition(kind,statut,d));}
function estPublic(kind,statut){return (publics[kind]||[]).includes(statut);}
// Explication affichée au professionnel pour chaque statut de ses fiches.
const explications=Object.freeze({
 'À valider':'En attente de validation par l’administration de Koki Connect. Elle n’est pas encore visible dans le catalogue.',
 'En attente':'En attente de validation par l’administration de Koki Connect. Elle n’est pas encore visible dans le catalogue.',
 'Actif':'Validée et visible dans le catalogue public.',
 'Refusé':'Refusée par l’administration. Corrigez-la puis renvoyez-la pour une nouvelle validation.',
 'Suspendu':'Suspendue par l’administration : contactez Koki Connect.',
 'Fermé':'Suspendue par l’administration : contactez Koki Connect.',
 'Archivé':'Archivée : elle n’apparaît plus dans le catalogue.',
 'Disponible':'En ligne dans le catalogue.',
 'Épuisé':'Affiché comme épuisé : les clients ne peuvent pas le commander.',
 'Indisponible':'Masqué temporairement : vous êtes indisponible.',
 'Masqué':'Masqué : il n’apparaît pas dans le catalogue.'
});
// Revalidation d'une fiche en ligne : champs comparés entre la version publiée et la proposition.
const champsSensibles=Object.freeze([['nom','Nom'],['type','Activité'],['telephone','Téléphone'],['whatsapp','WhatsApp'],['photos','Photos']]);
function comparerModification(payload){
 const m=payload?.modification;if(!m||typeof m!=='object')return [];
 const valeur=(source,k)=>k==='photos'?(Array.isArray(source?.photos)?source.photos:[]):(source?.[k]??null);
 return champsSensibles.map(([champ,label])=>{const avant=valeur(payload,champ),apres=valeur(m,champ);return {champ,label,avant,apres,modifie:JSON.stringify(avant)!==JSON.stringify(apres)};});
}
const libellesDemande=Object.freeze({inscription:'Nouvelle inscription',boutique:'Nouvelle boutique',modification:'Modification d’une fiche en ligne'});
function explicationStatut(kind,statut){return (statuts[kind]||[]).includes(statut)?explications[statut]:'';}
// Contrôles de formulaire (repris par le serveur) ; renvoie la liste des erreurs en français.
function verifierOffre(kind,v){
 const e=[];const nom=String(v?.nom??'').trim();
 if(nom.length<1||nom.length>180)e.push('Nom obligatoire (180 caractères maximum).');
 const entier=(x,max)=>typeof x==='number'&&Number.isInteger(x)&&x>=0&&x<=max;
 if(kind==='produits'){
  if(!entier(v.prix,1e9))e.push('Prix en FCFA obligatoire (nombre entier).');
  if(v.ancien_prix!==null&&v.ancien_prix!==undefined&&(!entier(v.ancien_prix,1e9)||!(v.ancien_prix>v.prix)))e.push('L’ancien prix doit être supérieur au prix actuel.');
  if(!entier(v.stock,1e6))e.push('Stock invalide (nombre entier).');
 }
 if(kind==='services'){
  if(!tarifs.includes(v.tarif))e.push('Choisissez un tarif fixe ou sur devis.');
  else if(v.tarif==='fixe'&&!entier(v.prix,1e9))e.push('Tarif fixe : prix en FCFA obligatoire.');
  else if(v.tarif==='devis'&&v.prix!==null&&v.prix!==undefined)e.push('Tarif sur devis : ne pas indiquer de prix.');
 }
 if(v?.photos!==undefined&&(!Array.isArray(v.photos)||v.photos.length>maxPhotos||new Set(v.photos).size!==v.photos.length))e.push('Cinq photos différentes au maximum.');
 if(v?.whatsapp&&!normaliserTelephone(v.whatsapp))e.push('Numéro WhatsApp invalide.');
 return e;
}
root.KokiCommerceContract=Object.freeze({version,parents,statuts,publics,enValidation,decisions,libellesDecision,disponibilites,tarifs,maxPhotos,categoriesCommerce,metiers,localitesParDefaut,
 normaliserTelephone,afficherTelephone,lienAppel,lienWhatsApp,formaterPrix,libellePrix,messageCommande,lienCommandeWhatsApp,cleNom,transition,decisionsPossibles,estPublic,explicationStatut,verifierOffre,champsSensibles,comparerModification,libellesDemande});
if(typeof module!=='undefined'&&module.exports)module.exports=root.KokiCommerceContract;
})(globalThis);
