import {authDestination,recoveryURL} from './auth-destination.js';
import {isProcessedImage,inspectImage,MAX_OUTPUT} from './image-processing.js';
import {createBusinessClient} from './business-client.js';
import {createClient} from '@supabase/supabase-js';
import {checkBackendTarget} from './backend-guard.js';
import {verifierLivre} from './livre-fichier.js';
const url=import.meta.env.VITE_SUPABASE_URL,key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
// Refuse une base locale hors « npm run dev:local » et toute base distante en mode local.
export const target=checkBackendTarget({url,key,mode:import.meta.env.MODE,dev:import.meta.env.DEV});
export const configured=target.configured;
export const {error:authLinkError,onboarding}=authDestination(location.href);
export const db=configured?createClient(url,key,{auth:{persistSession:false,autoRefreshToken:true,detectSessionInUrl:true}}):null;
const businessStorage=(()=>{try{return sessionStorage;}catch{return null;}})();
export const business=createBusinessClient(db,{enabled:import.meta.env.VITE_BUSINESS_RPC_ENABLED==='true',storage:businessStorage});
export async function result(query){const {data,error}=await query;if(error)throw Error('Opération refusée ou serveur indisponible : '+error.message);return data;}
export async function identity(){const {data,error}=await db.auth.getUser();if(error||!data.user)throw Error('Connexion requise.');const membership=await result(db.from('koki_admin_members').select('role,enabled').eq('user_id',data.user.id).maybeSingle());if(!membership?.enabled)throw Error('Ce compte n’est pas autorisé à administrer Koki Connect.');const aal=await db.auth.mfa.getAuthenticatorAssuranceLevel();if(aal.error)throw aal.error;return {user:data.user,role:membership.role,aal:aal.data.currentLevel};}
export async function list(table,filter={},search=''){let q=db.from(table).select('*').order('updated_at',{ascending:false}).limit(50);for(const [k,v]of Object.entries(filter))q=Array.isArray(v)?q.in(k,v):q.eq(k,v);if(search&&table==='koki_contents')q=q.ilike('titre','%'+search+'%');return result(q);}
export async function write(table,row,old){if(table==='koki_records')throw Error('Utilisez les commandes métier sécurisées.');if(old){const data=await result(db.from(table).update(row).eq('id',old.id).eq('updated_at',old.updated_at).select());if(!data.length)throw Error('Ce contenu a changé sur un autre appareil. Rechargez-le avant de modifier.');return data[0];}return result(db.from(table).insert(row).select().single());}
export async function remove(table,row){if(table==='koki_records')throw Error('La suppression métier directe est interdite. Utilisez une suspension ou une annulation.');const data=await result(db.from(table).delete().eq('id',row.id).eq('updated_at',row.updated_at).select('id'));if(!data.length)throw Error('Suppression non effectuée : rechargez les données.');}
export async function media(file){if(!file)return null;if(!isProcessedImage(file))throw Error('La photo doit être traitée avant son envoi.');const type=await inspectImage(file,MAX_OUTPUT);if(!['image/jpeg','image/png','image/webp'].includes(type)||file.type!==type)throw Error('Format de photo invalide.');const ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[type];const {data,error}=await db.auth.getUser();if(error||!data.user)throw Error('Connexion requise pour envoyer la photo.');const path=data.user.id+'/'+crypto.randomUUID()+'.'+ext;await result(db.storage.from('koki-media').upload(path,file,{contentType:type,upsert:false}));return path;}
// Bibliothèque : fichiers des livres gratuits dans le bucket privé koki-livres (50 Mo maximum).
export async function bookUpload(file){if(!file)return null;const info=await verifierLivre(file);const {data,error}=await db.auth.getUser();if(error||!data.user)throw Error('Connexion requise pour envoyer le fichier.');const path=data.user.id+'/'+crypto.randomUUID()+'.'+info.ext;await result(db.storage.from('koki-livres').upload(path,file,{contentType:info.type,upsert:false}));return {...info,path};}
export async function bookURL(path){const data=await result(db.storage.from('koki-livres').createSignedUrl(path,300));return data.signedUrl;}
export async function bookRemove(path){if(path)await result(db.storage.from('koki-livres').remove([path]));}
export async function imageURL(path){const data=await result(db.storage.from('koki-media').createSignedUrl(path,120));return data.signedUrl;}

export const recoveryRedirect=recoveryURL(import.meta.env.VITE_ADMIN_PREVIEW_URL||location.origin);
export const publicApplicationURL=import.meta.env.VITE_PUBLIC_PREVIEW_URL||(import.meta.env.VITE_BUSINESS_RPC_ENABLED==='true'?null:'https://koki-connect.vercel.app/');
