// Module Football : branchement dans l'administration (route « football », VITE_KOKI_FOOT_ADMIN, entrée conditionnelle).
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {sousEntrees,activerModules} from '../src/navigation-admin.js';
import '../src/rubriques-contract.js';
const R=globalThis.KokiRubriquesContract,sport=R.rubriques.find(r=>r.cle==='sports');
const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),ecrans=fs.readFileSync(new URL('../src/foot-admin.js',import.meta.url),'utf8');

test('navigation : entrée Football absente par défaut, présente seulement si activée',()=>{
 assert.equal(sousEntrees(R,sport).some(e=>e.cle==='football'),false);
 activerModules({football:'true'});assert.equal(sousEntrees(R,sport).some(e=>e.cle==='football'),false,'valeur non booléenne refusée');
 activerModules({football:true});assert.equal(sousEntrees(R,sport).find(e=>e.cle==='football')?.libelle,'⚽ Football (scores en direct)');
 assert.equal(R.rubriques.filter(r=>r.cle!=='sports').some(r=>sousEntrees(R,r).some(e=>e.cle==='football')),false,'seulement sous Sport');
 activerModules({football:false});assert.equal(sousEntrees(R,sport).some(e=>e.cle==='football'),false);
});
test('app.js : drapeau exact, contrôle à l’entrée de la route, RPC seulement',()=>{
 assert.match(app,/const FOOT_ADMIN=import\.meta\.env\.VITE_KOKI_FOOT_ADMIN==='true';/);
 assert.match(app,/activerModules\(\{football:FOOT_ADMIN\}\)/);
 const route=app.slice(app.indexOf("if(k==='football')"),app.indexOf("if(k==='clubs')"));
 assert.match(route,/if\(!FOOT_ADMIN\)\{[^}]*Module Football non activé/);
 assert.match(route,/if\(!configured\|\|!db\)/);assert.match(route,/if\(!can\(account\?\.role,'read'\)\)/);
 assert.match(route,/await guard\(\);const \{data,error:e\}=await db\.rpc\('koki_foot_admin'/,'session revérifiée avant chaque appel');
 assert.doesNotMatch(route,/\.from\(/,'aucun accès direct aux tables');
});
test('écrans : aucun accès direct aux tables ni à l’authentification',()=>{
 assert.doesNotMatch(ecrans,/\.from\(|koki_foot\.|\.auth\.|service_role|innerHTML/);
});
test('désactivé par défaut : aucune configuration ne l’active',()=>{
 for(const f of ['.env.example','.env.supabase-local.example','vercel.json']){const t=fs.readFileSync(new URL('../'+f,import.meta.url),'utf8');assert.doesNotMatch(t,/VITE_KOKI_FOOT_ADMIN\s*=?\s*["']?true/,f);}
});
