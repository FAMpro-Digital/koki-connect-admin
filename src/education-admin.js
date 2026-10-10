import './education-contract.js';
import {bindImageProcessing} from './image-processing.js';
import {saveImageRecord} from './images.js';
const C=globalThis.KokiEducationContract;
export async function renderEducation(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,media,imageURL,imagePreview,error,refresh}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Établissements scolaires · Les fiches publiées sont partagées avec Koki Connect. Seules les coordonnées professionnelles publiques doivent être renseignées.'));
 async function edit(row){await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');const old=C.decode(row)||{};main.replaceChildren(n('h1',row?'Modifier un établissement':'Ajouter un établissement'));const f=formPanel(),m={};
 field(f,m,'titre','Nom de l’établissement','text',null,row?.titre||'',true);
 field(f,m,'resume','Présentation courte','textarea',null,row?.resume||'',true);
 field(f,m,'niveau','Niveau','text',C.levels,old.niveau||C.levels[0],true);
 field(f,m,'secteur','Secteur','text',['Public','Privé','Communautaire','Autre'],old.secteur||'Public',true);
 field(f,m,'lieu','Adresse / village / quartier','text',null,row?.lieu||'',true);
 field(f,m,'telephone','Téléphone public de l’établissement','tel',null,old.telephone||'');
 field(f,m,'horaires','Horaires / accueil','text',null,old.horaires||'');
 field(f,m,'description','Informations complémentaires','textarea',null,old.description||'');
 field(f,m,'source','Source / responsable de publication','text',null,row?.source||'');
 field(f,m,'statut','Visibilité','text',['brouillon','publié'],row?.statut||'brouillon',true);
 field(f,m,'publication','Date de publication (heure de Koki)','datetime-local',null,(row?.publication||new Date().toISOString()).slice(0,16),true);
 field(f,m,'photo','Photo (10 Mo maximum, compression automatique)','file');
 const preview=n('section');f.append(preview);const previewFile=imagePreview(preview,row?.image_path,imageURL);
 const submit=n('button','Enregistrer l’établissement');submit.type='submit';submit.className='primary';const selected=bindImageProcessing(m.photo,preview,previewFile,submit);f.append(submit,button('Annuler',refresh));
 f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{await guard();const v=Object.fromEntries(Object.entries(m).filter(([k])=>k!=='photo').map(([k,x])=>[k,x.value.trim()]));const data={type:'Informations utiles',categorie:'Éducation',titre:v.titre,resume:v.resume,lieu:v.lieu,source:v.source,statut:v.statut,publication:new Date(v.publication+'Z').toISOString(),texte:C.encode({...v,archive:false}),image_path:row?.image_path||null};if(!v.titre||!v.resume||!v.lieu)throw Error('Nom, présentation et adresse requis.');await saveImageRecord({data,file:selected(),content:true,upload:media,persist:value=>write('koki_contents',value,row),cleanup:path=>result(db.storage.from('koki-media').remove([path]))});await refresh();}catch(e){error(e);}finally{submit.disabled=false;}};main.append(f);
 }
 const add=button('Ajouter un établissement',()=>edit(),'primary');add.disabled=!editable;main.append(add,button('Actualiser',refresh));if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=[];for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('type','Informations utiles').eq('categorie','Éducation').order('id').range(offset,offset+199));rows.push(...page.filter(C.decode));if(page.length<200)break;}
 if(!main.isConnected)return;
 const search=n('input');search.type='search';search.placeholder='Rechercher une école, un village…';search.setAttribute('aria-label','Rechercher un établissement');main.append(search);const grid=n('div');grid.className='list';main.append(grid);
 function show(){grid.replaceChildren();const found=rows.filter(r=>(r.titre+' '+r.lieu).toLocaleLowerCase('fr').includes(search.value.toLocaleLowerCase('fr')));for(const row of found){const school=C.decode(row),card=n('article');card.className='card';card.append(n('h2',row.titre),n('p',(school.archive?'Archivé':row.statut==='publié'&&Date.parse(row.publication)>Date.now()?'Programmé':row.statut)+' · '+school.niveau+' · '+school.secteur),n('p',row.lieu),n('p',row.resume));if(row.image_path)imagePreview(card,row.image_path,imageURL);const modify=button('Modifier',()=>edit(row));modify.disabled=!editable;card.append(modify);if(!school.archive){const archive=button('Archiver',async()=>{if(!confirm('Archiver cet établissement et le retirer du catalogue public ?'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:C.encode({...school,archive:true})},row);await refresh();});archive.disabled=!editable;card.append(archive);}grid.append(card);}if(!found.length)grid.append(n('p','Aucun établissement enregistré pour cette recherche.'));}search.oninput=show;show();
}
