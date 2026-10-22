// Uses the production Flutter host in source/tool/mcp_inspector_host_test.dart.
// Dependencies and ephemeral credentials remain in the ignored validation dir.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';

const [validationDir, modulesDir] = process.argv.slice(2);
if (!validationDir || !modulesDir) throw new Error('Usage: node tool/mcp_catalog_smoke.mjs <validation-dir> <node_modules>');
const session = JSON.parse(await fs.readFile(path.join(validationDir, 'session.json'), 'utf8'));
const moduleFile = (...parts) => pathToFileURL(path.resolve(modulesDir, ...parts));
const {Client} = await import(moduleFile('@modelcontextprotocol/sdk/dist/esm/client/index.js'));
const {StreamableHTTPClientTransport} = await import(moduleFile('@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js'));
const {default: Ajv2020} = await import(moduleFile('ajv/dist/2020.js'));
const ajv = new Ajv2020({strict: false, allErrors: true});
const version = async name => JSON.parse(await fs.readFile(path.resolve(modulesDir, name, 'package.json'), 'utf8')).version;
const report = {sdk: await version('@modelcontextprotocol/sdk'), inspector: await version('@modelcontextprotocol/inspector'), checks: []};
const transport = new StreamableHTTPClientTransport(new URL(session.url), {
  requestInit: {headers: {Authorization: `Bearer ${session.test_token}`}},
  fetch: async (url, init) => {
    const response = await fetch(url, init);
    if (typeof init?.body === 'string' && JSON.parse(init.body).method === 'tools/list') {
      const raw = await response.clone().text();
      await fs.writeFile(path.join(validationDir, 'tools-list-after.json'), raw);
      report.wire_bytes = Buffer.byteLength(raw, 'utf8');
    }
    return response;
  },
});
const client = new Client({name: 'frame-studio-compact-contract', version: '1.0.0'});
async function call(name, args = {}) {
  const result = await client.callTool({name, arguments: args});
  assert.equal(result.isError, false, JSON.stringify(result));
  return result.structuredContent;
}
async function inspector(method, extra = []) {
  const launcher = path.resolve(modulesDir, '@modelcontextprotocol/inspector/clients/launcher/build/index.js');
  const result = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [launcher, '--cli', session.url, '--transport', 'http', '--method', method,
      ...extra, '--format', 'json', '--stored-auth-only', '--header', `Authorization: Bearer ${session.test_token}`], {
      windowsHide: true,
      env: {...process.env, MCP_CATALOG_PATH: path.join(validationDir, 'inspector-catalog.json'), MCP_CLIENT_CONFIG_PATH: path.join(validationDir, 'inspector-client.json')},
    });
    let output = '', errors = '';
    child.stdout.on('data', chunk => output += chunk);
    child.stderr.on('data', chunk => errors += chunk);
    child.on('error', reject);
    child.on('exit', code => resolve({code, output, errors}));
  });
  await fs.writeFile(path.join(validationDir, `inspector-${method.replaceAll('/', '-')}.json`), result.output);
  assert.equal(result.code, 0, result.errors);
  return {exit: result.code, output_bytes: Buffer.byteLength(result.output), warnings: result.errors.trim()};
}
try {
  await client.connect(transport);
  const {tools} = await client.listTools();
  assert.equal(tools.length, 34);
  assert.ok(report.wire_bytes < 25000);
  for (const tool of tools) {
    ajv.compile(tool.inputSchema);
    assert.ok(Buffer.byteLength(JSON.stringify(tool.inputSchema)) <= 4000, tool.name);
    assert.ok(Buffer.byteLength(tool.description) < 300, tool.name);
  }
  report.tool_count = tools.length;
  report.schemas_validated = tools.length;
  report.first_eight = tools.slice(0, 8).map(tool => tool.name);
  report.checks.push('official SDK tools/list', 'all inputSchemas compile as JSON Schema 2020-12 with local refs', 'wire and per-tool budgets');
  const original = await call('get_project');
  assert.equal(original.format_version, 14);
  const video = original.clips.find(clip => clip.type === 'video');
  const compact = {base_revision: original.revision, commands: [
    {tool: 'add_marker', arguments: {at: 1, name: 'compact SDK marker'}},
    {tool: 'set_volume', arguments: {clip_id: video.id, volume: 0.4}},
  ]};
  assert.ok(ajv.validate(tools.find(tool => tool.name === 'preview_plan').inputSchema, compact), JSON.stringify(ajv.errors));
  const preview = await call('preview_plan', compact);
  assert.equal((await call('get_project')).revision, original.revision);
  const applied = await call('apply_plan', {plan_id: preview.plan_id, base_revision: original.revision});
  assert.equal((await call('get_clip', {clip_id: video.id})).volume, 0.4);
  await call('undo', {base_revision: applied.revision});
  report.checks.push('compact preview_plan -> apply_plan -> undo over real HTTP');

  const invalid = await client.callTool({name: 'preview_plan', arguments: {
    base_revision: (await call('get_project')).revision,
    commands: [{tool: 'set_volume', arguments: {clip_id: video.id, volume: 3}}],
  }});
  assert.equal(invalid.isError, true);
  const error = invalid.structuredContent.error;
  assert.equal(error.code, 'out_of_range');
  assert.equal(error.details.command_index, 0);
  assert.equal(error.details.example.tool, 'set_volume');
  assert.ok(ajv.validate(error.details.expected_schema, error.details.example.arguments));
  report.checks.push('structured error preserves bounds and supplies valid schema/minimal example');
  const malformed = await client.callTool({name: 'preview_plan', arguments: {
    base_revision: (await call('get_project')).revision,
    commands: [{tool: 'set_volume', arguments: 'invalid'}],
  }});
  assert.equal(malformed.isError, true);
  assert.equal(malformed.structuredContent.error.details.example.tool, 'set_volume');
  assert.equal(malformed.structuredContent.error.details.command_index, 0);
  report.checks.push('malformed argument object still includes selected tool schema/example');

  const legacy = await call('apply_commands', {
    base_revision: (await call('get_project')).revision,
    commands: [{command: 'add_marker', arguments: {at: 2, name: 'legacy SDK marker'}}],
  });
  await call('undo', {base_revision: legacy.revision});
  report.checks.push('legacy command alias apply_commands -> undo');
  report.inspector_tools = await inspector('tools/list', ['--strict']);
  report.inspector_read = await inspector('tools/call', ['--tool-name', 'get_project', '--tool-args-json', '{"limit":1}']);
  report.checks.push('MCP Inspector strict tools/list', 'MCP Inspector get_project');
  report.ok = true;
} catch (error) {
  report.ok = false;
  report.error = String(error.stack ?? error);
  process.exitCode = 1;
} finally {
  await transport.terminateSession().catch(() => {});
  await client.close().catch(() => {});
  await fs.writeFile(path.join(validationDir, 'report.json'), JSON.stringify(report, null, 2));
  await fs.writeFile(path.join(validationDir, 'stop'), 'complete');
  console.log(JSON.stringify(report, null, 2));
}
