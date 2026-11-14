#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const http = require('node:http');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '..');
const swift = fs.readFileSync(path.join(root, 'embedded/tahoe/ChatGPTPageScript.swift'), 'utf8');
const source = swift.match(/static let source = #"""([\s\S]*?)"""#/)[1];
const chrome = [process.env.SIDEOS_CHROME, '/usr/bin/chromium', '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable'].filter(Boolean).find(p => fs.existsSync(p));
if (!chrome) throw new Error('A real Chromium/Chrome executable is required; set SIDEOS_CHROME.');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'sideos-layout-'));
const checks = String.raw`
(async()=>{
 const passed=[];const assert=(condition,name)=>{if(!condition)throw new Error(name);passed.push(name);};
 const wait=()=>new Promise(resolve=>setTimeout(resolve,180));
 try {
  window.__sideosChat.configure({enabled:true,revealed:true,role:'primary',items:[{id:'a',title:'First conversation',generating:false},{id:'b',title:'A much longer second conversation title',generating:false}],left:'a',right:'b',focused:'a',ratio:.5});
  await wait();
  const row=document.querySelector('[data-sideos-chat-row]');
  assert(row&&row.getBoundingClientRect().height>=38,'tab row has real layout height');
  const report=()=>messages.filter(m=>m.type==='layout').at(-1);
  assert(report().rect&&report().rect.width>300,'split pane reports real usable width');
  assert(document.querySelector('#prompt-textarea').getBoundingClientRect().bottom<=innerHeight+2,'composer fits below real header and tabs');
  let writes=0;const observer=new MutationObserver(records=>{writes+=records.filter(r=>r.attributeName==='style').length;});
  observer.observe(document.querySelector('main'),{subtree:true,attributes:true,attributeFilter:['style']});
  window.__sideosChat.inspect();await wait();writes=0;window.__sideosChat.inspect();await wait();
  assert(writes===0,'unchanged inspection does not rewrite layout styles');observer.disconnect();
  const oldY=report().strip.y;window.scrollTo(0,120);await wait();
  assert(row.getBoundingClientRect().top>=-1,'integrated row stays reachable after root scroll');
  assert(report().strip.y!==oldY,'root scroll refreshes native hit geometry');
  assert(report().rect.y>=0&&report().rect.y+report().rect.height<=innerHeight+2,'native pane stays inside real viewport');
  window.scrollTo(0,0);await wait();
  const viewport=new EventTarget();viewport.height=500;viewport.offsetTop=0;
  Object.defineProperty(window,'visualViewport',{configurable:true,value:viewport});
  window.__sideosChat.inspect();await wait();
  assert(document.querySelector('#prompt-textarea').getBoundingClientRect().bottom<=502,'composer remains visible in a smaller keyboard viewport');
  const composer=document.querySelector('#prompt-textarea');composer.value='private draft';composer.dispatchEvent(new Event('input',{bubbles:true}));
  assert(messages.filter(m=>m.type==='status').at(-1).hasDraft===true,'draft protection updates immediately without waiting for layout');
  assert(!JSON.stringify(messages).includes('private draft'),'draft text does not cross the bridge');
  document.documentElement.dir='rtl';window.__sideosChat.inspect();await wait();
  assert(Math.abs(report().rect.x-document.querySelector('main').getBoundingClientRect().left)<2,'RTL split places secondary pane on the correct physical side');
  const secondary=report().rect;assert(document.querySelector('#content').getBoundingClientRect().left>=secondary.x+secondary.width-2,'RTL primary content does not overlap the native secondary pane');
  document.documentElement.dir='ltr';window.__sideosChat.inspect();await wait();
  window.__sideosChat.configure({right:null});await wait();
  assert(document.querySelector('#content').style.width==='','leaving split restores branch width');
  window.__sideosChat.dispose();await wait();
  assert(!document.querySelector('[data-sideos-chat-row]')&&!document.querySelector('[data-sideos-chat-divider]'),'dispose removes integrated controls');
  document.documentElement.dataset.sideosResults=btoa(JSON.stringify({passed}));
 }catch(error){document.documentElement.dataset.sideosResults=btoa(JSON.stringify({passed,error:String(error.stack||error)}));}
})();`;
// Use a local controlled document. This is layout evidence for the adapter, not
// an authenticated ChatGPT-site or iOS WebKit runtime claim.
const guarded = source.replace("location.protocol !== 'https:' || location.hostname !== 'chatgpt.com'", 'false').replaceAll('route(location.href)', "route('https://chatgpt.com/c/fixture')");
const fixture = `<!doctype html><html><head><meta charset="utf-8"><style>
*{box-sizing:border-box}html,body{margin:0}body{font:16px system-ui}#shell{display:flex}aside{width:200px;flex:none}main{display:flex;flex-direction:column;height:100vh;min-width:0;flex:1}header{height:48px;flex:none}#content{display:flex;flex-direction:column;min-height:0;flex:1}#messages{overflow:auto;flex:1;min-height:0}textarea{height:70px;flex:none;width:100%}footer{height:600px}
</style></head><body><div id="shell"><aside>Sidebar</aside><main><header>Conversation</header><section id="content"><div id="messages">${'<p>A message in a long conversation.</p>'.repeat(100)}</div><textarea id="prompt-textarea"></textarea></section></main></div><footer></footer>
<script>window.messages=[];window.webkit={messageHandlers:{sideosChat:{postMessage:m=>messages.push(m)}}};</script>
<script>${guarded.replace(/<\/script/gi, '<\\/script')}</script><script>${checks}</script></body></html>`;
async function run() {
 const file=path.join(temporary,'fixture.html');fs.writeFileSync(file,fixture);
 const server=http.createServer((request,response)=>{response.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});response.end(fixture);});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 // A local CDP pipe avoids flaky loopback WebSocket startup/proxy handling.
 const browser=spawn(chrome,['--headless','--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--disable-background-networking','--disable-extensions','--no-first-run','--remote-debugging-pipe','--user-data-dir='+path.join(temporary,'profile'),'about:blank'],{stdio:['ignore','ignore','pipe','pipe','pipe']});
 let log='',sequence=0,buffer=Buffer.alloc(0);const pending=new Map();
 browser.stderr.on('data',data=>{log=(log+data.toString()).slice(-12000);});
 const fail=reason=>{for(const request of pending.values())request.reject(new Error(reason+'\n'+log));pending.clear();};
 browser.on('error',error=>fail('Unable to start Chrome: '+error.message));
 browser.on('close',(code,signal)=>fail('Chrome closed: '+code+' '+signal));
 browser.stdio[4].on('data',data=>{
  buffer=Buffer.concat([buffer,data]);let end;
  while((end=buffer.indexOf(0))!==-1){
   const frame=buffer.subarray(0,end).toString('utf8');buffer=buffer.subarray(end+1);if(!frame)continue;
   let message;try{message=JSON.parse(frame);}catch(error){fail('Invalid Chrome protocol response: '+error.message);return;}
   const request=pending.get(message.id);if(!request)continue;pending.delete(message.id);
   message.error?request.reject(new Error(JSON.stringify(message.error))):request.resolve(message.result);
  }
 });
 const command=(method,params={},sessionId)=>new Promise((resolve,reject)=>{
  const id=++sequence;pending.set(id,{resolve,reject});
  browser.stdio[3].write(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})})+'\0',error=>{if(error){pending.delete(id);reject(error);}});
 });
 browser.stdio[3].on('error',error=>fail('Chrome pipe failed: '+error.message));
 const deadline=setTimeout(()=>browser.kill('SIGKILL'),45000);
 try {
  const {targetId}=await command('Target.createTarget',{url:'about:blank'});
  const {sessionId}=await command('Target.attachToTarget',{targetId,flatten:true});
  await command('Page.enable',{},sessionId);
  await command('Emulation.setDeviceMetricsOverride',{width:1200,height:1000,deviceScaleFactor:1,mobile:false},sessionId);
  await command('Page.navigate',{url:'http://127.0.0.1:'+server.address().port+'/'},sessionId);
  let encoded;
  for(let i=0;i<100;i++){
   const value=await command('Runtime.evaluate',{expression:'document.documentElement.dataset.sideosResults',returnByValue:true},sessionId);
   if(value.result.value){encoded=value.result.value;break;}
   await new Promise(resolve=>setTimeout(resolve,100));
  }
  if(!encoded){const value=await command('Runtime.evaluate',{expression:'document.documentElement.outerHTML',returnByValue:true},sessionId);fs.writeFileSync('/tmp/sideos-layout-last.html',value.result.value||'');throw new Error('Layout fixture did not finish; see /tmp/sideos-layout-last.html');}
  const output=JSON.parse(Buffer.from(encoded,'base64').toString());
  for(const name of output.passed)process.stdout.write('PASS '+name+'\n');
  if(output.error)throw new Error(output.error);
  process.stdout.write(output.passed.length+' real browser layout checks passed.\n');
 } finally {clearTimeout(deadline);if(browser.exitCode===null&&browser.signalCode===null){browser.kill('SIGKILL');await new Promise(resolve=>browser.once('close',resolve));}await new Promise(resolve=>server.close(resolve));fs.rmSync(temporary,{recursive:true,force:true});}
}
run().catch(error=>{process.stderr.write(String(error.stack||error)+'\n');process.exitCode=1;});
