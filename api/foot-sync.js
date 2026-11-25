// Synchronisation du module Football avec API-Football — fonction SERVEUR (Vercel).
// Appelée chaque minute par pg_cron (proposition 20261201000810) avec un secret partagé.
// La clé API-Football (API_FOOTBALL_KEY) et la clé service de Supabase ne quittent jamais le serveur :
// aucune n'est renvoyée, journalisée ni exposée au navigateur (variables sans préfixe client).
//
// Modes (corps JSON) :
//  {"mode":"passage"}                                   synchronisation planifiée selon le quota (défaut)
//  {"mode":"verifier","pays":"Senegal"}                 couverture réelle, sans écriture (1 à 2 requêtes)
//  {"mode":"decouvrir","ligue":<id>,"saison":<année>}   import d'une compétition NON publiée (2 à 3 requêtes)
import {timingSafeEqual} from 'node:crypto';
import {checkEnvironment,declaredEnvironment} from '../src/environment-guard.js';
import {creerClient,expurger,ErreurFournisseur,FOURNISSEUR} from '../server/foot/api-football.js';
import {passage,decouvrir,verifier,lireConfig} from '../server/foot/synchronisation.js';

const egal=(a,b)=>{if(typeof a!=='string'||typeof b!=='string')return false;const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);};
function environnementRefuse(env){try{checkEnvironment({environment:declaredEnvironment({koki:env.KOKI_ENV,vercel:env.VERCEL_ENV}),url:env.SUPABASE_URL});return false;}catch{return true;}}

// Appel RPC PostgREST avec la clé service (serveur uniquement).
export function creerRpc({url,cleService,request=fetch}){
 const appel=async(fonction,args)=>{
  const r=await request(url.replace(/\/$/,'')+'/rest/v1/rpc/'+fonction,{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),
   headers:{apikey:cleService,Authorization:'Bearer '+cleService,'Content-Type':'application/json'},body:JSON.stringify(args)});
  if(!r.ok){let m='';try{m=(await r.json())?.message||'';}catch{}throw Error('Base : '+(m||r.status));}
  return r.json();
 };
 return {
  rpc:(command,input)=>appel('koki_foot_sync',{command,input}),
  planning:()=>appel('koki_foot_sync_planning',{p_fournisseur:FOURNISSEUR})
 };
}

export function footSyncHandler({env=process.env,request=fetch,maintenant=()=>new Date()}={}){
 return async(req,res)=>{
  res.setHeader('Cache-Control','no-store');
  if(req.method!=='POST')return res.status(405).json({error:'Méthode refusée'});
  const secret=env.FOOT_SYNC_SECRET;
  if(!secret||secret.length<32||!egal(req.headers?.authorization,'Bearer '+secret))return res.status(401).json({error:'Non autorisé'});
  if(env.FOOT_SYNC_ENABLED!=='true')return res.status(503).json({error:'Synchronisation désactivée'});
  if(!env.API_FOOTBALL_KEY||!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY)return res.status(503).json({error:'Synchronisation non configurée'});
  if(environnementRefuse(env))return res.status(503).json({error:'Base non autorisée pour cet environnement'});
  let corps=req.body;if(typeof corps==='string'){try{corps=JSON.parse(corps);}catch{corps=null;}}
  corps=corps&&typeof corps==='object'?corps:{};
  const mode=corps.mode||'passage';
  const cle=env.API_FOOTBALL_KEY;
  try{
   const api=creerClient({cle,request});
   const {rpc,planning}=creerRpc({url:env.SUPABASE_URL,cleService:env.SUPABASE_SERVICE_ROLE_KEY,request});
   if(mode==='passage')return res.status(200).json(await passage({api,rpc,planning,maintenant:maintenant(),config:lireConfig(env),cle}));
   if(mode==='verifier'){
    const pays=/^[A-Za-z][A-Za-z -]{1,40}$/.test(String(corps.pays||''))?corps.pays:'Senegal';
    return res.status(200).json({...await verifier({api,pays}),requetes:api.requetes});
   }
   if(mode==='decouvrir'){
    const ligue=Number(corps.ligue),saison=Number(corps.saison);
    if(!Number.isInteger(ligue)||ligue<1||ligue>9999999||!Number.isInteger(saison)||saison<2000||saison>2100)return res.status(400).json({error:'Ligue ou saison invalide'});
    return res.status(200).json({...await decouvrir({api,rpc,ligue,saison}),requetes:api.requetes});
   }
   return res.status(400).json({error:'Mode inconnu'});
  }catch(e){
   const code=e instanceof ErreurFournisseur?e.code:'autre';
   return res.status(code==='authentification'?502:503).json({error:expurger(e?.message||'Erreur',cle),code});
  }
 };
}
export default footSyncHandler();
