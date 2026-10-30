// Real headed Chromium, disposable profiles, loopback-only test site and CDP observation.
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import http from 'node:http';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const folder=dirname(fileURLToPath(import.meta.url));
const root=await mkdtemp(join(tmpdir(),'fenjing-browsers-'));
const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><title>FenJing Local Isolation Test</title><h1>分境 · 本地隔离验证</h1><p>临时测试环境，无账号数据。</p>');});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
const proxyMode=process.argv.includes('--proxies');
const proxies=[];
if(proxyMode)for(const marker of ['proxy-a','proxy-b']){
 const proxy=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(`<title>FenJing Proxy Test</title><body data-proxy="${marker}"><h1>${marker}</h1></body>`);});
 await new Promise((resolve,reject)=>{proxy.once('error',reject);proxy.listen(0,'127.0.0.1',resolve);});proxies.push(proxy);
}
const url=proxyMode?'http://fenjing.test/':`http://127.0.0.1:${server.address().port}/`;
const child=spawn(join(folder,'../build/CoreTests'),['--browser-host',root,...proxies.map(p=>`http://127.0.0.1:${p.address().port}`)],{stdio:['ignore','pipe','pipe']});
let output='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>output+=d);
let exit;child.on('exit',code=>exit=code);
async function waitFor(fn,description,timeout=25000){const deadline=Date.now()+timeout;while(Date.now()<deadline){if(exit!==undefined&&exit!==0)throw Error(`Browser host exited ${exit}: ${output}`);try{const v=await fn();if(v)return v;}catch(e){if(e.message.startsWith('Browser host'))throw e;}await new Promise(r=>setTimeout(r,100));}throw Error(`Timeout: ${description}. ${output}`);}
async function state(phase){return waitFor(async()=>{const s=JSON.parse(await readFile(join(root,'status.json'),'utf8'));return s.phase===phase?s:null;},phase);}
class CDP {
 constructor(ws){this.ws=ws;this.id=0;this.pending=new Map();ws.addEventListener('message',event=>{const data=JSON.parse(String(event.data));if(data.id){const p=this.pending.get(data.id);if(p){this.pending.delete(data.id);data.error?p.reject(Error(data.error.message)):p.resolve(data.result);}}});}
 static async connect(profile){const target=await waitFor(async()=>{const text=await readFile(join(profile,'DevToolsActivePort'),'utf8');const port=text.split('\n')[0];const pages=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();return pages.find(p=>p.type==='page');},'live debugging port after startup');const ws=new WebSocket(target.webSocketDebuggerUrl);await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true});});return new CDP(ws);}
 call(method,params={}){const id=++this.id;return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending.delete(id);reject(Error(`CDP timeout ${method}`));},8000);this.pending.set(id,{resolve:v=>{clearTimeout(timer);resolve(v);},reject:e=>{clearTimeout(timer);reject(e);}});this.ws.send(JSON.stringify({id,method,params}));});}
 async eval(expression){const result=await this.call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value;}
 async navigate(){await this.call('Page.navigate',{url});await waitFor(async()=>await this.eval(`location.href===${JSON.stringify(url)} && document.readyState==='complete'`),'local page');}
 close(){this.ws.close();}
}
const sessions=[];
const observations=`(async()=>{const c=document.createElement('canvas');c.width=300;c.height=100;const x=c.getContext('2d');x.fillStyle='#78a34c';x.fillRect(2,3,160,70);x.font='19px Arial';x.fillStyle='#193546';x.fillText('FenJing fingerprint test',10,40);return {language:navigator.language,timezone:Intl.DateTimeFormat().resolvedOptions().timeZone,cpu:navigator.hardwareConcurrency,canvas:c.toDataURL(),storage:localStorage.getItem('identity'),cookie:document.cookie,geolocation:(await navigator.permissions.query({name:'geolocation'})).state};})()`;
try{
 const initial=await state('both-running');assert.equal(initial.a,true);assert.equal(initial.b,true);assert.notEqual(initial.pathA,initial.pathB);console.log('PASS simultaneous launches with distinct profile directories');
 const a=await CDP.connect(initial.pathA),b=await CDP.connect(initial.pathB);sessions.push(a,b);await Promise.all([a.navigate(),b.navigate()]);
 if(proxyMode){assert.equal(await a.eval('document.body.dataset.proxy'),'proxy-a');assert.equal(await b.eval('document.body.dataset.proxy'),'proxy-b');console.log('PASS each browser uses its own explicit proxy for the same origin');}
 const [av,bv]=await Promise.all([a.eval(observations),b.eval(observations)]);
 assert.equal(av.language,'en-US');assert.equal(bv.language,'ja-JP');assert.equal(av.timezone,'America/New_York');assert.equal(bv.timezone,'Asia/Tokyo');assert.equal(av.geolocation,'denied');assert.equal(bv.geolocation,'denied');assert.notEqual(av.canvas,bv.canvas);assert.equal(av.canvas,(await a.eval(observations)).canvas);console.log('PASS measured language, timezone, denied location and distinct stable Canvas fingerprints');
 assert.equal(av.storage,null);assert.equal(bv.storage,null);
 await a.eval(`localStorage.setItem('identity','account-a');document.cookie='identity=account-a; path=/; max-age=3600';`);
 assert.equal((await b.eval(observations)).storage,null);assert.equal((await b.eval(observations)).cookie,'');
 await b.eval(`localStorage.setItem('identity','account-b');document.cookie='identity=account-b; path=/; max-age=3600';`);
 assert.equal((await a.eval(observations)).storage,'account-a');assert.equal((await a.eval(observations)).cookie,'identity=account-a');console.log('PASS cookies and localStorage isolated for the same site');
 await writeFile(join(root,'stop-a'),'');const stopped=await state('a-stopped');assert.equal(stopped.a,false);assert.equal(stopped.b,true);assert.equal((await b.eval(observations)).storage,'account-b');console.log('PASS closing A leaves B alive and usable');
 await rm(join(root,'stop-a'));await writeFile(join(root,'restart-a'),'');const restarted=await state('a-restarted');assert.equal(restarted.a,true);assert.equal(restarted.b,true);
 const a2=await CDP.connect(initial.pathA);sessions.push(a2);await a2.navigate();const restored=await a2.eval(observations);assert.equal(restored.storage,'account-a');assert.equal(restored.cookie,'identity=account-a');assert.equal(restored.canvas,av.canvas);console.log('PASS restarted environment retains persistent cookies, storage and fingerprint');
 await writeFile(join(root,'finish'),'');const final=await state('all-stopped');assert.equal(final.a,false);assert.equal(final.b,false);console.log('PASS independent graceful shutdown');
 console.log(JSON.stringify({result:'passed',languageA:av.language,languageB:bv.language,timezoneA:av.timezone,timezoneB:bv.timezone,canvasA:createHash('sha256').update(av.canvas).digest('hex').slice(0,16),canvasB:createHash('sha256').update(bv.canvas).digest('hex').slice(0,16)}));
} finally {
 for(const session of sessions)session.close();
 await writeFile(join(root,'finish'),'').catch(()=>{});
 await waitFor(()=>exit!==undefined,'test host cleanup',12000).catch(()=>{});
 if(exit===undefined){child.kill('SIGTERM');throw Error('Cleanup not confirmed; retained temporary profiles at '+root);}
 server.close();for(const proxy of proxies)proxy.close();
 if(exit===0)await rm(root,{recursive:true,force:true});
 else console.error('Temporary profiles retained for diagnosis:',root,output);
}
