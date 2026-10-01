import {api} from './api.mjs';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
const path=new URL('../../release/app-store-setup.json',import.meta.url);
const c=JSON.parse(readFileSync(path));
const product=c.products.find(x=>x.productId===c.offer.productId);
const rel=(type,id)=>({data:{type,id}});
const points=await api('GET',`/v2/inAppPurchases/${product.resourceId}/pricePoints?filter[territory]=USA&limit=8000`);
const free=points.data.find(x=>Number(x.attributes.customerPrice)===0);
if(!free) throw new Error('Free offer price missing');
const equal=await api('GET',`/v1/inAppPurchasePricePoints/${free.id}/equalizations?limit=8000&include=territory`);
const byTerritory=new Map([['USA',free]]);
for(const p of equal.data){const t=p.relationships?.territory?.data?.id; if(t && Number(p.attributes.customerPrice)===0) byTerritory.set(t,p);}
if(byTerritory.size<170) throw new Error('Incomplete zero-price offer equalizations: '+byTerritory.size);
const existing=await api('GET',`/v2/inAppPurchases/${product.resourceId}/offerCodes`);
let offer=existing.data.find(x=>x.attributes.name===c.offer.referenceName);
if(!offer){
 const included=[...byTerritory].map(([t,p],i)=>({type:'inAppPurchaseOfferPrices',id:'${offerPrice'+i+'}',relationships:{territory:rel('territories',t),pricePoint:rel('inAppPurchasePricePoints',p.id)}}));
 offer=(await api('POST','/v1/inAppPurchaseOfferCodes',{data:{type:'inAppPurchaseOfferCodes',attributes:{name:c.offer.referenceName,customerEligibilities:['NON_SPENDER','ACTIVE_SPENDER','CHURNED_SPENDER']},relationships:{inAppPurchase:rel('inAppPurchases',product.resourceId),prices:{data:included.map(x=>({type:x.type,id:x.id}))}}},included})).data;
}
c.offer.resourceId=offer.id;c.status.offerCreated=true;writeFileSync(path,JSON.stringify(c,null,2)+'\n');
console.log('Free lifetime offer configured:',offer.id,byTerritory.size,'territories');
const batches=await api('GET',`/v1/inAppPurchaseOfferCodes/${offer.id}/oneTimeUseCodes`);
let batch=batches.data.find(x=>x.attributes.environment==='SANDBOX' && x.attributes.active);
if(!batch) batch=(await api('POST','/v1/inAppPurchaseOfferCodeOneTimeUseCodes',{data:{type:'inAppPurchaseOfferCodeOneTimeUseCodes',attributes:{numberOfCodes:10,expirationDate:'2027-03-01',environment:'SANDBOX'},relationships:{offerCode:rel('inAppPurchaseOfferCodes',offer.id)}}})).data;
c.offer.sandboxBatchId=batch.id;c.status.sandboxCodesGenerated=true;writeFileSync(path,JSON.stringify(c,null,2)+'\n');
console.log('Sandbox batch created:',batch.id,'10 codes; expires 2027-03-01');
