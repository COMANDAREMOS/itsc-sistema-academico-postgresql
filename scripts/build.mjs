import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const run = (args, cwd) => new Promise((ok, fail) => {
  const child = spawn(process.execPath, args, { cwd, stdio: 'inherit', windowsHide: true, env: { ...process.env, NEXT_TELEMETRY_DISABLED: '1' } });
  child.on('error', fail); child.on('exit', code => code === 0 ? ok() : fail(new Error(`La compilación terminó con código ${code}.`)));
});
await run(['node_modules/typescript/bin/tsc', '-p', 'backend/tsconfig.json'], root);
await run([resolve(root, 'node_modules/next/dist/bin/next'), 'build'], resolve(root, 'frontend'));
