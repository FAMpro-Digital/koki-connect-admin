self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
// Push volontaire : aucun contenu de commande sur l'écran verrouillé et aucune URL fournie par le message.
self.addEventListener('push',event=>{
 let data={};try{data=event.data?.json()||{};}catch{}
 event.waitUntil(self.registration.showNotification('Koki Connect',{
  body:'Une nouvelle information vous attend. Ouvrez vos notifications.',
  tag:typeof data.tag==='string'?data.tag.slice(0,100):'koki-notification',
  data:{url:new URL('./?notifications=1',self.registration.scope).href}
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 const url=new URL('./?notifications=1',self.registration.scope).href;
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async clients=>{
  for(const client of clients){if(new URL(client.url).origin===self.location.origin){await client.focus();client.postMessage({type:'koki-notifications-open'});return;}}
  await self.clients.openWindow(url);
 }));
});
