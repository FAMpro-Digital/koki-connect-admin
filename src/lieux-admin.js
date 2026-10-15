// Lieux de la carte : la carte intégrée de l'application publique (OpenStreetMap) et les lieux gérés ici.
// Ajouter un lieu (mairie, poste, gendarmerie, terrain…), corriger le nom, la catégorie ou la position
// d'un lieu de la carte intégrée, ou le masquer. Mêmes lieux dans la Carte, « Autour de moi » et le Transport.
// Stockage : koki_contents, contrat koki.carte.lieu (voir lieu-contract.js). Aucune migration.
import './lieu-contract.js';
import {positionField} from './position-gps.js';
import {reference} from './carte-reference.js';
const L=globalThis.KokiLieuContract;

export function etatLieu(row,v,now=Date.now()){if(!row)return 'Carte intégrée';if(v.archive)return 'Archivé';if(row.statut!=='publié')return 'Brouillon';return Date.parse(row.publication)>now?'Programmé':(v.masque?'Masqué':'Publié');}
// Coordonnées collées depuis Google Maps ou OpenStreetMap : « 15.5059, -15.9919 » (virgule décimale acceptée avec espace).
export function lireCoordonnees(texte){
 const m=String(texte||'').trim().match(/^(-?\d{1,2}(?:[.,]\d+)?)\s*[,; ]\s*(-?\d{1,3}(?:[.,]\d+)?)$/);
 if(!m)return null;const lat=Number(m[1].replace(',','.')),lon=Number(m[2].replace(',','.'));
 return L.dansCadre(lat,lon)?{latitude:lat,longitude:lon}:null;
}
// Une ligne par lieu : carte intégrée (avec sa correction éventuelle), puis lieux ajoutés. Les archivés restent listés.
export function inventaire(rows,ref=reference){
 const lignes=[];const parId=new Map();
 for(const row of rows){const v=L.decode(row);if(!v)continue;if(v.remplace){const old=parId.get(v.remplace);if(!old||Date.parse(row.updated_at||row.publication)>Date.parse(old.row.updated_at||old.row.publication))parId.set(v.remplace,{row,v});}else lignes.push({ref:null,row,v});}
 return [...ref.map(r=>({ref:r,...(parId.get(r.id)||{row:null,v:null})})),...lignes];
}
export function bilanLieux(lignes,now=Date.now()){
 const b={carte:0,ajoutes:0,corriges:0,masques:0,brouillons:0,parCategorie:Object.fromEntries(L.genres.map(g=>[g,0]))};
 for(const x of lignes){const s=etatLieu(x.row,x.v||{},now);
  if(x.ref)b.carte++;else if(s==='Publié')b.ajoutes++;
  if(x.ref&&s==='Publié')b.corriges++;if(s==='Masqué')b.masques++;if(s==='Brouillon'||s==='Programmé')b.brouillons++;
  const visible=x.ref?s!=='Masqué':s==='Publié';const cat=x.v&&s==='Publié'?x.v.genre:x.ref?.categorie;if(visible&&cat in b.parCategorie)b.parCategorie[cat]++;}
 return b;
}

