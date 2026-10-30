import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { randomBytes, scryptSync } from 'node:crypto';
import { spawn } from 'node:child_process';
import pg from 'pg';
import { config } from 'dotenv';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
process.chdir(root);
const exists = async path => access(path).then(() => true, () => false);
const privateDir = process.env.ITSC_PRIVATE_DIR || join(homedir(), 'Documents', 'Codex', 'Credenciales_Privadas', 'PostgreSQL_18');
const privateFile = join(privateDir, 'ITSC_PostgreSQL_accesos.json');
const password = () => 'ITSC_' + randomBytes(18).toString('base64url');
const quote = value => "'" + String(value).replaceAll("'", "''") + "'";
const run = (args) => new Promise((ok, fail) => {
  const child = spawn(process.execPath, args, { cwd: root, stdio: 'inherit', windowsHide: true });
  child.on('error', fail); child.on('exit', code => code === 0 ? ok() : fail(new Error(`El paso ${args[0]} terminó con código ${code}.`)));
});

await mkdir(privateDir, { recursive: true });
let credentials;
if (await exists(privateFile)) credentials = JSON.parse((await readFile(privateFile, 'utf8')).replace(/^\uFEFF/, ''));
else {
  credentials = {
    sitio: 'http://localhost:3000',
    base: { servidor: '127.0.0.1', puerto: 5432, nombre: 'itsc_postgres', usuario: 'itsc_pg_app', contrasena: password() },
    accesos: [
      { usuario: 'admin', nombre: 'Administrador académico', rol: 'ADMIN', contrasena: password(), docente_id: null },
      { usuario: 'docente.demo', nombre: 'Docente de demostración', rol: 'DOCENTE', contrasena: password(), docente_id: 1 },
      { usuario: 'caja.demo', nombre: 'Responsable de caja', rol: 'CAJA', contrasena: password(), docente_id: null }
    ],
    aviso: 'Credenciales privadas del proyecto nuevo. No publicar en GitHub.'
  };
  await writeFile(privateFile, JSON.stringify(credentials, null, 2), { mode: 0o600 });
}
if (!(await exists(join(root, '.env')))) {
  const pgAdminFile = join(privateDir, 'PostgreSQL_18_local.json');
  let adminUrl = process.env.PGADMIN_DATABASE_URL;
  if (!adminUrl && await exists(pgAdminFile)) {
    const admin = JSON.parse((await readFile(pgAdminFile, 'utf8')).replace(/^\uFEFF/, ''));
    adminUrl = `postgresql://${encodeURIComponent(admin.Usuario)}:${encodeURIComponent(admin.Contrasena)}@127.0.0.1:${admin.Puerto}/postgres`;
  }
  if (!adminUrl) throw new Error('Configura PGADMIN_DATABASE_URL para crear la base nueva, o prepara .env con tu propia DATABASE_URL.');
  const connection = new pg.Client({ connectionString: adminUrl });
  await connection.connect();
  try {
    const role = await connection.query('SELECT 1 FROM pg_roles WHERE rolname=$1', [credentials.base.usuario]);
    if (!role.rowCount) await connection.query(`CREATE ROLE itsc_pg_app LOGIN PASSWORD ${quote(credentials.base.contrasena)} NOSUPERUSER NOCREATEDB NOCREATEROLE`);
    const db = await connection.query('SELECT pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname=$1', [credentials.base.nombre]);
    if (db.rowCount && db.rows[0].owner !== credentials.base.usuario) throw new Error('La base itsc_postgres pertenece a otro usuario. No se modificó.');
    if (!db.rowCount) await connection.query("CREATE DATABASE itsc_postgres OWNER itsc_pg_app ENCODING 'UTF8' TEMPLATE template0");
  } finally { await connection.end(); }
  const appUrl = `postgresql://${credentials.base.usuario}:${encodeURIComponent(credentials.base.contrasena)}@127.0.0.1:5432/itsc_postgres?schema=public`;
  await writeFile(join(root, '.env'), `DATABASE_URL=${appUrl}\nSESSION_SECRET=${randomBytes(48).toString('base64url')}\nWEB_ORIGIN=http://localhost:3000\nAPI_PORT=4001\n`, { mode: 0o600 });
}
config({ path: join(root, '.env'), quiet: true });
console.log('Preparando la base independiente itsc_postgres...');
await run(['node_modules/prisma/build/index.js', 'generate']);
await run(['node_modules/prisma/build/index.js', 'migrate', 'deploy']);
await run(['db/seed.mjs']);
await run(['db/etl.mjs']);
const { PrismaClient } = await import('@prisma/client');
const { PrismaPg } = await import('@prisma/adapter-pg');
const db = new PrismaClient({ adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }) });
try {
  for (const account of credentials.accesos) {
    const found = await db.app_usuarios.findUnique({ where: { usuario: account.usuario } });
    if (found) continue;
    const salt = randomBytes(16).toString('hex');
    const password_hash = `scrypt$${salt}$${scryptSync(account.contrasena, salt, 64).toString('hex')}`;
    await db.app_usuarios.create({ data: { usuario: account.usuario, nombre: account.nombre, rol: account.rol, docente_id: account.docente_id, password_hash, activo: 1 } });
  }
  console.log('Base de datos, datos ficticios y accesos preparados.');
  console.log(`Los accesos están en el archivo privado: ${privateFile}`);
} finally { await db.$disconnect(); }
