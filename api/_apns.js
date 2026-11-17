// Envoi vers Apple Push Notification service (APNs), sans dépendance : jeton JWT ES256 signé avec la clé .p8,
// puis requête HTTP/2. Configuration (variables Vercel) : APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (contenu du .p8),
// APNS_BUNDLE_ID (com.kokiconnect.app), APNS_SANDBOX=true seulement pour les essais lancés depuis Xcode.
import {createPrivateKey,sign} from 'node:crypto';
import http2 from 'node:http2';

export function apnsConfigured(env){return !!(env.APNS_KEY_ID&&env.APNS_TEAM_ID&&env.APNS_PRIVATE_KEY&&env.APNS_BUNDLE_ID);}
export const validToken=t=>typeof t==='string'&&/^[0-9a-f]{64,200}$/.test(t);
const b64=v=>Buffer.from(typeof v==='string'?v:JSON.stringify(v)).toString('base64url');
// Apple refuse un jeton de plus d'une heure et en limite le renouvellement : il est gardé 50 minutes.
let cache={cle:'',jwt:'',at:0};
export function apnsJwt(env,now=Date.now()){
 const cle=env.APNS_KEY_ID+':'+env.APNS_TEAM_ID;
 if(cache.cle===cle&&now-cache.at<50*60*1000)return cache.jwt;
 const pem=String(env.APNS_PRIVATE_KEY).replace(/\\n/g,'\n');
 const head=b64({alg:'ES256',kid:env.APNS_KEY_ID}),body=b64({iss:env.APNS_TEAM_ID,iat:Math.floor(now/1000)});
 const signature=sign('sha256',Buffer.from(head+'.'+body),{key:createPrivateKey(pem),dsaEncoding:'ieee-p1363'}).toString('base64url');
 cache={cle,jwt:head+'.'+body+'.'+signature,at:now};
 return cache.jwt;
}
// Renvoie {status, reason}. Ne relance jamais : le résultat est inscrit dans la file par l'appelant.
export function sendApns(env,token,{title,body,id},{connect=http2.connect,timeout=5000}={}){
 if(!validToken(token))return Promise.resolve({status:400,reason:'BadDeviceToken'});
 const host=env.APNS_SANDBOX==='true'?'https://api.sandbox.push.apple.com':'https://api.push.apple.com';
 const payload=JSON.stringify({aps:{alert:{title,body},sound:'default'},id});
 return new Promise((resolve,reject)=>{
  let client;try{client=connect(host);}catch(e){reject(e);return;}
  const finir=(f,v)=>{try{client.close();}catch{}f(v);};
  client.on('error',e=>finir(reject,e));
  const req=client.request({':method':'POST',':path':'/3/device/'+token,authorization:'bearer '+apnsJwt(env),'apns-topic':env.APNS_BUNDLE_ID,
   'apns-push-type':'alert','apns-priority':'10','apns-expiration':String(Math.floor(Date.now()/1000)+3600),'content-type':'application/json'});
  let status=0,data='';
  req.setTimeout(timeout,()=>{req.close();finir(reject,Error('Délai APNs dépassé'));});
  req.on('response',h=>{status=Number(h[':status'])||0;});
  req.on('data',c=>{data+=c;if(data.length>4096)req.close();});
  req.on('end',()=>{let reason='';try{reason=JSON.parse(data||'{}').reason||'';}catch{}finir(resolve,{status,reason});});
  req.on('error',e=>finir(reject,e));
  req.end(payload);
 });
}
// Jeton à oublier : appareil désinscrit ou jeton refusé par Apple.
export const tokenGone=r=>r.status===410||(r.status===400&&['BadDeviceToken','DeviceTokenNotForTopic'].includes(r.reason));
