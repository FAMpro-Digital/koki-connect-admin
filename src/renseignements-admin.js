// Renseignements d'une rubrique : présentation affichée en tête de la rubrique dans l'application, responsable,
// contact, horaires de permanence et affichage de la tuile sur l'accueil. Une fiche par rubrique (contrat Rubriques).
import './rubriques-contract.js';
const R=globalThis.KokiRubriquesContract;

export async function renderRenseignements(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,error,navigate,refresh,query}=ctx;
 const editable=configured&&can(account?.role,'content');
 const r=R.rubriques.find(x=>x.cle===query);
 if(!r){main.append(n('p','Choisissez la rubrique dont vous voulez modifier les renseignements.'));const l=n('div');l.className='sous-rubriques';for(const x of R.rubriques)l.append(button(R.libelle(x),()=>navigate('renseignements',x.cle)));main.append(l);return;}
 main.append(n('h2',R.libelle(r)),n('p','Renseignements propres à la rubrique « '+r.nom+' » : ils s’affichent en tête de cette rubrique dans l’application, et nulle part ailleurs.'));
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=await result(db.from('koki_contents').select('*').eq('type','Informations utiles').eq('categorie',R.categorieFiche).order('updated_at',{ascending:false}).limit(200));
 if(!main.isConnected)return;
 const actuelle=R.fiches(rows)[r.cle],row=actuelle?.row,v=actuelle?.v||{presentation:'',responsable:'',telephone:'',horaires:'',visible:true};
 const etat=n('p',!row?'Aucun renseignement enregistré pour cette rubrique.':row.statut!=='publié'?'Brouillon : non visible dans l’application.':v.visible?'Publié · rubrique affichée sur l’accueil.':'Publié · tuile masquée sur l’accueil.');etat.className='hint';main.append(etat);
 const f=formPanel(),m={};
 field(f,m,'presentation','Présentation (affichée en tête de la rubrique, 600 caractères maximum)','textarea',null,v.presentation);
 field(f,m,'responsable','Responsable de la rubrique (nom ou service)','text',null,v.responsable);
 field(f,m,'telephone','Téléphone du responsable (facultatif, public)','tel',null,v.telephone);
 field(f,m,'horaires','Permanence / horaires de contact (ex. Lun–Ven 9h–17h)','text',null,v.horaires);
 const visible=field(f,m,'visible','Afficher la tuile de cette rubrique sur l’accueil de l’application','checkbox',null,v.visible);
 field(f,m,'statut','Visibilité des renseignements','text',['publié','brouillon'],row?.statut||'publié',true);
 m.presentation.maxLength=600;
 const apercu=n('section');apercu.className='panel rubrique-apercu';
 const majApercu=()=>{apercu.replaceChildren(n('h3','Aperçu dans l’application'));const p=m.presentation.value.trim(),resp=m.responsable.value.trim(),tel=m.telephone.value.trim(),h=m.horaires.value.trim();
  if(!p&&!resp&&!tel)apercu.append(n('p','Rien ne s’affichera en tête de la rubrique.'));else{if(p)apercu.append(n('p',p));const ligne=[resp&&'Responsable : '+resp,h,tel&&'📞 '+tel].filter(Boolean).join(' · ');if(ligne)apercu.append(n('small',ligne));}
  if(!visible.checked)apercu.append(n('p','⚠ La tuile « '+r.nom+' » sera masquée sur l’accueil (la rubrique reste accessible par la recherche et le menu).'));};
 for(const k of ['presentation','responsable','telephone','horaires'])m[k].addEventListener('input',majApercu);visible.addEventListener('change',majApercu);majApercu();
 const submit=n('button','Enregistrer les renseignements');submit.type='submit';submit.className='primary';submit.disabled=!editable;f.append(submit);
 f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  if(!visible.checked&&v.visible!==false&&!confirm('Masquer la tuile « '+r.nom+' » sur l’accueil de l’application ?'))return;
  const val=k=>m[k].value.trim();
  const texte=R.encodeFiche({cle:r.cle,presentation:val('presentation'),responsable:val('responsable'),telephone:val('telephone'),horaires:val('horaires'),visible:visible.checked});
  const data={type:'Informations utiles',categorie:R.categorieFiche,titre:r.nom,resume:(val('presentation')||'Renseignements de la rubrique '+r.nom).slice(0,2000),lieu:'',source:val('responsable'),statut:val('statut'),publication:row?.statut==='publié'?row.publication:new Date().toISOString(),texte,image_path:null};
  await write('koki_contents',data,row);await refresh();
 }catch(err){error(err);}finally{submit.disabled=!editable;}};
 main.append(f,apercu);
}
