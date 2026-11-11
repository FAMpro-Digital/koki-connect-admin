import test from 'node:test';import assert from 'node:assert';import fs from 'node:fs';
const s=fs.readFileSync('src/app.js','utf8');
test('la publication envoie la photo traitée, jamais le fichier brut',()=>{
 assert.ok(s.includes('file:selectedImage(),content'));
 assert.ok(!s.includes('file:selectedFiles[0]'));
 assert.ok(s.includes('media((await processImage(photo)).file)'));
});
test('le message d’erreur est amené à l’écran',()=>assert.ok(s.includes("box.scrollIntoView?.({block:'center'})")));
test('le choix vidéo n’est pas envoyé comme colonne de koki_contents',()=>{
 assert.ok(s.includes('const {video_source:_video,...contenu}=values;data={...contenu,image_path'));
 const colonnes='type,titre,resume,texte,categorie,statut,publication,source,lieu,evenement,une,actif,emplacement,fin'.split(',');
 const champs=[...s.matchAll(/field\(f,fields,'([a-z_]+)'/g)].map(m=>m[1]).filter(k=>!['photo','video_file','youtube_url','video_source','statut'].includes(k));
 for(const k of colonnes)assert.ok(champs.includes(k)||k==='statut',k);
 for(const k of new Set(champs))if(!['email','password'].includes(k))assert.ok(colonnes.includes(k),k+' n’est pas une colonne');
});
