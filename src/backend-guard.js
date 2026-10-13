// Garde-fou de la cible Supabase de l'administration.
// - Mode « supabase-local » (npm run dev:local) : uniquement le Supabase local de la machine
//   (http://127.0.0.1:54321 ou http://localhost:54321), uniquement avec le serveur de développement Vite.
// - Tout autre mode : uniquement une adresse https://<référence>.supabase.co ; une adresse locale
//   ou http:// est refusée, donc une version publiée ne peut jamais viser une base locale.
// - Dans tous les cas : clé publishable uniquement, jamais de clé secrète.
export const LOCAL_MODE='supabase-local';
export const PRODUCTION_REFS=Object.freeze(['qsbmzzbiztfqysstepxm','paegdthtusbwxuarhacb']);
const LOCAL_URL=/^http:\/\/(127\.0\.0\.1|localhost):54321$/;
const CLOUD_URL=/^https:\/\/([a-z0-9]+)\.supabase\.co$/;
export function checkBackendTarget({url,key,mode,dev}){
 if(!url&&!key){if(mode===LOCAL_MODE)throw Error('Mode local : VITE_SUPABASE_URL et VITE_SUPABASE_PUBLISHABLE_KEY sont requis (voir .env.supabase-local.example).');return {configured:false,local:false};}
 if(!url||!key)throw Error('Configuration Supabase incomplète.');
 if(!String(key).startsWith('sb_publishable_'))throw Error('Utilisez uniquement une clé Supabase publishable. Les clés secrètes sont interdites.');
 if(mode===LOCAL_MODE){
  if(dev!==true)throw Error('Le mode Supabase local est réservé au serveur de développement (npm run dev:local).');
  if(!LOCAL_URL.test(url))throw Error('Mode local : seule l’adresse http://127.0.0.1:54321 est acceptée. Aucune base distante.');
  return {configured:true,local:true};
 }
 const cloud=CLOUD_URL.exec(url);
 if(!cloud)throw Error('Adresse Supabase invalide : seule une adresse https://<référence>.supabase.co est acceptée hors mode local.');
 return {configured:true,local:false,ref:cloud[1],production:PRODUCTION_REFS.includes(cloud[1])};
}
