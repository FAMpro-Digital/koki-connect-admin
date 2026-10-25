import {createClient} from '@supabase/supabase-js';
import webpush from 'web-push';
import {timingSafeEqual} from 'node:crypto';

export function allowedEndpoint(value){
 try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com'].includes(u.hostname);}catch{return false;}
}
const equal=(a,b)=>{if(typeof a!=='string'||typeof b!=='string')return false;const left=Buffer.from(a),right=Buffer.from(b);return left.length===right.length&&timingSafeEqual(left,right);};
export function dispatchHandler({env=process.env,client=createClient,sendPush=webpush.sendNotification.bind(webpush),request=fetch}={}){
 return async(req,res)=>{
  res.setHeader('Cache-Control','no-store');
  if(!['GET','POST'].includes(req.method))return res.status(405).json({error:'Méthode refusée'});
  if(!env.NOTIFICATION_DISPATCH_SECRET||!equal(req.headers.authorization,'Bearer '+env.NOTIFICATION_DISPATCH_SECRET))return res.status(401).json({error:'Non autorisé'});
  const push=env.NOTIFICATION_PUSH_ENABLED==='true'&&!!env.VAPID_PRIVATE_KEY&&!!env.VAPID_PUBLIC_KEY&&!!env.VAPID_SUBJECT;
  const sms=env.NOTIFICATION_SMS_ENABLED==='true'&&!!env.TWILIO_ACCOUNT_SID&&!!env.TWILIO_AUTH_TOKEN&&!!env.TWILIO_MESSAGING_SERVICE_SID;
  if(!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY||(!push&&!sms))return res.status(503).json({error:'Envois non configurés'});
  const db=client(env.SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const result=await db.rpc('koki_notification_claim',{p_push:push,p_sms:sms});
  if(result.error)return res.status(503).json({error:'File indisponible'});
  let sent=0,failed=0,skipped=0;
  for(const job of result.data||[]){
   let state='skipped',providerId=null;
   try{
    const {data:n,error:nError}=await db.from('koki_notifications').select('recipient_id,category').eq('id',job.notification_id).single();
    if(nError||!n)throw Error('Notification absente');
    // Le texte extérieur reste générique : aucun détail privé sur l'écran verrouillé.
    const body='Une nouvelle information vous attend dans Koki Connect. Ouvrez vos notifications.';
    if(job.channel==='push'){
     const {data:s,error}=await db.from('koki_push_subscriptions').select('*').eq('id',job.destination).eq('user_id',n.recipient_id).maybeSingle();
     if(error)throw error;
     if(s&&allowedEndpoint(s.endpoint)){
      try{await sendPush({endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth}},JSON.stringify({title:'Koki Connect',body,tag:job.notification_id}),{TTL:3600,timeout:5000,vapidDetails:{subject:env.VAPID_SUBJECT,publicKey:env.VAPID_PUBLIC_KEY,privateKey:env.VAPID_PRIVATE_KEY}});state='sent';}
      catch(e){if([404,410].includes(e.statusCode))await db.from('koki_push_subscriptions').delete().eq('id',s.id);throw e;}
     }
    }else if(job.channel==='sms'){
     const {data:p,error}=await db.from('koki_notification_preferences').select('sms').eq('user_id',n.recipient_id).maybeSingle();
     if(error)throw error;
     const {data:u,error:authError}=await db.auth.admin.getUserById(n.recipient_id);
     if(authError)throw authError;
     const phone=String(u?.user?.phone||'').replace(/^\+?/,'+');
     if(p?.sms&&u?.user?.phone_confirmed_at&&/^\+221\d{9}$/.test(phone)){
      const response=await request('https://api.twilio.com/2010-04-01/Accounts/'+encodeURIComponent(env.TWILIO_ACCOUNT_SID)+'/Messages.json',{
       method:'POST',redirect:'error',signal:AbortSignal.timeout(5000),
       headers:{Authorization:'Basic '+Buffer.from(env.TWILIO_ACCOUNT_SID+':'+env.TWILIO_AUTH_TOKEN).toString('base64'),'Content-Type':'application/x-www-form-urlencoded'},
       body:new URLSearchParams({To:phone,MessagingServiceSid:env.TWILIO_MESSAGING_SERVICE_SID,Body:'Koki Connect : une mise a jour vous attend. Ouvrez les notifications dans votre application.'})
      });
      if(!response.ok)throw Error('SMS refusé');
      const data=await response.json();providerId=data.sid||null;state='sent';
     }
    }
   }catch{state='failed';}
   const saved=await db.from('koki_notification_deliveries').update({state,provider_id:providerId,completed_at:new Date().toISOString()}).eq('id',job.id).eq('state','processing');
   if(saved.error)return res.status(503).json({error:'Résultat à vérifier dans la file, ne pas renvoyer automatiquement'});
   if(state==='sent')sent++;else if(state==='failed')failed++;else skipped++;
  }
  return res.status(200).json({sent,failed,skipped});
 };
}
export default dispatchHandler();
