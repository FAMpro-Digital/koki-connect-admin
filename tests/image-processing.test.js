import test from 'node:test';import assert from 'node:assert/strict';
import {detectImageType,inspectImage,fitDimensions,processImage,isProcessedImage,MAX_INPUT,MAX_OUTPUT} from '../src/image-processing.js';
const jpeg=size=>new Blob([new Uint8Array([255,216,255]),new Uint8Array(size-3)],{type:'image/jpeg'});
const heic=()=>new Blob([new Uint8Array([0,0,0,24,102,116,121,112,104,101,105,99,0,0,0,0,109,105,102,49,104,101,105,99])],{type:'image/heic'});
test('image signatures override misleading MIME and reject SVG/AVIF/unknown',async()=>{
  assert.equal(await inspectImage(new Blob([await jpeg(32).arrayBuffer()],{type:'text/plain'})),'image/jpeg');
  assert.equal(detectImageType(new Uint8Array([137,80,78,71,13,10,26,10])),'image/png');
  assert.equal(detectImageType(new TextEncoder().encode('RIFF0000WEBP')),'image/webp');
  assert.equal(await inspectImage(heic()),'image/heic');
  await assert.rejects(inspectImage(new Blob(['<svg/>'],{type:'image/jpeg'})),/Format non pris/);
  const avif=new Uint8Array(await heic().arrayBuffer());avif.set(new TextEncoder().encode('avif'),16);assert.equal(detectImageType(avif),null);
});
test('input size is limited to 10 MiB, output to 1 MiB',async()=>{
  await assert.rejects(inspectImage(jpeg(MAX_INPUT+1)),/10 Mo/);await assert.rejects(inspectImage(jpeg(MAX_OUTPUT+1),MAX_OUTPUT),/1 Mo/);
  assert.equal(await inspectImage(jpeg(MAX_INPUT)),'image/jpeg');
});
test('portrait and landscape dimensions preserve aspect ratio without upscaling',()=>{
  assert.deepEqual(fitDimensions(4000,3000),{width:1920,height:1440});assert.deepEqual(fitDimensions(3000,4000),{width:1440,height:1920});assert.deepEqual(fitDimensions(320,200),{width:320,height:200});assert.throws(()=>fitDimensions(100000,100000),/Dimensions/);
});
function runtime(sizes){let calls=0,closed=false;const canvas={width:0,height:0,getContext:()=>({drawImage(){}})};return {decode:async()=>({width:4000,height:3000,close(){closed=true;}}),canvas:()=>canvas,encode:async()=>jpeg(sizes[Math.min(calls++,sizes.length-1)]),get calls(){return calls;},get closed(){return closed;},get released(){return canvas.width===0;}};}
test('compression retries quality, marks only processed output and frees decoded image',async()=>{
  const r=runtime([MAX_OUTPUT+1,500000]);const progress=[];const source=jpeg(2000000);const output=await processImage(source,value=>progress.push(value),r);
  assert.equal(output.finalSize,500000);assert.equal(output.width,1920);assert.equal(r.calls,2);assert.equal(isProcessedImage(source),false);assert.equal(isProcessedImage(output.file),true);assert.equal(progress.at(-1),100);assert.ok(r.closed&&r.released);
});
test('compression lowers dimensions if quality alone is insufficient',async()=>{
  const r=runtime([MAX_OUTPUT+1,MAX_OUTPUT+1,MAX_OUTPUT+1,MAX_OUTPUT+1,400000]);const output=await processImage(jpeg(32),()=>{},r);assert.equal(output.width,1536);assert.equal(output.height,1152);
});
test('undecodable HEIC fails explicitly without calling encoder',async()=>{
  await assert.rejects(processImage(heic(),()=>{},{decode:async()=>{throw Error('Unsupported');},encode:()=>assert.fail('No encoding')}),/HEIC\/HEIF/);
});
test('output above bucket limit is refused and resources released',async()=>{
  const r=runtime([MAX_OUTPUT+1]);await assert.rejects(processImage(jpeg(32),()=>{},r),/sous 1 Mo/);assert.ok(r.closed&&r.released);
});
test('failed processing leaves previously saved image untouched',async()=>{
  const stored={image_path:'user/existing.jpg'};let uploaded=false;
  try{const result=await processImage(heic(),()=>{},{decode:async()=>{throw Error('Unsupported');}});uploaded=true;stored.image_path=result.file;}catch{}
  assert.equal(uploaded,false);assert.equal(stored.image_path,'user/existing.jpg');
});
