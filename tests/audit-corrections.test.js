// Corrections de l'audit (administration) : déconnexion après inactivité, plus de suppression définitive d'un contenu publié.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {expire,surveillerInactivite,DELAI_INACTIVITE} from '../src/inactivite.js';
test('déconnexion automatique après 30 minutes sans activité',async()=>{
 assert.equal(DELAI_INACTIVITE,30*60*1000);assert.equal(expire(0,DELAI_INACTIVITE-1),false);assert.equal(expire(0,DELAI_INACTIVITE),true);
 let t=0,fermetures=0,connecte=true;const ecoute={};const cible={addEventListener:(e,f)=>{ecoute[e]=f;}};
 const s=surveillerInactivite({cible,horloge:()=>t,actif:()=>connecte,expirer:async()=>{fermetures++;},intervalle:1e9});
 t=DELAI_INACTIVITE-1;assert.equal(await s.verifier(),false);
 ecoute.pointerdown();t+=DELAI_INACTIVITE-1;assert.equal(await s.verifier(),false,'une action repousse l’échéance');
 t+=10;assert.equal(await s.verifier(),true);assert.equal(fermetures,1);
 connecte=false;t+=DELAI_INACTIVITE*2;assert.equal(await s.verifier(),false,'rien à fermer sans session');s.arreter();
});
test('branché dans l’administration ; contenu publié : dépublier au lieu de supprimer',()=>{
 const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
 assert.match(app,/surveillerInactivite\(\{actif:\(\)=>!!account,expirer:async\(\)=>\{try\{await db\.auth\.signOut\(\{scope:'local'\}\);\}catch\{\}mfaManager\.clearProof\(\);account=null;login\(\);/);
 assert.match(app,/const publie=content&&row\.statut==='publié';const del=publie\?button\('Dépublier \(brouillon\)'/);
 assert.match(app,/Cette action est irréversible/);
});
