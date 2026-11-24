// Essais Realtime RÉELS avec deux clients indépendants (deux connexions WebSocket, deux clients supabase-js)
// et le module public assets/portail/foot-direct.js tel quel. Environnement d'essai indépendant uniquement.
import {createClient} from '@supabase/supabase-js';
import {createRequire} from 'node:module';import path from 'node:path';import {fileURLToPath} from 'node:url';
import {environnement,compte,totpFrais,rapporteur,vrai} from './commun.mjs';

const ICI=path.dirname(fileURLToPath(import.meta.url));
const D=createRequire(import.meta.url)(path.resolve(process.env.KOKI_PUBLIC_DIR||path.join(ICI,'../../../../../koki-connect'),'assets/portail/foot-direct.js'));
const E=environnement(),{url,cle}=E;const R=rapporteur('realtime',{heberge:E.heberge,ref:E.ref,cle:E.type});const MATCH=process.env.KOKI_ESSAI_MATCH_ID;
const attendre=(f,ms=10000)=>new Promise((ok,ko)=>{const t0=Date.now();const i=setInterval(()=>{if(f()){clearInterval(i);ok(Date.now()-t0);}else if(Date.now()-t0>ms){clearInterval(i);ko(Error('délai dépassé ('+ms+' ms)'));}},50);});
const pause=ms=>new Promise(r=>setTimeout(r,ms));
if(!MATCH){console.log('KOKI_ESSAI_MATCH_ID requis (match d’essai publié, en direct).');process.exit(2);}

function appareil(nom){
 const db=createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:false}});const etats=[];let lectures=0;
 const rpc=async(command,input)=>{lectures++;const {data,error}=await db.rpc('koki_foot_public',{command,input});if(error)throw error;return data;};
 const d=D.creer({client:db,rpc,onEtat:e=>etats.push(e)});
 return {nom,db,d,etats,lectures:()=>lectures,match:()=>d.matchs().find(m=>m.id===MATCH)};
}
async function editeur(){
 const c=compte('editeur');if(!c)return null;
 const db=createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:true}}); // rafraîchissement : la session reste aal2
 const {error}=await db.auth.signInWithPassword({email:c.email,password:c.motDePasse});if(error)throw error;
 if(c.totp){const {data:f}=await db.auth.mfa.listFactors();const {data:ch}=await db.auth.mfa.challenge({factorId:f.totp[0].id});
  const v=await db.auth.mfa.verify({factorId:f.totp[0].id,challengeId:ch.id,code:await totpFrais(c.totp)});if(v.error)throw v.error;}
 const a=async(command,input)=>{if(command==='etat'&&input.id){const e=await a('etat',{});return e.matchs.find(x=>x.id===input.id);}
  const {data,error}=await db.rpc('koki_foot_admin',{command,input});if(error)throw Error(command+' : '+error.message);return data;};
 return a;
}
async function intrus(){const db=createClient(url,cle,{auth:{persistSession:false}});const canal=db.channel(D.CANAL);
 await new Promise((ok,ko)=>{canal.subscribe(s=>{if(s==='SUBSCRIBED')ok();else if(s==='CHANNEL_ERROR'||s==='TIMED_OUT')ko(Error('abonnement intrus : '+s));});});
 return {db,canal,envoyer:p=>canal.send({type:'broadcast',event:'match',payload:p})};}

const A=appareil('A'),B=appareil('B');const ed=await editeur();
await A.d.demarrer();await B.d.demarrer();
await attendre(()=>A.d.etat()==='connecte'&&B.d.etat()==='connecte',15000);
const initial=ed?await ed('etat',{id:MATCH}):null;
const but=async(champ,motif)=>{const m=await ed('etat',{id:MATCH});return ed('score',{id:MATCH,revision:m.revision,[champ]:(m[champ]??0)+1,motif});};

