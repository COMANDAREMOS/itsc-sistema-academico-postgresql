import { readFile, writeFile, mkdir, open } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import pg from 'pg';
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const privateDir = join(homedir(), 'Documents', 'Codex', 'Credenciales_Privadas', 'PostgreSQL_18');
const loadJson = async name => JSON.parse((await readFile(join(privateDir, name), 'utf8')).replace(/^\uFEFF/, ''));
const admin = await loadJson('PostgreSQL_18_local.json');
const app = await loadJson('ITSC_PostgreSQL_accesos.json');
const connection = new pg.Client({ host: '127.0.0.1', port: admin.Puerto, user: admin.Usuario, password: admin.Contrasena, database: 'postgres' });
await connection.connect();
try {
  const found = await connection.query('SELECT pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname=$1', ['itsc_postgres_pruebas']);
  if (found.rowCount && found.rows[0].owner !== 'itsc_pg_app') throw Error('La base de pruebas pertenece a otro usuario. No se modificó.');
  if (!found.rowCount) await connection.query("CREATE DATABASE itsc_postgres_pruebas OWNER itsc_pg_app ENCODING 'UTF8' TEMPLATE template0");
} finally { await connection.end(); }
const url = `postgresql://itsc_pg_app:${encodeURIComponent(app.base.contrasena)}@127.0.0.1:5432/itsc_postgres_pruebas?schema=public`;
const env = { ...process.env, DATABASE_URL: url, API_PORT: '4002' };
await new Promise((ok, fail) => {
  const child = spawn(process.execPath, ['scripts/setup.mjs'], { cwd: root, env, windowsHide: true, stdio: 'inherit' });
  child.on('error', fail); child.on('exit', code => code === 0 ? ok() : fail(Error(`Preparación de pruebas falló: ${code}`)));
});
await mkdir(resolve(root, '.local'), { recursive: true });
const out = await open(resolve(root, '.local/qa-api.log'), 'a');
const err = await open(resolve(root, '.local/qa-api-error.log'), 'a');
const api = spawn(process.execPath, ['backend/dist/main.js'], { cwd: root, env, windowsHide: true, detached: true, stdio: ['ignore', out.fd, err.fd] });
await writeFile(resolve(root, '.local/qa-pid.json'), JSON.stringify({ pid: api.pid, database: 'itsc_postgres_pruebas', port: 4002 }));
api.unref(); await out.close(); await err.close();
console.log('API de pruebas independiente: http://127.0.0.1:4002/api');
