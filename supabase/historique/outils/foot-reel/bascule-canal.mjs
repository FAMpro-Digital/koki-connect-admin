// Séquence complète de bascule vers le canal Realtime PRIVÉ, sur un environnement d'ESSAI uniquement :
//  1. proposition 0700 (double émission) : réception sur les canaux public ET privé ;
//  2. site configuré prive:true (foot-direct.js) : écran à jour par le canal privé ;
//  3. proposition 0710 : plus AUCUNE émission publique, le privé continue ;
//  4. retour arrière : émission publique rétablie, canal privé fermé (plus de politique d'écoute).
// Les fichiers SQL sont appliqués sur KOKI_ESSAI_DB_URL (base de l'environnement d'essai) — jamais la production.
import {createClient} from '@supabase/supabase-js';
import {createRequire} from 'node:module';import path from 'node:path';import {fileURLToPath} from 'node:url';import {execFileSync} from 'node:child_process';
import {environnement,compte,totpFrais,rapporteur,vrai,PRODUCTION_REF} from './commun.mjs';

const ICI=path.dirname(fileURLToPath(import.meta.url)),P=path.resolve(ICI,'../../propositions');
const D=createRequire(import.meta.url)(path.resolve(process.env.KOKI_PUBLIC_DIR||path.join(ICI,'../../../../../koki-connect'),'assets/portail/foot-direct.js'));
const E=environnement(),{url,cle}=E;const R=rapporteur('bascule-canal',{heberge:E.heberge,ref:E.ref,cle:E.type});const MATCH=process.env.KOKI_ESSAI_MATCH_ID;
const DB=process.env.KOKI_ESSAI_DB_URL||'';if(!DB||DB.includes(PRODUCTION_REF))throw Error('REFUS : KOKI_ESSAI_DB_URL (base d’essai) requise');
if(E.heberge&&!DB.includes(E.ref))throw Error('REFUS : la base ne correspond pas au projet '+E.ref);
const sql=f=>execFileSync('psql',[DB,'-X','-q','-v','ON_ERROR_STOP=1','-f',path.join(P,f)],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
const politique=()=>execFileSync('psql',[DB,'-X','-Atq','-c',"select count(*) from pg_policies where schemaname='realtime' and tablename='messages' and policyname='koki_foot_ecoute'"],{encoding:'utf8'}).trim();
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const attendre=(f,ms=8000)=>new Promise((ok,ko)=>{const t0=Date.now();const i=setInterval(()=>{if(f()){clearInterval(i);ok(Date.now()-t0);}else if(Date.now()-t0>ms){clearInterval(i);ko(Error('délai dépassé'));}},50);});
const nouveau=()=>createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:false}});

// Éditeur (vraie session aal2) pour produire de vrais changements de score.
const c=compte('editeur');const ed=createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:true}});
await ed.auth.signInWithPassword({email:c.email,password:c.motDePasse});
{const {data:f}=await ed.auth.mfa.listFactors();const {data:ch}=await ed.auth.mfa.challenge({factorId:f.totp[0].id});await ed.auth.mfa.verify({factorId:f.totp[0].id,challengeId:ch.id,code:await totpFrais(c.totp)});}
const admin=async(command,input)=>{const {data,error}=await ed.rpc('koki_foot_admin',{command,input});if(error)throw Error(error.message);return data;};
const but=async motif=>{const m=(await admin('etat',{})).matchs.find(x=>x.id===MATCH);return admin('score',{id:MATCH,revision:m.revision,score_exterieur:(m.score_exterieur??0)+1,motif});};

// Écouteurs bruts : ils voient chaque message émis sur leur canal (révision du match).
async function ecouteur(prive){const db=nouveau();const recus=[];let statut='?';
 const ch=db.channel(D.CANAL,{config:prive?{private:true}:{}}).on('broadcast',{event:'match'},({payload})=>{if(payload?.id===MATCH)recus.push(payload.revision);});
 await new Promise(ok=>{ch.subscribe(s=>{statut=s;if(s!=='JOINING')ok();});setTimeout(ok,8000);});
 return {recus,statut:()=>statut,fermer:()=>db.removeChannel(ch)};}
const ecran=async prive=>{const db=nouveau();const d=D.creer({client:db,prive,rpc:async(command,input)=>{const {data,error}=await db.rpc('koki_foot_public',{command,input});if(error)throw error;return data;}});await d.demarrer();return d;};

