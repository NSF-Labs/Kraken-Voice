import {api} from './api.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const file=process.argv[2]; if(!file) throw new Error('Provide a reviewed, actual app screenshot path');
const bytes=readFileSync(file);
const configPath=new URL('../../release/app-store-setup.json',import.meta.url);
const c=JSON.parse(readFileSync(configPath));
for(const p of c.products){
 const image=(await api('POST','/v1/inAppPurchaseAppStoreReviewScreenshots',{data:{type:'inAppPurchaseAppStoreReviewScreenshots',attributes:{fileName:'voice-purchase-review.png',fileSize:bytes.length},relationships:{inAppPurchaseV2:{data:{type:'inAppPurchases',id:p.resourceId}}}}})).data;
 p.reviewScreenshotId=image.id;writeFileSync(configPath,JSON.stringify(c,null,2)+'\n');
 for(const op of image.attributes.uploadOperations){
  const response=await fetch(op.url,{method:op.method,headers:Object.fromEntries(op.requestHeaders.map(h=>[h.name,h.value])),body:bytes.subarray(op.offset,op.offset+op.length)});
  if(!response.ok) throw new Error('Apple asset upload failed: '+response.status);
 }
 await api('PATCH',`/v1/inAppPurchaseAppStoreReviewScreenshots/${image.id}`,{data:{type:'inAppPurchaseAppStoreReviewScreenshots',id:image.id,attributes:{uploaded:true,sourceFileChecksum:createHash('md5').update(bytes).digest('hex')}}});
 console.log('Review screenshot committed:',p.productId,image.id);
}
