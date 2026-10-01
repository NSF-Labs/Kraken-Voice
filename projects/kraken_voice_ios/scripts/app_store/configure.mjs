import {api} from './api.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
const configPath=new URL('../../release/app-store-setup.json',import.meta.url);
const config=JSON.parse(readFileSync(configPath));
const apps=await api('GET','/v1/apps?filter[bundleId]='+config.bundleId);
if(apps.data.length!==1) throw new Error('Expected exactly one matching app');
const app=apps.data[0]; config.appId=app.id;
const rel=(type,id)=>({data:{type,id}});
const infos=await api('GET',`/v1/apps/${app.id}/appInfos`);
const info=infos.data.find(x=>x.attributes.appStoreState==='PREPARE_FOR_SUBMISSION');
if(!info) throw new Error('No editable app information');
const locs=await api('GET',`/v1/appInfos/${info.id}/appInfoLocalizations`);
for(const loc of locs.data){
 await api('PATCH',`/v1/appInfoLocalizations/${loc.id}`,{data:{type:'appInfoLocalizations',id:loc.id,attributes:{privacyPolicyUrl:config.privacyPolicyURL}}});
 console.log('Privacy URL saved:',loc.attributes.locale);
}
const existing=await api('GET',`/v1/apps/${app.id}/inAppPurchasesV2?limit=200`);
for(const p of config.products){
 let product=existing.data.find(x=>x.attributes.productId===p.productId);
 if(!product) product=(await api('POST','/v2/inAppPurchases',{data:{type:'inAppPurchases',attributes:{name:p.displayName,productId:p.productId,inAppPurchaseType:p.type,familySharable:false,reviewNote:'Settings > Trial & Lifetime Unlock. Free non-consumable trial lasts 30 days from original purchase. Lifetime unlock is a separate one-time purchase. Existing saved work remains accessible after trial expiry.'},relationships:{app:rel('apps',app.id)}}})).data;
 p.resourceId=product.id;
 writeFileSync(configPath,JSON.stringify(config,null,2)+'\n');
 const locales=await api('GET',`/v2/inAppPurchases/${product.id}/inAppPurchaseLocalizations`);
 if(!locales.data.some(x=>x.attributes.locale==='en-US')) await api('POST','/v1/inAppPurchaseLocalizations',{data:{type:'inAppPurchaseLocalizations',attributes:{name:p.displayName,locale:'en-US',description:p.description},relationships:{inAppPurchaseV2:rel('inAppPurchases',product.id)}}});
 console.log('Product and English localization:',p.productId,product.id);
}
config.status.appRecordCreated=true; config.status.appStoreConnectProductsCreated=true;
writeFileSync(configPath,JSON.stringify(config,null,2)+'\n');
