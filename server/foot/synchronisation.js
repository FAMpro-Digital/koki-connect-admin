// Synchronisation API-Football → koki_foot, adaptée au quota.
// Toutes les écritures passent par public.koki_foot_sync (service_role) : verrous manuels, conflits,
// journal des synchronisations, pause après erreur et fraîcheur restent gérés par la base.
import {FOURNISSEUR,ErreurFournisseur,expurger,lireRefCompetition,convertirMatchs,convertirClassement,convertirCompetition,couverture} from './api-football.js';

export const CONFIG_DEFAUT=Object.freeze({
 limiteJour:100,        // formule gratuite : 100 requêtes par jour (remise à zéro à 00:00 UTC)
 reserve:10,            // gardées pour la vérification, la découverte et les essais manuels
 parMinute:10,          // plafond par minute de la formule gratuite
 directMinS:60,         // au plus une interrogation du direct par minute
 directMaxS:900,        // au moins toutes les 15 min pendant un match si le quota le permet
 calendrierH:12,        // calendrier et résultats : deux fois par jour
 classementH:24,        // classement : une fois par jour, et après chaque match terminé
 dureeMatchMin:130      // fenêtre d'un match (prolongations comprises)
});
export function lireConfig(env={}){
 const n=(v,d,min,max)=>{const x=Number(v);return Number.isFinite(x)&&x>=min&&x<=max?Math.trunc(x):d;};
 const c={...CONFIG_DEFAUT};
 c.limiteJour=n(env.API_FOOTBALL_LIMITE_JOUR,c.limiteJour,10,1500000);
 c.reserve=n(env.API_FOOTBALL_RESERVE,Math.min(c.reserve,Math.floor(c.limiteJour/5)),0,c.limiteJour-1);
 c.parMinute=n(env.API_FOOTBALL_PAR_MINUTE,c.parMinute,1,1000);
 return c;
}

const jourUTC=d=>new Date(d).toISOString().slice(0,10);
const finJourUTC=d=>{const x=new Date(d);x.setUTCHours(24,0,0,0);return x.getTime();};

// Minutes de direct restantes aujourd'hui (réunion des fenêtres de match, à partir de maintenant).
export function minutesDirectRestantes(coups,maintenant,dureeMin){
 const fin=finJourUTC(maintenant),t0=+maintenant;
 const f=(coups||[]).map(k=>+new Date(k)).filter(Number.isFinite).map(k=>[Math.max(k,t0),Math.min(k+dureeMin*60000,fin)]).filter(([a,b])=>b>a).sort((x,y)=>x[0]-y[0]);
 let total=0,cA=null,cB=null;
 for(const [a,b] of f){if(cB===null||a>cB){if(cB!==null)total+=cB-cA;cA=a;cB=b;}else cB=Math.max(cB,b);}
 if(cB!==null)total+=cB-cA;
 return Math.ceil(total/60000);
}

