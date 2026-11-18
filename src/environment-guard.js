// Séparation des environnements Koki Connect : local, test (préproduction), production.
// Une base protégée (production Koki Connect, FAMpro Évents) n'est acceptée que par
// l'environnement « production » ; un environnement de production n'accepte que
// la base de production. Utilisé côté navigateur (src/backend.js) et côté serveur (api/).
export const PRODUCTION_REF='qsbmzzbiztfqysstepxm';
export const PROTECTED_REFS=Object.freeze([PRODUCTION_REF,'paegdthtusbwxuarhacb']);
export const ENVIRONMENTS=Object.freeze(['local','test','production']);

// Environnement déclaré : KOKI_ENV (ou VITE_KOKI_ENV) en priorité, sinon déduit de
// l'environnement Vercel (VERCEL_ENV / VITE_VERCEL_ENV) : production → production,
// preview et development → test. Rien de déclaré : null (développement sur la machine).
export function declaredEnvironment({koki,vercel}={}){
 if(koki){if(!ENVIRONMENTS.includes(koki))throw Error(`Environnement inconnu « ${koki} » (attendu : ${ENVIRONMENTS.join(', ')}).`);return koki;}
 if(vercel==='production')return 'production';
 if(vercel==='preview'||vercel==='development')return 'test';
 return null;
}

export function projectRef(url){
 const m=/^https:\/\/([a-z0-9]+)\.supabase\.co\/?$/.exec(String(url||''));
 return m?m[1]:null;
}

// Lève une erreur si la base visée ne correspond pas à l'environnement.
export function checkEnvironment({environment,url}){
 if(!environment||!url)return {environment:environment||null,ref:projectRef(url)};
 const ref=projectRef(url);
 if(environment==='production'){
  if(ref!==PRODUCTION_REF)throw Error('Environnement production : seule la base de production Koki Connect est acceptée.');
 }else if(ref&&PROTECTED_REFS.includes(ref)){
  throw Error(`Environnement ${environment} : la base de production est interdite. Utilisez la base de test.`);
 }
 return {environment,ref};
}
