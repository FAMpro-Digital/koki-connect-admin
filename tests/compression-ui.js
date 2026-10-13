import '../src/styles.css';
import {processImage,decodeImage} from '../src/image-processing.js';
import {saveImageRecord,imagePreview} from '../src/images.js';
const saved=document.querySelector('#saved');
function reopen(){saved.replaceChildren();const row=JSON.parse(sessionStorage.getItem('TEST-compressed-row')||'null');if(row)imagePreview(saved,row.image_path,async()=>sessionStorage.getItem('TEST-compressed-file'));}
reopen();
document.querySelector('#run').onclick=async()=>{
 const results=document.querySelector('#results');results.replaceChildren();
 for(const name of ['orientation.jpg','noise.png','noise.webp','photo.heic']){
  const status=document.createElement('p');results.append(status);
  try{
   const file=await (await fetch('./fixtures/'+name)).blob();const result=await processImage(file,(percent,label)=>status.textContent=name+' : '+label+' '+Math.round(percent)+' %');
   const bitmap=await decodeImage(result.file);const dimensions=(bitmap.naturalWidth||bitmap.width)+' × '+(bitmap.naturalHeight||bitmap.height);bitmap.close?.();
   const dataURL=await new Promise(resolve=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.readAsDataURL(result.file);});
   await saveImageRecord({data:{},file:result.file,content:true,upload:async processed=>{if(processed!==result.file)throw Error('Fichier original transmis');sessionStorage.setItem('TEST-compressed-file',dataURL);return 'TEST/'+name;},persist:async row=>sessionStorage.setItem('TEST-compressed-row',JSON.stringify(row)),cleanup:async()=>{}});
   status.textContent=name+' : RÉUSSI · '+file.size+' → '+result.finalSize+' octets · '+dimensions+' · EXIF absent : '+!new TextDecoder('latin1').decode(await result.file.arrayBuffer()).includes('Exif');
   reopen();
  }catch(error){status.textContent=name+' : '+error.message;}
 }
};
// Actual selection workflow, isolated from the live backend.
import {bindImageProcessing} from '../src/image-processing.js';
const form=document.createElement('form'),label=document.createElement('label'),input=document.createElement('input'),preview=document.createElement('section'),submit=document.createElement('button');
input.type='file';label.textContent='Photo de test (10 Mo maximum)';label.append(input);submit.type='submit';submit.textContent='Enregistrer le test local';form.append(label,preview,submit);document.querySelector('main').append(form);
const previewFile=imagePreview(preview,null,async()=>null);const selected=bindImageProcessing(input,preview,previewFile,submit);
form.onsubmit=async e=>{e.preventDefault();try{const file=selected();if(!file)throw Error('Choisissez une photo.');const dataURL=await new Promise(resolve=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.readAsDataURL(file);});await saveImageRecord({data:{},file,content:true,upload:async()=>{sessionStorage.setItem('TEST-compressed-file',dataURL);return 'TEST/manual';},persist:async row=>sessionStorage.setItem('TEST-compressed-row',JSON.stringify(row)),cleanup:async()=>{}});reopen();submit.textContent='Test local enregistré';}catch(error){submit.textContent=error.message;}};