// Décide quoi demander au fournisseur pendant ce passage. Fonction pure (testée seule).
export function planifier({maintenant=new Date(),planning,config=CONFIG_DEFAUT}){
 const p=planning||{};const now=+maintenant;
 const res={actions:[],raison:'',budget:{}};
 if(p.pause_jusqu_a&&+new Date(p.pause_jusqu_a)>now){res.raison='pause fournisseur jusqu’à '+p.pause_jusqu_a;return res;}
 const memeJour=p.derniere_tentative&&jourUTC(p.derniere_tentative)===jourUTC(maintenant);
 const restant=memeJour&&Number.isInteger(p.quota_restant)?p.quota_restant:config.limiteJour;
 const disponible=Math.max(0,restant-config.reserve);
 const ops=p.operations||{};const depuis=op=>ops[op]?(now-+new Date(ops[op]))/1000:Infinity;
 const comps=(p.competitions||[]).filter(c=>lireRefCompetition(c.ref));
 // Besoins fixes du reste de la journée : calendrier et classement de chaque compétition suivie.
 const fixes=[];
 for(const c of comps){
  if(depuis('calendrier:'+c.ref)>=config.calendrierH*3600)fixes.push({type:'calendrier',ref:c.ref});
  if(depuis('classement:'+c.ref)>=config.classementH*3600)fixes.push({type:'classement',ref:c.ref});
 }
 const suivre=[...new Set(p.matchs_a_suivre||[])].map(String);
 const parPassage=Math.max(1,Math.ceil(suivre.length/20));
 const minutes=minutesDirectRestantes(p.coups_d_envoi,maintenant,config.dureeMatchMin);
 // Une requête de classement réservée par compétition ayant un match aujourd'hui (après le coup de sifflet final).
 const reserveFin=new Set((p.competitions_du_jour||[]).map(String)).size;
 const pourDirect=disponible-fixes.length-reserveFin;
 let intervalle=null;
 if(suivre.length){
  if(pourDirect>=parPassage){
   intervalle=Math.min(config.directMaxS,Math.max(config.directMinS,Math.ceil(Math.max(minutes,15)*60*parPassage/pourDirect)));
   if(depuis('direct')>=intervalle-5)res.actions.push({type:'direct',refs:suivre});
  }else res.raison='quota insuffisant pour le direct (données marquées anciennes)';
 }
 let place=Math.min(disponible,config.parMinute-1)-(res.actions.length?parPassage:0);
 for(const a of fixes){if(place<=0)break;res.actions.push(a);place--;}
 res.budget={restant,disponible,fixes:fixes.length,pour_direct:pourDirect,intervalle_direct_s:intervalle,minutes_direct:minutes};
 if(!res.actions.length&&!res.raison)res.raison=disponible<=0?'quota du jour épuisé':'rien à faire';
 return res;
}

function fusionnerEquipes(...listes){const m=new Map();for(const l of listes)for(const e of l||[])m.set(e.ref,e);return [...m.values()];}

// Un passage complet. deps : {api, rpc, maintenant, config}.
//  rpc(command,input) → public.koki_foot_sync ; planning() → public.koki_foot_sync_planning.
export async function passage({api,rpc,planning,maintenant=new Date(),config=CONFIG_DEFAUT,cle}){
 const pl=await planning();
 const plan=planifier({maintenant,planning:pl,config});
 const bilan={raison:plan.raison,budget:plan.budget,operations:[],requetes:0};
 const termines=new Set();
 const file=[...plan.actions];
 const fait=new Set();
 while(file.length){
  const a=file.shift();const op=a.type==='direct'?'direct':a.type+':'+a.ref;
  if(fait.has(op))continue;fait.add(op);
  try{
   let payload;
   if(a.type==='direct'){
    const reponse=[];
    for(let i=0;i<a.refs.length;i+=20){
     const lot=a.refs.slice(i,i+20);
     try{reponse.push(...await api.matchsIds(lot));}
     catch(e){
      // Requête groupée refusée par la formule : repli match par match (2 au plus pour préserver le quota).
      if(!(e instanceof ErreurFournisseur)||e.code!=='donnees')throw e;
      for(const id of lot.slice(0,2))reponse.push(...await api.matchId(id));
     }
    }
    const c=convertirMatchs(reponse,{avecEvenements:true});
    for(const m of c.matchs)if(m.statut==='Terminé')termines.add(m.competition_ref);
    payload={equipes:c.equipes,matchs:c.matchs,evenements:c.evenements,evenements_complets:c.evenements_complets};
   }else{
    const r=lireRefCompetition(a.ref);
    if(a.type==='calendrier'){const c=convertirMatchs(await api.matchsLigue(r.ligue,r.saison));payload={equipes:c.equipes,matchs:c.matchs};}
    else{const c=convertirClassement(await api.classement(r.ligue,r.saison));payload={equipes:c.equipes,inscriptions:c.inscriptions,classements:c.classements};}
   }
   const res=await rpc('importer',{fournisseur:FOURNISSEUR,operation:op,quota_restant:api.quota.restant??undefined,...payload});
   bilan.operations.push({operation:op,statut:res?.statut,lus:res?.lus,crees:res?.crees,mis_a_jour:res?.mis_a_jour,ignores_verrou:res?.ignores_verrou,rejetes:res?.rejetes});
   // Match terminé : classement de sa compétition actualisé dans le même passage si le quota le permet.
   if(a.type==='direct')for(const ref of termines)if((pl.competitions||[]).some(c=>c.ref===ref)&&!fait.has('classement:'+ref)&&(api.quota.restant??config.limiteJour)>config.reserve)file.push({type:'classement',ref});
  }catch(e){
   const code=e instanceof ErreurFournisseur?e.code:'autre';
   const message=expurger(e?.message||'Erreur',cle);
   const err={fournisseur:FOURNISSEUR,operation:op,code,message};
   if(e?.reessayerApres)err.reessayer_apres=e.reessayerApres;
   try{await rpc('erreur',err);}catch{}
   bilan.operations.push({operation:op,statut:'erreur',code,message});
   if(code==='quota'||code==='authentification'||code==='indisponible'||code==='delai')break; // pause gérée par la base
  }
 }
 bilan.requetes=api.requetes??null;
 return bilan;
}

