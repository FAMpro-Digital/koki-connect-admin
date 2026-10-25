// Les réponses personnelles restent en mémoire : aucun stockage hors ligne.
const element=(tag,text)=>{const e=document.createElement(tag);if(text)e.textContent=text;return e;};
export function decodeKey(value){const bytes=atob(value.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-value.length%4)%4));return Uint8Array.from(bytes,c=>c.charCodeAt(0));}
export async function disablePush(db){
 if(!('serviceWorker' in navigator))return;
 const registration=await navigator.serviceWorker.getRegistration();
 const subscription=await registration?.pushManager?.getSubscription();
 if(!subscription)return;
 const {error}=await db.from('koki_push_subscriptions').delete().eq('endpoint',subscription.endpoint);
 // Même si la base est indisponible, le navigateur ne recevra plus de messages.
 await subscription.unsubscribe();
 if(error)throw Error('Notifications désactivées sur cet appareil ; synchronisation serveur indisponible.');
}
export async function renderNotifications(host,db,{vapidPublicKey='',smsEnabled=false}={}){
 host.notificationCleanup?.();const renderId=Symbol();host.notificationRender=renderId;host.replaceChildren();
 const heading=element('h3','Mes notifications'),status=element('p');status.setAttribute('role','status');host.append(heading,status);
 if(!db){status.textContent='Connectez-vous pour consulter vos notifications personnelles.';return;}
 const userResponse=await db.auth.getUser();const user=userResponse.data?.user;
 if(host.notificationRender!==renderId)return;
 if(userResponse.error||!user){status.textContent='Connectez-vous dans Profil pour consulter vos notifications personnelles.';return;}
 let disposed=false;
 let timer;const listener=db.auth.onAuthStateChange((event,session)=>{if(session?.user?.id!==user.id){disposed=true;clearInterval(timer);host.replaceChildren(element('p','Connectez-vous pour consulter vos notifications personnelles.'));listener.data.subscription.unsubscribe();}});
 // Un seul abonnement d'auth par écran, nettoyé au prochain affichage.
 host.notificationCleanup=()=>{disposed=true;clearInterval(timer);listener.data.subscription.unsubscribe();};
 const list=element('div');host.append(list);
 const button=(label,fn)=>{const b=element('button',label);b.type='button';b.className='btn';b.onclick=()=>{b.disabled=true;Promise.resolve().then(fn).catch(()=>{if(!disposed)status.textContent='Opération indisponible. Vérifiez votre connexion et réessayez.';}).finally(()=>{b.disabled=false;});};return b;};
 async function refresh(){
  const {data,error}=await db.from('koki_notifications').select('id,title,body,created_at,read_at').eq('recipient_id',user.id).order('created_at',{ascending:false}).limit(50);
  if(disposed)return;
  if(error){status.textContent='Les notifications personnelles sont en cours de préparation.';return;}
  list.replaceChildren();
  if(!data.length)list.append(element('p','Aucune notification personnelle pour le moment.'));
  for(const item of data){const card=element('article');card.className='card';card.append(element('h4',item.title),element('p',item.body),element('small',new Date(item.created_at).toLocaleString('fr-FR')));
   if(!item.read_at)card.append(button('Marquer comme lue',async()=>{const r=await db.from('koki_notifications').update({read_at:new Date().toISOString()}).eq('id',item.id).eq('recipient_id',user.id);if(r.error)throw r.error;await refresh();}));list.append(card);}
  status.textContent=data.filter(x=>!x.read_at).length+' notification(s) non lue(s).';
 }
 host.append(button('Actualiser',refresh));
 const settings=element('section');settings.className='card';settings.append(element('h4','Recevoir mes alertes'));host.append(settings);
 if(!vapidPublicKey)settings.append(element('p','Les alertes sur téléphone seront disponibles prochainement.'));
 else if(!('serviceWorker' in navigator)||!('PushManager' in window)||!('Notification' in window))settings.append(element('p','Sur iPhone : ajoutez Koki Connect à l’écran d’accueil, puis ouvrez son icône pour activer les notifications.'));
 else{
  settings.append(button('Activer les notifications sur cet appareil',async()=>{
   // Demande directement après le clic ; aucun appel réseau avant l'autorisation iOS.
   if(await Notification.requestPermission()!=='granted'){status.textContent='Autorisation refusée. Vous pouvez la modifier dans les réglages du téléphone.';return;}
   const reg=await navigator.serviceWorker.ready;const sub=await reg.pushManager.getSubscription()||await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:decodeKey(vapidPublicKey)});
   const json=sub.toJSON();const {error}=await db.rpc('koki_push_register',{p_endpoint:json.endpoint,p_p256dh:json.keys.p256dh,p_auth:json.keys.auth});
   if(error){await sub.unsubscribe();throw error;}status.textContent='Notifications activées sur cet appareil.';
  }),button('Désactiver sur cet appareil',async()=>{await disablePush(db);status.textContent='Notifications désactivées sur cet appareil.';}));
 }
 if(smsEnabled){
  const {data:p}=await db.from('koki_notification_preferences').select('sms').eq('user_id',user.id).maybeSingle();
  if(disposed)return;
  const label=element('label','Recevoir les SMS de suivi (maximum 5 par jour) '),check=element('input');check.type='checkbox';check.checked=p?.sms===true;label.append(check);settings.append(label);
  check.disabled=!user.phone_confirmed_at;
  if(!user.phone_confirmed_at)settings.append(element('p','Vérifiez votre numéro sénégalais pour activer les SMS.'));
  check.onchange=async()=>{check.disabled=true;try{const {error}=await db.from('koki_notification_preferences').upsert({user_id:user.id,sms:check.checked,updated_at:new Date().toISOString()});if(error)throw error;status.textContent=check.checked?'SMS de suivi activés.':'SMS désactivés.';}catch{check.checked=!check.checked;status.textContent='Préférence non enregistrée.';}finally{check.disabled=false;}};
  const phone=element('input');phone.type='tel';phone.placeholder='+221771234567';phone.setAttribute('aria-label','Numéro sénégalais');
  const code=element('input');code.inputMode='numeric';code.autocomplete='one-time-code';code.setAttribute('aria-label','Code reçu par SMS');
  let pendingPhone=null;
  settings.append(phone,button('Recevoir un code de vérification',async()=>{const value=phone.value.replace(/[\s()-]/g,'');if(!/^\+221\d{9}$/.test(value)){status.textContent='Utilisez +221 suivi de neuf chiffres.';return;}const r=await db.auth.updateUser({phone:value});if(r.error)throw r.error;pendingPhone=value;status.textContent='Code envoyé. Saisissez-le ci-dessous.';}),code,button('Vérifier mon numéro',async()=>{if(!pendingPhone||!/^\d{6,10}$/.test(code.value))return;const r=await db.auth.verifyOtp({phone:pendingPhone,token:code.value,type:'phone_change'});if(r.error)throw r.error;code.value='';await renderNotifications(host,db,{vapidPublicKey,smsEnabled});}));
 }else settings.append(element('p','Les SMS de suivi ne sont pas encore disponibles.'));
 await refresh();
 if(!disposed)timer=setInterval(()=>{if(!host.isConnected){host.notificationCleanup();return;}if(!document.hidden&&!host.closest('[hidden]'))refresh().catch(()=>{});},30000);
}
