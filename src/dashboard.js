import {types} from './model.js';
export function dashboardSummary(contents,now=Date.now()){
 const published=contents.filter(x=>x.statut==='publié'&&Date.parse(x.publication)<=now&&(x.type!=='Publicités'||(x.actif&&(!x.fin||Date.parse(x.fin)>now))));
 const counts=types.map(type=>({type,count:published.filter(x=>x.type===type).length}));
 const months=Array.from({length:6},(_,i)=>{const d=new Date(now);d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()-5+i);return {key:d.toISOString().slice(0,7),label:d.toLocaleDateString('fr-FR',{month:'short',timeZone:'Africa/Dakar'}),count:0};});
 for(const row of published){const m=months.find(x=>x.key===row.publication.slice(0,7));if(m)m.count++;}
 return {upcomingCount:published.filter(x=>x.type==='Événements'&&Date.parse(x.evenement)>=now).length,counts,months,total:published.length,latest:[...contents].sort((a,b)=>Date.parse(b.updated_at)-Date.parse(a.updated_at)).slice(0,5),events:published.filter(x=>x.type==='Événements'&&Date.parse(x.evenement)>=now).sort((a,b)=>Date.parse(a.evenement)-Date.parse(b.evenement)).slice(0,4)};
}
