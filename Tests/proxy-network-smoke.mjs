// Optional real-network diagnostic. Only fresh profiles and the explicitly supplied proxy.
// Reports readiness/status, never page bodies, cookies, proxy credentials or exit IPs.
import {mkdtemp, readFile, writeFile, rm, readdir, copyFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';

const argument = process.argv[2];
if (!argument) throw Error('Usage: node Tests/proxy-network-smoke.mjs http://127.0.0.1:PORT (or --system)');
const proxy = argument === '--system' ? '' : argument;
if (proxy) {
    const parsed = new URL(proxy);
    if (!['http:', 'https:', 'socks5:'].includes(parsed.protocol) || parsed.username || parsed.password) throw Error('Use an explicit proxy without embedded credentials.');
}
const root = await mkdtemp(join(tmpdir(), 'fenjing-network-'));
const folder = dirname(fileURLToPath(import.meta.url));
const child = spawn(process.env.FENJING_TEST_HOST || join(folder, '../build/CoreTests'), ['--browser-host', root, proxy, proxy], {stdio: ['ignore', 'pipe', 'pipe']});
let output = '', exited;
child.stdout.on('data', data => output += data);
child.stderr.on('data', data => output += data);
child.on('exit', code => exited = code);
const sessions = [];
async function until(fn, label, timeout = 30000) {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
        if (exited !== undefined && exited !== 0) throw Error('Browser fixture failed: ' + output);
        try { const value = await fn(); if (value) return value; } catch (e) { if (e.message.startsWith('Browser fixture')) throw e; }
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw Error('Timed out: ' + label);
}
class Client {
    constructor(ws) {
        this.ws = ws; this.next = 0; this.pending = new Map(); this.failures = []; this.requests = new Map();
        ws.addEventListener('message', event => {
            const value = JSON.parse(String(event.data));
            if (value.id) {
                const waiting = this.pending.get(value.id);
                if (waiting) { this.pending.delete(value.id); value.error ? waiting.reject(Error(value.error.message)) : waiting.resolve(value.result); }
            } else {
                const p = value.params;
                if (value.method === 'Network.requestWillBeSent') {
                    try { this.requests.set(p.requestId, {url:p.request.url,host: new URL(p.request.url).hostname, type: p.type, since: Date.now(), bytes: 0}); } catch {}
                }
                const request = this.requests.get(p?.requestId);
                if (value.method === 'Network.responseReceived' && request) Object.assign(request, {status:p.response.status, protocol:p.response.protocol});
                if (value.method === 'Network.dataReceived' && request) request.bytes += p.dataLength;
                if (value.method === 'Network.loadingFinished' && request) request.done = true;
                if (value.method === 'Network.loadingFailed') { this.failures.push(p.errorText); if(request) Object.assign(request, {done:true,error:p.errorText}); }
            }
        });
    }
    static async connect(profile) {
        const target = await until(async () => {
            const port = (await readFile(join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0];
            return (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(value => value.type === 'page');
        }, 'debug endpoint');
        const ws = new WebSocket(target.webSocketDebuggerUrl);
        await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, {once: true}); ws.addEventListener('error', reject, {once: true}); });
        return new Client(ws);
    }
    call(method, params = {}) {
        const id = ++this.next;
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => { this.pending.delete(id); reject(Error('Diagnostic call timed out')); }, 5000);
            this.pending.set(id, {resolve: value => {clearTimeout(timer); resolve(value);}, reject: error => {clearTimeout(timer); reject(error);}});
            this.ws.send(JSON.stringify({id, method, params}));
        });
    }
    async read() {
        const value = await this.call('Runtime.evaluate', {expression: `({host:location.hostname,ready:document.readyState,search:!!document.querySelector('[name="q"]'),title:document.title})`, returnByValue: true});
        return value.result.value;
    }
    async visit(url, profile) {
        this.failures = []; this.requests.clear();
        const started = Date.now();
        const navigation = await this.call('Page.navigate', {url});
        if (navigation.errorText) throw Error(navigation.errorText);
        let last;
        try {
            await until(async () => {
                last = await this.read();
                // ip.sb includes advertising frames that can remain pending after its
                // actual page is usable. Google must complete its essential load.
                return last.host === new URL(url).hostname && (last.host.includes('google.') ? last.ready === 'complete' && last.search : last.ready !== 'loading');
            }, 'complete HTTPS page: ' + new URL(url).hostname, 25000);
        } catch (error) {
            const pending = [...this.requests.values()].filter(x=>!x.done);
            await writeFile(join(folder, '../build/network-probe-last.json'),JSON.stringify({staticResources:pending.filter(x=>x.host.endsWith('.gstatic.com')).map(x=>x.url)}),{mode:0o600});
            throw Error(JSON.stringify({profile, host: new URL(url).hostname, observed: last, pendingRequests:pending.map(({since,url,...x})=>({...x,elapsedMs:Date.now()-since})),networkErrors: this.failures, error: error.message}));
        }
        console.log(JSON.stringify({profile, host: last.host, ready: last.ready, search: last.search, elapsedMs: Date.now() - started, networkErrors: this.failures}));
    }
}
try {
    const fixture = await until(async () => { const state = JSON.parse(await readFile(join(root, 'status.json'), 'utf8')); return state.phase === 'both-running' ? state : null; }, 'browser startup');
    assert.equal(fixture.a, true); assert.equal(fixture.b, true);
    const clients = await Promise.all([Client.connect(fixture.pathA), Client.connect(fixture.pathB)]);
    sessions.push(...clients);
    await Promise.all(clients.map(client => client.call('Network.enable')));
    // Use IP.SB's plain endpoint so unrelated advertising frames do not make
    // the proxy-baseline check depend on third-party ad services.
    for (const url of ['https://www.google.com/', 'https://api.ip.sb/ip', 'https://www.google.com/']) {
        for (const [index, client] of clients.entries()) await client.visit(url, String(index + 1));
    }
    console.log('PASS Google completes loading and the IP.SB HTTPS baseline is usable through the explicitly supplied proxy in two clean browser profiles.');
} finally {
    for (const client of sessions) client.ws.close();
    await writeFile(join(root, 'finish'), '').catch(() => {});
    await until(() => exited !== undefined, 'normal cleanup', 12000).catch(() => {});
    if (exited === undefined) { child.kill('SIGTERM'); throw Error('Cleanup not confirmed; diagnostic files retained at ' + root); }
    if (exited === 0) {
        if (process.env.FENJING_KEEP_NETLOG === '1') for (const name of await readdir(root)) {
            if (name.startsWith('netlog-') && name.endsWith('.json')) await copyFile(join(root,name),join(folder,'../build',name));
        }
        await rm(root, {recursive: true, force: true});
    }
}
