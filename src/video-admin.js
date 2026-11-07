import {validateVideo} from './video-contract.js';

export async function renderVideos(main,{n,button,db,result,guard,account,can,media,refresh}){
  const editable=can(account?.role,'content');
  const panel=n('section');panel.className='panel';
  panel.append(n('p','Ajoutez une vidéo à une publication existante.'));
  const contents=await result(db.from('koki_contents').select('id,titre,statut').order('updated_at',{ascending:false}).limit(100));
  const form=document.createElement('form');form.className='admin-form';
  const content=document.createElement('select');
  for(const item of contents)content.append(new Option(item.titre+' · '+item.statut,item.id));
  const source=document.createElement('select');
  source.append(new Option('Téléchargement MP4/WebM','upload'),new Option('Lien YouTube','youtube'));
  const url=document.createElement('input');url.type='url';url.placeholder='https://www.youtube.com/watch?v=…';
  const file=document.createElement('input');file.type='file';file.accept='video/mp4,video/webm';
  const add=(label,element)=>{const wrapper=document.createElement('label');wrapper.append(n(label),element);form.append(wrapper);};
  add('Publication',content);add('Source',source);add('Lien YouTube',url);add('Fichier vidéo',file);
  const submit=button('Ajouter la vidéo');submit.type='submit';submit.className='primary';submit.disabled=!editable;form.append(submit);
  const toggle=()=>{url.hidden=source.value!=='youtube';file.hidden=source.value!=='upload';};
  source.onchange=toggle;toggle();
  form.onsubmit=async event=>{event.preventDefault();submit.disabled=true;try{await guard();const video=validateVideo({source:source.value,file:file.files[0],youtubeUrl:url.value});const row={content_id:content.value,...video};if(source.value==='upload')row.storage_path=await media(file.files[0]);await result(db.from('koki_content_media').insert(row));await refresh();}catch(error){panel.prepend(n('p',error.message));}finally{submit.disabled=!editable;}};
  panel.append(form);
  const rows=await result(db.from('koki_content_media').select('id,content_id,source,storage_path').order('created_at',{ascending:false}).limit(100));
  const list=n('div');list.className='list';
  for(const row of rows){const card=n('article');card.className='card';card.append(n('h3',contents.find(item=>item.id===row.content_id)?.titre||row.content_id),n('p',row.source==='youtube'?'YouTube':'Fichier vidéo'));const remove=button('Supprimer',async()=>{if(!confirm('Supprimer cette vidéo ?'))return;await guard();if(row.storage_path)await result(db.storage.from('koki-videos').remove([row.storage_path]));await result(db.from('koki_content_media').delete().eq('id',row.id));await refresh();},'danger');remove.disabled=!editable;card.append(remove);list.append(card);}
  panel.append(list);main.append(panel);
}
