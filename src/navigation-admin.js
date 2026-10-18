// Navigation de l'administration : chaque rubrique de l'application s'ouvre (accordéon) sur ses sous-rubriques.
// Le menu latéral, la page « Rubriques » (téléphone) et le tableau de bord utilisent la même liste, dans le même ordre.
// Une entrée : {cle, libelle, query?} ; cle est une route de navigate().

// Sous-rubriques d'une rubrique : ses renseignements (présentation, responsable), ses écrans dédiés, ses publications (Opportunités et Événements : écran dédié seulement) et leurs sous-catégories, puis les lieux
// et numéros utiles qu'elle affiche dans l'application publique.
export function sousEntrees(R,r){
 if(!r)return [];
 const out=[];const deja=new Set();const ajoute=(cle,libelle,query='')=>{const id=cle+'|'+query;if(deja.has(id))return;deja.add(id);out.push({cle,libelle,query});};
 if(!r.type&&!r.ecrans.length)ajoute('rubrique:'+r.cle,'🧭 Vue d’ensemble');
 ajoute('renseignements','🪪 Renseignements',r.cle);
 for(const [k,label]of r.ecrans)ajoute(k,label);
 if(r.type&&r.type!=='Opportunités'&&r.type!=='Événements'){ajoute('contenus:'+r.type,'📰 Publications');for(const x of R.sousRubriques[r.type]||[])ajoute('contenus:'+r.type+':'+x.nom,x.icone+' '+x.nom);}
 if(r.type==='Opportunités')for(const x of R.sousRubriques[r.type]||[])ajoute('offres',x.icone+' '+x.nom,x.nom);
 if(r.lieux&&r.lieux!=='Santé')ajoute('lieux','📍 Lieux de la carte',r.lieux);
 if(r.numeros)ajoute('numeros','📞 Numéros utiles',r.cle);
 return out;
}
// Rubrique à laquelle appartient l'écran courant (route et, pour les écrans partagés, filtre).
export function rubriqueCourante(R,current,query=''){
 for(const r of R.rubriques)if(sousEntrees(R,r).some(e=>e.cle===current&&(!e.query||e.query===query))||('rubrique:'+r.cle)===current)return r;
 return R.rubriqueDe(current);
}
// Rubriques ouvertes dans le menu : mémorisées sur cet appareil (sessionStorage), la rubrique courante toujours ouverte.
const CLE='koki.admin.rubriquesOuvertes';
export function lireOuvertes(stockage=globalThis.sessionStorage){try{const x=JSON.parse(stockage?.getItem(CLE)||'[]');return new Set(Array.isArray(x)?x.filter(v=>typeof v==='string'):[]);}catch{return new Set();}}
export function ecrireOuvertes(set,stockage=globalThis.sessionStorage){try{stockage?.setItem(CLE,JSON.stringify([...set]));}catch{}}

// Menu latéral en accordéon. h = {n, button, navigate, current, query}.
export function menuRubriques(side,R,h){
 const ouvertes=lireOuvertes(),active=rubriqueCourante(R,h.current,h.query);if(active)ouvertes.add(active.cle);
 for(const r of R.rubriques){
  const bloc=h.n('div');bloc.className='nav-bloc';bloc.style.setProperty('--rubrique',r.couleur);
  const ouvert=ouvertes.has(r.cle),entrees=sousEntrees(R,r),id='nav-sous-'+r.cle;
  const tete=h.n('button');tete.type='button';tete.className='nav-rubrique';tete.setAttribute('aria-expanded',String(ouvert));tete.setAttribute('aria-controls',id);
  if(active===r)tete.classList.add('nav-rubrique-active');
  tete.append(h.n('span',r.icone+' '+r.nom),h.n('span',String(entrees.length),'nav-compte'),h.n('span','▾','nav-chevron'));
  const liste=h.n('div');liste.id=id;liste.className='nav-sous';liste.hidden=!ouvert;
  for(const e of entrees){const b=h.button(e.libelle,()=>h.navigate(e.cle,e.query),'nav-sub');if(e.cle===h.current&&(!e.query||e.query===h.query))b.setAttribute('aria-current','page');liste.append(b);}
  tete.onclick=()=>{const o=tete.getAttribute('aria-expanded')!=='true';tete.setAttribute('aria-expanded',String(o));liste.hidden=!o;const s=lireOuvertes();if(o)s.add(r.cle);else s.delete(r.cle);ecrireOuvertes(s);};
  bloc.append(tete,liste);side.append(bloc);
 }
}
// Cartes des rubriques (tableau de bord et page « Rubriques ») : même ordre, mêmes sous-rubriques que le menu.
export function cartesRubriques(R,h){
 const grille=h.n('div');grille.className='rubriques-cartes';
 for(const r of R.rubriques){const c=h.n('article');c.className='rubrique-carte';c.style.setProperty('--rubrique',r.couleur);
  const t=h.n('h3');t.append(h.n('span',r.icone,'rubrique-carte-icone'),h.n('span',r.nom));c.append(t);
  const puces=h.n('div');puces.className='rubrique-carte-sous';for(const e of sousEntrees(R,r))puces.append(h.button(e.libelle,()=>h.navigate(e.cle,e.query),'rubrique-puce'));
  c.append(puces);grille.append(c);}
 return grille;
}

// Historique interne : le retour reste dans l'administration et conserve les filtres.
export function createNavigationTrail(){
 let entries=[];
 const same=(a,b)=>a?.key===b.key&&a?.query===b.query&&a?.open===b.open;
 return {
  visit(key,query='',open=null){const next={key,query,open};if(!same(entries.at(-1),next))entries.push(next);if(entries.length>60)entries.shift();},
  back(){if(entries.length>1)entries.pop();return entries.at(-1)||{key:'dashboard',query:'',open:null};},
  reset(){entries=[];},
  get canBack(){return entries.length>1;}
 };
}
