// Essais du canal Realtime PRIVÉ (proposition 20261201000700), sur l'environnement d'essai éphémère SEULEMENT,
// après application de la proposition sur cet environnement. Rien n'est appliqué ailleurs.
import {createClient} from '@supabase/supabase-js';
import {createRequire} from 'node:module';import path from 'node:path';import {fileURLToPath} from 'node:url';
import {environnement,compte,totpFrais,rapporteur,vrai} from './commun.mjs';

const ICI=path.dirname(fileURLToPath(import.meta.url));
const D=createRequire(import.meta.url)(path.resolve(process.env.KOKI_PUBLIC_DIR||path.join(ICI,'../../../../../koki-connect'),'assets/portail/foot-direct.js'));
const E=environnement(),{url,cle}=E;const R=rapporteur('realtime-prive',{heberge:E.heberge,ref:E.ref,cle:E.type});const MATCH=process.env.KOKI_ESSAI_MATCH_ID;
const attendre=(f,ms=10000)=>new Promise((ok,ko)=>{const t0=Date.now();const i=setInterval(()=>{if(f()){clearInterval(i);ok(Date.now()-t0);}else if(Date.now()-t0>ms){clearInterval(i);ko(Error('délai dépassé'));}},50);});
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const nouveau=()=>createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:false}});
function appareil(prive){const db=nouveau();const d=D.creer({client:db,prive,rpc:async(command,input)=>{const {data,error}=await db.rpc('koki_foot_public',{command,input});if(error)throw error;return data;}});
 return {db,d,match:()=>d.matchs().find(m=>m.id===MATCH)};}
const c=compte('editeur');const ed=createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:true}});
await ed.auth.signInWithPassword({email:c.email,password:c.motDePasse});
{const {data:f}=await ed.auth.mfa.listFactors();const {data:ch}=await ed.auth.mfa.challenge({factorId:f.totp[0].id});await ed.auth.mfa.verify({factorId:f.totp[0].id,challengeId:ch.id,code:await totpFrais(c.totp)});}
const admin=async(command,input)=>{const {data,error}=await ed.rpc('koki_foot_admin',{command,input});if(error)throw Error(error.message);return data;};
const lire=async()=>(await admin('etat',{})).matchs.find(x=>x.id===MATCH);
const but=async()=>{const m=await lire();return admin('score',{id:MATCH,revision:m.revision,score_domicile:(m.score_domicile??0)+1,motif:'essai canal privé'});};

const P=appareil(true),A=appareil(false);await P.d.demarrer();await A.d.demarrer();
await R.cas('canal privé : un visiteur anonyme s’abonne et reçoit les scores','abonnement accepté (politique d’écoute) ; score reçu',async preuve=>{
 await attendre(()=>P.d.etat()==='connecte',15000);const r=await but();
 const t=await attendre(()=>P.match()?.revision===r.revision,6000);preuve('reçu en',t,'ms sur le canal privé');return 'reçu en '+t+' ms';
});
await R.cas('canal privé : un client ne peut PAS émettre (aucune politique d’insertion)','faux message jamais reçu par un écouteur du canal privé',async preuve=>{
 const ecoute=nouveau();const recus=[];const ce=ecoute.channel(D.CANAL,{config:{private:true}}).on('broadcast',{event:'match'},({payload})=>recus.push(payload));
 await new Promise((ok,ko)=>ce.subscribe(s=>{if(s==='SUBSCRIBED')ok();else if(s==='CHANNEL_ERROR'||s==='TIMED_OUT')ko(Error(s));}));
 const intrus=nouveau();const ci=intrus.channel(D.CANAL,{config:{private:true}});let statut='?';
 await new Promise(ok=>ci.subscribe(s=>{statut=s;if(s!=='JOINING')ok();}));
 const envoi=statut==='SUBSCRIBED'?await ci.send({type:'broadcast',event:'match',payload:{id:MATCH,revision:999999,score_domicile:9}}):'non abonné';
 await pause(3000);preuve('abonnement intrus :',statut,'· envoi :',envoi,'· reçus par l’écouteur :',recus.filter(x=>x.revision===999999).length);
 vrai(!recus.some(x=>x.revision===999999),'message de l’intrus reçu sur le canal privé');
 await ecoute.removeChannel(ce);await intrus.removeChannel(ci);return 'émission refusée (envoi : '+envoi+')';
});
await R.cas('transition : le canal public continue de recevoir les signaux','ancien client (canal public) à jour',async preuve=>{
 await attendre(()=>A.d.etat()==='connecte',15000);const r=await but();const t=await attendre(()=>A.match()?.revision===r.revision,6000);preuve('public reçu en',t,'ms');return 'reçu';
});
P.d.arreter();A.d.arreter();process.exit(R.bilan()?0:1);
