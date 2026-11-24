// Essais d'authentification RÉELLE (sessions Supabase véritables, MFA TOTP) du module Football.
// Environnement d'essai indépendant uniquement : la production est refusée par environnement().
// Variables : voir docs/football-tests-reels.md ; KOKI_ESSAI_RAPPORT=<fichier.json> pour le rapport détaillé.
import {createClient} from '@supabase/supabase-js';
import {environnement,compte,totpFrais,rapporteur,vrai} from './commun.mjs';

const E=environnement(),{url,cle}=E;const R=rapporteur('authentification',{heberge:E.heberge,ref:E.ref,cle:E.type});const MATCH=process.env.KOKI_ESSAI_MATCH_ID;
const nouveau=(o={})=>createClient(url,cle,{auth:{persistSession:false,autoRefreshToken:false},...o});
const jwt=t=>{try{return JSON.parse(Buffer.from(t.split('.')[1],'base64url').toString());}catch{return {};}};

async function connecter(nom,{mfa=true}={}){
 const c=compte(nom);if(!c)return null;const db=nouveau();
 const {data:s,error}=await db.auth.signInWithPassword({email:c.email,password:c.motDePasse});if(error)throw Error('connexion '+nom+' : '+error.message);
 if(mfa&&c.totp){const {data:f,error:e1}=await db.auth.mfa.listFactors();if(e1)throw e1;const fac=f.totp?.[0];vrai(fac,'aucun facteur TOTP pour '+nom);
  const {data:ch,error:e2}=await db.auth.mfa.challenge({factorId:fac.id});if(e2)throw e2;
  const {error:e3}=await db.auth.mfa.verify({factorId:fac.id,challengeId:ch.id,code:await totpFrais(c.totp)});if(e3)throw Error('MFA '+nom+' : '+e3.message);}
 const {data:a}=await db.auth.mfa.getAuthenticatorAssuranceLevel();const {data:{session}}=await db.auth.getSession();
 return {db,aal:a?.currentLevel,jeton:session?.access_token};
}
const admin=(db,command,input={})=>db.rpc('koki_foot_admin',{command,input});
const lire=async db=>{const r=await admin(db,'etat',{});if(r.error)throw Error(r.error.message);const m=r.data.matchs.find(x=>x.id===MATCH);vrai(m,'match d’essai introuvable');return m;};
// Refus attendu = refus de DROITS (42501), pas une autre erreur (commande inconnue, paramètre…).
const refuse=r=>!!r.error&&r.error.code==='42501';
const code=r=>r.error?`refus ${r.error.code||'?'} « ${r.error.message} »`:'accepté';

// Jeton destiné au cas « session expirée » : obtenu dès le début (durée de vie du projet d'essai : 60 s).
const pourExpiration=await connecter('editeur').catch(()=>null);

