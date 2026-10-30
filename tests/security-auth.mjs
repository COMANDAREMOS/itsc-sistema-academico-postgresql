import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';

const root=resolve(fileURLToPath(new URL('..',import.meta.url)));
const base=String(process.env.ITSC_API_URL||'http://127.0.0.1:4002/api').replace(/\/$/,'');
const url=new URL(base);
if(!['localhost','127.0.0.1','[::1]'].includes(url.hostname)||url.port!=='4002'||url.username||url.password)throw Error('Estas pruebas de seguridad solo pueden ejecutarse contra localhost:4002, la API de pruebas independiente.');
const privateDir=process.env.ITSC_PRIVATE_DIR||join(homedir(),'Documents','Codex','Credenciales_Privadas','PostgreSQL_18');
const credentials=JSON.parse((await readFile(join(privateDir,'ITSC_PostgreSQL_accesos.json'),'utf8')).replace(/^\uFEFF/,''));
const secrets=[],results=[],sessions=new Map(),users=new Map();
const redact=value=>secrets.reduce((out,secret)=>secret?out.replaceAll(secret,'[privado]'):out,String(value));
const tag='QA_SEC_'+Date.now().toString(36).toUpperCase();
const password=()=>{const value='QA_'+randomBytes(22).toString('base64url');secrets.push(value);return value;};
async function request(path,{method='GET',body,role='ADMIN',cookie,anonymous=false,headers={},expected=[200]}={}){
 const session=anonymous?'':cookie??sessions.get(role)??'';
 const response=await fetch(base+path,{method,redirect:'manual',signal:AbortSignal.timeout(20000),headers:{...(session?{Cookie:session}:{}),...(body===undefined?{}:{'Content-Type':'application/json'}),...(!['GET','HEAD'].includes(method)?{'X-Requested-With':'ITSC',Origin:'http://localhost:3000'}:{}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})});
 const text=await response.text();let json;try{json=JSON.parse(text);}catch{json=null;}
 assert.ok(expected.includes(response.status),`${method} ${path}: HTTP ${response.status}, esperado ${expected.join('/')}; ${json?.message??'respuesta inválida'}`);
 return {json,response};
}
async function test(nombre,action){const started=Date.now();try{await action();results.push({nombre,estado:'correcto',milisegundos:Date.now()-started});}catch(error){results.push({nombre,estado:'fallo',mensaje:redact(error.message||error),milisegundos:Date.now()-started});}}
async function login(usuario,clave){const result=await request('/auth/login',{method:'POST',anonymous:true,body:{usuario,password:clave},expected:[200,201]});const cookie=result.response.headers.getSetCookie().map(v=>v.split(';')[0]).join('; ');assert.ok(cookie);secrets.push(cookie);return {cookie,user:result.json.user};}
const created=[];
async function createUser(suffix,rol='CAJA'){const clave=password();const usuario=tag+'_'+suffix;const result=await request('/datos/usuarios',{method:'POST',body:{usuario,nombre:'Verificación de seguridad '+suffix,password:clave,rol,docente_id:null},expected:[200,201]});assert.ok(result.json?.data?.id);created.push(result.json.data.id);return {id:result.json.data.id,usuario,clave};}
const started=Date.now();
try{
 for(const role of ['ADMIN','DOCENTE','CAJA']){
  const account=credentials.accesos.find(a=>a.rol===role);if(!account)throw Error('Falta un acceso para la comprobación de roles.');const clave=account.contrasena??account.password;secrets.push(clave);const session=await login(account.usuario,clave);sessions.set(role,session.cookie);users.set(role,session.user);
 }
 await test('El origen hostil se rechaza antes de procesar una escritura',()=>request('/datos/cargos',{method:'POST',headers:{Origin:'https://sitio-ajeno.example'},body:{},expected:[403]}));
 await test('No se admiten escrituras sin cabecera CSRF de aplicación',()=>request('/auth/logout',{method:'POST',headers:{'X-Requested-With':''},expected:[403]}));
 await test('Un origen parecido a localhost se rechaza',()=>request('/auth/logout',{method:'POST',headers:{Origin:'http://localhost:3000.sitio-ajeno.example'},expected:[403]}));
 await test('Un formulario de login de otro origen se rechaza',()=>request('/auth/login',{method:'POST',anonymous:true,headers:{Origin:'https://sitio-ajeno.example'},body:{usuario:'x',password:'x'},expected:[403]}));
 await test('Una cookie con codificación inválida produce 401',()=>request('/auth/me',{cookie:'itsc_pg_sesion=%no-valido',expected:[401]}));
 await test('Un token inventado produce 401',()=>request('/auth/me',{cookie:'itsc_pg_sesion=eyJhbGciOiJub25lIn0.e30.',expected:[401]}));
 await test('Una firma de sesión modificada produce 401',()=>{const original=sessions.get('CAJA');const [name,value]=original.split('=');const pieces=value.split('.');pieces[2]=(pieces[2][0]==='A'?'B':'A')+pieces[2].slice(1);return request('/auth/me',{cookie:name+'='+pieces.join('.'),expected:[401]});});
 for(const [name,body] of [
  ['La inyección SQL en usuario no permite autenticación',{usuario:"' OR 1=1 --",password:'sin_clave'}],
  ['Los objetos JSON como usuario o contraseña se rechazan',{usuario:{id:1},password:{valor:'x'}}],
  ['Un objeto con toString no causa un fallo interno',{usuario:{toString:'invalidado'},password:'x'}],
  ['Un array vacío no permite autenticación',{usuario:[],password:[]}],
  ['El texto excesivo se rechaza sin error interno',{usuario:'x'.repeat(1000),password:'x'.repeat(1000)}],
 ])await test(name,()=>request('/auth/login',{method:'POST',anonymous:true,body,expected:[400,401,422]}));
 await test('Un objeto como identificador de matrícula se rechaza',()=>request('/datos/cargos',{method:'POST',body:{matricula_id:{id:1},concepto:'Carga inválida',monto:10,vencimiento:'2026-12-01'},expected:[400,422]}));
 await test('No se crean accesos con contraseña mayor al límite de login',()=>request('/datos/usuarios',{method:'POST',body:{usuario:tag+'_clave_larga',nombre:'Carga inválida',password:'x'.repeat(201),rol:'CAJA',docente_id:null},expected:[400,422]}));
 await test('Caja no puede crear usuarios administradores',()=>request('/datos/usuarios',{method:'POST',role:'CAJA',body:{usuario:tag+'_escalar',nombre:'No autorizado',password:password(),rol:'ADMIN'},expected:[403]}));
 await test('Caja no puede activar ni desactivar usuarios',()=>request('/datos/usuarios/'+users.get('ADMIN').id,{method:'PATCH',role:'CAJA',body:{activo:0},expected:[403]}));
 await test('Caja no puede registrar calificaciones',()=>request('/datos/notas',{method:'POST',role:'CAJA',body:{inscripcion_id:1,evaluacion_id:1,nota:99},expected:[403]}));
 const offers=(await request('/datos/ofertas?pageSize=100')).json.rows;
 const foreign=offers.find(o=>o.docente_id!==users.get('DOCENTE').docente_id);
 assert.ok(foreign,'La demostración debe contener una oferta de otro docente.');
 await test('Docente no puede leer el detalle de una oferta ajena',()=>request('/datos/ofertas/'+foreign.id,{role:'DOCENTE',expected:[403]}));
 await test('Docente no puede consultar la planilla de una oferta ajena',()=>request('/planillas?tipo=notas&oferta_id='+foreign.id,{role:'DOCENTE',expected:[403]}));
 await test('Docente no puede crear evaluaciones de una oferta ajena',()=>request('/datos/evaluaciones',{method:'POST',role:'DOCENTE',body:{oferta_id:foreign.id,nombre:tag,componente:'PRACTICA',peso:1},expected:[403]}));
 await test('Un filtro docente ajeno no sustituye el alcance de la sesión',async()=>{const result=(await request('/datos/ofertas?docente_id='+foreign.docente_id+'&pageSize=100',{role:'DOCENTE'})).json;assert.ok(result.rows.every(row=>row.docente_id===users.get('DOCENTE').docente_id));});
 const limitedUser=tag+'_limite';
 for(let i=0;i<5;i++)await test(`Login incorrecto ${i+1} de 5 permite respuesta 401`,()=>request('/auth/login',{method:'POST',anonymous:true,body:{usuario:limitedUser,password:'fallo_para_verificar_limite'},expected:[401]}));
 await test('El sexto intento de login se limita con 429',()=>request('/auth/login',{method:'POST',anonymous:true,body:{usuario:limitedUser,password:'fallo_para_verificar_limite'},expected:[429]}));
 await test('El límite no se evita cambiando mayúsculas del mismo usuario',()=>request('/auth/login',{method:'POST',anonymous:true,body:{usuario:limitedUser.toLowerCase(),password:'fallo_para_verificar_limite'},expected:[429]}));
 await test('El límite de cinco intentos también resiste solicitudes concurrentes',async()=>{
  const usuario=tag+'_concurrente';
  const replies=await Promise.all(Array.from({length:8},()=>request('/auth/login',{method:'POST',anonymous:true,body:{usuario,password:'fallo_concurrente_para_verificar_limite'},expected:[401,429]})));
  const failed=replies.filter(r=>r.response.status===401).length;
  assert.ok(failed<=5,`El límite permitió ${failed} intentos incorrectos simultáneos; debe permitir como máximo 5.`);
  await request('/auth/login',{method:'POST',anonymous:true,body:{usuario,password:'fallo_concurrente_para_verificar_limite'},expected:[429]});
 });
 await test('La desactivación de un usuario QA revoca inmediatamente su sesión',async()=>{
  const account=await createUser('revocacion');const session=await login(account.usuario,account.clave);
  await request('/auth/me',{cookie:session.cookie});
  await request('/datos/usuarios/'+account.id,{method:'PATCH',body:{activo:0}});
  await request('/auth/me',{cookie:session.cookie,expected:[401]});
  await request('/auth/login',{method:'POST',anonymous:true,body:{usuario:account.usuario,password:account.clave},expected:[401]});
 });
 await test('Cambiar contraseña QA revoca el token anterior y admite la nueva clave',async()=>{
  const account=await createUser('clave');const session=await login(account.usuario,account.clave);const nueva=password();
  const result=await request('/auth/password',{method:'POST',cookie:session.cookie,body:{actual:account.clave,nueva,confirmacion:nueva},expected:[200,201]});assert.equal(result.json.relogin,true);
  await request('/auth/me',{cookie:session.cookie,expected:[401]});
  await request('/auth/login',{method:'POST',anonymous:true,body:{usuario:account.usuario,password:account.clave},expected:[401]});
  const after=await login(account.usuario,nueva);assert.equal(after.user.id,account.id);await request('/auth/me',{cookie:after.cookie});
  await request('/datos/usuarios/'+account.id,{method:'PATCH',body:{activo:0}});
 });
}catch(error){results.push({nombre:'Preparación de pruebas de seguridad',estado:'fallo',mensaje:redact(error.message||error)});}
finally{
 for(const id of created)try{await request('/datos/usuarios/'+id,{method:'PATCH',body:{activo:0}});}catch{}
 const summary={total:results.length,correctas:results.filter(r=>r.estado==='correcto').length,fallos:results.filter(r=>r.estado==='fallo').length,duracion_segundos:Number(((Date.now()-started)/1000).toFixed(2))};
 await mkdir(join(root,'.local'),{recursive:true});await writeFile(join(root,'.local/pruebas-seguridad.json'),JSON.stringify({resumen:summary,pruebas:results},null,2));
 console.log(JSON.stringify({...summary,informe:'.local/pruebas-seguridad.json'}));
 for(const result of results.filter(r=>r.estado==='fallo'))console.error(result.nombre+': '+result.mensaje);
 if(summary.fallos)process.exitCode=1;
}
