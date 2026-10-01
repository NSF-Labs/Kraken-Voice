import {api} from './api.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
const path=new URL('../../release/app-store-setup.json',import.meta.url);
const c=JSON.parse(readFileSync(path));
const rel=(type,id)=>({data:{type,id}});
for(const p of c.products){
 const points=await api('GET',`/v2/inAppPurchases/${p.resourceId}/pricePoints?filter[territory]=USA&limit=8000`);
 const point=points.data.find(x=>Number(x.attributes.customerPrice)===p.priceUSD);
 if(!point) throw new Error('No matching USD price for '+p.productId);
 p.usPricePointId=point.id;
 await api('POST','/v1/inAppPurchasePriceSchedules',{data:{type:'inAppPurchasePriceSchedules',relationships:{inAppPurchase:rel('inAppPurchases',p.resourceId),baseTerritory:rel('territories','USA'),manualPrices:{data:[{type:'inAppPurchasePrices',id:'${price}'}]}}},included:[{type:'inAppPurchasePrices',id:'${price}',attributes:{startDate:null,endDate:null},relationships:{inAppPurchaseV2:rel('inAppPurchases',p.resourceId),inAppPurchasePricePoint:rel('inAppPurchasePricePoints',point.id)}}]});
 console.log('Price set:',p.productId,point.attributes.customerPrice,'USD');
 writeFileSync(path,JSON.stringify(c,null,2)+'\n');
}
const territories=(await api('GET','/v1/territories?limit=200')).data;
for(const p of c.products){
 await api('POST','/v1/inAppPurchaseAvailabilities',{data:{type:'inAppPurchaseAvailabilities',attributes:{availableInNewTerritories:true},relationships:{inAppPurchase:rel('inAppPurchases',p.resourceId),availableTerritories:{data:territories.map(x=>({type:'territories',id:x.id}))}}}});
 console.log('Product availability configured:',p.productId,territories.length,'territories');
}
c.status.productPricingConfigured=true;
writeFileSync(path,JSON.stringify(c,null,2)+'\n');
