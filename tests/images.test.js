import test from 'node:test';import assert from 'node:assert/strict';
import {saveImageRecord} from '../src/images.js';
test('saved image reference survives reload and saving without choosing another file',async()=>{
  let stored;const persist=async row=>stored=structuredClone(row);const cleanup=async()=>assert.fail('No cleanup after commit');
  await saveImageRecord({data:{image_path:null},file:{},content:true,upload:async()=> 'user/image.jpg',persist,cleanup});
  const reopened=JSON.parse(JSON.stringify(stored));assert.equal(reopened.image_path,'user/image.jpg');
  await saveImageRecord({data:reopened,content:true,upload:async()=>null,persist,cleanup});assert.equal(stored.image_path,'user/image.jpg');
});
test('database failure cleans only new upload, without replacing existing reference',async()=>{
  const removed=[];await assert.rejects(saveImageRecord({data:{image_path:'user/old.jpg'},file:{},content:true,upload:async()=> 'user/new.jpg',persist:async()=>{throw Error('DB conflict');},cleanup:async path=>removed.push(path)}),/DB conflict/);
  assert.deepEqual(removed,['user/new.jpg']);
});
test('failure after save cannot delete committed image',async()=>{
  let stored;const removed=[];await saveImageRecord({data:{payload:{}},file:{},content:false,upload:async()=> 'user/image.png',persist:async row=>stored=structuredClone(row),cleanup:async path=>removed.push(path)});
  try{throw Error('Reload failed');}catch{}assert.equal(stored.payload.image_path,'user/image.png');assert.deepEqual(removed,[]);
});
test('upload failure never writes a record without its selected photo',async()=>{
  await assert.rejects(saveImageRecord({data:{},content:true,file:{},upload:async()=>{throw Error('Upload refused');},persist:async()=>assert.fail('No write'),cleanup:async()=>assert.fail('No delete')}),/Upload refused/);
});
