import {api} from './api.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const originalFetch=globalThis.fetch;
globalThis.fetch=(url,opts)=>originalFetch(url,{...opts,signal:AbortSignal.timeout(60000)});
const localization='41fcfa6c-79ca-4da7-bbea-3f0511690ed0';
const device=process.argv[2] || 'iphone';
if(!['iphone','ipad'].includes(device)) throw Error('Expected iphone or ipad');
const display=device==='ipad' ? 'APP_IPAD_PRO_3GEN_129' : 'APP_IPHONE_67';
const existing=(await api('GET',`/v1/appStoreVersionLocalizations/${localization}/appScreenshotSets`)).data;
const set=existing.find(x=>x.attributes.screenshotDisplayType===display) ?? (await api('POST','/v1/appScreenshotSets',{data:{type:'appScreenshotSets',attributes:{screenshotDisplayType:display},relationships:{appStoreVersionLocalization:{data:{type:'appStoreVersionLocalizations',id:localization}}}}})).data;
const current=(await api('GET',`/v1/appScreenshotSets/${set.id}/appScreenshots`)).data;
const evidence={setId:set.id,display,screenshots:[]};
const output=new URL('../../release/screenshots/'+device+'/app-store-upload.json',import.meta.url);
for (const number of (device==='ipad' ? [55] : [22,28,24,25,23,27,26])) {
 const name=`IMG_00${number}.PNG`;
 const bytes=readFileSync(new URL('../../release/screenshots/'+device+'/'+name,import.meta.url));
 const checksum=createHash('md5').update(bytes).digest('hex');
 let item=current.find(x=>x.attributes.fileName===name);
 if(item && item.attributes.sourceFileChecksum && item.attributes.sourceFileChecksum!==checksum) throw Error('Existing screenshot has different bytes: '+name);
 if(!item) item=(await api('POST','/v1/appScreenshots',{data:{type:'appScreenshots',attributes:{fileName:name,fileSize:bytes.length},relationships:{appScreenshotSet:{data:{type:'appScreenshotSets',id:set.id}}}}})).data;
 if(item.attributes.assetDeliveryState?.state==='AWAITING_UPLOAD') {
  for (const op of item.attributes.uploadOperations) {
   const response=await fetch(op.url,{method:op.method,headers:Object.fromEntries(op.requestHeaders.map(h=>[h.name,h.value])),body:bytes.subarray(op.offset,op.offset+op.length)});
   if(!response.ok) throw Error('Asset upload failed: '+response.status);
  }
  item=(await api('PATCH',`/v1/appScreenshots/${item.id}`,{data:{type:'appScreenshots',id:item.id,attributes:{uploaded:true,sourceFileChecksum:checksum}}})).data;
 }
 evidence.screenshots.push({id:item.id,file:name,checksum,state:item.attributes.assetDeliveryState});
 writeFileSync(output,JSON.stringify(evidence,null,2)+'\n');
 console.log(name,item.attributes.assetDeliveryState?.state);
}
