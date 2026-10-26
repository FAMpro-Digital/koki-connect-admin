import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
import {setupBusinessDB,fixtureBusiness,actor,rpc,testActors} from './helpers/business-db.js';
const source=await readFile(new URL('../supabase/proposals/notifications.sql',import.meta.url),'utf8');
test('Notifications : destinataires métier, isolation, lecture seule et file protégée',async()=>{
 const pg=new PGlite();const db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};
 try{
  await setupBusinessDB(db);await db.query("create role service_role bypassrls;alter table auth.users add phone text,add phone_confirmed_at timestamptz;");
  const f=await fixtureBusiness(db);await db.query('reset role');await db.query(source);await db.query(await readFile(new URL('../supabase/proposals/audit-notification-health.sql',import.meta.url),'utf8'));await db.query(await readFile(new URL('../supabase/proposals/audit-notification-policy.sql',import.meta.url),'utf8'));
  await actor(db,testActors.client);
  const order=await rpc(db,'create_order',{request_id:crypto.randomUUID(),shop_id:f.shop.id,items:[{product_id:f.product.id,quantity:1}],mode:'retrait',address:''});
  let rows=(await db.query('select * from koki_notifications')).rows;assert.equal(rows.length,1);assert.equal(rows[0].record_id,order.id);
  await assert.rejects(db.query("insert into koki_notifications(recipient_id,record_id,revision,title,body,category) values($1,$2,99,'fake','fake','commandes')",[testActors.other,order.id]),/permission denied/);
  await assert.rejects(db.query("update koki_notifications set recipient_id=$1",[testActors.other]),/permission denied/);
  await db.query('update koki_notifications set read_at=now()');
  await actor(db,testActors.other);assert.equal((await db.query('select * from koki_notifications')).rows.length,0);
  await assert.rejects(db.query('select * from koki_notification_claim(true,true)'),/permission denied/);
  await actor(db,testActors.merchant);assert.equal((await db.query('select * from koki_notifications')).rows.length,1);
  const endpoint='https://fcm.googleapis.com/fcm/send/test';
  await db.query('select koki_push_register($1,$2,$3)',[endpoint,'A'.repeat(87),'B'.repeat(22)]);
  await actor(db,testActors.other);await assert.rejects(db.query('select koki_push_register($1,$2,$3)',[endpoint,'A'.repeat(87),'B'.repeat(22)]),/Désactivez/);
  await assert.rejects(db.query('select koki_push_register($1,$2,$3)',['https://localhost/attack','A'.repeat(87),'B'.repeat(22)]),/check constraint/);
  await db.query('reset role');
  // Le changement de statut produit un nouvel événement ; une mise à jour sans changement n'en produit pas.
  await db.query("update koki_records set statut='Confirmée',revision=revision+1 where id=$1",[order.id]);
  const total=(await db.query('select count(*)::int n from koki_notifications')).rows[0].n;
  await db.query('update koki_records set payload=payload where id=$1',[order.id]);assert.equal((await db.query('select count(*)::int n from koki_notifications')).rows[0].n,total);
  const claim=(await db.query('select * from koki_notification_claim(true,false)')).rows;assert.equal(claim.length,1);assert.equal(claim[0].channel,'push');
  assert.equal((await db.query('select * from koki_notification_claim(true,false)')).rows.length,0,'pas de seconde réservation');
  // Consentement + téléphone confirmé + maximum cinq SMS par compte et par jour.
  await db.query("update auth.users set phone='221771234567',phone_confirmed_at=now() where id=$1",[testActors.client]);
  await db.query("insert into koki_notification_preferences(user_id,sms,updated_at) values($1,true,now()-interval '1 hour')",[testActors.client]);
  for(let i=0;i<8;i++)await db.query("insert into koki_notifications(recipient_id,record_id,revision,title,body,category) values($1,$2,$3,'Test','Test','commandes')",[testActors.client,order.id,100+i]);
  const sms=(await db.query('select * from koki_notification_claim(false,true)')).rows;assert.equal(sms.length,5);
  assert.equal((await db.query('select * from koki_notification_claim(false,true)')).rows.length,0);
  await db.query("update koki_notification_deliveries set processing_started_at=now()-interval '11 minutes' where state='processing'");
  assert.equal((await db.query('select * from koki_notification_claim(true,true)')).rows.length,0);
  assert.equal((await db.query("select count(*)::int n from koki_notification_deliveries where state='failed' and failure_code='delivery_unknown'")).rows[0].n,6);
  await actor(db,testActors.other);await assert.rejects(db.query('select koki_notification_health()'),/Accès refusé/);
 }finally{await pg.close();}
});
