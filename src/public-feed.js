// Adaptateur SDK disponible pour les futurs clients. Le portail statique utilise assets/portail/feed.js.
// Même base et mêmes règles serveur ; aucune clé secrète ou droit administrateur.
import {createClient} from '@supabase/supabase-js';
export async function publicFeed(url,publishableKey){
 if(!publishableKey.startsWith('sb_publishable_'))throw Error('Clé publique attendue.');
 const client=createClient(url,publishableKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
 const {data,error}=await client.rpc('koki_public_feed');if(error)throw error;
 for(const content of data.contenus){if(content.image_path){const signed=await client.storage.from('koki-media').createSignedUrl(content.image_path,120);content.image=signed.error?null:signed.data.signedUrl;}}
 return data;
}
