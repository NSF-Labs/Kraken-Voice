import {api} from './api.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
const path=new URL('../../release/app-store-setup.json',import.meta.url);
const c=JSON.parse(readFileSync(path));
const rel=(type,id)=>({data:{type,id}});
const prices=await api('GET',`/v1/apps/${c.appId}/appPricePoints?filter[territory]=USA&limit=200`);
const free=prices.data.find(x=>Number(x.attributes.customerPrice)===0);
if(!free) throw new Error('Free app price missing');
await api('POST','/v1/appPriceSchedules',{data:{type:'appPriceSchedules',relationships:{app:rel('apps',c.appId),baseTerritory:rel('territories','USA'),manualPrices:{data:[{type:'appPrices',id:'${freePrice}'}]}}},included:[{type:'appPrices',id:'${freePrice}',attributes:{startDate:null,endDate:null},relationships:{appPricePoint:rel('appPricePoints',free.id)}}]});
c.status.freeAppPriceConfigured=true;
writeFileSync(path,JSON.stringify(c,null,2)+'\n');
console.log('App download price set to free.');
for(const p of c.products){
 const r=await api('GET',`/v2/inAppPurchases/${p.resourceId}`);
 console.log(p.productId,r.data.attributes);
 const schedule=await api('GET',`/v2/inAppPurchases/${p.resourceId}/iapPriceSchedule`);
 const manual=await api('GET',`/v1/inAppPurchasePriceSchedules/${schedule.data.id}/manualPrices?include=inAppPurchasePricePoint&limit=200`);
 console.log('Verified prices:',manual.included?.filter(x=>x.type==='inAppPurchasePricePoints').map(x=>x.attributes.customerPrice));
}
