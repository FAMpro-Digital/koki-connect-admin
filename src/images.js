export async function saveImageRecord({data,file,content,upload,persist,cleanup}){
  const path=await upload(file);
  if(path){if(content)data.image_path=path;else data.payload.image_path=path;}
  try{return await persist(data);}catch(error){
    if(path){try{await cleanup(path);}catch{/* Preserve the original database error. */}}
    throw error;
  }
}
export function imagePreview(host,path,resolveURL){
  const img=document.createElement('img');img.className='record-image';img.alt='Image enregistrée';
  const status=document.createElement('p');status.setAttribute('role','status');
  host.append(img,status);let generation=0,localURL=null;
  async function load(savedPath){const g=++generation;status.textContent='Chargement de l’image…';
    try{const url=await resolveURL(savedPath);if(g!==generation||!img.isConnected)return;img.src=url;}
    catch{if(g===generation){img.removeAttribute('src');status.textContent='Image inaccessible. Vérifiez votre connexion et réessayez.';}}
  }
  img.onload=()=>{status.textContent=localURL?'Aperçu local — image pas encore enregistrée.':'Image enregistrée affichée.';};
  img.onerror=()=>{status.textContent='Impossible d’afficher l’image. Réessayez pour renouveler son accès.';};
  const retry=document.createElement('button');retry.type='button';retry.textContent='Réessayer l’image';retry.disabled=!path;retry.onclick=()=>{if(path&&!localURL)load(path);};host.append(retry);
  const observer=new MutationObserver(()=>{if(!host.isConnected){generation++;if(localURL)URL.revokeObjectURL(localURL);observer.disconnect();}});
  observer.observe(document.body,{childList:true,subtree:true});
  if(path)load(path);else{img.hidden=true;status.textContent='Aucune image enregistrée.';}
  return file=>{generation++;if(localURL)URL.revokeObjectURL(localURL);localURL=null;retry.disabled=!!file||!path;
    if(file){localURL=URL.createObjectURL(file);img.hidden=false;img.src=localURL;status.textContent='Aperçu local — image pas encore enregistrée.';}
    else if(path){img.hidden=false;load(path);}else{img.hidden=true;img.removeAttribute('src');}
  };
}
