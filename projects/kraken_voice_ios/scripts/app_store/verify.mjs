import {api} from './api.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
const c=JSON.parse(readFileSync(new URL('../../release/app-store-setup.json',import.meta.url)));
const evidence={appId:c.appId,checkedAt:new Date().toISOString(),products:[]};
for(const p of c.products){
 const product=(await api('GET',`/v2/inAppPurchases/${p.resourceId}`)).data;
 const loc=(await api('GET',`/v2/inAppPurchases/${p.resourceId}/inAppPurchaseLocalizations`)).data;
 const schedule=(await api('GET',`/v2/inAppPurchases/${p.resourceId}/iapPriceSchedule`)).data;
 const prices=await api('GET',`/v1/inAppPurchasePriceSchedules/${schedule.id}/manualPrices?include=inAppPurchasePricePoint&limit=200`);
 evidence.products.push({id:p.resourceId,...product.attributes,localizations:loc.map(x=>x.attributes),manualPrices:prices.included?.filter(x=>x.type==='inAppPurchasePricePoints').map(x=>x.attributes)});
}
const infos=(await api('GET',`/v1/apps/${c.appId}/appInfos`)).data;
evidence.localizations=(await api('GET',`/v1/appInfos/${infos[0].id}/appInfoLocalizations`)).data.map(x=>x.attributes);
evidence.offer=(await api('GET',`/v1/inAppPurchaseOfferCodes/${c.offer.resourceId}`)).data.attributes;
evidence.batches=(await api('GET',`/v1/inAppPurchaseOfferCodes/${c.offer.resourceId}/oneTimeUseCodes`)).data.map(x=>({id:x.id,...x.attributes}));
const appPrices=await api('GET',`/v1/appPriceSchedules/${c.appId}/manualPrices?include=appPricePoint&limit=200`);
evidence.appManualPrices=appPrices.included?.filter(x=>x.type==='appPricePoints').map(x=>x.attributes);
writeFileSync(new URL('../../release/app-store-verified.json',import.meta.url),JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence,null,2));
