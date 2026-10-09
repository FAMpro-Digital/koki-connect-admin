export async function renderMfaSettings(main,manager,{n,button,field,formPanel,error,refresh}){
  const factors=await manager.list();if(!main.isConnected)return;
  main.append(n('p','Les secrets des facteurs existants ne sont jamais affichés. Vérifiez le facteur à conserver avant toute révocation. Supabase peut fermer vos autres sessions lors de la vérification ; votre accord est demandé avant cet appel.'));
  const pending=n('section');pending.className='panel';pending.setAttribute('aria-live','polite');
  function verifyForm(id,after){
    const f=formPanel(),map={};const code=field(f,map,'mfa-code','Code à six chiffres','text',null,'',true);code.inputMode='numeric';code.autocomplete='one-time-code';code.pattern='[0-9]{6}';code.maxLength=6;
    const consent=field(f,map,'verify-consent','J’autorise cette vérification et la fermeture éventuelle de mes autres sessions par Supabase','checkbox');consent.required=true;
    const submit=n('button','Vérifier ce facteur');submit.type='submit';submit.className='primary';f.append(submit);
    f.onsubmit=async e=>{e.preventDefault();if(!consent.checked)return;submit.disabled=true;const value=code.value;code.value='';try{await manager.verify(id,value,consent.checked);await after();}catch(err){error(err);}finally{submit.disabled=false;}};return f;
  }
  for(const factor of factors){
    const card=n('article');card.className='card mfa-factor';card.append(n('h2',factor.name),n('p','Identifiant : '+factor.id),n('p',factor.status==='verified'?'Vérifié':'En attente de vérification'));
    const actions=n('div');actions.className='actions';
    actions.append(button('Vérifier / utiliser ce facteur',()=>{pending.replaceChildren(n('h2','Vérifier '+factor.name),verifyForm(factor.id,async()=>{pending.replaceChildren(n('p','Facteur vérifié. Vous pouvez maintenant demander la révocation d’un autre facteur.'));}));}));
    actions.append(button('Demander la révocation',()=>{
      pending.replaceChildren(n('h2','Confirmer la révocation'),n('p','Cette opération retirera uniquement '+factor.name+' ('+factor.id+'). Vérifiez d’abord un autre facteur que vous conserverez.'));
      const form=formPanel(),map={};const confirmation=field(form,map,'confirm-factor','Recopiez l’identifiant du facteur à révoquer','text',null,'',true);
      const consent=field(form,map,'consent','J’autorise la révocation de ce facteur uniquement','checkbox');consent.required=true;
      const submit=n('button','Révoquer le facteur confirmé');submit.type='submit';submit.className='danger';form.append(submit,button('Annuler',()=>pending.replaceChildren()));
      form.onsubmit=async e=>{e.preventDefault();if(!consent.checked)return;submit.disabled=true;try{await manager.revoke(factor.id,confirmation.value);await refresh();}catch(err){error(err);}finally{submit.disabled=false;}};pending.append(form);
    },'danger'));card.append(actions);main.append(card);
  }
  if(!factors.length)main.append(n('p','Aucun facteur TOTP. Reconnectez-vous pour configurer votre premier authentificateur.'));
  const add=formPanel(),map={};const name=field(add,map,'factor-name','Nom du nouvel authentificateur','text',null,'',true);name.maxLength=64;
  const submit=n('button','Ajouter un facteur TOTP');submit.type='submit';submit.className='primary';add.append(submit);
  add.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{const data=await manager.enroll(name.value);if(!main.isConnected)return;const qr=n('img');qr.className='qr';qr.alt='QR privé du nouvel authentificateur';qr.src=data.qr;
    pending.replaceChildren(n('h2','Configurer le nouvel authentificateur'),n('p','Scannez ce QR directement avec votre application. Ne partagez pas cet écran. La clé n’est jamais affichée en texte.'),qr,verifyForm(data.id,async()=>{qr.removeAttribute('src');pending.replaceChildren();await refresh();}),button('Masquer le QR',()=>{qr.removeAttribute('src');pending.replaceChildren(n('p','QR masqué. Le facteur reste en attente ; aucune révocation automatique.'));}));
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(add,pending);
}