export async function renderLieux(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,error,refresh,navigate}=ctx;
 const editable=configured&&can(account?.role,'content');
 // Lieux d'une rubrique (ctx.query = catégorie de la carte) : seule cette catégorie est affichée et proposée.
 const propre=L.genres.includes(ctx.query)?ctx.query:null;
 if(propre)main.append(n('p','Rubrique : seuls les lieux « '+propre+' » sont affichés ici. Les autres catégories restent dans leur rubrique ou dans « Lieux de la carte ».'));
 main.append(n('p','Lieux affichés dans la Carte de l’application, dans « Autour de moi » et dans les listes Départ / Destination du Transport. La carte intégrée vient d’OpenStreetMap : ici, vous ajoutez des lieux (mairie, poste, gendarmerie, terrain…), vous corrigez un nom, une catégorie ou une position, ou vous masquez un lieu. Les structures de santé se gèrent dans l’écran Santé.'));

 async function edit(ligne={}){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const {ref,row,v}=ligne;const old=v||{genre:ref?.categorie&&L.genres.includes(ref.categorie)?ref.categorie:propre||'Services publics',latitude:ref?.latitude??null,longitude:ref?.longitude??null,description:''};
  main.replaceChildren(n('h1',ref?'Corriger un lieu de la carte':row?'Modifier un lieu':'Ajouter un lieu'));const f=formPanel(),m={};
  if(ref)f.append(n('p','Lieu de la carte intégrée : « '+ref.nom+' » ('+ref.categorie+'). Votre correction remplace ce lieu dans l’application, sans modifier OpenStreetMap.'));
  field(f,m,'titre','Nom du lieu','text',null,row?.titre||ref?.nom||'',true);
  field(f,m,'genre','Catégorie','text',propre&&old.genre===propre?[propre]:L.genres,old.genre,true);
  field(f,m,'lieu','Village / quartier','text',null,row?.lieu||'');
  field(f,m,'description','Description courte (facultatif, 500 caractères)','textarea',null,old.description||'');
  const gps={};positionField(f,gps,{latitude:old.latitude,longitude:old.longitude},{onError:error});
  field(f,m,'coordonnees','Ou collez des coordonnées (Google Maps : « 15.5059, -15.9919 »)','text',null,'');
  field(f,m,'source','Source / responsable','text',null,row?.source||'');
  field(f,m,'statut','Visibilité','text',['publié','brouillon'],row?.statut||'publié',true);
  const submit=n('button',ref?'Enregistrer la correction':'Enregistrer le lieu');submit.type='submit';submit.className='primary';f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
   await guard();const val=k=>m[k].value.trim();
   if(!val('titre'))throw Error('Nom du lieu requis.');
   let pos={latitude:gps.latitude.value,longitude:gps.longitude.value};
   if(val('coordonnees')){const c=lireCoordonnees(val('coordonnees'));if(!c)throw Error('Coordonnées illisibles ou hors de la commune de Koki. Exemple : 15.5059, -15.9919');pos=c;}
   const texte=L.encode({genre:val('genre'),...pos,description:val('description'),remplace:ref?.id||'',masque:false,archive:false});
   const resume=(val('description')||val('genre')+(val('lieu')?' · '+val('lieu'):'')).slice(0,2000);
   const data={type:'Informations utiles',categorie:L.categorie,titre:val('titre'),resume,lieu:val('lieu'),source:val('source'),statut:val('statut'),publication:row?.publication&&row.statut==='publié'?row.publication:new Date().toISOString(),texte};
   await write('koki_contents',data,row||undefined);
   await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }
 async function masquer(ligne){
  const {ref,row,v}=ligne;if(!confirm('Masquer « '+(row?.titre||ref.nom)+' » de la carte et du Transport ?'))return;await guard();
  const texte=L.encode({genre:v?.genre||(L.genres.includes(ref.categorie)?ref.categorie:'Services publics'),latitude:v?.latitude??ref.latitude,longitude:v?.longitude??ref.longitude,description:v?.description||'',remplace:ref.id,masque:true,archive:false});
  const data={type:'Informations utiles',categorie:L.categorie,titre:row?.titre||ref.nom,resume:'Lieu masqué de la carte',lieu:row?.lieu||'',statut:'publié',publication:new Date().toISOString(),texte};
  await write('koki_contents',data,row||undefined);await refresh();
 }
 async function changerArchive(ligne,archive){
  const {row,v}=ligne;if(archive&&!confirm(ligne.ref?'Annuler la correction et revenir au lieu d’origine ?':'Archiver « '+row.titre+' » et le retirer de la carte ?'))return;await guard();
  await write('koki_contents',{statut:archive?'brouillon':row.statut,texte:L.encode({...v,archive})},row);await refresh();
 }

 const actions=n('div');actions.className='quick-actions';
 const add=button('Ajouter un lieu',()=>edit(),'primary');add.disabled=!editable;
 actions.append(add,button('🏥 Structures de santé',()=>navigate('sante')),button('Actualiser',refresh));main.append(actions);
 let rows=[];
 if(configured){for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('categorie',L.categorie).order('id').range(offset,offset+199));rows.push(...page);if(page.length<200)break;}}
 else main.append(n('p','Connexion requise pour enregistrer des lieux. La carte intégrée est affichée ci-dessous.'));
 if(!main.isConnected)return;
 const lignes=inventaire(rows),b=bilanLieux(lignes);
 const grid=n('div');grid.className='grid dashboard-metrics';
 for(const [t,val,note]of [['Carte intégrée',b.carte,'Lieux OpenStreetMap'],['Lieux ajoutés',b.ajoutes,'Publiés par l’administration'],['Corrigés',b.corriges,b.masques+' masqué(s)'],['Services publics',b.parCategorie['Services publics'],'Visibles dans la rubrique']]){const c=n('article');c.className='card metric';const d=n('div');d.append(n('p',t),n('strong',String(val)),n('small',note));c.append(d);grid.append(c);}
 main.append(grid);
 const search=n('input');search.type='search';search.placeholder='Rechercher un lieu ou un village…';search.setAttribute('aria-label','Rechercher un lieu');search.value=ctx.query&&!L.genres.includes(ctx.query)?ctx.query:'';
 const filtre=n('select');filtre.setAttribute('aria-label','Filtrer par catégorie');for(const x of propre?[propre]:['Toutes les catégories',...L.genres,'Ajoutés','Corrigés ou masqués','Brouillons et archivés']){const o=n('option',x);o.value=x;filtre.append(o);}
 if(L.genres.includes(ctx.query))filtre.value=ctx.query;
 const list=n('div');list.className='list';main.append(search,filtre,list);
 function garde(x){const s=etatLieu(x.row,x.v||{}),cat=x.v?.genre||x.ref?.categorie;switch(filtre.value){case 'Toutes les catégories':return true;case 'Ajoutés':return !x.ref;case 'Corrigés ou masqués':return !!(x.ref&&x.row&&!x.v.archive);case 'Brouillons et archivés':return ['Brouillon','Programmé','Archivé'].includes(s);default:return cat===filtre.value;}}
 function show(){list.replaceChildren();const q=search.value.toLocaleLowerCase('fr').trim();
  const found=lignes.filter(x=>garde(x)&&((x.row?.titre||'')+' '+(x.ref?.nom||'')+' '+(x.row?.lieu||'')).toLocaleLowerCase('fr').includes(q));
  for(const x of found){const {ref,row,v}=x,s=etatLieu(row,v||{}),card=n('article');card.className='card';
   const nom=row&&!v.masque?row.titre:ref?.nom,cat=row&&!v.masque?v.genre:ref?.categorie,lat=row?v.latitude:ref.latitude,lon=row?v.longitude:ref.longitude;
   card.append(n('h2',nom),n('p',(ref?'Carte intégrée':'Ajouté')+' · '+s+' · '+cat+(row?.lieu?' · '+row.lieu:'')));
   if(ref&&row&&!v.masque&&!v.archive&&row.titre!==ref.nom)card.append(n('p','Nom d’origine : '+ref.nom));
   if(v?.description)card.append(n('p',v.description));
   const carte=n('a','Voir sur la carte ('+lat.toFixed(5)+', '+lon.toFixed(5)+')');carte.href='https://www.openstreetmap.org/?mlat='+lat+'&mlon='+lon+'#map=17/'+lat+'/'+lon;carte.target='_blank';carte.rel='noopener';card.append(carte);
   const ajout=(label,fn)=>{const bt=button(label,fn);bt.disabled=!editable;card.append(bt);};
   if(ref){
    if(!row||v.archive){ajout('Corriger',()=>edit({ref}));ajout('Masquer',()=>masquer({ref}));}
    else if(v.masque){ajout('Afficher à nouveau',()=>changerArchive(x,true));}
    else{ajout('Modifier la correction',()=>edit(x));ajout('Masquer',()=>masquer(x));ajout('Revenir à l’origine',()=>changerArchive(x,true));}
   }else if(!v.archive){ajout('Modifier',()=>edit(x));
    ajout(row.statut==='publié'?'Dépublier':'Publier maintenant',async()=>{await guard();await write('koki_contents',row.statut==='publié'?{statut:'brouillon'}:{statut:'publié',publication:new Date().toISOString()},row);await refresh();});
    ajout('Archiver',()=>changerArchive(x,true));
   }else ajout('Restaurer en brouillon',()=>changerArchive(x,false));
   list.append(card);}
  if(!found.length)list.append(n('p','Aucun lieu pour ce filtre.'));}
 search.oninput=show;filtre.onchange=show;show();
 if(ctx.open){const cible=lignes.find(x=>x.row?.id===ctx.open);if(cible&&editable)await edit(cible);}
}
