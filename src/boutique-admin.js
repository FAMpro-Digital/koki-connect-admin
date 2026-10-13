// Commerces & Services · Boutique en ligne : vue d'ensemble de ce que voient les clients dans l'application
// (produits en ligne, promotions, ruptures) et liste des fiches à compléter pour bien vendre en ligne.
// Lecture seule : les corrections se font dans les écrans Fiches professionnelles, Boutiques, Produits et Services
// (commande serveur admin_records, droits Commerce et double authentification exigés par le serveur).
import './commerce-contract.js';
const C=globalThis.KokiCommerceContract;
export const RUBRIQUES={professionnels:'Fiches professionnelles',boutiques:'Boutiques',produits:'Produits',services:'Services'};
const INACTIFS=['Archivé','Refusé','Suspendu','Fermé'];
const photos=p=>(p?.photos?.length||0)+(p?.image_path?1:0);
const promo=p=>Number.isInteger(p?.prix)&&Number.isInteger(p?.ancien_prix)&&p.ancien_prix>p.prix;

// Points qui empêchent ou gênent la vente en ligne. Rien n'est signalé pour une fiche archivée, refusée ou suspendue.
export function problemesBoutique(row){
 const p=row?.payload||{},out=[];if(!row||INACTIFS.includes(row.statut)||p.moderation_lock)return out;
 if(row.kind==='produits'){
  if(!Number.isInteger(p.prix))out.push('Prix manquant : le produit ne peut pas être commandé.');
  if(row.statut==='Épuisé'||p.stock===0)out.push('Épuisé : réapprovisionner ou masquer le produit.');
  if(!photos(p))out.push('Pas de photo : les clients voient seulement un pictogramme.');
  if(!String(p.description||'').trim())out.push('Pas de description.');
 }
 if(row.kind==='boutiques'){
  if(!p.whatsapp&&!row.professionnel?.telephone)out.push('Aucun numéro : impossible de commander sur WhatsApp ou d’appeler.');
  else if(!p.whatsapp)out.push('Pas de WhatsApp propre : les commandes WhatsApp iront au téléphone du commerce.');
  if(!p.village)out.push('Village ou quartier non renseigné : absente du filtre par village.');
  if(!photos(p))out.push('Pas de photo de la boutique.');
 }
 if(row.kind==='professionnels'){
  if(!p.telephone)out.push('Pas de téléphone : les clients ne peuvent pas appeler.');
  if(!p.localisation)out.push('Pas de position GPS : absent de « Voir sur la carte ».');
  if(!p.village)out.push('Village ou quartier non renseigné.');
 }
 if(row.kind==='services'){
  if(p.tarif!=='devis'&&!Number.isInteger(p.prix))out.push('Tarif à préciser : prix fixe ou « Sur devis ».');
  if(!String(p.description||'').trim())out.push('Pas de description du service.');
 }
 if(p.modification)out.push('Modification proposée en attente de validation.');
 return out;
}
export function bilanBoutique(rows){
 const b={produitsEnLigne:0,promotions:0,epuises:0,sansPhoto:0,boutiquesEnLigne:0,servicesEnLigne:0,enAttente:0,aVerifier:0};
 for(const r of Array.isArray(rows)?rows:[]){const p=r.payload||{};
  if(r.kind==='produits'&&r.publie){b.produitsEnLigne++;if(promo(p)&&r.statut==='Disponible')b.promotions++;if(r.statut==='Épuisé')b.epuises++;if(!photos(p))b.sansPhoto++;}
  if(r.kind==='boutiques'&&r.publie)b.boutiquesEnLigne++;if(r.kind==='services'&&r.publie)b.servicesEnLigne++;
  if(['À valider','En attente'].includes(r.statut)||p.modification)b.enAttente++;
  if(problemesBoutique(r).length)b.aVerifier++;}
 return b;
}
// Promotions en cours, plus forte remise d'abord (même règle que l'application).
export function promotionsEnCours(rows){return (Array.isArray(rows)?rows:[]).filter(r=>r.kind==='produits'&&r.publie&&r.statut==='Disponible'&&promo(r.payload)).map(r=>({...r,remise:Math.round((1-r.payload.prix/r.payload.ancien_prix)*100)})).sort((a,b)=>b.remise-a.remise);}

async function tout(api,kind,max=400){const rows=[];for(let offset=0;offset<max;){const r=await api.run('admin_records',{kind,offset});rows.push(...r.rows);offset+=r.rows.length;if(!r.rows.length||offset>=r.total)break;}return rows;}

