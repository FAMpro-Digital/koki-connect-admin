// Crée les comptes et le match d'essai dans le Supabase LOCAL éphémère (appelé par preparer-supabase-local.sh).
// Écrit sur la sortie standard les variables KOKI_ESSAI_* (fichier hors dépôt, droits 600).
// Mots de passe et secrets TOTP : aléatoires, propres à cette exécution, jamais affichés dans le journal.
import {createClient} from '@supabase/supabase-js';
import {randomBytes} from 'node:crypto';import {execFileSync} from 'node:child_process';
import {totpFrais} from './commun.mjs';

import {environnement} from './commun.mjs';
// Local éphémère : clés de « supabase status » (ANON_KEY / PUBLISHABLE_KEY, SERVICE_ROLE_KEY).
// Projet HÉBERGÉ d'essai : KOKI_ESSAI_PUBLISHABLE_KEY, KOKI_ESSAI_SECRET_KEY, KOKI_ESSAI_DB_URL (variables d'environnement).
const envE={...process.env,KOKI_ESSAI_CONFIRME:process.env.KOKI_ESSAI_CONFIRME||'projet-essai',
 KOKI_ESSAI_PUBLISHABLE_KEY:process.env.KOKI_ESSAI_PUBLISHABLE_KEY||process.env.PUBLISHABLE_KEY||'',KOKI_ESSAI_ANON_KEY:process.env.KOKI_ESSAI_ANON_KEY||process.env.ANON_KEY||''};
const E=environnement(envE),url=E.url,anon=E.cle;
const service=process.env.KOKI_ESSAI_SECRET_KEY||(E.heberge?'':process.env.SERVICE_ROLE_KEY);
const DB_URL=process.env.KOKI_ESSAI_DB_URL||(E.heberge?'':'postgresql://supabase_admin:postgres@127.0.0.1:54322/postgres');
if(!service||!DB_URL)throw Error('Clé secrète et adresse de base du projet d’essai requises (variables d’environnement)');
if(DB_URL.includes('qsbmzzbiztfqysstepxm'))throw Error('REFUS : base de PRODUCTION');
const opts={auth:{persistSession:false,autoRefreshToken:false}};
const adm=createClient(url,service,opts);
const sql=q=>execFileSync('psql',[DB_URL,'-X','-Atq','-v','ON_ERROR_STOP=1','-c',q],{encoding:'utf8'}).trim();
const env=[];const out=(k,v)=>env.push(`${k}=${v}`);

async function compte(nom,role,mfa){
 const email=`${nom}@essai.koki.invalid`,motDePasse=randomBytes(18).toString('base64url');
 const {data,error}=await adm.auth.admin.createUser({email,password:motDePasse,email_confirm:true});if(error)throw Error(nom+' : '+error.message);
 if(role)sql(`insert into public.koki_admin_members(user_id,role) values('${data.user.id}','${role}')`);
 const p='KOKI_ESSAI_'+nom.toUpperCase();out(p+'_EMAIL',email);out(p+'_MOT_DE_PASSE',motDePasse);
 if(!mfa)return null;
 const db=createClient(url,anon,opts);
 const s=await db.auth.signInWithPassword({email,password:motDePasse});if(s.error)throw s.error;
 const e=await db.auth.mfa.enroll({factorType:'totp',friendlyName:'essai'});if(e.error)throw e.error;
 const secret=e.data.totp.secret;
 const c=await db.auth.mfa.challenge({factorId:e.data.id});if(c.error)throw c.error;
 const v=await db.auth.mfa.verify({factorId:e.data.id,challengeId:c.data.id,code:await totpFrais(secret)});if(v.error)throw v.error;
 out(p+'_TOTP',secret);
 return db;
}
const editeur=await compte('editeur','editor',true);
await compte('superadmin','superadmin',true);
await compte('sansmfa','editor',false);
await compte('sansdroit',null,false);

// Projet hébergé : le marqueur d'environnement d'essai doit exister (posé par preparer-projet-essai.sh).
if(E.heberge&&sql("select count(*) from pg_namespace where nspname='koki_essai'")!=='1')throw Error('REFUS : marqueur koki_essai absent : ce projet n’est pas identifié comme projet d’essai');

// Match d'essai créé par l'éditeur (vraie session aal2, vraies RPC).
const rpc=async(command,input)=>{const {data,error}=await editeur.rpc('koki_foot_admin',{command,input});if(error)throw Error(command+' : '+error.message);return data;};
const comp=await rpc('enregistrer_competition',{nom:'ESSAI Navétanes',type:'Championnat',portee:'Koki',publie:true});
const a=await rpc('enregistrer_equipe',{nom:'ESSAI ASC A'}),b=await rpc('enregistrer_equipe',{nom:'ESSAI ASC B'});
const m=await rpc('enregistrer_match',{competition_id:comp.id,domicile_id:a.id,exterieur_id:b.id,date_match:new Date(Date.now()-30*60000).toISOString(),lieu:'Stade d’essai',publie:true});
const d=await rpc('score',{id:m.id,revision:m.revision,statut:'En direct',minute:30,score_domicile:0,score_exterieur:0});
out('KOKI_ESSAI_MATCH_ID',m.id);
out('KOKI_ESSAI_URL',url);out(E.type==='publishable'?'KOKI_ESSAI_PUBLISHABLE_KEY':'KOKI_ESSAI_ANON_KEY',anon);out('KOKI_ESSAI_CONFIRME','projet-essai');
process.stdout.write(env.join('\n')+'\n');
console.error(`comptes d'essai : 4 · match d'essai publié (révision ${d.revision})`);
