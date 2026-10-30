import { readFile, unlink } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const file = resolve(root,'.local/servers.json');
let state;
try { state=JSON.parse(await readFile(file,'utf8')); } catch { console.log('El sistema no está iniciado.'); process.exit(0); }
if (resolve(state.root)!==root || !Number.isSafeInteger(state.manager) || state.manager<1) throw Error('No se pudo verificar el proceso del proyecto.');
if(process.platform==='win32') {
  const cmd=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',`(Get-CimInstance Win32_Process -Filter 'ProcessId=${state.manager}' -ErrorAction SilentlyContinue).CommandLine`],{encoding:'utf8',windowsHide:true}).trim();
  if(cmd) {
    const normalized=cmd.replaceAll('\\','/').toLowerCase();
    if(!normalized.includes(root.replaceAll('\\','/').toLowerCase()) || !normalized.includes('scripts/start.mjs')) throw Error('El proceso registrado no pertenece al servidor del proyecto. No se detuvo.');
    execFileSync('taskkill.exe',['/PID',String(state.manager),'/T','/F'],{windowsHide:true,stdio:'ignore'});
  }
} else { try {process.kill(state.manager,'SIGINT');} catch(e){if(e.code!=='ESRCH')throw e;} }
await unlink(file).catch(()=>{});
console.log('Sistema académico detenido. PostgreSQL y el proyecto anterior siguen disponibles.');
