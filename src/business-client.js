const reads=new Set(['catalog','history','get','quote','nearby_drivers','ride_contacts','localites','admin_stats','admin_queue','admin_records']);
export const vehicles=['Moto','Taxi','Voiture','Minicar'];
export function nextStatus(row){const chain=row.kind==='courses'?['En attente','Acceptée','Chauffeur en route','Course en cours','Terminée']:row.kind==='commandes'?(row.payload.mode==='retrait'?['Commande reçue','Confirmée','Préparation','Prête au retrait','Retirée']:['Commande reçue','Confirmée','Préparation','En livraison','Livrée']):['Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé'];return chain[chain.indexOf(row.statut)+1]||null;}
export function createBusinessClient(db,{enabled=false,storage=null,uuid=()=>crypto.randomUUID(),notify=()=>{}}={}){
 let recovering=false;db?.auth.onAuthStateChange?.(event=>{if(event==='PASSWORD_RECOVERY'){recovering=true;queueMicrotask(()=>emit({state:'recovery'}));}});
 let user=null;const pending=new Map(),listeners=new Set(),waiters=[];let busy=false;const emit=value=>{notify(value);for(const listener of listeners)listener(value);};
 const requireReady=()=>{if(!enabled||!db)throw Error('Service connecté en préparation : activation après validation des migrations.');};
 const scope=()=>`koki.business.pending.${user?.id}`;
 function restore(){pending.clear();try{for(const [k,v] of JSON.parse(storage?.getItem(scope())||'[]'))pending.set(k,v);}catch{}}
 function persist(){try{storage?.setItem(scope(),JSON.stringify([...pending]));}catch{/* Retry remains available in memory. */}}
 async function identity(){requireReady();const {data,error}=await db.auth.getUser();if(error||!data?.user||data.user.is_anonymous){user=null;pending.clear();throw Error('Connectez-vous avec un compte client permanent.');}if(user?.id!==data.user.id){user=data.user;restore();}return user;}
 async function run(command,input={},operation=command){requireReady();const mutation=!reads.has(command);if(command!=='catalog')await identity();while(busy){if(mutation)throw Error('Une opération est déjà en cours.');await new Promise(resolve=>waiters.push(resolve));}
 const body=structuredClone(input);let item;
 if(mutation){const fingerprint=JSON.stringify(body);item=pending.get(operation);if(item&&(item.command!==command||item.fingerprint!==fingerprint))throw Error('Une demande attend confirmation. Reprenez-la avec les mêmes informations avant de les modifier.');if(!item){item={command,fingerprint,input:structuredClone(body),request_id:uuid()};pending.set(operation,item);persist();}body.request_id=item.request_id;}
 busy=true;emit({state:'loading',command});try{const {data,error}=await db.rpc('koki_business',{command,input:body});if(error){const e=Error(error.code==='42501'?'Autorisation refusée. Vérifiez votre compte et vos droits.':error.code==='PGRST202'?'Fonctions serveur non activées sur cet environnement.':error.message||'Opération refusée.');e.definitive=!!error.code&&!['57014','08006','08000'].includes(error.code)&&!String(error.code).startsWith('5');throw e;}
 if(mutation){pending.delete(operation);persist();}emit({state:'success',command});return data;
 }catch(e){if(mutation&&e.definitive){pending.delete(operation);persist();}emit({state:'error',command,retry:mutation&&pending.has(operation)});throw e;}finally{busy=false;emit({state:'idle',command});waiters.shift()?.();}}
 return {subscribe(listener){listeners.add(listener);return ()=>listeners.delete(listener);},get enabled(){return enabled&&!!db;},get busy(){return busy;},get user(){return user;},get recovering(){return recovering;},identity,run,
 async recover(email,redirect){requireReady();const url=new URL(redirect);if(url.origin!==location.origin||!(url.protocol==='https:'||url.hostname==='127.0.0.1'||url.hostname==='localhost'))throw Error('Lien de récupération invalide.');const {error}=await db.auth.resetPasswordForEmail(email.trim(),{redirectTo:url.href});if(error)throw Error('Envoi indisponible. Patientez avant de réessayer.');},
 async changePassword(password){requireReady();await identity();if(password.length<12)throw Error('Choisissez au moins 12 caractères.');const {error}=await db.auth.updateUser({password});if(error)throw Error('Modification refusée. Vérifiez votre session et la double authentification si elle est activée.');recovering=false;},
 async login(email,password){requireReady();const {error}=await db.auth.signInWithPassword({email:email.trim(),password});if(error)throw Error('Connexion refusée. Vérifiez vos identifiants.');return identity();},
 async signup(email,password){requireReady();const {error}=await db.auth.signUp({email:email.trim(),password});if(error)throw Error('Inscription impossible. Réessayez ou contactez Koki Connect.');},
 async logout(){requireReady();if(pending.size)throw Error('Une demande attend confirmation. Reprenez-la avant de vous déconnecter.');const {error}=await db.auth.signOut({scope:'local'});if(error)throw Error('Déconnexion impossible.');try{storage?.removeItem(scope());}catch{}user=null;pending.clear();},
 pending(){return [...pending.entries()].map(([operation,v])=>({operation,...structuredClone(v)}));},
 retry(operation){const v=pending.get(operation);if(!v)throw Error('Aucune demande à reprendre.');return run(v.command,v.input,operation);},
 catalog:()=>run('catalog'),history:kind=>run('history',{kind}),get:id=>run('get',{id}),
 estimate:(category,start,end)=>run('quote',{category,start:{latitude:start.latitude,longitude:start.longitude},end:{latitude:end.latitude,longitude:end.longitude}}),
 nearby:(category,start)=>run('nearby_drivers',{category,start:{latitude:start.latitude,longitude:start.longitude}}),
 reserve:(quote,vehicle)=>run('reserve_ride',{quote_id:quote.quote_id,vehicle_id:vehicle},'reserve'),
 order:(shop,items,mode,address)=>run('create_order',{shop_id:shop,items:items.map(x=>({product_id:x.product_id,quantity:x.quantity})),mode,address},'order'),
 transition:(row,next)=>run('transition',{id:row.id,revision:row.revision,next},'transition:'+row.id),
 async mine(kind){requireReady();await identity();const {data,error}=await db.from('koki_records').select('*').eq('kind',kind).eq('owner_id',user.id).order('updated_at',{ascending:false}).limit(100);if(error)throw Error('Chargement de votre espace impossible.');return data||[];},
 async rates(){requireReady();const {data,error}=await db.from('koki_transport_rates').select('*').order('category');if(error)throw Error('Tarifs indisponibles.');return data||[];},
 async image(path){requireReady();const {data,error}=await db.storage.from('koki-media').createSignedUrl(path,120);if(error)throw Error('Image inaccessible.');const url=new URL(data.signedUrl);if(url.origin!==new URL(db.supabaseUrl).origin||url.protocol!=='https:'||!url.pathname.startsWith('/storage/v1/object/'))throw Error('Image invalide.');return url.href;}
 };
}