if(politique()!=='0')throw Error('REFUS : canal privé déjà en place ; départ attendu depuis l’état de la migration 0600');
let Lpub,Lpriv,ecranPrive;
await R.cas('étape 1 · 0700 (double émission) : réception sur les deux canaux','un même changement reçu sur le canal public et sur le canal privé',async preuve=>{
 sql('20261201000700_foot_canal_prive.sql');preuve('0700 appliquée ; politique d’écoute :',politique());
 Lpub=await ecouteur(false);Lpriv=await ecouteur(true);preuve('abonnements : public',Lpub.statut(),'· privé',Lpriv.statut());
 const r=await but('essai bascule 1');await attendre(()=>Lpub.recus.includes(r.revision)&&Lpriv.recus.includes(r.revision));
 preuve('révision',r.revision,'reçue sur les deux canaux');return 'double réception';
});
await R.cas('étape 1 bis · canal privé : écoute anonyme permise, émission d’un client non autorisé non relayée','message de l’intrus jamais reçu',async preuve=>{
 const db=nouveau();const ch=db.channel(D.CANAL,{config:{private:true}});let st='?';
 await new Promise(ok=>{ch.subscribe(s=>{st=s;if(s!=='JOINING')ok();});setTimeout(ok,8000);});
 const envoi=st==='SUBSCRIBED'?await ch.send({type:'broadcast',event:'match',payload:{id:MATCH,revision:999999,score_domicile:9}}):'non abonné';
 await pause(3000);preuve('intrus : abonnement',st,'· envoi',envoi,'· reçu par l’écouteur privé :',Lpriv.recus.includes(999999));
 vrai(!Lpriv.recus.includes(999999),'message de l’intrus relayé sur le canal privé');await db.removeChannel(ch);return 'non relayé';
});
await R.cas('étape 2 · site configuré prive:true : écran à jour par le canal privé','l’écran prive:true affiche le score du serveur',async preuve=>{
 ecranPrive=await ecran(true);await attendre(()=>ecranPrive.etat()==='connecte',15000);
 const r=await but('essai bascule 2');const t=await attendre(()=>ecranPrive.matchs().find(m=>m.id===MATCH)?.revision===r.revision);
 preuve('écran privé à jour en',t,'ms');return 'à jour en '+t+' ms';
});
await R.cas('étape 3 · 0710 : plus aucune émission publique ; le privé continue','canal public muet ; canal privé reçoit',async preuve=>{
 sql('20261201000710_foot_canal_public_fin.sql');const n=Lpub.recus.length;
 const r=await but('essai bascule 3');await attendre(()=>Lpriv.recus.includes(r.revision));
 await attendre(()=>ecranPrive.matchs().find(m=>m.id===MATCH)?.revision===r.revision);await pause(4000);
 preuve('après 0710 : messages publics reçus',Lpub.recus.length-n,'· privé : révision',r.revision);
 vrai(Lpub.recus.length===n,'émission publique encore présente');return 'public muet, privé actif';
});
await R.cas('étape 4 · retour arrière : canal public rétabli, canal privé fermé','public reçoit de nouveau ; nouvel abonné privé : aucun message',async preuve=>{
 sql('retour-20261201000700_foot_canal_prive.sql');preuve('retour appliqué ; politique d’écoute :',politique());vrai(politique()==='0','politique encore présente');
 const nouveauPriv=await ecouteur(true);preuve('nouvel abonnement privé :',nouveauPriv.statut());
 const n=Lpub.recus.length;const r=await but('essai bascule 4');await attendre(()=>Lpub.recus.length>n&&Lpub.recus.includes(r.revision));await pause(3000);
 preuve('public : révision',r.revision,'reçue · nouvel abonné privé : messages',nouveauPriv.recus.length);
 vrai(!nouveauPriv.recus.includes(r.revision),'canal privé encore alimenté après retour');await nouveauPriv.fermer();return 'retour conforme';
});
await Lpub?.fermer();await Lpriv?.fermer();ecranPrive?.arreter();
if(politique()!=='0'){try{sql('retour-20261201000700_foot_canal_prive.sql');}catch{}}
process.exit(R.bilan()?0:1);
