// Ancrage externe du journal Football : signature Ed25519, vérification, détection d'une réécriture.
import test from 'node:test';import assert from 'node:assert/strict';import {generateKeyPairSync} from 'node:crypto';
import {signer,verifier,comparer} from '../scripts/ancrage-journal.mjs';
const {privateKey,publicKey}=generateKeyPairSync('ed25519');
const prive=privateKey.export({type:'pkcs8',format:'pem'}),pub=publicKey.export({type:'spki',format:'pem'});
const ancre={dernier_id:42,empreinte:'a'.repeat(64),lignes:42,premiere_alteration:null,lu_le:'2026-11-24T23:00:00Z'};

test('reçu signé et vérifiable avec la clé publique',()=>{
 const r=signer(ancre,prive);assert.equal(r.empreinte,ancre.empreinte);assert.ok(verifier(r,pub));
});
test('reçu modifié : signature invalide',()=>{
 const r=signer(ancre,prive);assert.equal(verifier({...r,empreinte:'b'.repeat(64)},pub),false);assert.equal(verifier({...r,lignes:41},pub),false);
});
test('autre clé : signature invalide',()=>{
 const autre=generateKeyPairSync('ed25519').publicKey.export({type:'spki',format:'pem'});assert.equal(verifier(signer(ancre,prive),autre),false);
});
test('journal altéré : ancrage refusé',()=>{assert.throws(()=>signer({...ancre,premiere_alteration:7},prive),/altéré à la ligne 7/);});
test('comparaison de deux reçus : croissance normale, rétrécissement ou réécriture détectés',()=>{
 assert.equal(comparer(ancre,{...ancre,dernier_id:50,lignes:50,empreinte:'c'.repeat(64)}).ok,true);
 assert.match(comparer(ancre,{...ancre,dernier_id:40,lignes:40}).raison,/rétréci/);
 assert.match(comparer(ancre,{...ancre,empreinte:'d'.repeat(64)}).raison,/réécrite/);
});
