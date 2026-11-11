import test from 'node:test';import assert from 'node:assert';import fs from 'node:fs';
const s=fs.readFileSync('src/app.js','utf8');
test('la publication envoie la photo traitée, jamais le fichier brut',()=>{
 assert.ok(s.includes('file:selectedImage(),content'));
 assert.ok(!s.includes('file:selectedFiles[0]'));
 assert.ok(s.includes('media((await processImage(photo)).file)'));
});
test('le message d’erreur est amené à l’écran',()=>assert.ok(s.includes("box.scrollIntoView?.({block:'center'})")));