export async function renderBoutique(main,{n,button,api,guard,can,account,navigate,publicApplicationURL}){
 const status=n('p');status.setAttribute('role','status');
 main.append(n('p','Ce que les clients voient dans la boutique en ligne de Koki Connect, et les fiches à compléter pour mieux vendre. Les corrections se font dans les écrans de chaque rubrique.'));
 main.append(status);
 if(publicApplicationURL){const a=n('a','Ouvrir la boutique publique ↗');a.href=publicApplicationURL;a.target='_blank';a.rel='noopener noreferrer';a.className='com-btn';main.append(a);}
 if(!can(account?.role,'commerce')){status.textContent='Votre rôle ne permet pas de consulter cette vue.';return;}
 if(!api.enabled){status.textContent='Vue disponible après l’activation du serveur Commerces & Services dans l’administration.';return;}
 const zone=n('div');main.append(zone);
 async function charger(){
  zone.replaceChildren(n('p','Chargement…'));let rows=[];
  try{await guard();for(const kind of Object.keys(RUBRIQUES))rows.push(...await tout(api,kind));}catch(e){zone.replaceChildren();status.textContent=e.message;return;}
  zone.replaceChildren();const b=bilanBoutique(rows);
  const grid=n('div');grid.className='grid dashboard-metrics com-metrics';
  for(const [label,value,note,target] of [
   ['Produits en ligne',b.produitsEnLigne,'Visibles par les clients (disponibles ou épuisés)','produits'],
   ['Promotions en cours',b.promotions,'Ancien prix barré affiché','produits'],
   ['Produits épuisés',b.epuises,'Affichés « Épuisé », non commandables','produits'],
   ['Produits sans photo',b.sansPhoto,'Un pictogramme remplace la photo','produits'],
   ['Boutiques en ligne',b.boutiquesEnLigne,'Statut Actif, commerce approuvé','boutiques'],
   ['Services en ligne',b.servicesEnLigne,'Demande de devis possible','services'],
   ['En attente de validation',b.enAttente,'Inscriptions, boutiques ou modifications','validations'],
   ['Fiches à compléter',b.aVerifier,'Voir la liste ci-dessous',null]]){
   const card=n('article');card.className='card metric com-metric';const t=n('div');t.append(n('p',label),n('strong',Number(value).toLocaleString('fr-FR')),n('small',note));card.append(t);
   if(target)card.append(button('Ouvrir : '+label,()=>navigate(target),'com-btn com-ghost'));grid.append(card);}
  zone.append(grid);
  const promos=promotionsEnCours(rows);
  if(promos.length){const sec=n('section');sec.className='panel';sec.append(n('h2','Promotions affichées ('+promos.length+')'));const ul=n('ul');for(const r of promos.slice(0,20))ul.append(n('li',r.payload.nom+' · '+C.formaterPrix(r.payload.prix)+' au lieu de '+C.formaterPrix(r.payload.ancien_prix)+' (−'+r.remise+' %)'+(r.parent?.nom?' · '+r.parent.nom:'')));sec.append(ul);zone.append(sec);}
  const sec=n('section');sec.className='panel';const aCorriger=rows.map(r=>({r,p:problemesBoutique(r)})).filter(x=>x.p.length);
  sec.append(n('h2','Fiches à compléter ('+aCorriger.length+')'));
  if(!aCorriger.length)sec.append(n('p','Rien à signaler : toutes les fiches en ligne sont complètes.'));
  for(const kind of Object.keys(RUBRIQUES)){const xs=aCorriger.filter(x=>x.r.kind===kind);if(!xs.length)continue;sec.append(n('h3',RUBRIQUES[kind]+' ('+xs.length+')'));
   for(const {r,p} of xs.slice(0,50)){const card=n('article');card.className='card com-card';card.append(n('h4',r.payload.nom+' · '+r.statut));const ul=n('ul');for(const x of p)ul.append(n('li',x));card.append(ul,button('Corriger dans « '+RUBRIQUES[kind]+' »',()=>navigate(kind),'com-btn'));sec.append(card);}
   if(xs.length>50)sec.append(n('p','… et '+(xs.length-50)+' autre(s) dans « '+RUBRIQUES[kind]+' ».'));}
  zone.append(sec,n('p','Lecture seule, données réelles du serveur au '+new Date().toLocaleString('fr-FR',{timeZone:'Africa/Dakar'})+'.'));
  zone.append(button('Actualiser',charger,'com-btn'));
 }
 await charger();
}
