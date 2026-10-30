import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
import assert from 'node:assert/strict';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';
const api = process.env.ITSC_API_URL || 'http://127.0.0.1:4002/api';
const url = new URL(api);
if (!['localhost','127.0.0.1'].includes(url.hostname) || url.port !== '4002') throw Error('Esta comprobación solo utiliza el servidor local de pruebas4002.');
const credentials = JSON.parse((await readFile(join(homedir(),'Documents','Codex','Credenciales_Privadas','PostgreSQL_18','ITSC_PostgreSQL_accesos.json'),'utf8')).replace(/^\uFEFF/,''));
const db = new PrismaClient({ adapter: new PrismaPg({ connectionString: `postgresql://itsc_pg_app:${encodeURIComponent(credentials.base.contrasena)}@127.0.0.1:5432/itsc_postgres_pruebas?schema=public` }) });
const results = [], cookies = {};
async function request(path, method='GET', role='ADMIN') {
  const res = await fetch(api+path,{method,headers:{cookie:cookies[role]||'','x-requested-with':'ITSC',origin:'http://localhost:3000'}});
  const json = await res.json(); return {status:res.status,json};
}
async function test(name, fn) { try {await fn();results.push({nombre:name,estado:'correcto'});}catch(e){results.push({nombre:name,estado:'fallo',mensaje:String(e.message).slice(0,500)});} }
try {
  for(const account of credentials.accesos){
    const res=await fetch(api+'/auth/login',{method:'POST',headers:{'content-type':'application/json','x-requested-with':'ITSC',origin:'http://localhost:3000'},body:JSON.stringify({usuario:account.usuario,password:account.contrasena})});
    assert.ok(res.ok,'No se pudo iniciar la sesión de pruebas.');cookies[account.rol]=res.headers.get('set-cookie').split(';')[0];
  }
  const source={matriculas:await db.matriculas.count(),resultados:await db.resultados_finales.count(),pagos:await db.pagos.count()};
  await test('Administración puede consultar el almacén',async()=>assert.equal((await request('/analitica')).status,200));
  for(const role of ['DOCENTE','CAJA']){
    await test(`${role} no consulta análisis institucional`,async()=>assert.equal((await request('/analitica','GET',role)).status,403));
    await test(`${role} no ejecuta ETL`,async()=>assert.equal((await request('/analitica/actualizar','POST',role)).status,403));
  }
  for(let n=1;n<=2;n++)await test(`ETL completo y conteos coherentes ${n}`,async()=>{
    const res=await request('/analitica/actualizar','POST');assert.ok([200,201].includes(res.status));assert.equal(res.json.resumen.estado,'COMPLETADO');
    for(const key of Object.keys(source))assert.equal(res.json.resumen[key],source[key]);
  });
  await test('Los hechos no se duplican al repetir ETL',async()=>{
    assert.equal(await db.dw_fact_matriculas.count(),source.matriculas);assert.equal(await db.dw_fact_resultados.count(),source.resultados);assert.equal(await db.dw_fact_pagos.count(),source.pagos);
  });
  await test('Las dimensiones conservan su origen operativo',async()=>{
    assert.equal(await db.dw_dim_estudiante.count(),await db.estudiantes.count());assert.equal(await db.dw_dim_docente.count(),await db.docentes.count());assert.equal(await db.dw_dim_carrera.count(),await db.carreras.count());assert.equal(await db.dw_dim_materia.count(),await db.materias.count());
  });
  await test('Las vistas analíticas coinciden con los hechos',async()=>{
    const {json}=await request('/analitica');assert.equal(json.matriculas.reduce((s,r)=>s+Number(r.total),0),source.matriculas);assert.equal(json.rendimiento.reduce((s,r)=>s+Number(r.inscripciones),0),source.resultados);
    const amount=await db.pagos.aggregate({_sum:{monto:true}});assert.equal(json.recaudacion.reduce((s,r)=>s+Number(r.total),0),Number(amount._sum.monto));assert.ok(json.ejecuciones.length>0);
  });
  await test('La actualización simultánea comparte un proceso seguro',async()=>{
    const responses=await Promise.all([request('/analitica/actualizar','POST'),request('/analitica/actualizar','POST')]);for(const res of responses)assert.ok([200,201].includes(res.status));assert.equal(responses[0].json.resumen.id,responses[1].json.resumen.id);
  });
  await test('ETL conserva matrículas, resultados y pagos operativos',async()=>{
    assert.equal(await db.matriculas.count(),source.matriculas);assert.equal(await db.resultados_finales.count(),source.resultados);assert.equal(await db.pagos.count(),source.pagos);
  });
}finally{await db.$disconnect();}
const summary={total:results.length,correctas:results.filter(r=>r.estado==='correcto').length,fallos:results.filter(r=>r.estado==='fallo').length,pruebas:results};
await mkdir(resolve('.local'),{recursive:true});await writeFile(resolve('.local/pruebas-analitica.json'),JSON.stringify(summary,null,2));console.log(JSON.stringify(summary));if(summary.fallos)process.exitCode=1;
