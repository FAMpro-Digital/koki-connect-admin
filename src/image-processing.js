export const MAX_INPUT=10*1024*1024,MAX_OUTPUT=1024*1024;
const processed=new WeakSet();
const ascii=(bytes,start,end)=>String.fromCharCode(...bytes.slice(start,end));
export function detectImageType(bytes){
  if(bytes[0]===255&&bytes[1]===216&&bytes[2]===255)return 'image/jpeg';
  if([137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v))return 'image/png';
  if(ascii(bytes,0,4)==='RIFF'&&ascii(bytes,8,12)==='WEBP')return 'image/webp';
  if(ascii(bytes,4,8)==='ftyp'&&bytes.length>=16){
    const length=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength).getUint32(0);
    if(length<16||length>bytes.length)return null;
    const brands=[ascii(bytes,8,12)];for(let i=16;i+4<=length;i+=4)brands.push(ascii(bytes,i,i+4));
    if(brands.some(b=>['avif','avis'].includes(b)))return null;
    if(brands.some(b=>['heic','heix','hevc','hevx','mif1','msf1'].includes(b)))return 'image/heic';
  }
  return null;
}
export async function inspectImage(file,limit=MAX_INPUT){
  if(!file.size||file.size>limit)throw Error(`Photo trop volumineuse ou vide : maximum ${limit===MAX_INPUT?'10 Mo':'1 Mo'}.`);
  const type=detectImageType(new Uint8Array(await file.slice(0,4096).arrayBuffer()));
  if(!type)throw Error('Format non pris en charge. Choisissez une photo JPEG, PNG, WebP ou HEIC/HEIF.');
  return type;
}
export function fitDimensions(width,height,maximum=1920){
  if(!width||!height||width*height>64000000)throw Error('Dimensions de photo invalides ou trop importantes (64 millions de pixels maximum).');
  const ratio=Math.min(1,maximum/Math.max(width,height));return {width:Math.max(1,Math.round(width*ratio)),height:Math.max(1,Math.round(height*ratio))};
}
export async function decodeImage(blob){
  if(typeof createImageBitmap==='function'){try{return await createImageBitmap(blob,{imageOrientation:'from-image'});}catch{/* Safari may decode HEIC through an HTML image instead. */}}
  const url=URL.createObjectURL(blob),image=new Image();
  try{await new Promise((resolve,reject)=>{image.onload=resolve;image.onerror=()=>reject(Error('Décodage impossible'));image.src=url;});return image;}finally{URL.revokeObjectURL(url);}
}
function encode(canvas,type,quality){return new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(Error('Compression impossible sur cet appareil.')),type,quality));}
export async function processImage(file,onProgress=()=>{},runtime={decode:decodeImage,canvas:()=>document.createElement('canvas'),encode}){
  onProgress(5,'Vérification du fichier');const type=await inspectImage(file);onProgress(15,'Décodage et orientation');
  let image;try{image=await runtime.decode(new Blob([file],{type}));}catch{throw Error(type==='image/heic'?'Cette photo HEIC/HEIF ne peut pas être décodée sur cet appareil. Exportez-la en JPEG ou choisissez une autre photo.':'Photo illisible ou endommagée. Choisissez une autre image.');}
  let canvas;
  try{
    const size=fitDimensions(image.naturalWidth||image.width,image.naturalHeight||image.height);canvas=runtime.canvas();
    let width=size.width,height=size.height;
    for(let step=0;step<7;step++){
      canvas.width=width;canvas.height=height;const context=canvas.getContext('2d');if(!context)throw Error('Traitement des images indisponible sur cet appareil.');
      context.drawImage(image,0,0,width,height);
      for(const quality of [.86,.76,.66,.56]){
        onProgress(Math.min(95,25+step*10+(1-quality)*20),'Compression automatique');
        const blob=await runtime.encode(canvas,type==='image/jpeg'||type==='image/heic'?'image/jpeg':'image/webp',quality);
        if(blob.size<MAX_OUTPUT){
          const outputType=await inspectImage(blob,MAX_OUTPUT);if(!['image/jpeg','image/png','image/webp'].includes(outputType))throw Error('Le format obtenu ne peut pas être téléversé.');
          const output=new Blob([blob],{type:outputType});processed.add(output);onProgress(100,'Image prête à enregistrer');
          return {file:output,originalSize:file.size,finalSize:output.size,width,height,type:outputType};
        }
      }
      width=Math.max(1,Math.round(width*.8));height=Math.max(1,Math.round(height*.8));
    }
    throw Error('Impossible de réduire cette photo sous 1 Mo. Choisissez une autre image.');
  }finally{image.close?.();if(canvas){canvas.width=0;canvas.height=0;}}
}
export function isProcessedImage(file){return processed.has(file);}
export function bindImageProcessing(input,host,preview,submit){
  const status=document.createElement('p');status.setAttribute('role','status');const progress=document.createElement('progress');progress.max=100;progress.hidden=true;progress.setAttribute('aria-label','Traitement de la photo');host.append(progress,status);
  let generation=0,ready=null,busy=false,failed=false;
  input.accept='.jpg,.jpeg,.png,.webp,.heic,.heif,image/jpeg,image/png,image/webp,image/heic,image/heif';
  input.onchange=async()=>{
    const id=++generation,file=input.files[0];ready=null;failed=false;busy=!!file;submit.disabled=busy;progress.hidden=!file;
    preview(null);status.textContent='';if(!file)return;
    try{
      const result=await processImage(file,(value,label)=>{if(id===generation){progress.value=value;status.textContent=label;}});
      if(id!==generation||!host.isConnected)return;ready=result.file;preview(ready);
      const weight=bytes=>bytes>=1024*1024?(bytes/1024/1024).toFixed(2)+' Mo':Math.ceil(bytes/1024)+' Ko';
      status.textContent=`Image prête : ${weight(result.originalSize)} → ${weight(result.finalSize)} · ${result.width} × ${result.height} pixels. Enregistrez pour la téléverser.`;
    }catch(error){if(id===generation){failed=true;status.textContent=error.message;}}
    finally{if(id===generation){busy=false;submit.disabled=failed;}}
  };
  return ()=>{if(busy)throw Error('Patientez pendant la compression.');if(failed||input.files[0]&&!ready)throw Error('La photo n’a pas été traitée. Choisissez une autre image.');return ready;};
}
