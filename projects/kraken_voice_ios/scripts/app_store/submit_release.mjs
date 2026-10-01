import {api} from './api.mjs';
import {writeFileSync} from 'node:fs';
if(!process.argv.includes('--submit'))throw new Error('Use --submit only for the owner-authorized release.');
const original=fetch;globalThis.fetch=(u,o)=>original(u,{...o,signal:AbortSignal.timeout(30000)});
const app='6817940644',version='38743d7d-f77a-4480-85d5-202a072601de',submission='74904eac-7d70-4393-b45a-84e3dbb1d3c9';
const state=(await api('GET',`/v1/reviewSubmissions/${submission}`)).data;
if(state.attributes.state!=='READY_FOR_REVIEW')throw new Error(`Submission is ${state.attributes.state}; no further submission mutation attempted.`);
const builds=await api('GET',`/v1/builds?filter[app]=${app}&filter[version]=12`);
const build=builds.data.find(b=>b.attributes.processingState==='VALID');
if(!build)throw new Error('Build 12 has not finished Apple processing.');
const territories=(await api('GET',`/v2/appAvailabilities/${app}/territoryAvailabilities?include=territory&limit=200`)).data;
if(territories.some(t=>t.relationships.territory.data.id==='FRA'&&t.attributes.available))throw new Error('France must remain excluded for this document-exempt release.');
// False means exempt from Apple's documentation-upload requirements here;
// SQLCipher encryption is present and documented in export-compliance.json.
if(build.attributes.usesNonExemptEncryption===true)throw new Error('Build has a conflicting encryption declaration.');
if(build.attributes.usesNonExemptEncryption!==false){
 await api('PATCH',`/v1/builds/${build.id}`,{data:{type:'builds',id:build.id,attributes:{usesNonExemptEncryption:false}}});
}
await api('PATCH',`/v1/appStoreVersions/${version}`,{data:{type:'appStoreVersions',id:version,relationships:{build:{data:{type:'builds',id:build.id}}}}});
let items=(await api('GET',`/v1/reviewSubmissions/${submission}/items?include=appStoreVersion,inAppPurchaseVersion`)).data;
if(!items.some(i=>i.relationships.appStoreVersion?.data?.id===version)){
 await api('POST','/v1/reviewSubmissionItems',{data:{type:'reviewSubmissionItems',relationships:{reviewSubmission:{data:{type:'reviewSubmissions',id:submission}},appStoreVersion:{data:{type:'appStoreVersions',id:version}}}}});
}
items=(await api('GET',`/v1/reviewSubmissions/${submission}/items?include=appStoreVersion,inAppPurchaseVersion`)).data;
for(const id of ['2e29399e-e235-4847-8967-9323ac6d8ffc','23badebd-ba5a-46a7-8de7-0032eac17483']){
 if(!items.some(i=>i.relationships.inAppPurchaseVersion?.data?.id===id))throw new Error(`Required purchase ${id} missing from submission.`);
}
if(items.length!==3||items.some(i=>i.attributes.state!=='READY_FOR_REVIEW'))throw new Error('Expected exactly three ready review items.');
writeFileSync(new URL('../../release/submission-preflight.json',import.meta.url),JSON.stringify({checkedAt:new Date().toISOString(),build:build.id,version,submission,items},null,2)+'\n');
const result=await api('PATCH',`/v1/reviewSubmissions/${submission}`,{data:{type:'reviewSubmissions',id:submission,attributes:{submitted:true}}});
writeFileSync(new URL('../../release/submission-result.json',import.meta.url),JSON.stringify({requestedAt:new Date().toISOString(),build:build.id,version,submission,result},null,2)+'\n');
console.log(JSON.stringify({build:build.id,submission,...result.data.attributes},null,2));
