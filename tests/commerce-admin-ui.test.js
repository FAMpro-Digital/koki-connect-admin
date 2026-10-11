import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
import {setupBusinessDB,fixtureBusiness} from './helpers/business-db.js';
const file=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
test('administration Commerces & Services : écrans branchés, aucun identifiant à saisir',async()=>{
 const ui=await file('src/commerce-admin.js'),app=await file('src/app.js'),model=await file('src/model.js'),client=await file('src/business-client.js');
 assert.match(app,/\['validations','✅ Validations commerciales'\]/);assert.match(app,/renderCommerceRubric\(main,k,/);assert.match(app,/await commerceDashboard\(main,/);
 for(const c of ['admin_stats','admin_queue','admin_records'])assert.match(client,new RegExp("'"+c+"'"),'lecture sans clé de requête : '+c);
 for(const c of ['moderate','review_changes','admin_update'])assert.match(ui,new RegExp("run\\(ctx,'"+c+"'"),c);
 assert.doesNotMatch(ui,/Identifiant|owner_id|innerHTML/);
 const commerce=model.slice(model.indexOf('professionnels:{'),model.indexOf('chauffeurs:{'));assert.doesNotMatch(commerce,/_id'|Identifiant/,'plus de saisie d’identifiant dans les rubriques commerce');
 assert.match(ui,/Indiquez le motif du refus/);assert.match(ui,/La version publiée reste visible/);assert.match(ui,/await ctx\.guard\(\)/,'double authentification vérifiée avant chaque action');
});
test('inventaire des photos historiques : lecture seule, exécutable',async()=>{
 const sql=await file('supabase/preproduction/inventaire-photos-historiques.sql');assert.doesNotMatch(sql.replace(/--.*$/gm,''),/\b(insert|update|delete|drop|alter|create|grant|revoke|truncate)\b/i);
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};
 try{await setupBusinessDB(db);const f=await fixtureBusiness(db);await db.query('reset role');
  await db.query("update koki_records set payload=payload||jsonb_build_object('photos',jsonb_build_array($1::text)) where id=$2",[f.merchant.owner_id+'/'+'1'.repeat(8)+'-1111-4111-8111-'+'1'.repeat(12)+'.jpg',f.merchant.id]);
  const rows=(await db.query(sql)).rows;assert.equal(rows.length,1);assert.equal(rows[0].kind,'professionnels');assert.equal(Number(rows[0].fichiers_absents),1);
 }finally{await pg.close();}
});