await R.cas('éditeur aal2 : lecture et écriture via RPC ; tables privées inaccessibles','aal2 ; lecture et écriture acceptées puis retour à l’état initial ; accès direct aux tables refusé',async preuve=>{
 const s=await connecter('editeur');if(!s)return 'non_execute';preuve('aal',s.aal,'· amr',(jwt(s.jeton).amr||[]).map(x=>x.method).join('+'));vrai(s.aal==='aal2','niveau '+s.aal);
 const l=await admin(s.db,'etat',{});preuve('lecture :',code(l));vrai(!l.error,'lecture refusée');
 if(MATCH){const m=await lire(s.db);
  const r1=await admin(s.db,'score',{id:MATCH,revision:m.revision,score_domicile:(m.score_domicile??0)+1,motif:'essai auth réelle'});preuve('écriture :',code(r1),'révision',m.revision,'→',r1.data?.revision);vrai(!r1.error,'écriture refusée');
  const r2=await admin(s.db,'score',{id:MATCH,revision:r1.data.revision,score_domicile:m.score_domicile??0,motif:'essai auth réelle : retour'});vrai(!r2.error,r2.error?.message);}
 for(const t of ['matchs','equipes','corrections','reglages']){const d=await s.db.schema('koki_foot').from(t).select('*').limit(1);preuve('koki_foot.'+t+' :',code(d));vrai(d.error,'accès direct à koki_foot.'+t+' accordé');}
 return 'aal2, RPC acceptées, tables refusées';
});
await R.cas('superadmin aal2 : opération réservée acceptée','aal2 ; verifier_journal accepté',async preuve=>{
 const s=await connecter('superadmin');if(!s)return 'non_execute';preuve('aal',s.aal);vrai(s.aal==='aal2','niveau '+s.aal);
 const v=await admin(s.db,'verifier_journal',{});preuve('verifier_journal :',code(v),'→',JSON.stringify(v.data));vrai(!v.error,v.error?.message);
 return 'accepté';
});
await R.cas('éditeur aal2 : opération réservée au superadmin refusée','regler_verrous refusé',async preuve=>{
 const s=await connecter('editeur');if(!s)return 'non_execute';
 const r=await admin(s.db,'regler_verrous',{mode:'independant'});preuve('regler_verrous :',code(r));vrai(refuse(r),'réglage superadmin non refusé pour droits');
 return 'refusé';
});
await R.cas('session aal1 (sans MFA) : lecture et écriture refusées','aal1 ; refus « double authentification requise »',async preuve=>{
 const s=await connecter('sansmfa',{mfa:false})||await connecter('editeur',{mfa:false});if(!s)return 'non_execute';preuve('aal',s.aal);vrai(s.aal==='aal1','niveau '+s.aal);
 const l=await admin(s.db,'etat',{});preuve('lecture :',code(l));vrai(refuse(l),'lecture acceptée sans MFA');
 if(MATCH){const w=await admin(s.db,'score',{id:MATCH,revision:1,score_domicile:9});preuve('écriture :',code(w));vrai(refuse(w),'écriture acceptée sans MFA');}
 return 'refusé';
});
await R.cas('utilisateur authentifié sans droits : refusé','lecture et écriture refusées',async preuve=>{
 const s=await connecter('sansdroit');if(!s)return 'non_execute';preuve('aal',s.aal);
 const l=await admin(s.db,'etat',{});preuve('lecture :',code(l));vrai(refuse(l),'lecture admin accordée');
 if(MATCH){const w=await admin(s.db,'score',{id:MATCH,revision:1,score_domicile:9});preuve('écriture :',code(w));vrai(refuse(w),'écriture accordée');}
 return 'refusé';
});
await R.cas('anonyme (clé publique) : admin et synchronisation refusées ; lecture publique permise','admin refusé, sync refusée, accueil public lisible',async preuve=>{
 const db=nouveau();const a=await admin(db,'etat',{});preuve('admin :',code(a));vrai(refuse(a),'admin anonyme non refusé pour droits');
 const s=await db.rpc('koki_foot_sync',{command:'importer',input:{}});preuve('sync :',code(s));vrai(refuse(s),'synchronisation anonyme non refusée pour droits');
 const p=await db.rpc('koki_foot_public',{command:'accueil',input:{}});preuve('public :',code(p));vrai(!p.error,p.error?.message);
 return 'conforme';
});
await R.cas('session expirée : vrai jeton périmé refusé par le serveur','refus après expiration (exp dépassé)',async preuve=>{
 const jeton=process.env.KOKI_ESSAI_JETON_EXPIRE||pourExpiration?.jeton;if(!jeton)return 'non_execute';
 // PostgREST tolère un décalage d'horloge de 30 s : l'essai attend exp + 40 s.
 const exp=jwt(jeton).exp*1000;const attente=exp-Date.now()+40000;
 if(attente>0){if(attente>150000)return 'non_execute';preuve('attente',Math.round(attente/1000),'s (exp + 40 s)');await new Promise(r=>setTimeout(r,attente));}
 const db=nouveau({global:{headers:{Authorization:'Bearer '+jeton}}});
 const r=await admin(db,'etat',{});preuve('après expiration :',code(r));
 vrai(r.error&&/expired|expir|PGRST30/i.test((r.error.code||'')+' '+r.error.message),'jeton expiré non refusé comme tel');
 return 'refusé';
});
await R.cas('interruption pendant une écriture : erreur propre, aucune écriture partielle','erreur côté client ; en base soit rien, soit l’écriture complète',async preuve=>{
 const s=await connecter('editeur');if(!s||!MATCH)return 'non_execute';
 const avant=await lire(s.db);const ctl=new AbortController();
 const p=s.db.rpc('koki_foot_admin',{command:'score',input:{id:MATCH,revision:avant.revision,score_domicile:(avant.score_domicile??0)+1,motif:'essai coupure'}}).abortSignal(ctl.signal);
 setTimeout(()=>ctl.abort(),5);const r=await p;preuve('client :',code(r));
 await new Promise(r=>setTimeout(r,1500));const apres=await lire(s.db);preuve('révision',avant.revision,'→',apres.revision);
 vrai(apres.revision===avant.revision||(apres.revision===avant.revision+1&&apres.score_domicile===(avant.score_domicile??0)+1),'état intermédiaire');
 if(apres.revision!==avant.revision)await admin(s.db,'score',{id:MATCH,revision:apres.revision,score_domicile:avant.score_domicile??0,motif:'essai coupure : retour'});
 if(!r.error){preuve('requête terminée avant l’interruption : cas non probant');return 'non_execute';}
 return apres.revision===avant.revision?'interrompue : rien écrit':'interrompue après validation : écriture complète';
});
process.exit(R.bilan()?0:1);
