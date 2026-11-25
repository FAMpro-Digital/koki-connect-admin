// Module Football — client d'administration (PRÉPARATION, pas encore branché sur un écran).
// Construit et contrôle les appels à public.koki_foot_admin avant envoi ; le serveur reste l'autorité
// (droits, double authentification, révisions, verrous, motifs). `appel(command, input)` est fourni par
// l'écran : en production db.rpc('koki_foot_admin', {command, input}).
export const PERIODES=['mi_temps_1','mi_temps_2','prolongation_1','prolongation_2','tirs_au_but'];
export const LIBELLES_PERIODES={mi_temps_1:'1re mi-temps',mi_temps_2:'2e mi-temps',prolongation_1:'1re prolongation',prolongation_2:'2e prolongation',tirs_au_but:'Tirs au but'};
export const TYPES_SEANCE=['tab_reussi','tab_manque'];
export const TYPES_JEU=['but','but_csc','penalty','penalty_manque','carton_jaune','carton_rouge','remplacement'];
export const STATUTS=['À venir','En direct','Mi-temps','Prolongations','Tirs au but','Terminé','Reporté','Annulé','Interrompu','Suspendu'];
export const VERROUS=['score','statut','evenements','programmation'];

const entier=v=>v===''||v===null||v===undefined?undefined:Number(v);
const motifOk=m=>typeof m==='string'&&m.trim().length>=3;
function exiger(cond,msg){if(!cond)throw Error(msg);}

// Heure saisie dans un champ datetime-local, à l'heure de Koki (Africa/Dakar = UTC toute l'année).
export function versISO(local){exiger(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(local||''),'Date et heure du match requises.');return new Date(local+':00Z').toISOString();}

// Nécessite-t-on un motif ? (même règle que le serveur, pour l'afficher avant l'envoi)
export function motifRequis(match,{scoreChange=false,statutChange=false,programmationChange=false}={}){
 if(programmationChange&&match?.source==='api')return true;
 return (scoreChange||statutChange)&&(match?.source==='api'||match?.statut==='Terminé');
}

export function evenement(match,{type,periode,minute,minute_add,equipe_id,joueur='',joueur2='',motif,maj_score=true}){
 exiger(PERIODES.includes(periode),'Choisissez la période.');
 exiger(TYPES_SEANCE.includes(type)?periode==='tirs_au_but':TYPES_JEU.includes(type)&&periode!=='tirs_au_but','Type d’événement incompatible avec la période.');
 exiger(periode.startsWith('mi_temps')||match?.competition?.type!=='Championnat','Pas de prolongation ni de tirs au but en championnat.');
 exiger([match?.domicile?.id,match?.exterieur?.id].includes(equipe_id),'Choisissez l’équipe.');
 const m=entier(minute),a=entier(minute_add);
 exiger(m===undefined||(Number.isInteger(m)&&m>=0&&m<=150),'Minute invalide.');exiger(a===undefined||(Number.isInteger(a)&&a>=0&&a<=30),'Temps additionnel invalide.');
 if(match?.source==='api')exiger(motifOk(motif),'Motif requis pour un match importé.');
 const input={match_id:match.id,revision:match.revision,type,periode,equipe_id,joueur:joueur.trim(),joueur2:joueur2.trim(),maj_score};
 if(m!==undefined&&periode!=='tirs_au_but')input.minute=m;if(a!==undefined&&periode!=='tirs_au_but')input.minute_add=a;if(motif)input.motif=motif.trim();
 return input;
}
export function score(match,{statut,minute,score_domicile,score_exterieur,pro_domicile,pro_exterieur,tab_domicile,tab_exterieur,motif}){
 exiger(STATUTS.includes(statut),'Statut invalide.');
 const input={id:match.id,revision:match.revision,statut};
 for(const [k,v] of Object.entries({minute,score_domicile,score_exterieur,pro_domicile,pro_exterieur,tab_domicile,tab_exterieur})){const n=entier(v);if(n!==undefined){exiger(Number.isInteger(n)&&n>=0,'Nombre invalide : '+k);input[k]=n;}}
 for(const [a,b] of [['score_domicile','score_exterieur'],['pro_domicile','pro_exterieur'],['tab_domicile','tab_exterieur']])exiger((a in input)===(b in input),'Indiquez le score des deux équipes.');
 const scoreChange=['score_domicile','score_exterieur','pro_domicile','pro_exterieur','tab_domicile','tab_exterieur'].some(k=>k in input&&input[k]!==match[k]);
 if(motifRequis(match,{scoreChange,statutChange:statut!==match.statut}))exiger(motifOk(motif),'Motif de la correction requis.');
 if(motif)input.motif=motif.trim();
 return input;
}
export function programmation(match,{date_local,lieu,motif}){
 const input={id:match.id,revision:match.revision};
 if(date_local)input.date_match=versISO(date_local);if(typeof lieu==='string')input.lieu=lieu.trim();
 if(motifRequis(match,{programmationChange:true}))exiger(motifOk(motif),'Motif requis pour corriger l’horaire ou le lieu d’un match importé.');
 if(motif)input.motif=motif.trim();
 return input;
}
export function deverrouiller(match,{verrous=VERROUS,motif}){
 exiger(Array.isArray(verrous)&&verrous.length&&verrous.every(v=>VERROUS.includes(v)),'Choisissez au moins un verrou.');
 exiger(motifOk(motif),'Motif requis.');
 return {id:match.id,revision:match.revision,verrous:[...verrous],motif:motif.trim()};
}
export function resoudreConflit(conflit,{decision,motif}){
 exiger(['garder','accepter_api'].includes(decision),'Décision : garder ou accepter la valeur du fournisseur.');exiger(motifOk(motif),'Motif requis.');
 return {id:conflit.id,decision,motif:motif.trim()};
}

// Client : chaque méthode contrôle puis appelle le serveur.
export function creerClientFoot(appel){
 return {
  etat:(depuis)=>appel('etat',depuis?{depuis}:{}),
  evenements:match_id=>appel('evenements',{match_id}),
  programmationDe:match_id=>appel('programmation',{match_id}),
  conflits:(tous=false)=>appel('conflits',{tous}),
  verifierJournal:()=>appel('verifier_journal',{}),
  ajouterEvenement:(match,v)=>appel('ajouter_evenement',evenement(match,v)),
  retirerEvenement:(id,motif,maj_score=true)=>{exiger(motifOk(motif),'Motif requis.');return appel('retirer_evenement',{id,motif:motif.trim(),maj_score});},
  score:(match,v)=>appel('score',score(match,v)),
  corrigerProgrammation:(match,v)=>appel('enregistrer_match',programmation(match,v)),
  deverrouiller:(match,v)=>appel('deverrouiller',deverrouiller(match,v)),
  resoudreConflit:(conflit,v)=>appel('resoudre_conflit',resoudreConflit(conflit,v)),
 };
}