await R.cas('propagation d’un score aux deux clients','les deux clients affichent le score du serveur, en moins de 5 s',async preuve=>{
 if(!ed)return 'non_execute';const avant=await ed('etat',{id:MATCH});const r=await but('score_domicile','essai Realtime réel');
 const t=await attendre(()=>A.match()?.revision===r.revision&&B.match()?.revision===r.revision,5000);
 preuve('révision',avant.revision,'→',r.revision,'· délai',t,'ms');vrai(A.match().score_domicile===r.score_domicile&&B.match().score_domicile===r.score_domicile,'score différent');
 return 'reçu en '+t+' ms';
});
await R.cas('ordre des révisions : trois buts rapides, état final exact et révisions croissantes','révision finale = serveur, aucune régression observée',async preuve=>{
 if(!ed)return 'non_execute';const vues=[];const t=setInterval(()=>{const m=A.match();if(m)vues.push(m.revision);},20);
 let r;for(let i=0;i<3;i++)r=await but('score_exterieur','essai ordre '+i);
 await attendre(()=>A.match()?.revision===r.revision&&B.match()?.revision===r.revision,8000);clearInterval(t);
 const croissant=vues.every((v,i)=>i===0||v>=vues[i-1]);preuve('révisions vues par A :',[...new Set(vues)].join(','));vrai(croissant,'révision en recul');
 return 'conforme';
});
await R.cas('rejet des anciens messages (rejeu d’une révision passée)','aucune lecture serveur, affichage inchangé',async preuve=>{
 const m=A.match();const x=await intrus();const n=A.lectures();
 await x.envoyer({id:MATCH,revision:m.revision-1,score_domicile:0});await pause(2500);
 preuve('lectures supplémentaires A :',A.lectures()-n);vrai(A.match().revision===m.revision&&A.match().score_domicile===m.score_domicile,'ancien message appliqué');
 vrai(A.lectures()===n,'lecture déclenchée par un message ancien');await x.db.removeChannel(x.canal);return 'ignoré';
});
await R.cas('faux messages d’un client non autorisé : écritures refusées, contenu Broadcast jamais affiché','RPC et table refusées ; faux score 9–9 non affiché ; vraie mise à jour suivante reçue',async preuve=>{
 const db=createClient(url,cle,{auth:{persistSession:false}});const m=A.match();
 const w=await db.rpc('koki_foot_admin',{command:'score',input:{id:MATCH,revision:m.revision,score_domicile:9}});preuve('RPC :',w.error?.code||'acceptée');vrai(w.error,'écriture anonyme acceptée');
 const t=await db.schema('koki_foot').from('matchs').update({score_domicile:9}).eq('id',MATCH);preuve('table :',t.error?.code||'acceptée');vrai(t.error,'écriture directe acceptée');
 const x=await intrus();const envoi=await x.envoyer({id:MATCH,revision:999999,statut:'Terminé',score_domicile:9,score_exterieur:9});
 preuve('émission Broadcast par un anonyme :',envoi,'(canal public)');await pause(3000);
 vrai(A.match().score_domicile===m.score_domicile&&B.match().score_domicile===m.score_domicile,'faux score affiché');
 if(ed){const r=await but('score_domicile','essai après faux message');await attendre(()=>A.match()?.revision===r.revision,6000);preuve('vraie mise à jour reçue, révision',r.revision);}
 await x.db.removeChannel(x.canal);return 'émission possible, sans effet à l’écran';
});
await R.cas('avalanche de faux signaux : lectures plafonnées','au plus 1 lecture par tranche de 2 s par client',async preuve=>{
 const x=await intrus();const n=A.lectures(),t0=Date.now();
 for(let i=0;i<300;i++){await x.envoyer({id:MATCH,revision:1000000+i});}
 const duree=Date.now()-t0;await pause(4500);const lectures=A.lectures()-n;const plafond=Math.ceil((duree+4500)/2000)+1;
 preuve('300 signaux en',duree,'ms → lectures A :',lectures,'· plafond théorique',plafond);
 vrai(lectures<=plafond,'trop de lectures : '+lectures);await x.db.removeChannel(x.canal);return lectures+' lectures pour 300 signaux';
});
await R.cas('reconnexion : changements manqués récupérés','après coupure du WebSocket de B, état serveur récupéré',async preuve=>{
 if(!ed)return 'non_execute';B.db.realtime.disconnect();await attendre(()=>B.d.etat()!=='connecte',10000);
 const r=await but('score_exterieur','essai coupure Realtime');B.db.realtime.connect();
 const t=await attendre(()=>B.match()?.revision===r.revision,40000);preuve('états B :',B.etats.slice(-4).join('→'),'· récupéré en',t,'ms');return 'récupéré en '+t+' ms';
});
await R.cas('réseau instable : coupures répétées pendant les changements','état final identique au serveur',async preuve=>{
 if(!ed)return 'non_execute';let r;
 for(let i=0;i<3;i++){B.db.realtime.disconnect();r=await but('score_domicile','essai instabilité '+i);await pause(400);B.db.realtime.connect();await pause(700);}
 const t=await attendre(()=>B.match()?.revision===r.revision&&A.match()?.revision===r.revision,45000);
 preuve('révision finale',r.revision,'· convergence en',t,'ms');return 'convergence en '+t+' ms';
});
await R.cas('dépublication : le match disparaît des deux clients','absent de A et B, puis republié',async preuve=>{
 if(!ed)return 'non_execute';const m=await ed('etat',{id:MATCH});
 await ed('enregistrer_match',{id:MATCH,revision:m.revision,publie:false,motif:'essai dépublication'});
 const t=await attendre(()=>!A.match()&&!B.match(),8000);preuve('disparu en',t,'ms');
 const m2=await ed('etat',{id:MATCH});await ed('enregistrer_match',{id:MATCH,revision:m2.revision,publie:true,motif:'essai : republication'});
 return 'disparu en '+t+' ms';
});
if(ed&&initial){const m=await ed('etat',{id:MATCH});await ed('score',{id:MATCH,revision:m.revision,score_domicile:initial.score_domicile,score_exterieur:initial.score_exterieur,motif:'essai Realtime : retour à l’état initial'});}
A.d.arreter();B.d.arreter();process.exit(R.bilan()?0:1);
