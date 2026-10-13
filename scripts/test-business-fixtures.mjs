// Aucun client, secret ni accès réseau créé par ce module. Exécution après validation du projet TEST.
import {validateTarget} from './prepare-coordinated-preview.mjs';
export async function seedTestBusiness({testProjectURL,client,driver,merchant,provider,admin}){
 validateTarget(testProjectURL,'sb_publishable_TARGET_CHECK_ONLY');
 for(const api of [client,driver,merchant,provider,admin])if(api?.targetURL!==testProjectURL)throw Error('Chaque adaptateur doit désigner exclusivement le projet TEST validé.');
 for(const api of [client,driver,merchant,provider,admin])await api.identity();
 const d=await driver.run('register_driver',{name:'TEST Chauffeur — fictif',phone:'+999000000001'});
 const vehicle=await driver.run('save_vehicle',{parent_id:d.id,name:'TEST Taxi — fictif',category:'Taxi',registration:'TEST-UNIQUEMENT'});
 const trader=await merchant.run('register_professional',{name:'TEST Boutique — fictive',phone:'+999000000002',profile:'Commerçant',description:'TEST sans commerce réel',zone:'TEST Koki'});
 const serviceProvider=await provider.run('register_professional',{name:'TEST Prestataire — fictif',phone:'+999000000003',profile:'Prestataire de services',description:'TEST sans intervention réelle',zone:'TEST Koki'});
 for(const id of [d.id,vehicle.id,trader.id,serviceProvider.id])await admin.run('admin_review',{id,decision:'approve'},'approve:'+id);
 for(const [category,base_fcfa,per_km_fcfa]of [['Moto',200,100],['Taxi',500,250],['Voiture',700,300],['Minicar',1000,400]])await admin.run('set_rate',{category,base_fcfa,per_km_fcfa,active:true},'rate:'+category);
 await driver.run('driver_position',{position:{latitude:15.56,longitude:-16.21},available:true});
 const shop=await merchant.run('save_shop',{parent_id:trader.id,name:'TEST Boutique Koki',address:'TEST adresse fictive Koki'});
 const product=await merchant.run('save_product',{parent_id:shop.id,name:'TEST Produit fictif',category:'TEST',description:'Aucune vente réelle',price:500,stock:2});
 const service=await provider.run('save_service',{parent_id:serviceProvider.id,name:'TEST Service fictif',category:'TEST plomberie',description:'Aucune prestation réelle',price:null});
 return {driver:d.id,vehicle:vehicle.id,merchant:trader.id,provider:serviceProvider.id,shop:shop.id,product:product.id,service:service.id,fictional:true};
}
