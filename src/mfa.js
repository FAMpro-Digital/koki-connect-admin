// Only Supabase Auth owns factors, verification and revocation. Never retain secrets.
export function factorMetadata(data){
  return (data.all||data.totp||[]).filter(x=>x.factor_type==='totp'||(data.totp||[]).some(t=>t.id===x.id)).map(x=>({id:x.id,name:x.friendly_name||'Authentificateur',status:x.status,createdAt:x.created_at}));
}
export function createMfaManager(auth,authorize,now=Date.now){
  let proof=null,busy=false;
  const unwrap=r=>{if(r.error)throw Error('Opération MFA refusée. Réessayez ou reconnectez-vous.');return r.data;};
  const list=async()=>factorMetadata(unwrap(await auth.mfa.listFactors()));
  async function exclusive(fn){if(busy)throw Error('Une opération MFA est déjà en cours.');busy=true;try{return await fn();}finally{busy=false;}}
  async function aal2(){await authorize();const level=unwrap(await auth.mfa.getAuthenticatorAssuranceLevel());if(level.currentLevel!=='aal2')throw Error('Double authentification requise.');}
  return {
    list,
    clearProof: ()=>{proof=null;},
    enroll: name=>exclusive(async()=>{
      await aal2();name=name.trim();if(!name||name.length>64)throw Error('Choisissez un nom de 1 à 64 caractères.');
      const data=unwrap(await auth.mfa.enroll({factorType:'totp',friendlyName:name,issuer:'Koki Connect Admin'}));
      return {id:data.id,qr:data.totp.qr_code};
    }),
    verify: (id,code,allowSessionChanges=false)=>exclusive(async()=>{
      await authorize();proof=null;
      if(allowSessionChanges!==true)throw Error('Autorisez explicitement les changements de sessions associés à la vérification Supabase.');
      if(!/^\d{6}$/.test(code))throw Error('Saisissez exactement six chiffres.');
      if(!(await list()).some(x=>x.id===id))throw Error('Ce facteur n’existe plus.');
      unwrap(await auth.mfa.challengeAndVerify({factorId:id,code}));await aal2();
      if(!(await list()).some(x=>x.id===id&&x.status==='verified'))throw Error('Facteur non vérifié.');
      proof={id,time:now()};
    }),
    revoke: (id,confirmation)=>exclusive(async()=>{
      await aal2();const factors=await list(),target=factors.find(x=>x.id===id);
      if(!target)throw Error('Ce facteur n’existe plus.');
      if(confirmation!==id)throw Error('Confirmation explicite requise.');
      if(!proof||proof.id===id||now()-proof.time>300000||!factors.some(x=>x.id===proof.id&&x.status==='verified'))throw Error('Vérifiez d’abord un autre facteur que vous conserverez (moins de cinq minutes).');
      if(target.status==='verified'&&factors.filter(x=>x.status==='verified').length<2)throw Error('Le dernier facteur vérifié ne peut pas être révoqué.');
      proof=null;unwrap(await auth.mfa.unenroll({factorId:id}));
      if((await list()).some(x=>x.id===id))throw Error('La révocation n’est pas confirmée. Actualisez les facteurs.');
    })
  };
}
