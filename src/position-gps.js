// Position GPS : remplace la saisie manuelle de la latitude et de la longitude.
// La position vient uniquement du GPS de l'appareil (navigator.geolocation) ;
// les coordonnées restent dans deux champs cachés lus tels quels à l'enregistrement.
export const PRECISION_FAIBLE=100; // mètres : au-delà, on invite à réessayer à l'extérieur

const arrondi=x=>Math.round(x*1e6)/1e6;

export function coordonneesValides(latitude,longitude){
 return Number.isFinite(latitude)&&Number.isFinite(longitude)&&latitude>=-90&&latitude<=90&&longitude>=-180&&longitude<=180;
}

export function messageErreurPosition(err){
 const code=err?.code;
 if(code===1)return 'Localisation refusée. Autorisez la position pour ce site dans les réglages du navigateur (iPhone : Réglages › Safari › Position), puis réessayez.';
 if(code===2)return 'Position introuvable. Activez la localisation du téléphone, placez-vous à l’extérieur et réessayez.';
 if(code===3)return 'Le GPS met trop de temps à répondre. Placez-vous à l’extérieur et réessayez.';
 return err?.message||'Localisation impossible sur cet appareil.';
}

export function lirePosition(geo=globalThis.navigator?.geolocation,{delai=20000}={}){
 return new Promise((resolve,reject)=>{
  if(!geo?.getCurrentPosition)return reject(Error('Ce navigateur ne permet pas la localisation GPS.'));
  if(globalThis.isSecureContext===false)return reject(Error('La localisation exige une connexion sécurisée (https).'));
  geo.getCurrentPosition(p=>{
   const latitude=arrondi(p.coords.latitude),longitude=arrondi(p.coords.longitude);
   if(!coordonneesValides(latitude,longitude))return reject(Error('Position GPS invalide.'));
   resolve({latitude,longitude,precision:Number.isFinite(p.coords.accuracy)?Math.round(p.coords.accuracy):null});
  },err=>reject(Error(messageErreurPosition(err))),{enableHighAccuracy:true,timeout:delai,maximumAge:0});
 });
}

export function textePosition(latitude,longitude,precision=null){
 if(!coordonneesValides(latitude,longitude))return 'Aucune position enregistrée.';
 let t='Position enregistrée : '+latitude.toFixed(5)+', '+longitude.toFixed(5);
 if(precision!=null)t+=' (précision ± '+precision+' m)';
 return t;
}

export function lienCarte(latitude,longitude){
 return 'https://www.openstreetmap.org/?mlat='+latitude+'&mlon='+longitude+'#map=18/'+latitude+'/'+longitude;
}

// Bloc « Position GPS » d'un formulaire. map.latitude / map.longitude reçoivent des champs
// numériques cachés : le code d'enregistrement existant les lit sans changement (vide → null).
export function positionField(form,map,valeurs={},{geo,onError}={}){
 const el=(t,txt)=>{const e=document.createElement(t);if(txt!==undefined)e.textContent=txt;return e;};
 const bloc=el('div');bloc.className='wide position-gps';
 const titre=el('strong','Position GPS');
 const etat=el('p');etat.className='position-etat';etat.setAttribute('role','status');etat.setAttribute('aria-live','polite');
 const champs={};
 for(const k of ['latitude','longitude']){const i=el('input');i.type='number';i.step='any';i.name=k;i.id='field-'+k;i.hidden=true;i.tabIndex=-1;i.setAttribute('aria-hidden','true');const x=Number(valeurs[k]);i.value=valeurs[k]===''||valeurs[k]==null||!Number.isFinite(x)?'':String(x);champs[k]=i;map[k]=i;}
 const capter=el('button','📍 Utiliser ma position actuelle (GPS)');capter.type='button';capter.className='primary';
 const effacer=el('button','Effacer la position');effacer.type='button';
 const carte=el('a','Voir sur la carte');carte.target='_blank';carte.rel='noopener';
 const aide=el('small','Placez-vous sur le lieu (commerce, point de stationnement…) puis appuyez sur le bouton. La position est prise par le GPS de l’appareil, aucune saisie manuelle.');
 let precision=null;
 const afficher=(avertissement='')=>{
  const lat=champs.latitude.value===''?NaN:Number(champs.latitude.value),lon=champs.longitude.value===''?NaN:Number(champs.longitude.value);
  const ok=coordonneesValides(lat,lon);
  etat.textContent=textePosition(lat,lon,precision)+(avertissement?' '+avertissement:'');
  carte.hidden=!ok;effacer.hidden=!ok;if(ok)carte.href=lienCarte(lat,lon);
  capter.textContent=ok?'📍 Remplacer par ma position actuelle (GPS)':'📍 Utiliser ma position actuelle (GPS)';
 };
 capter.onclick=async()=>{
  capter.disabled=true;etat.textContent='Recherche de votre position GPS…';
  try{
   const p=await lirePosition(geo);
   champs.latitude.value=String(p.latitude);champs.longitude.value=String(p.longitude);precision=p.precision;
   afficher(p.precision!=null&&p.precision>PRECISION_FAIBLE?'Précision faible : placez-vous à l’extérieur et réessayez si possible.':'');
  }catch(err){afficher();etat.textContent+=' '+err.message;onError?.(err);}
  finally{capter.disabled=false;}
 };
 effacer.onclick=()=>{champs.latitude.value='';champs.longitude.value='';precision=null;afficher();};
 const actions=el('div');actions.className='position-actions';actions.append(capter,carte,effacer);
 bloc.append(titre,etat,actions,aide,champs.latitude,champs.longitude);
 form.append(bloc);afficher();
 return bloc;
}
