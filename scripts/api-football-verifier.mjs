#!/usr/bin/env node
// Vérification RÉELLE de la couverture API-Football (aucune écriture en base) — à lancer par le propriétaire.
// La clé est lue dans l'environnement, jamais en argument (historique du terminal) et jamais affichée :
//   API_FOOTBALL_KEY=… node scripts/api-football-verifier.mjs [Senegal]
// Coût : 1 requête (ligues du pays) ; la requête « status » n'est pas décomptée par le fournisseur.
import {creerClient,expurger} from '../server/foot/api-football.js';
import {verifier} from '../server/foot/synchronisation.js';
const cle=process.env.API_FOOTBALL_KEY||'';
const pays=/^[A-Za-z][A-Za-z -]{1,40}$/.test(process.argv[2]||'')?process.argv[2]:'Senegal';
try{
 const api=creerClient({cle});
 const v=await verifier({api,pays});
 console.log('Compte :',JSON.stringify(v.compte));
 for(const l of v.ligues){
  console.log(`\n${l.nom} (id ${l.id}, ${l.type})`);
  for(const s of l.saisons.slice(0,4))console.log(`  saison ${s.saison}${s.courante?' (en cours)':''} : événements ${s.evenements?'oui':'non'}, classement ${s.classement?'oui':'non'}, compositions ${s.compositions?'oui':'non'}`);
 }
 console.log(`\nLigue 1 : ${v.ligue1?'id '+v.ligue1.id:'NON TROUVÉE'} | Ligue 2 : ${v.ligue2?'id '+v.ligue2.id:'NON TROUVÉE'} | requêtes utilisées : ${api.requetes} | quota restant : ${api.quota.restant??'?'}`);
}catch(e){console.error('Échec ('+(e.code||'autre')+') : '+expurger(e.message,cle));process.exit(1);}
