import {api} from './api.mjs';
import {writeFileSync} from 'node:fs';
const orig=fetch;globalThis.fetch=(u,o)=>orig(u,{...o,signal:AbortSignal.timeout(30000)});
const app='6817940644';
const existing=await api('GET',`/v1/apps/${app}/reviewSubmissions`);
let submission=existing.data.find(s=>s.attributes.state==='READY_FOR_REVIEW');
if(!submission){submission=(await api('POST','/v1/reviewSubmissions',{data:{type:'reviewSubmissions',attributes:{platform:'IOS'},relationships:{app:{data:{type:'apps',id:app}}}}})).data;}
const items=await api('GET',`/v1/reviewSubmissions/${submission.id}/items?include=appStoreVersion,inAppPurchaseVersion`);
const results=[];
for(const [relationship,type,id] of [
 ['appStoreVersion','appStoreVersions','38743d7d-f77a-4480-85d5-202a072601de'],
 ['inAppPurchaseVersion','inAppPurchaseVersions','2e29399e-e235-4847-8967-9323ac6d8ffc'],
 ['inAppPurchaseVersion','inAppPurchaseVersions','23badebd-ba5a-46a7-8de7-0032eac17483']
]) {
 if(items.data.some(i=>i.relationships?.[relationship]?.data?.id===id)){results.push({id,exists:true});continue;}
 try{ const r=await api('POST','/v1/reviewSubmissionItems',{data:{type:'reviewSubmissionItems',relationships:{reviewSubmission:{data:{type:'reviewSubmissions',id:submission.id}},[relationship]:{data:{type,id}}}}});results.push(r.data); }
 catch(e){results.push({id,error:JSON.parse(e.message)});}
}
const result={preparedAt:new Date().toISOString(),submission,results};
writeFileSync(new URL('../../release/review-submission.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result,null,2));
