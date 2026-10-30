import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdir, writeFile, unlink } from 'node:fs/promises';
import { config } from 'dotenv';
import net from 'node:net';
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
config({ path: resolve(root, '.env'), quiet: true });
const dev = process.argv.includes('--dev');
const ports = [Number(process.env.API_PORT || 4001), 3000];
for (const port of ports) await new Promise((ok, fail) => {
  const server = net.createServer();
  server.once('error', () => fail(new Error(`El puerto ${port} está ocupado. Si el sistema ya está iniciado, abre http://localhost:3000.`)));
  server.listen(port, '127.0.0.1', () => server.close(ok));
});
const env = { ...process.env, NEXT_TELEMETRY_DISABLED: '1', NODE_ENV: dev ? 'development' : 'production' };
const compiler = dev ? spawn(process.execPath, [resolve(root, 'node_modules/typescript/bin/tsc'), '--watch', '-p', 'tsconfig.json'], { cwd: resolve(root, 'backend'), stdio: 'inherit', windowsHide: true, env }) : null;
const api = spawn(process.execPath, dev ? ['--watch', 'dist/main.js'] : ['dist/main.js'], { cwd: resolve(root, 'backend'), stdio: 'inherit', windowsHide: true, env });
const web = spawn(process.execPath, [resolve(root, 'node_modules/next/dist/bin/next'), dev ? 'dev' : 'start', '--hostname', '127.0.0.1', '--port', '3000'], { cwd: resolve(root, 'frontend'), stdio: 'inherit', windowsHide: true, env });
await mkdir(resolve(root, '.local'), { recursive: true });
await writeFile(resolve(root, '.local/servers.json'), JSON.stringify({ root, manager: process.pid, api: api.pid, web: web.pid, startedAt: new Date().toISOString() }));
console.log('Sistema académico: http://localhost:3000');
let stopping = false;
async function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  api.kill(); web.kill(); compiler?.kill();
  await unlink(resolve(root, '.local/servers.json')).catch(() => {});
  process.exit(code);
}
process.on('SIGINT', () => stop()); process.on('SIGTERM', () => stop());
api.on('error', error => { console.error(error.message); stop(1); });
web.on('error', error => { console.error(error.message); stop(1); });
api.on('exit', code => { if (!stopping) stop(code || 0); });
web.on('exit', code => { if (!stopping) stop(code || 0); });
