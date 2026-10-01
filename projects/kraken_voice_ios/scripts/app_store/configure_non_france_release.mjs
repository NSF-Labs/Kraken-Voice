// Explicitly select this narrower initial-release configuration; France needs
// a separate encryption declaration before it can be added.
import {api} from './api.mjs';
import {writeFileSync} from 'node:fs';
if(!process.argv.includes('--exclude-france')) throw new Error('Explicit --exclude-france selection required.');
const orig=fetch;globalThis.fetch=(u,o)=>orig(u,{...o,signal:AbortSignal.timeout(30000)});
const app='6817940644';
let availability;
try{availability=(await api('GET',`/v1/apps/${app}/appAvailabilityV2`)).data;}catch(e){if(JSON.parse(e.message).status!==404)throw e;}
if(!availability){
 const territories=(await api('GET','/v1/territories?limit=200')).data;
 const included=territories.map(t=>({type:'territoryAvailabilities',id:`\u0024{territory-${t.id}}`,attributes:{available:t.id!=='FRA',preOrderEnabled:false},relationships:{territory:{data:{type:'territories',id:t.id}}}}));
 availability=(await api('POST','/v2/appAvailabilities',{data:{type:'appAvailabilities',attributes:{availableInNewTerritories:true},relationships:{app:{data:{type:'apps',id:app}},territoryAvailabilities:{data:included.map(({type,id})=>({type,id}))}}},included})).data;
}else{
 const r=await api('GET',`/v2/appAvailabilities/${availability.id}/territoryAvailabilities?include=territory&limit=200`);
 const france=r.data.find(t=>t.relationships.territory.data.id==='FRA');
 if(!france)throw new Error('France availability record missing');
 await api('PATCH',`/v1/territoryAvailabilities/${france.id}`,{data:{type:'territoryAvailabilities',id:france.id,attributes:{available:false}}});
}
// Apple only creates documentation declarations for proprietary encryption,
// or standard third-party encryption distributed in France. This release uses
// standard algorithms and excludes France, so no document record is required.
const result={configuredAt:new Date().toISOString(),availability,usesNonExemptEncryption:false,scope:'Standard encryption; France excluded',documentationRequiredInAppStoreConnect:false,documentation:'https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/'};
writeFileSync(new URL('../../release/export-compliance.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result,null,2));
