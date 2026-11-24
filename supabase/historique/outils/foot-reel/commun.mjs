// Outils communs aux essais réels (authentification, Realtime) du module Football.
// À exécuter UNIQUEMENT contre un projet Supabase d'essai (copie de la structure de production).
// Aucun secret n'est écrit dans ce fichier : tout vient de variables d'environnement.
import {createHmac} from 'node:crypto';

export const PRODUCTION_REF='qsbmzzbiztfqysstepxm';

// Garde-fou : refuse toute adresse de production, et exige une confirmation explicite de l'environnement.
export function environnement(env=process.env){
 const url=env.KOKI_ESSAI_URL||'',cle=env.KOKI_ESSAI_ANON_KEY||'';
 if(!url||!cle)throw Error('KOKI_ESSAI_URL et KOKI_ESSAI_ANON_KEY sont requis (projet d’essai).');
 if(url.includes(PRODUCTION_REF))throw Error('Refus : l’adresse désigne le projet de PRODUCTION.');
 if(env.KOKI_ESSAI_CONFIRME!=='projet-essai')throw Error('Confirmer l’environnement : KOKI_ESSAI_CONFIRME=projet-essai.');
 if(!/^https:\/\/[a-z0-9]{20}\.supabase\.co$|^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url))throw Error('Adresse inattendue : '+url);
 return {url,cle};
}

// Comptes d'essai : KOKI_ESSAI_<NOM>_EMAIL, _MOT_DE_PASSE et, pour la double authentification, _TOTP (secret base32).
export function compte(nom,env=process.env){
 const p='KOKI_ESSAI_'+nom.toUpperCase()+'_';
 const c={email:env[p+'EMAIL'],motDePasse:env[p+'MOT_DE_PASSE'],totp:env[p+'TOTP']||null};
 if(!c.email||!c.motDePasse)return null;return c;
}

// TOTP RFC 6238 (SHA-1, 30 s, 6 chiffres) : code de double authentification calculé localement.
export function base32(s){const A='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';let bits='';for(const ch of s.replace(/=+$/,'').replace(/\s/g,'').toUpperCase()){const v=A.indexOf(ch);if(v<0)throw Error('Secret base32 invalide');bits+=v.toString(2).padStart(5,'0');}
 const o=[];for(let i=0;i+8<=bits.length;i+=8)o.push(parseInt(bits.slice(i,i+8),2));return Buffer.from(o);}
export function totp(secret,{temps=Date.now(),pas=30,chiffres=6,cle=null}={}){
 const k=cle||base32(secret);const c=Buffer.alloc(8);c.writeBigUInt64BE(BigInt(Math.floor(temps/1000/pas)));
 const h=createHmac('sha1',k).update(c).digest();const o=h[h.length-1]&15;
 const n=((h[o]&127)<<24|h[o+1]<<16|h[o+2]<<8|h[o+3])%10**chiffres;return String(n).padStart(chiffres,'0');}

// Résultats lisibles : réussi / échoué / non exécuté (compte absent), sans jamais afficher de secret.
export function rapporteur(){
 const r=[];
 return {r,
  async cas(nom,fn){try{const v=await fn();if(v==='non_execute'){r.push({nom,etat:'non exécuté'});console.log('--      '+nom+' (compte d’essai absent)');return;}r.push({nom,etat:'réussi'});console.log('ok      '+nom);}
   catch(e){r.push({nom,etat:'échoué',erreur:String(e.message).slice(0,200)});console.log('ÉCHEC   '+nom+'\n        '+e.message);}},
  bilan(){const n=e=>r.filter(x=>x.etat===e).length;console.log(`\nRéussis ${n('réussi')} · échoués ${n('échoué')} · non exécutés ${n('non exécuté')} · total ${r.length}`);return n('échoué')===0;}};
}
export function vrai(c,m){if(!c)throw Error(m);}
