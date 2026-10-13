// Boutons « Modifier » : chaque élément s'ouvre sur son propre formulaire et l'enregistrement revient à l'écran d'origine.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const src=f=>fs.readFileSync(new URL('../src/'+f,import.meta.url),'utf8');
test('numéros utiles et établissements : « Modifier » ouvre l’élément choisi, pas la liste',()=>{
 const app=src('app.js');
 assert.match(app,/KokiEducationContract\.decode\(row\)\)\{await navigate\('education','',row\.id\)/);
 assert.match(app,/KokiNumeroContract\?\.decode\(row\)\)\{await navigate\('numeros','',row\.id\)/);
 for(const f of ['numeros-admin.js','education-admin.js'])assert.match(src(f),/if\(ctx\.open\)\{const cible=rows\.find\(r=>r\.id===ctx\.open\);if\(cible&&editable\)await edit\(cible\);\}/,f);
});
test('contenus filtrés : « Modifier » ouvre l’éditeur et revient à la rubrique après enregistrement ou annulation',()=>{
 const app=src('app.js');
 assert.match(app,/button\('Modifier',\(\)=>content\?editor\('contents',row,k\):editor\(k,row\)\)/);
 assert.match(app,/async function editor\(kind,row,back\)/);assert.match(app,/button\('Annuler',\(\)=>navigate\(back\|\|kind\)\)/);assert.match(app,/await navigate\(back\|\|kind\);\}catch/);
});
test('photos de l’administration : 10 Mo à l’import, compression automatique',()=>{
 assert.match(src('image-processing.js'),/MAX_INPUT=10\*1024\*1024/);assert.match(src('app.js'),/10 Mo maximum/);assert.doesNotMatch(src('app.js'),/1 Mo maximum/);
});
