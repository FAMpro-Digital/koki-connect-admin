// Essais Realtime RÉELS à deux appareils simulés (deux clients WebSocket indépendants) — projet d'essai seulement.
// Usage : mêmes variables que auth-reel.mjs (compte éditeur aal2 requis) + KOKI_ESSAI_MATCH_ID.
// Le module foot-direct.js du site public est utilisé tel quel (KOKI_PUBLIC_DIR, par défaut ../koki-connect).
import {createClient} from '@supabase/supabase-js';
import {createRequire} from 'node:module';import path from 'node:path';import {fileURLToPath} from 'node:url';
import {environnement,compte,totp,rapporteur,vrai} from './commun.mjs';

const ICI=path.dirname(fileURLToPath(import.meta.url));
const D=createRequire(import.meta.url)(path.resolve(process.env.KOKI_PUBLIC_DIR||path.join(ICI,'../../../../../koki-connect'),'assets/portail/foot-direct.js'));
const {url,cle}=environnement();const R=rapporteur();const MATCH=process.env.KOKI_ESSAI_MATCH_ID;
const attendre=(f,ms=8000)=>new Promise((ok,ko)=>{const t0=Date.now();const i=setInterval(()=>{if(f()){clearInterval(i);ok();}else if(Date.now()-t0>ms){clearInterval(i);ko(Error('délai dépassé'));}},100);});
const pause=ms=>new Promise(r=>setTimeout(r,ms));

function appareil(nom){
 const db=createClient(url,cle,{auth:{persistSession:false}});const etats=[];
 const rpc=async(command,input)=>{const {data,error}=await db.rpc('koki_foot_public',{command,input});if(error)throw error;return data;};
 const d=D.creer({client:db,rpc,onEtat:e=>etats.push(e)});
 return {nom,db,d,etats,match:()=>d.matchs().find(m=>m.id===MATCH)};
}
async function editeur(){
 const c=compte('editeur');if(!c)return null;const db=createClient(url,cle,{auth:{persistSession:false}});
 const {error}=await db.auth.signInWithPassword({email:c.email,password:c.motDePasse});if(error)throw error;
 if(c.totp){const {data:f}=await db.auth.mfa.listFactors();const {data:ch}=await db.auth.mfa.challenge({factorId:f.totp[0].id});await db.auth.mfa.verify({factorId:f.totp[0].id,challengeId:ch.id,code:totp(c.totp)});}
 const a=async(command,input)=>{if(command==='etat'&&input.id){const e=await a('etat',{});return e.matchs.find(x=>x.id===input.id);}const {data,error}=await db.rpc('koki_foot_admin',{command,input});if(error)throw error;return data;};return a;
}
if(!MATCH){console.log('KOKI_ESSAI_MATCH_ID requis (match d’essai publié, en direct).');process.exit(2);}
const A=appareil('A'),B=appareil('B');const ed=await editeur();
await A.d.demarrer();await B.d.demarrer();
await attendre(()=>A.d.etat()==='connecte'&&B.d.etat()==='connecte');
const initial=ed?await ed('etat',{id:MATCH}):null;

await R.cas('changement de score reçu par les deux appareils, révision croissante',async()=>{
 if(!ed)return 'non_execute';const avant=await ed('etat',{id:MATCH});
 const r=await ed('score',{id:MATCH,revision:avant.revision,score_domicile:(avant.score_domicile??0)+1,motif:'essai Realtime réel'});
 await attendre(()=>A.match()?.revision===r.revision&&B.match()?.revision===r.revision);
 vrai(r.revision>avant.revision,'révision non croissante');vrai(A.match().score_domicile===r.score_domicile&&B.match().score_domicile===r.score_domicile,'score différent');
});
await R.cas('message ancien rejeté (rejeu d’une révision passée)',async()=>{
 const m=A.match();const canal=B.db.channel(D.CANAL);await new Promise(ok=>canal.subscribe(s=>s==='SUBSCRIBED'&&ok()));
 await canal.send({type:'broadcast',event:'match',payload:{id:MATCH,revision:m.revision-1,score_domicile:0}});await pause(2500);
 vrai(A.match().revision===m.revision&&A.match().score_domicile===m.score_domicile,'ancien message appliqué');await B.db.removeChannel(canal);
});
await R.cas('client non autorisé : écriture refusée et faux message Broadcast sans effet sur l’affichage',async()=>{
 const intrus=createClient(url,cle,{auth:{persistSession:false}});const m=A.match();
 const w=await intrus.rpc('koki_foot_admin',{command:'score',input:{id:MATCH,revision:m.revision,score_domicile:9}});vrai(w.error,'écriture anonyme acceptée');
 const t=await intrus.schema('koki_foot').from('matchs').update({score_domicile:9}).eq('id',MATCH);vrai(t.error,'écriture directe en table acceptée');
 const canal=intrus.channel(D.CANAL);await new Promise(ok=>canal.subscribe(s=>s==='SUBSCRIBED'&&ok()));
 const envoi=await canal.send({type:'broadcast',event:'match',payload:{id:MATCH,revision:999999,score_domicile:9,score_exterieur:9}});
 console.log('        (émission Broadcast publique par un anonyme : '+envoi+' — attendu « ok » tant que le canal est public)');
 await pause(3000);vrai(A.match().score_domicile===m.score_domicile&&A.match().revision===m.revision,'faux score affiché');
 await intrus.removeChannel(canal);
});
await R.cas('reconnexion : changements manqués récupérés depuis le serveur',async()=>{
 if(!ed)return 'non_execute';B.db.realtime.disconnect();await attendre(()=>B.d.etat()!=='connecte');
 const avant=await ed('etat',{id:MATCH});const r=await ed('score',{id:MATCH,revision:avant.revision,score_exterieur:(avant.score_exterieur??0)+1,motif:'essai coupure Realtime'});
 B.db.realtime.connect();await attendre(()=>B.match()?.revision===r.revision,40000);
});
await R.cas('match dépublié : disparaît des deux appareils',async()=>{
 if(!ed)return 'non_execute';const m=await ed('etat',{id:MATCH});
 await ed('enregistrer_match',{id:MATCH,revision:m.revision,publie:false,motif:'essai dépublication'});
 await attendre(()=>!A.match()&&!B.match());
 const m2=await ed('etat',{id:MATCH});await ed('enregistrer_match',{id:MATCH,revision:m2.revision,publie:true,motif:'essai : republication'});
});
if(ed&&initial){const m=await ed('etat',{id:MATCH});await ed('score',{id:MATCH,revision:m.revision,score_domicile:initial.score_domicile,score_exterieur:initial.score_exterieur,motif:'essai Realtime : retour à l’état initial'});}
A.d.arreter();B.d.arreter();process.exit(R.bilan()?0:1);