// Découverte d'une compétition (action manuelle) : créée NON publiée ; l'administrateur choisit de l'afficher.
// 2 ou 3 requêtes : ligue (couverture), matchs de la saison, classement si couvert.
export async function decouvrir({api,rpc,ligue,saison}){
 const ent=(await api.ligues({id:ligue,season:saison}))[0];
 const comp=convertirCompetition(ent,saison);
 if(!comp)throw new ErreurFournisseur('donnees',`Saison ${saison} absente pour la ligue ${ligue} (formule ou couverture)`);
 const cov=couverture(ent,saison);
 const m=convertirMatchs(await api.matchsLigue(ligue,saison),{porteeCompetition:comp.portee});
 const k=cov.classement?convertirClassement(await api.classement(ligue,saison),{porteeCompetition:comp.portee}):{equipes:[],inscriptions:[],classements:[]};
 const op='decouverte:'+comp.ref;
 const res=await rpc('importer',{fournisseur:FOURNISSEUR,operation:op,quota_restant:api.quota.restant??undefined,competitions:[comp],
  equipes:fusionnerEquipes(m.equipes,k.equipes),inscriptions:k.inscriptions.length?k.inscriptions:m.inscriptions,matchs:m.matchs,classements:k.classements});
 return {competition:comp,couverture:cov,matchs:m.matchs.length,classement:k.classements.length,rejetes_conversion:m.rejetes.length,import:res};
}

// Vérification réelle de la couverture (aucune écriture) : compte, puis ligues d'un pays.
const NIVEAUX=[/^ligue 1$/i,/^ligue 2$/i];
export async function verifier({api,pays='Senegal'}){
 let compte=null;
 try{const s=await api.statut();const st=Array.isArray(s)?s[0]:s;compte={formule:st?.subscription?.plan??null,active:st?.subscription?.active??null,fin:st?.subscription?.end??null,requetes_jour:st?.requests?.current??null,limite_jour:st?.requests?.limit_day??null};}
 catch(e){if(e instanceof ErreurFournisseur&&e.code==='authentification')throw e;}
 const ligues=(await api.ligues({country:pays})).map(e=>({id:e?.league?.id,nom:e?.league?.name,type:e?.league?.type,
  saisons:(e?.seasons||[]).map(s=>couverture(e,s.year)).sort((a,b)=>b.saison-a.saison)}));
 const cibles=ligues.filter(l=>NIVEAUX.some(r=>r.test(String(l.nom||'').trim())));
 return {compte,pays,ligues,ligue1:cibles.find(l=>/1$/.test(l.nom))||null,ligue2:cibles.find(l=>/2$/.test(l.nom))||null};
}
