// Run against tool/mcp_inspector_host_test.dart. Dependencies stay in .work/.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';

const [validationDir,modulesDir] = process.argv.slice(2);
if (!validationDir || !modulesDir) throw new Error('Usage: node tool/mcp_client_smoke.mjs <validation-dir> <node_modules>');
const session = JSON.parse(await fs.readFile(path.join(validationDir,'session.json'),'utf8'));
const sdk = path.resolve(modulesDir,'@modelcontextprotocol/sdk/dist/esm/client');
const {Client} = await import(pathToFileURL(path.join(sdk,'index.js')));
const {StreamableHTTPClientTransport} = await import(pathToFileURL(path.join(sdk,'streamableHttp.js')));
const report = {sdk:'1.32.1',inspector:'2.11.0',checks:[]};
const transport = new StreamableHTTPClientTransport(new URL(session.url),{requestInit:{headers:{Authorization:`Bearer ${session.test_token}`}}});
const client = new Client({name:'frame-studio-independent-smoke',version:'1.0.0'});
async function call(name,args={}) {
  const result = await client.callTool({name,arguments:args});
  assert.equal(result.isError,false,JSON.stringify(result));
  return result.structuredContent;
}
async function job(name,args) {
  let result=await call(name,args);
  for(let i=0;i<90 && ['queued','running'].includes(result.status);i++) {
    await new Promise(resolve=>setTimeout(resolve,1000)); result=await call('get_job',{job_id:result.job_id});
  }
  assert.equal(result.status,'completed',JSON.stringify(result)); return result.result;
}
function inspector(method,extra=[]) {
  const launcher=path.resolve(modulesDir,'@modelcontextprotocol/inspector/clients/launcher/build/index.js');
  return new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[launcher,'--cli',session.url,'--transport','http','--method',method,
      ...extra,'--format','json','--stored-auth-only','--header',`Authorization: Bearer ${session.test_token}`],
      {windowsHide:true,env:{...process.env,MCP_CATALOG_PATH:path.join(validationDir,'inspector-catalog.json'),MCP_CLIENT_CONFIG_PATH:path.join(validationDir,'inspector-client.json')}});
    let out='',err=''; child.stdout.on('data',c=>out+=c); child.stderr.on('data',c=>err+=c);
    child.on('error',reject); child.on('exit',code=>{
      fs.writeFile(path.join(validationDir,`inspector-${method.replaceAll('/','-')}.json`),out).catch(()=>{});
      code===0?resolve({exit:code,output_bytes:out.length,warnings:err.trim()}):reject(new Error(`Inspector ${method} exit ${code}: ${err}`));
    });
  });
}
try {
  await client.connect(transport);
  const tools=await client.listTools(); assert.ok(tools.tools.length>=30); report.tool_count=tools.tools.length; report.checks.push('sdk tools/list');
  const original=await call('get_project'); assert.equal(original.format_version,14); report.checks.push('sdk get_project');
  const resources=await client.listResources(); assert.equal(resources.resources[0].uri,'editor://project/summary');
  await client.readResource({uri:'editor://project/summary'}); report.checks.push('sdk project resource');
  const video=original.clips.find(c=>c.type==='video');
  const preview=await call('preview_plan',{base_revision:original.revision,commands:[
    {command:'add_marker',arguments:{at:1,name:'independent client'}},
    {command:'set_volume',arguments:{clip_id:video.id,volume:0.4}},
  ]});
  assert.equal((await call('get_project')).revision,original.revision);
  const applied=await call('apply_plan',{plan_id:preview.plan_id,base_revision:original.revision}); report.checks.push('sdk preview/apply exact plan');
  const stale=await client.callTool({name:'add_marker',arguments:{at:0,name:'stale',base_revision:original.revision}});
  assert.equal(stale.structuredContent.error.code,'revision_conflict'); report.checks.push('sdk stale revision rejection');
  await call('undo',{base_revision:applied.revision}); report.checks.push('sdk undo');
  const wrong=await fetch(session.url,{method:'POST',headers:{Authorization:'Bearer invalid',Accept:'application/json, text/event-stream','Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{}})});
  assert.equal(wrong.status,401); await wrong.text(); report.checks.push('http invalid token 401');
  const unsafe=await client.callTool({name:'export',arguments:{filename:'../escape.mp4',base_revision:(await call('get_project')).revision}});
  assert.equal(unsafe.structuredContent.error.code,'path_not_allowed'); report.checks.push('sdk outside export rejection');
  await call('get_frames',{media_id:video.media_id,times:[0,2]}); report.checks.push('sdk source PNG thumbnails');
  await call('get_loudness',{media_id:video.media_id}); report.checks.push('sdk ebur128 loudness');
  await job('detect_scenes',{media_id:video.media_id}); await job('detect_silence',{media_id:video.media_id}); report.checks.push('sdk native analysis jobs');
  const media=(await call('list_media')).media;
  const speech=media.find(m=>m.type==='audio');
  if(speech) {
    const transcription=await job('transcribe',{media_id:speech.id,language:'pt'});
    assert.ok(transcription.cue_count>0); const cues=await call('get_transcript',{media_id:speech.id});
    report.whisper_cue_count=cues.total; report.checks.push('sdk real local Whisper transcription');
  }
  await job('export',{filename:'independent-client.mp4',base_revision:(await call('get_project')).revision}); report.checks.push('sdk native export');
  report.inspector_tools=await inspector('tools/list',['--strict']);
  report.inspector_read=await inspector('tools/call',['--tool-name','get_project','--tool-args-json','{"limit":1}']);
  report.checks.push('MCP Inspector strict tools/list','MCP Inspector get_project');
  report.ok=true;
} catch(e) { report.ok=false; report.error=String(e); process.exitCode=1; }
finally {
  await transport.terminateSession().catch(()=>{}); await client.close().catch(()=>{});
  await fs.writeFile(path.join(validationDir,'report.json'),JSON.stringify(report,null,2));
  await fs.writeFile(path.join(validationDir,'stop'),'complete');
  console.log(JSON.stringify(report,null,2));
}
