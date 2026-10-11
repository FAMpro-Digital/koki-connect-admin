import {types} from './model.js';
export function dashboardSummary(contents,now=Date.now()){
 const published=contents.filter(x=>x.statut==='publié'&&Date.parse(x.publication)<=now&&(x.type!=='Publicités'||(x.actif&&(!x.fin||Date.parse(x.fin)>now))));
 const counts=types.map(type=>({type,count:published.filter(x=>x.type===type).length}));
 const months=Array.from({length:6},(_,i)=>{const d=new Date(now);d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()-5+i);return {key:d.toISOString().slice(0,7),label:d.toLocaleDateString('fr-FR',{month:'short',timeZone:'Africa/Dakar'}),count:0};});
 for(const row of published){const m=months.find(x=>x.key===row.publication.slice(0,7));if(m)m.count++;}
 return {upcomingCount:published.filter(x=>x.type==='Événements'&&Date.parse(x.evenement)>=now).length,counts,months,total:published.length,latest:[...contents].sort((a,b)=>Date.parse(b.updated_at)-Date.parse(a.updated_at)).slice(0,5),events:published.filter(x=>x.type==='Événements'&&Date.parse(x.evenement)>=now).sort((a,b)=>Date.parse(a.evenement)-Date.parse(b.evenement)).slice(0,4)};
}
// Un compteur connu à zéro est différent d'une mesure absente.
export function dashboardMetrics(stats,summary,operational={}){
 const count=type=>stats?summary.counts.find(x=>x.type===type)?.count??0:null;
 return [
 {label:'Utilisateurs inscrits',value:stats?.['Utilisateurs inscrits']??null,note:'Comptes Auth, administrateurs inclus',color:7},
 {label:'Utilisateurs actifs',value:stats?.['Utilisateurs actifs']??null,note:'Suivi d’activité non connecté',color:1},
 {label:'Actualités publiées',value:stats?.['Actualités publiées']??null,target:'contenus:Actualités',color:0},
 {label:'Annonces en attente',value:null,note:'File de propositions à développer',target:'contenus:Annonces',color:4},
 {label:'Publicités actives',value:stats?.['Publicités actives']??null,target:'contenus:Publicités',color:3},
 {label:'Commerces et prestataires',value:stats?.['Commerces et prestataires']??null,target:'professionnels',color:5},
 {label:'Chauffeurs disponibles',value:operational.drivers??null,target:'chauffeurs',color:6},
 {label:'Commandes',value:stats?.Commandes??null,target:'commandes',color:3},
 {label:'Courses',value:stats?.Courses??null,target:'courses',color:6},
 {label:'Revenus FCFA',value:stats?.['Revenus FCFA']??null,note:'Paiements non connectés',color:1},
 {label:'Sports / ASC',value:count('Sports & ASC'),target:'contenus:Sports & ASC',color:1},
 {label:'Événements à venir',value:stats?summary.upcomingCount:null,target:'contenus:Événements',color:2},
 {label:'Annonces publiées',value:stats?.['Annonces publiées']??null,target:'contenus:Annonces',color:4},
 {label:'Opportunités',value:count('Opportunités'),target:'contenus:Opportunités',color:5}
 ];
}
export function csvReport(metrics,measuredAt){
 const cell=v=>'"'+String(v??'').replace(/^[\s]*[=+\-@]/,'\'$&').replace(/"/g,'""')+'"';
 return '\uFEFF'+[['Indicateur','Valeur','État','Mesuré le'],...metrics.map(x=>[x.label,x.value??'',typeof x.value==='number'?'Mesuré':x.note||'Indisponible',measuredAt||''])].map(row=>row.map(cell).join(';')).join('\r\n');
}
