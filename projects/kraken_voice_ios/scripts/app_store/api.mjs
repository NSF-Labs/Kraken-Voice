import { readFileSync } from 'node:fs';
import { createPrivateKey, sign } from 'node:crypto';
const keyPath = process.env.ASC_PRIVATE_KEY_PATH;
if (!keyPath) throw new Error('Set ASC_PRIVATE_KEY_PATH to the private .p8 file.');
const keyId = process.env.ASC_KEY_ID || 'H3426ABVMJ';
const issuer = process.env.ASC_ISSUER_ID || '277c068d-1703-4392-9c1b-16c55e1c3c6a';
const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
export async function api(method, path, body) {
  if (!path.startsWith('/v1/') && !path.startsWith('/v2/')) throw new Error('Expected App Store Connect API path');
  const now = Math.floor(Date.now()/1000);
  const unsigned = b64({alg:'ES256',kid:keyId,typ:'JWT'})+'.'+b64({iss:issuer,iat:now,exp:now+600,aud:'appstoreconnect-v1'});
  const token = unsigned+'.'+sign('sha256',Buffer.from(unsigned),{key:createPrivateKey(readFileSync(keyPath)),dsaEncoding:'ieee-p1363'}).toString('base64url');
  const response = await fetch('https://api.appstoreconnect.apple.com'+path,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body ? JSON.stringify(body) : undefined});
  const text = await response.text();
  let data; try {data=JSON.parse(text);} catch { data={text}; }
  if (!response.ok) throw new Error(JSON.stringify({status:response.status,path,errors:data.errors ?? data}));
  return data;
}
if (process.argv[1] && import.meta.url === new URL('file://'+process.argv[1]).href) {
 const [method,path,file]=process.argv.slice(2);
 console.log(JSON.stringify(await api(method || 'GET',path || '/v1/apps?limit=10',file ? JSON.parse(readFileSync(file,'utf8')) : undefined),null,2));
}
