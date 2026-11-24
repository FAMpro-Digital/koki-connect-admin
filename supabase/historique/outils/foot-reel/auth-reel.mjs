// Essais d'authentification RÉELLE (sessions Supabase véritables) du module Football — projet d'essai seulement.
// Usage : KOKI_ESSAI_URL=… KOKI_ESSAI_ANON_KEY=… KOKI_ESSAI_CONFIRME=projet-essai \
//         KOKI_ESSAI_EDITEUR_EMAIL=… KOKI_ESSAI_EDITEUR_MOT_DE_PASSE=… KOKI_ESSAI_EDITEUR_TOTP=… \
//         KOKI_ESSAI_SUPERADMIN_… KOKI_ESSAI_SANSMFA_… KOKI_ESSAI_SANSDROIT_… \
//         KOKI_ESSAI_MATCH_ID=<match d'essai> node auth-reel.mjs
// Le match d'essai est remis dans son état initial à la fin (score saisi puis annulé par le même compte).
import {createClient} from '@supabase/supabase-js';
import {environnement,compte,totp,rapporteur,vrai} from './commun.mjs';

const {url,cle}=environnement();const R=rapporteur();const MATCH=process.env.KOKI_ESSAI_MATCH_ID;
const nouveau=()=>createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:false}});

async function connecter(nom,{mfa=true}={}){
 const c=compte(nom);if(!c)return null;const db=nouveau();
 const {error}=await db.auth.signInWithPassword({email:c.email,password:c.motDePasse});if(error)throw Error('connexion '+nom+' : '+error.message);
 if(mfa&&c.totp){const {data:f,error:e1}=await db.auth.mfa.listFactors();if(e1)throw e1;const fac=f.totp?.[0];vrai(fac,'aucun facteur TOTP pour '+nom);
  const {data:ch,error:e2}=await db.auth.mfa.challenge({factorId:fac.id});if(e2)throw e2;
  const {error:e3}=await db.auth.mfa.verify({factorId:fac.id,challengeId:ch.id,code:totp(c.totp)});if(e3)throw Error('MFA '+nom+' : '+e3.message);}
 const {data:a}=await db.auth.mfa.getAuthenticatorAssuranceLevel();return {db,aal:a?.currentLevel};
}
const admin=(db,command,input={})=>db.rpc('koki_foot_admin',{command,input});
const lire=async db=>{const r=await admin(db,'etat',{});if(r.error)throw Error(r.error.message);const m=r.data.matchs.find(x=>x.id===MATCH);vrai(m,'match d’essai introuvable');return m;};
const refuse=r=>r.error&&(r.error.code==='42501'||/double authentification|Administration|permission|JWT|refus/i.test(r.error.message));

await R.cas('éditeur aal2 : lecture et écriture via RPC ; tables privées inaccessibles',async()=>{
 const s=await connecter('editeur');if(!s)return 'non_execute';vrai(s.aal==='aal2','niveau '+s.aal);
 const l=await admin(s.db,'matchs',{});vrai(!l.error,'lecture refusée : '+l.error?.message);
 if(MATCH){const m={data:await lire(s.db)};
  const r1=await admin(s.db,'score',{id:MATCH,revision:m.data.revision,score_domicile:(m.data.score_domicile??0)+1,motif:'essai auth réelle'});vrai(!r1.error,'écriture refusée : '+r1.error?.message);
  const r2=await admin(s.db,'score',{id:MATCH,revision:r1.data.revision,score_domicile:m.data.score_domicile??0,motif:'essai auth réelle : retour'});vrai(!r2.error,r2.error?.message);}
 for(const t of ['matchs','equipes','corrections','reglages']){const d=await s.db.schema('koki_foot').from(t).select('*').limit(1);vrai(d.error,'accès direct à koki_foot.'+t+' accordé');}
});
await R.cas('superadmin aal2 : réglages réservés acceptés',async()=>{
 const s=await connecter('superadmin');if(!s)return 'non_execute';vrai(s.aal==='aal2','niveau '+s.aal);
 const v=await admin(s.db,'verifier_journal',{});vrai(!v.error,v.error?.message);
});
await R.cas('éditeur aal2 : réglage réservé au superadmin refusé',async()=>{
 const s=await connecter('editeur');if(!s)return 'non_execute';
 const r=await admin(s.db,'regler_verrous',{mode:'independant'});vrai(r.error,'réglage superadmin accepté pour un éditeur');
});
await R.cas('session sans MFA (aal1) : lecture et écriture refusées',async()=>{
 const s=await connecter('sansmfa',{mfa:false})||await connecter('editeur',{mfa:false});if(!s)return 'non_execute';vrai(s.aal==='aal1','niveau '+s.aal);
 vrai(refuse(await admin(s.db,'matchs',{})),'lecture acceptée sans MFA');
 if(MATCH)vrai(refuse(await admin(s.db,'score',{id:MATCH,revision:1,score_domicile:9})),'écriture acceptée sans MFA');
});
await R.cas('utilisateur authentifié sans droits : refusé',async()=>{
 const s=await connecter('sansdroit');if(!s)return 'non_execute';
 vrai(refuse(await admin(s.db,'matchs',{})),'lecture admin accordée');
 if(MATCH)vrai(refuse(await admin(s.db,'score',{id:MATCH,revision:1,score_domicile:9})),'écriture accordée');
});
await R.cas('anonyme (clé publique) : admin et synchronisation refusées ; lecture publique permise',async()=>{
 const db=nouveau();vrai((await admin(db,'matchs',{})).error,'admin anonyme accepté');
 vrai((await db.rpc('koki_foot_sync',{command:'importer',input:{}})).error,'synchronisation anonyme acceptée');
 const p=await db.rpc('koki_foot_public',{command:'accueil',input:{}});vrai(!p.error,p.error?.message);
});
await R.cas('session expirée : jeton périmé refusé par le serveur',async()=>{
 const jeton=process.env.KOKI_ESSAI_JETON_EXPIRE; // jeton d'accès d'essai déjà expiré (durée de vie courte sur le projet d'essai)
 if(!jeton)return 'non_execute';
 const db=createClient(url,cle,{global:{headers:{Authorization:'Bearer '+jeton}},auth:{persistSession:false}});
 const r=await admin(db,'matchs',{});vrai(r.error,'jeton expiré accepté');
});
await R.cas('perte de connexion pendant une écriture : erreur propre, aucune écriture partielle',async()=>{
 const s=await connecter('editeur');if(!s||!MATCH)return 'non_execute';
 const avant=await lire(s.db);
 const ctl=new AbortController();const p=s.db.rpc('koki_foot_admin',{command:'score',input:{id:MATCH,revision:avant.revision,score_domicile:(avant.score_domicile??0)+1,motif:'essai coupure'}}).abortSignal(ctl.signal);ctl.abort();
 const r=await p;vrai(r.error,'requête interrompue sans erreur');
 const apres=await lire(s.db);
 // Soit rien n'a été écrit, soit l'écriture complète a eu lieu (transaction) : jamais un état intermédiaire.
 vrai(apres.revision===avant.revision||(apres.revision===avant.revision+1&&apres.score_domicile===(avant.score_domicile??0)+1),'état intermédiaire');
 if(apres.revision!==avant.revision)await admin(s.db,'score',{id:MATCH,revision:apres.revision,score_domicile:avant.score_domicile??0,motif:'essai coupure : retour'});
});
process.exit(R.bilan()?0:1);
