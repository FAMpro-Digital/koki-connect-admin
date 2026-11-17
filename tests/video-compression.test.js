// Compression des vidéos avant l'envoi : MP4 seulement, 720p maximum, original gardé en cas d'échec.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {typeMp4,dimensions,doitCompresser,preparerVideo,SEUIL_COMPRESSION} from '../src/video-compression.js';
const AAC='video/mp4;codecs=avc1.42E01E,mp4a.40.2';const Rec=types=>({isTypeSupported:t=>types.includes(t)});
test('MP4 obligatoire : sans enregistreur MP4, aucune compression (le WebM ne se lit pas sur tous les iPhone)',()=>{
 assert.equal(typeMp4(Rec(['video/mp4;codecs=avc1.42E01E,mp4a.40.2'])),'video/mp4;codecs=avc1.42E01E,mp4a.40.2');
 assert.equal(typeMp4(Rec(['video/mp4','video/mp4;codecs=avc1']),'Mozilla/5.0 Chrome/131.0 Safari/537.36'),null,'Chrome sans AAC : son Opus refusé');
 assert.equal(typeMp4(Rec(['video/mp4']),'Mozilla/5.0 (Macintosh) Version/18.0 Safari/605.1.15'),'video/mp4');assert.equal(typeMp4(Rec(['video/webm;codecs=vp9'])),null);assert.equal(typeMp4(undefined),null);
 globalThis.document={};
 assert.equal(doitCompresser({size:SEUIL_COMPRESSION+1},Rec([AAC])),true);
 assert.equal(doitCompresser({size:SEUIL_COMPRESSION-1},Rec([AAC])),false,'petite vidéo envoyée telle quelle');
 assert.equal(doitCompresser({size:SEUIL_COMPRESSION+1},Rec(['video/webm'])),false);
 delete globalThis.document;
});
test('dimensions : 720p au plus sur le petit côté, nombres pairs, jamais d’agrandissement',()=>{
 assert.deepEqual(dimensions(1920,1080),{largeur:1280,hauteur:720});assert.deepEqual(dimensions(1080,1920),{largeur:720,hauteur:1280});
 assert.deepEqual(dimensions(640,360),{largeur:640,hauteur:360});assert.deepEqual(dimensions(1001,1777),{largeur:720,hauteur:1278});assert.equal(dimensions(0,0),null);
});
test('échec de la compression : la vidéo d’origine est envoyée et la personne est prévenue',async()=>{
 globalThis.document={createElement:()=>{throw Error('boom');}};const messages=[];const original={size:SEUIL_COMPRESSION*3,name:'a.mp4',type:'video/mp4'};
 const sortie=await preparerVideo(original,t=>messages.push(t),{Recorder:Rec([AAC])});
 assert.equal(sortie,original);assert.match(messages.at(-1),/vidéo d’origine est envoyée/);
 assert.equal(await preparerVideo({size:10},()=>{},{Recorder:Rec([AAC])}).then(x=>x.size),10);
 delete globalThis.document;
});
test('les deux envois de vidéo passent par la compression avant le contrôle de taille',()=>{
 const a=fs.readFileSync('src/video-admin.js','utf8');assert.ok(a.indexOf('preparerVideo(fichier')<a.indexOf('validateVideo({source:source.value,file:fichier'));assert.ok(a.includes('media(fichier)'));
 const b=fs.readFileSync('src/app.js','utf8');assert.ok(b.indexOf('file=await preparerVideo(file')<b.indexOf("validateVideo({source:values.video_source,file,"));
});
