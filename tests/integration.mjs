import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const api = String(process.env.ITSC_API_URL || 'http://localhost:4001/api').replace(/\/$/, '');
const apiUrl = new URL(api);
if (!['localhost', '127.0.0.1', '[::1]'].includes(apiUrl.hostname) || apiUrl.username || apiUrl.password) {
  throw new Error('Las pruebas y las credenciales solo se pueden utilizar contra el servidor local.');
}
// Mutations are enabled by default only on the separate QA API. Running the
// default URL against the finished application performs read-only checks.
const writes = apiUrl.port === '4002' || process.env.ITSC_TEST_ALLOW_WRITES === 'true';
const privateDir = process.env.ITSC_PRIVATE_DIR || join(homedir(), 'Documents', 'Codex', 'Credenciales_Privadas', 'PostgreSQL_18');
const privateFile = join(privateDir, 'ITSC_PostgreSQL_accesos.json');
const results = [], sessions = new Map(), users = new Map(), metadata = new Map();
const created = [], secrets = [];
const began = Date.now();
const token = Date.now().toString(36).toUpperCase();
const prefix = `QA_PG_${token}`;
let credentials;
const redact = value => secrets.reduce((text, secret) => secret ? text.replaceAll(secret, '[privado]') : text, String(value));

async function test(name, run) {
  const start = Date.now();
  try {
    const value = await run();
    results.push({ nombre: name, estado: 'correcto', milisegundos: Date.now() - start });
    return value;
  } catch (error) {
    results.push({ nombre: name, estado: 'fallo', mensaje: redact(error?.message || error), milisegundos: Date.now() - start });
    return undefined;
  }
}

async function request(path, { role = 'ADMIN', method = 'GET', body, expected = [200], headers = {}, anonymous = false } = {}) {
  const cookie = anonymous ? '' : sessions.get(role);
  const response = await fetch(api + path, {
    method, redirect: 'manual', signal: AbortSignal.timeout(45000),
    headers: { ...(cookie ? { Cookie: cookie } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(method === 'GET' || method === 'HEAD' ? {} : { 'X-Requested-With': 'ITSC', Origin: 'http://localhost:3000' }), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const bytes = Buffer.from(await response.arrayBuffer());
  let json;
  if (response.headers.get('content-type')?.includes('application/json')) {
    try { json = JSON.parse(bytes.toString('utf8')); } catch { throw new Error(`${method} ${path}: respuesta JSON inválida.`); }
  }
  if (!expected.includes(response.status)) {
    const message = json?.message;
    throw new Error(`${method} ${path}: HTTP ${response.status}; esperado ${expected.join('/')}${message ? `; ${Array.isArray(message) ? message.join('; ') : message}` : ''}`);
  }
  return { status: response.status, json, bytes, headers: response.headers };
}

const get = (path, role = 'ADMIN') => request(path, { role }).then(response => response.json);
const post = (path, body, role = 'ADMIN', expected = [200, 201]) => request(path, { method: 'POST', body, role, expected }).then(response => response.json);
const patch = (path, body, role = 'ADMIN', expected = [200]) => request(path, { method: 'PATCH', body, role, expected }).then(response => response.json);
const invalid = (path, body, expected = [400, 409], role = 'ADMIN') => post(path, body, role, expected);
const qs = values => '?' + new URLSearchParams(Object.entries(values).filter(([, value]) => value != null).map(([key, value]) => [key, String(value)]));

async function create(module, data, role = 'ADMIN') {
  const response = await post(`/datos/${module}`, data, role);
  const result = response?.data;
  assert.ok(result && (result.id || result.inscripcion_id || result.oferta_id), `Crear ${module} no devolvió su identificador.`);
  created.push({ modulo: module, id: result.id ?? result.inscripcion_id ?? result.oferta_id });
  return result;
}

async function mapLimit(values, run, concurrency = 4) {
  const pending = [...values];
  await Promise.all(Array.from({ length: Math.min(concurrency, pending.length) }, async () => {
    while (pending.length) await run(pending.shift());
  }));
}

async function allRows(module, query = {}, role = 'ADMIN') {
  const rows = [];
  let page = 1, total = 1;
  while (rows.length < total) {
    const result = await get(`/datos/${module}${qs({ ...query, page, pageSize: 100 })}`, role);
    assert.ok(Array.isArray(result.rows), `La lista ${module} no tiene filas.`);
    rows.push(...result.rows); total = result.total;
    if (!result.rows.length) break;
    if (++page > 200) throw new Error(`La paginación de ${module} no finaliza.`);
  }
  return rows;
}

async function authentication() {
  await test('Servicio disponible y conectado a PostgreSQL', async () => {
    const result = await request('/health', { anonymous: true });
    assert.equal(result.json?.status, 'ok'); assert.equal(result.json?.database, 'PostgreSQL');
  });
  await test('Sin sesión no se permite consultar el sistema', () => request('/auth/me', { anonymous: true, expected: [401] }));
  await test('Las credenciales incorrectas se rechazan', () => request('/auth/login', {
    method: 'POST', anonymous: true, body: { usuario: `${prefix}_inexistente`, password: 'incorrecta_para_comprobacion' }, expected: [401],
  }));
  for (const role of ['ADMIN', 'DOCENTE', 'CAJA']) {
    await test(`Inicio de sesión ${role} y cookie protegida`, async () => {
      const account = credentials.accesos.find(account => account.rol === role);
      assert.ok(account, `No se encontró un acceso ${role} en el archivo privado.`);
      const response = await request('/auth/login', { method: 'POST', anonymous: true,
        body: { usuario: account.usuario, password: account.contrasena ?? account.password }, expected: [200, 201] });
      assert.equal(response.json?.user?.rol, role);
      const cookies = response.headers.getSetCookie();
      assert.ok(cookies.some(cookie => /httponly/i.test(cookie) && /samesite=strict/i.test(cookie)), 'La cookie debe ser HttpOnly y SameSite Strict.');
      const cookie = cookies.map(value => value.split(';')[0]).join('; ');
      secrets.push(cookie);
      sessions.set(role, cookie); users.set(role, response.json.user);
    });
    await test(`Consulta de sesión ${role} sin datos de contraseña`, async () => {
      const result = await get('/auth/me', role); assert.equal(result.user.rol, role);
      assert.ok(!('password_hash' in result.user) && !('password' in result.user) && !('contrasena' in result.user));
    });
  }
  await test('Las escrituras requieren la cabecera de verificación', () => request('/auth/logout', {
    method: 'POST', headers: { 'X-Requested-With': '' }, expected: [403],
  }));
  await test('Las escrituras rechazan un origen ajeno', () => request('/auth/logout', {
    method: 'POST', headers: { Origin: 'https://otro-origen.example' }, expected: [403],
  }));
  await test('No es posible cambiar la contraseña con la clave actual incorrecta', () => invalid('/auth/password', {
    actual: 'incorrecta_para_comprobacion', nueva: 'ContrasenaNuevaQA_123456', confirmacion: 'ContrasenaNuevaQA_123456',
  }, [400]));
}

async function readOnly() {
  console.log('Comprobando catálogos, listas, permisos y búsquedas de los tres roles.');
  for (const role of ['ADMIN', 'DOCENTE', 'CAJA']) {
    const catalogue = await test(`Metadatos de módulos ${role}`, async () => {
      const result = await get('/catalogo', role);
      assert.ok(Array.isArray(result.modules) && result.modules.length > 0);
      assert.equal(new Set(result.modules.map(module => module.key)).size, result.modules.length);
      for (const module of result.modules) {
        assert.ok(module.key && module.title && Array.isArray(module.fields));
        assert.ok(module.roles.includes(role));
      }
      return result.modules;
    });
    if (!catalogue) continue;
    metadata.set(role, catalogue);
    await mapLimit(catalogue, module => test(`Lista ${role}: ${module.key}`, async () => {
      const result = await get(`/datos/${module.key}?pageSize=2`, role);
      assert.ok(Array.isArray(result.rows) && Array.isArray(result.columns));
      assert.ok(Number.isInteger(result.total) && result.total >= 0);
      assert.ok(result.rows.length <= 2 && result.page >= 1);
      assert.ok(!result.rows.some(row => 'password_hash' in row));
    }));
    const sources = [...new Set(catalogue.filter(module => !module.readonly).flatMap(module => module.fields.map(field => field.source).filter(Boolean)))];
    await mapLimit(sources, source => test(`Opciones ${role}: ${source}`, async () => {
      const options = await get(`/opciones/${source}`, role);
      assert.ok(Array.isArray(options));
      for (const option of options) assert.ok(option.id && typeof option.label === 'string');
    }));
    await test(`Panel por gestión ${role}`, async () => {
      const result = await get('/dashboard?periodo_id=1', role);
      assert.ok(Array.isArray(result.kpis) && Array.isArray(result.grupos));
      assert.ok(result.kpis.every(kpi => Number.isFinite(Number(kpi.value))));
      assert.ok(result.catalogo.estudiantes >= 1000 && result.catalogo.docentes >= 80 && result.catalogo.carreras >= 12);
    });
  }
  for (const [module, minimum] of [['estudiantes', 1000], ['docentes', 80], ['carreras', 12], ['grupos', 4]]) {
    await test(`Catálogo inicial: al menos ${minimum} ${module}`, async () => assert.ok((await get(`/datos/${module}?pageSize=1`)).total >= minimum));
  }
  await test('La paginación de estudiantes no repite filas', async () => {
    const [first, second] = await Promise.all([get('/datos/estudiantes?page=1&pageSize=13'), get('/datos/estudiantes?page=2&pageSize=13')]);
    assert.equal(first.rows.length, 13); assert.equal(second.rows.length, 13);
    assert.equal(first.total, second.total);
    assert.ok(!second.rows.some(row => first.rows.some(previous => previous.id === row.id)));
  });
  await test('La búsqueda encuentra un registro exacto', async () => {
    const first = (await get('/datos/estudiantes?pageSize=1')).rows[0];
    const found = await get(`/datos/estudiantes${qs({ q: first.registro })}`);
    assert.ok(found.rows.some(row => row.id === first.id));
  });
  await test('La búsqueda escapa comodines y trata el texto como datos', async () => {
    const result = await get(`/datos/estudiantes${qs({ q: "' OR 1=1 -- %_" })}`);
    assert.equal(result.total, 0);
  });
  await test('Una página inválida se rechaza', () => request('/datos/estudiantes?page=-1', { expected: [400] }));
  await test('Un módulo inexistente devuelve 404', () => request('/datos/no_existe', { expected: [404] }));
  await test('Docente sin acceso al catálogo completo de estudiantes', () => request('/datos/estudiantes', { role: 'DOCENTE', expected: [403] }));
  await test('Docente sin acceso a administración de usuarios', () => request('/datos/usuarios', { role: 'DOCENTE', expected: [403] }));
  await test('Caja sin acceso a calificaciones', () => request('/datos/notas', { role: 'CAJA', expected: [403] }));
  await test('Caja sin acceso a administración de usuarios', () => request('/datos/usuarios', { role: 'CAJA', expected: [403] }));
  await test('Docente consulta únicamente ofertas asignadas', async () => {
    const offers = await get('/opciones/ofertas', 'DOCENTE');
    assert.ok(offers.length > 0 && offers.every(offer => offer.docente_id === users.get('DOCENTE').docente_id));
  });
  await test('La administración no puede desactivar su propio acceso', () => patch(`/datos/usuarios/${users.get('ADMIN').id}`, { activo: 0 }, 'ADMIN', [409]));
}

async function scenarios() {
  if (!writes) {
    results.push({ nombre: 'Escrituras aisladas en base de pruebas', estado: 'omitido', mensaje: 'Usar ITSC_API_URL=http://localhost:4002/api. La aplicación principal solo se consultó.' });
    return;
  }
  console.log('Comprobando procesos completos en la base de pruebas independiente.');
  const studentData = index => ({ registro: `QA${token}${index}`, documento: `QA-${token}-${index}`, nombres: `${prefix} ${index}`,
    apellidos: 'Estudiante de pruebas', fecha_nacimiento: '1970-03-15', telefono: '', correo: `qa.${token.toLowerCase()}.${index}@example.invalid`, direccion: 'Registro independiente de comprobación' });
  const studentA = await test('Crear estudiante de pruebas', () => create('estudiantes', studentData(1)));
  const studentB = await test('Crear segundo estudiante de pruebas', () => create('estudiantes', studentData(2)));
  if (!studentA || !studentB) throw new Error('No se pudieron preparar los estudiantes aislados; se omitió el resto de las escrituras.');
  await test('Consultar y editar estudiante', async () => {
    const original = await get(`/datos/estudiantes/${studentA.id}`); assert.equal(original.registro, studentData(1).registro);
    await patch(`/datos/estudiantes/${studentA.id}`, { ...studentData(1), nombres: `${prefix} actualizado` });
    assert.equal((await get(`/datos/estudiantes/${studentA.id}`)).nombres, `${prefix} actualizado`);
  });
  await test('No se duplica el documento ni el registro estudiantil', () => invalid('/datos/estudiantes', studentData(1), [409]));
  await test('No se acepta nacimiento futuro', () => invalid('/datos/estudiantes', { ...studentData(3), fecha_nacimiento: '2100-01-01' }, [400]));
  await test('No se acepta una fecha inexistente', () => invalid('/datos/estudiantes', { ...studentData(3), fecha_nacimiento: '2025-02-30' }, [400]));
  await test('No se acepta correo inválido', () => invalid('/datos/estudiantes', { ...studentData(3), correo: 'no-es-correo' }, [400]));

  const teacherData = { documento: `QA-D-${token}`, nombres: prefix, apellidos: 'Docente de pruebas', especialidad: 'Verificación académica', telefono: '', correo: `qa.docente.${token.toLowerCase()}@example.invalid` };
  const teacher = await test('Crear docente de pruebas', () => create('docentes', teacherData));
  if (!teacher) throw new Error('No se pudo preparar el docente de pruebas.');
  await test('Consultar y editar docente', async () => {
    await patch(`/datos/docentes/${teacher.id}`, { ...teacherData, especialidad: 'Verificación funcional' });
    assert.equal((await get(`/datos/docentes/${teacher.id}`)).especialidad, 'Verificación funcional');
  });
  const careerData = { codigo: `QA${token}`, nombre: `${prefix} Carrera de pruebas`, nivel: 'Técnico Superior', duracion_anios: 3,
    regimen: 'ANUAL', fuente_url: 'Prueba automatizada aislada, sin validez oficial.', activa: '1' };
  const career = await test('Crear carrera independiente', () => create('carreras', careerData));
  if (!career) throw new Error('No se pudo preparar la carrera independiente.');
  await test('Consultar y editar carrera', async () => {
    await patch(`/datos/carreras/${career.id}`, { ...careerData, nombre: `${prefix} Carrera verificada` });
    assert.equal((await get(`/datos/carreras/${career.id}`)).nombre, `${prefix} Carrera verificada`);
  });
  const courses = [];
  for (let index = 1; index <= 3; index++) {
    const subject = await test(`Crear materia de pruebas ${index}`, () => create('materias', {
      carrera_id: career.id, codigo: `QA-${token}-${index}`, nombre: `${prefix} Materia ${index}`, nivel_curso: 1, horas_semanales: 4, fuente_url: 'Prueba aislada de funcionamiento.',
    }));
    if (subject) courses.push(subject);
  }
  assert.equal(courses.length, 3, 'Faltan materias de prueba.');
  await test('Consultar y editar materia', async () => {
    const detail = await get(`/datos/materias/${courses[0].id}`);
    await patch(`/datos/materias/${courses[0].id}`, { ...detail, nombre: `${prefix} Materia actualizada` });
    assert.equal((await get(`/datos/materias/${courses[0].id}`)).nombre, `${prefix} Materia actualizada`);
  });
  const rules = await get('/opciones/reglas');
  const planData = { carrera_id: career.id, denominacion: `${prefix} Plan de pruebas`, cohorte: prefix, regla_id: rules[0].id };
  const plan = await test('Crear plan independiente', () => create('planes', planData));
  if (!plan) throw new Error('No se pudo preparar el plan de pruebas.');
  await test('Consultar y editar plan', async () => {
    await patch(`/datos/planes/${plan.id}`, { ...planData, denominacion: `${prefix} Plan verificado` });
    assert.equal((await get(`/datos/planes/${plan.id}`)).denominacion, `${prefix} Plan verificado`);
  });
  for (const subject of courses) await test(`Vincular materia ${subject.id} al plan`, () => post('/datos/plan_materias', { plan_id: plan.id, materia_id: subject.id }));
  await test('Un prerrequisito no puede apuntar a sí mismo', () => invalid('/datos/prerrequisitos', { plan_id: plan.id, materia_id: courses[0].id, requerida_id: courses[0].id }, [400]));
  await test('Crear prerrequisito válido', () => post('/datos/prerrequisitos', { plan_id: plan.id, materia_id: courses[0].id, requerida_id: courses[1].id }));
  await test('No se permiten ciclos en prerrequisitos', () => invalid('/datos/prerrequisitos', { plan_id: plan.id, materia_id: courses[1].id, requerida_id: courses[0].id }, [400]));
  await test('Retirar el prerrequisito de prueba', () => request(`/datos/prerrequisitos/${plan.id}-${courses[0].id}-${courses[1].id}`, { method: 'DELETE' }));

  const periods = await allRows('periodos');
  const years = [];
  for (let year = 2025; year >= 1950 && years.length < 2; year--) {
    if (!periods.some(period => period.fecha_inicio.slice(0, 10) <= `${year}-12-31` && period.fecha_fin.slice(0, 10) >= `${year}-01-01`)) years.push(year);
  }
  assert.equal(years.length, 2, 'No hay dos gestiones históricas libres para aislar la prueba.');
  const periodData = { nombre: `${prefix}_A`, fecha_inicio: `${years[0]}-01-01`, fecha_fin: `${years[0]}-12-31` };
  const period = await test('Crear gestión independiente', () => create('periodos', periodData));
  const overlap = await test('Crear gestión superpuesta para verificar cruces', () => create('periodos', { nombre: `${prefix}_B`, fecha_inicio: `${years[0]}-06-01`, fecha_fin: `${years[0]}-12-31` }));
  const separate = await test('Crear gestión sin superposición de fechas', () => create('periodos', { nombre: `${prefix}_C`, fecha_inicio: `${years[1]}-01-01`, fecha_fin: `${years[1]}-12-31` }));
  if (!period || !overlap || !separate) throw new Error('No se pudieron preparar las gestiones de pruebas.');
  await test('Consultar y editar gestión vacía', async () => {
    await patch(`/datos/periodos/${period.id}`, { ...periodData, nombre: `${prefix}_EDIT` });
    assert.equal((await get(`/datos/periodos/${period.id}`)).nombre, `${prefix}_EDIT`);
  });
  await test('La gestión rechaza fechas invertidas', () => invalid('/datos/periodos', { nombre: `${prefix}_INVALIDA`, fecha_inicio: '2025-12-31', fecha_fin: '2025-01-01' }, [400]));
  const groupData = { periodo_id: period.id, carrera_id: career.id, curso: 1, paralelo: `Q${token.slice(-7)}`, turno: 'MAÑANA', cupo: 1, tutor_id: teacher.id, estado: 'ACTIVO' };
  const group = await test('Crear grupo por carrera y gestión', () => create('grupos', groupData));
  if (!group) throw new Error('No se pudo preparar el grupo de pruebas.');
  const teacherId = users.get('DOCENTE').docente_id;
  const offerData = { materia_id: courses[0].id, periodo_id: period.id, docente_id: teacherId, paralelo: groupData.paralelo, turno: 'MAÑANA', cupo: 1 };
  const offerA = await test('Crear oferta asignada al docente de demostración', () => create('ofertas', offerData));
  const offerB = await test('Crear oferta asignada a otro docente', () => create('ofertas', { ...offerData, materia_id: courses[1].id, docente_id: teacher.id }));
  const offerC = await test('Crear oferta independiente de cupo uno', () => create('ofertas', { ...offerData, materia_id: courses[2].id }));
  const offerOverlap = await test('Crear oferta en gestión superpuesta', () => create('ofertas', { ...offerData, periodo_id: overlap.id }));
  const offerSeparate = await test('Crear oferta en gestión separada', () => create('ofertas', { ...offerData, periodo_id: separate.id }));
  if (![offerA, offerB, offerC, offerOverlap, offerSeparate].every(Boolean)) throw new Error('Faltan ofertas de prueba.');
  for (const offer of [offerA, offerB]) await test(`Asignar oferta ${offer.id} al grupo`, () => post('/datos/grupo_materias', { grupo_id: group.id, oferta_id: offer.id }));
  const enrolmentData = { estudiante_id: studentA.id, plan_id: plan.id, periodo_id: period.id, fecha: `${years[0]}-02-02` };
  const enrollmentA = await test('Matricular estudiante A en su plan y gestión', () => create('matriculas', enrolmentData));
  const enrollmentB = await test('Matricular estudiante B en su plan y gestión', () => create('matriculas', { ...enrolmentData, estudiante_id: studentB.id }));
  const enrollmentOtherPeriod = await test('Matricular estudiante en gestión distinta', () => create('matriculas', { ...enrolmentData, estudiante_id: studentB.id, periodo_id: overlap.id }));
  const enrollmentOtherCareer = await test('Matricular estudiante en carrera distinta', () => create('matriculas', { ...enrolmentData, estudiante_id: studentB.id, plan_id: 1 }));
  if (![enrollmentA, enrollmentB, enrollmentOtherPeriod, enrollmentOtherCareer].every(Boolean)) throw new Error('Faltan matrículas de prueba.');
  await test('No se duplica una matrícula en la misma carrera y gestión', () => invalid('/datos/matriculas', enrolmentData, [409]));
  await test('Candidatos del grupo filtran carrera y gestión', async () => {
    const result = await get(`/grupos/${group.id}/candidatos`);
    assert.ok(result.rows.some(row => row.matricula_id === enrollmentA.id));
    assert.ok(result.rows.some(row => row.matricula_id === enrollmentB.id));
    assert.ok(!result.rows.some(row => [enrollmentOtherPeriod.id, enrollmentOtherCareer.id].includes(row.matricula_id)));
  });
  await test('No se asignan matrículas de otra carrera', () => invalid('/datos/integrantes', { grupo_id: group.id, matricula_id: enrollmentOtherCareer.id }, [400]));
  await test('No se asignan matrículas de otra gestión', () => invalid('/datos/integrantes', { grupo_id: group.id, matricula_id: enrollmentOtherPeriod.id }, [400]));
  await test('La inscripción directa requiere pertenencia al grupo', () => invalid('/datos/inscripciones', { matricula_id: enrollmentA.id, oferta_id: offerA.id, fecha: `${years[0]}-02-02` }, [400]));
  await test('La selección de inscripción grupal rechaza duplicados', () => invalid(`/grupos/${group.id}/inscribir`, { matricula_ids: [enrollmentA.id, enrollmentA.id] }, [400]));
  await test('El lote completo se revierte si incluye una matrícula de otra carrera', async () => {
    await invalid(`/grupos/${group.id}/inscribir`, { matricula_ids: [enrollmentA.id, enrollmentOtherCareer.id] });
    const candidates = await get(`/grupos/${group.id}/candidatos`);
    assert.equal(candidates.rows.find(row => row.matricula_id === enrollmentA.id)?.asignado, false);
  });
  await test('La inscripción por grupo crea integrante y dos materias', async () => {
    const result = await post(`/grupos/${group.id}/inscribir`, { matricula_ids: [enrollmentA.id] });
    assert.equal(result.integrantes_nuevos, 1); assert.equal(result.inscripciones_nuevas, 2);
  });
  await test('Repetir la inscripción por grupo es idempotente', async () => {
    const result = await post(`/grupos/${group.id}/inscribir`, { matricula_ids: [enrollmentA.id] });
    assert.equal(result.integrantes_nuevos, 0); assert.equal(result.inscripciones_nuevas, 0); assert.equal(result.existentes, 2);
  });
  await test('No se supera el cupo del grupo', () => invalid(`/grupos/${group.id}/inscribir`, { matricula_ids: [enrollmentB.id] }, [409]));
  await test('Se conserva el tamaño del grupo después de rechazar exceso de cupo', async () => {
    const result = await get(`/datos/integrantes${qs({ grupo_id: group.id })}`); assert.equal(result.total, 1);
  });
  const inscriptionA = (await get(`/opciones/inscripciones${qs({ oferta_id: offerA.id })}`)).find(row => row.matricula_id === enrollmentA.id);
  const inscriptionB = (await get(`/opciones/inscripciones${qs({ oferta_id: offerB.id })}`)).find(row => row.matricula_id === enrollmentA.id);
  assert.ok(inscriptionA && inscriptionB, 'No aparecen las inscripciones creadas por el grupo.');
  await test('Inscripción individual válida en una oferta independiente', () => create('inscripciones', { matricula_id: enrollmentA.id, oferta_id: offerC.id, fecha: `${years[0]}-02-02` }));
  await test('No se supera el cupo de una oferta', () => invalid('/datos/inscripciones', { matricula_id: enrollmentB.id, oferta_id: offerC.id, fecha: `${years[0]}-02-02` }, [409]));
  await test('No se puede retirar del grupo una matrícula con inscripciones', async () => {
    const row = (await get(`/datos/integrantes${qs({ grupo_id: group.id })}`)).rows[0];
    await request(`/datos/integrantes/${row.id}`, { method: 'DELETE', expected: [409] });
  });
  await test('No se retira una materia del plan con inscripciones existentes', () => request(`/datos/plan_materias/${plan.id}-${courses[0].id}`, { method: 'DELETE', expected: [409] }));

  const roomA = await test('Crear aula de pruebas', () => create('aulas', { codigo: `QA${token}A`, capacidad: 2 }));
  const roomB = await test('Crear segunda aula de pruebas', () => create('aulas', { codigo: `QA${token}B`, capacidad: 2 }));
  if (!roomA || !roomB) throw new Error('No se pudieron preparar las aulas de prueba.');
  const scheduleData = { oferta_id: offerA.id, aula_id: roomA.id, dia: 1, hora_inicio: '08:00', hora_fin: '10:00' };
  const schedule = await test('Crear horario válido', () => create('horarios', scheduleData));
  await test('No se admite un horario con horas invertidas', () => invalid('/datos/horarios', { ...scheduleData, hora_inicio: '10:00', hora_fin: '08:00' }, [400]));
  await test('No se permite cruce de aula', () => invalid('/datos/horarios', { ...scheduleData, oferta_id: offerB.id, hora_inicio: '09:00', hora_fin: '10:30' }, [409]));
  await test('No se permite cruce de grupo usando otra aula y docente', () => invalid('/datos/horarios', { ...scheduleData, oferta_id: offerB.id, aula_id: roomB.id, hora_inicio: '09:00', hora_fin: '10:30' }, [409]));
  await test('No se permite cruce de docente', () => invalid('/datos/horarios', { ...scheduleData, oferta_id: offerC.id, aula_id: roomB.id, hora_inicio: '09:00', hora_fin: '10:30' }, [409]));
  await test('No se permiten cruces entre gestiones con fechas superpuestas', () => invalid('/datos/horarios', { ...scheduleData, oferta_id: offerOverlap.id, aula_id: roomB.id, hora_inicio: '09:00', hora_fin: '10:30' }, [409]));
  const adjacent = await test('Se permiten intervalos contiguos del mismo grupo', () => create('horarios', { ...scheduleData, oferta_id: offerB.id, aula_id: roomB.id, hora_inicio: '10:00', hora_fin: '11:00' }));
  const separateSchedule = await test('Se permite el mismo horario en una gestión sin fechas superpuestas', () => create('horarios', { ...scheduleData, oferta_id: offerSeparate.id }));
  if (schedule) await test('Consultar y editar horario manteniendo validez', async () => {
    const detail = await get(`/datos/horarios/${schedule.id}`); assert.equal(detail.hora_inicio, '08:00');
    await patch(`/datos/horarios/${schedule.id}`, { ...scheduleData, hora_fin: '09:50' });
    assert.equal((await get(`/datos/horarios/${schedule.id}`)).hora_fin, '09:50');
  });
  await test('La gestión con horarios no permite cambiar sus fechas', () => patch(`/datos/periodos/${period.id}`, { ...periodData, fecha_fin: `${years[0]}-11-30` }, 'ADMIN', [409]));
  await test('El aula debe tener capacidad suficiente', async () => {
    const bigOffer = await create('ofertas', { ...offerData, paralelo: `B${token.slice(-7)}`, cupo: 3 });
    await invalid('/datos/horarios', { ...scheduleData, oferta_id: bigOffer.id, dia: 5 }, [400]);
  });

  const evaluationA = await test('Crear evaluación práctica con peso completo', () => create('evaluaciones', { oferta_id: offerA.id, nombre: `${prefix} Práctica`, componente: 'PRACTICA', peso: 100 }, 'DOCENTE'));
  const evaluationTheory = await test('Crear evaluación teórica con peso completo', () => create('evaluaciones', { oferta_id: offerA.id, nombre: `${prefix} Teoría`, componente: 'TEORIA', peso: 100 }, 'DOCENTE'));
  const evaluationB = await test('Crear evaluación de otra oferta', () => create('evaluaciones', { oferta_id: offerB.id, nombre: `${prefix} Otra oferta`, componente: 'PRACTICA', peso: 100 }));
  if (!evaluationA || !evaluationTheory || !evaluationB) throw new Error('Faltan evaluaciones aisladas.');
  await test('Los pesos no pueden superar 100 por componente', () => invalid('/datos/evaluaciones', { oferta_id: offerA.id, nombre: `${prefix} Exceso`, componente: 'PRACTICA', peso: 1 }, [400]));
  await test('La nota mínima es uno', () => invalid('/datos/notas', { inscripcion_id: inscriptionA.id, evaluacion_id: evaluationA.id, nota: 0 }, [400]));
  await test('La nota máxima es cien', () => invalid('/datos/notas', { inscripcion_id: inscriptionA.id, evaluacion_id: evaluationA.id, nota: 101 }, [400]));
  await test('No se mezcla una evaluación de otra oferta', () => invalid('/datos/notas', { inscripcion_id: inscriptionA.id, evaluacion_id: evaluationB.id, nota: 80 }, [400]));
  await test('Docente guarda una nota de su materia', () => post('/datos/notas', { inscripcion_id: inscriptionA.id, evaluacion_id: evaluationA.id, nota: 50 }, 'DOCENTE'));
  await test('Docente no puede consultar detalle de oferta ajena', () => request(`/datos/ofertas/${offerB.id}`, { role: 'DOCENTE', expected: [403] }));
  await test('Docente no puede registrar notas de oferta ajena', () => invalid('/datos/notas', { inscripcion_id: inscriptionB.id, evaluacion_id: evaluationB.id, nota: 80 }, [403], 'DOCENTE'));
  await test('Docente no puede abrir una planilla ajena', () => request(`/planillas${qs({ tipo: 'notas', oferta_id: offerB.id, evaluacion_id: evaluationB.id })}`, { role: 'DOCENTE', expected: [403] }));
  await test('Caja no puede guardar una nota', () => invalid('/datos/notas', { inscripcion_id: inscriptionA.id, evaluacion_id: evaluationA.id, nota: 90 }, [403], 'CAJA'));
  const sessionData = { oferta_id: offerA.id, inicio: `${years[0]}-07-20T08:00`, fin: `${years[0]}-07-20T10:00` };
  await test('Una sesión requiere duración positiva', () => invalid('/datos/sesiones', { ...sessionData, fin: `${years[0]}-07-20T07:00` }, [400]));
  const session = await test('Registrar sesión de clase realizada', () => create('sesiones', sessionData, 'DOCENTE'));
  if (!session) throw new Error('No se pudo preparar la sesión de pruebas.');
  await test('Asistencia no puede superar minutos de la sesión', () => invalid('/datos/asistencias', { inscripcion_id: inscriptionA.id, sesion_id: session.id, minutos_presentes: 121 }, [400]));
  await test('Asistencia no acepta minutos negativos', () => invalid('/datos/asistencias', { inscripcion_id: inscriptionA.id, sesion_id: session.id, minutos_presentes: -1 }, [400]));
  await test('Asistencia no acepta fracciones de minuto', () => invalid('/datos/asistencias', { inscripcion_id: inscriptionA.id, sesion_id: session.id, minutos_presentes: 1.5 }, [400]));
  await test('Registrar asistencia de la sesión propia', () => post('/datos/asistencias', { inscripcion_id: inscriptionA.id, sesion_id: session.id, minutos_presentes: 120 }, 'DOCENTE'));
  await test('Consultar planilla de asistencia con límite de minutos', async () => {
    const roster = await get(`/planillas${qs({ tipo: 'asistencias', oferta_id: offerA.id, sesion_id: session.id })}`, 'DOCENTE');
    assert.equal(roster.max, 120); assert.equal(roster.rows.length, 1); assert.equal(Number(roster.rows[0].valor), 120);
  });
  await test('Una planilla mixta inválida se revierte de forma atómica', async () => {
    await invalid('/planillas', { tipo: 'notas', oferta_id: offerA.id, evaluacion_id: evaluationA.id,
      registros: [{ inscripcion_id: inscriptionA.id, valor: 99 }, { inscripcion_id: inscriptionB.id, valor: 70 }] }, [400]);
    const roster = await get(`/planillas${qs({ tipo: 'notas', oferta_id: offerA.id, evaluacion_id: evaluationA.id })}`);
    assert.equal(Number(roster.rows[0].valor), 50);
  });
  await test('La planilla conserva filas dejadas en blanco', async () => {
    const result = await post('/planillas', { tipo: 'notas', oferta_id: offerA.id, evaluacion_id: evaluationA.id,
      registros: [{ inscripcion_id: inscriptionA.id, valor: 50 }, { inscripcion_id: inscriptionB.id, valor: '' }] }, 'DOCENTE');
    assert.equal(result.guardados, 1);
  });
  await test('No se cierra una oferta con notas pendientes', () => invalid('/datos/cierres', { oferta_id: offerA.id, minutos_carga: 120 }, [409]));
  await test('Registrar calificación teórica pendiente', () => post('/datos/notas', { inscripcion_id: inscriptionA.id, evaluacion_id: evaluationTheory.id, nota: 60 }, 'DOCENTE'));
  await test('El cierre requiere carga igual a sesiones realizadas', () => invalid('/datos/cierres', { oferta_id: offerA.id, minutos_carga: 119 }, [400]));
  await test('Cerrar oferta completa y calcular resultados', async () => {
    const result = await post('/datos/cierres', { oferta_id: offerA.id, minutos_carga: 120 });
    assert.equal(result.data.resultados, 1);
    const bulletin = await get(`/datos/boletin${qs({ periodo_id: period.id, carrera_id: career.id })}`);
    const row = bulletin.rows.find(row => row.inscripcion_id === inscriptionA.id);
    assert.ok(row); assert.equal(Number(row.promedio), 53); assert.equal(Number(row.porcentaje_asistencia), 100); assert.equal(row.resultado, 'REPROBADO');
  });
  await test('El cierre bloquea modificaciones de notas', () => invalid('/datos/notas', { inscripcion_id: inscriptionA.id, evaluacion_id: evaluationA.id, nota: 95 }, [409]));
  await test('El cierre bloquea nuevas sesiones', () => invalid('/datos/sesiones', { ...sessionData, inicio: `${years[0]}-07-21T08:00`, fin: `${years[0]}-07-21T10:00` }, [409]));
  await test('La planilla cerrada se muestra no editable', async () => assert.equal((await get(`/planillas${qs({ tipo: 'notas', oferta_id: offerA.id, evaluacion_id: evaluationA.id })}`)).editable, false));
  await test('La recuperación rechaza notas fuera de rango', () => invalid('/datos/recuperaciones', { inscripcion_id: inscriptionA.id, nota_prueba: 101, fecha: `${years[0]}-11-30` }, [400]));
  await test('La recuperación requiere resultado académico habilitado', () => invalid('/datos/recuperaciones', { inscripcion_id: inscriptionB.id, nota_prueba: 80, fecha: `${years[0]}-11-30` }, [400]));
  await test('Recuperación aprobada registra 61 y actualiza el boletín', async () => {
    const result = await post('/datos/recuperaciones', { inscripcion_id: inscriptionA.id, nota_prueba: 90, fecha: `${years[0]}-11-30` });
    assert.equal(Number(result.data.nota_registrada), 61);
    const row = (await get(`/datos/boletin${qs({ periodo_id: period.id, carrera_id: career.id })}`)).rows.find(row => row.inscripcion_id === inscriptionA.id);
    assert.equal(Number(row.nota_final), 61); assert.equal(row.resultado, 'APROBADO_RECUPERACION');
  });
  await test('No se duplica una recuperación definitiva', () => invalid('/datos/recuperaciones', { inscripcion_id: inscriptionA.id, nota_prueba: 92, fecha: `${years[0]}-11-30` }, [409]));

  await test('Los cargos requieren importe positivo', () => invalid('/datos/cargos', { matricula_id: enrollmentA.id, concepto: prefix, monto: 0, vencimiento: `${years[0]}-11-15` }, [400]));
  const charge = await test('Caja registra cargo propio de pruebas', () => create('cargos', { matricula_id: enrollmentA.id, concepto: `${prefix} Cargo ficticio`, monto: 100, vencimiento: `${years[0]}-11-15` }, 'CAJA'));
  if (!charge) throw new Error('No se pudo preparar el cargo de prueba.');
  const paymentData = { cargo_id: charge.id, recibo: `QA-${token}-1`, fecha: `${years[0]}-10-30`, monto: 40.25, metodo: 'QR' };
  await test('Se rechaza el sobrepago', () => invalid('/datos/pagos', { ...paymentData, monto: 100.01 }, [400], 'CAJA'));
  await test('Se rechaza pago de importe cero', () => invalid('/datos/pagos', { ...paymentData, monto: 0 }, [400], 'CAJA'));
  await test('Caja registra abono con decimales y saldo exacto', async () => {
    await create('pagos', paymentData, 'CAJA');
    const row = (await get(`/datos/saldos${qs({ periodo_id: period.id })}`, 'CAJA')).rows.find(row => row.cargo_id === charge.id);
    assert.equal(Number(row.pagado), 40.25); assert.equal(Number(row.saldo), 59.75);
  });
  await test('Caja liquida el saldo sin excederlo', async () => {
    await create('pagos', { ...paymentData, recibo: `QA-${token}-2`, monto: 59.75 }, 'CAJA');
    const row = (await get(`/datos/saldos${qs({ periodo_id: period.id })}`, 'CAJA')).rows.find(row => row.cargo_id === charge.id);
    assert.equal(Number(row.saldo), 0);
    assert.ok(!(await get(`/opciones/cargos${qs({ matricula_id: enrollmentA.id })}`, 'CAJA')).some(row => row.id === charge.id));
  });
  await test('No se pueden seguir abonando cargos liquidados', () => invalid('/datos/pagos', { ...paymentData, recibo: `QA-${token}-3`, monto: 0.01 }, [400], 'CAJA'));
  await test('Los números de recibo son únicos', async () => {
    const anotherCharge = await create('cargos', { matricula_id: enrollmentA.id, concepto: `${prefix} Segundo cargo ficticio`, monto: 10, vencimiento: `${years[0]}-11-15` });
    await invalid('/datos/pagos', { ...paymentData, cargo_id: anotherCharge.id, monto: 1 }, [409]);
  });
  await test('Se actualiza documentación sin duplicar el documento', async () => {
    const types = await get('/opciones/tipos_documento');
    const data = { matricula_id: enrollmentA.id, tipo_documento_id: types[0].id, estado: 'PENDIENTE', observacion: prefix };
    const first = await post('/datos/documentos', data);
    const second = await post('/datos/documentos', { ...data, estado: 'RECIBIDO' });
    assert.equal(first.data.id, second.data.id); assert.ok(second.data.fecha_recepcion);
  });
  await test('Registrar y editar trámite de prueba', async () => {
    const data = { matricula_id: enrollmentA.id, tipo: 'OTRO', fecha: `${years[0]}-10-30`, estado: 'SOLICITADO', detalle: prefix };
    const row = await create('tramites', data); await patch(`/datos/tramites/${row.id}`, { ...data, estado: 'EN_REVISION' });
    assert.equal((await get(`/datos/tramites/${row.id}`)).estado, 'EN_REVISION');
  });
  await test('La pasantía rechaza fechas invertidas', () => invalid('/datos/pasantias', { matricula_id: enrollmentA.id, tutor_id: teacher.id,
    empresa: prefix, fecha_inicio: `${years[0]}-10-30`, fecha_fin: `${years[0]}-09-30`, horas: 10, estado: 'EN_CURSO' }, [400]));
  await test('Registrar pasantía ficticia', () => create('pasantias', { matricula_id: enrollmentA.id, tutor_id: teacher.id,
    empresa: `${prefix} Empresa ficticia`, fecha_inicio: `${years[0]}-09-01`, fecha_fin: `${years[0]}-09-30`, horas: 120, estado: 'CONCLUIDA' }));

  for (const row of [adjacent, separateSchedule].filter(Boolean)) await test(`Retirar horario independiente ${row.id}`, () => request(`/datos/horarios/${row.id}`, { method: 'DELETE' }));
  await test('Cerrar el grupo propio de pruebas', () => patch(`/datos/grupos/${group.id}`, { ...groupData, estado: 'CERRADO' }));
  await test('Un grupo cerrado no admite inscripción en lote', () => invalid(`/grupos/${group.id}/inscribir`, { matricula_ids: [enrollmentB.id] }, [409]));
  await test('La auditoría contiene las operaciones de comprobación', async () => {
    const audit = await get('/datos/auditoria?pageSize=100');
    assert.ok(audit.rows.some(row => ['GUARDAR', 'EDITAR', 'INSCRIBIR_GRUPO', 'GUARDAR_PLANILLA'].includes(row.accion)));
  });
}

async function reports() {
  console.log('Comprobando exportaciones PDF y XLSX y sus permisos.');
  const allowed = { ADMIN: ['matriculas', 'notas', 'asistencias', 'saldos', 'grupos', 'horarios', 'boletin', 'estudiantes', 'docentes'],
    DOCENTE: ['notas', 'asistencias', 'horarios', 'boletin'], CAJA: ['saldos', 'estudiantes'] };
  for (const [role, types] of Object.entries(allowed)) {
    await mapLimit(types.flatMap(tipo => ['pdf', 'xlsx'].map(formato => ({ tipo, formato }))), ({ tipo, formato }) =>
      test(`Reporte ${role}: ${tipo}.${formato}`, async () => {
        const response = await request(`/reportes${qs({ tipo, formato, ...(tipo === 'estudiantes' ? {} : { periodo_id: 1 }) })}`, { role });
        if (formato === 'pdf') {
          assert.equal(response.bytes.subarray(0, 5).toString('ascii'), '%PDF-');
          assert.ok(response.bytes.includes(Buffer.from('%%EOF')));
          assert.ok(response.headers.get('content-type')?.includes('application/pdf'));
        } else {
          assert.equal(response.bytes.subarray(0, 4).toString('hex'), '504b0304');
          assert.ok(response.bytes.includes(Buffer.from('[Content_Types].xml')) && response.bytes.includes(Buffer.from('xl/workbook.xml')));
          assert.ok(response.headers.get('content-type')?.includes('spreadsheetml'));
        }
        assert.ok(response.headers.get('content-disposition')?.includes(`.${formato}`));
      }), 2);
  }
  await test('No se exporta un tipo de reporte inexistente', () => request('/reportes?tipo=inexistente&formato=pdf', { expected: [400] }));
  await test('No se exporta un formato inexistente', () => request('/reportes?tipo=estudiantes&formato=csv', { expected: [400] }));
  await test('No se exportan filtros de gestión inválidos', () => request('/reportes?tipo=estudiantes&formato=pdf&periodo_id=no-numero', { expected: [400] }));
  await test('Docente no exporta datos de caja', () => request('/reportes?tipo=saldos&formato=xlsx', { role: 'DOCENTE', expected: [403] }));
  await test('Caja no exporta calificaciones', () => request('/reportes?tipo=notas&formato=pdf', { role: 'CAJA', expected: [403] }));
}

async function finish() {
  for (const role of ['DOCENTE', 'CAJA', 'ADMIN']) {
    if (!sessions.has(role)) continue;
    await test(`Cerrar sesión ${role}`, () => post('/auth/logout', undefined, role));
    sessions.delete(role);
    await test(`Sesión ${role} cerrada en el cliente`, () => request('/auth/me', { role, expected: [401] }));
  }
}

try {
  credentials = JSON.parse(await readFile(privateFile, 'utf8'));
  assert.ok(Array.isArray(credentials.accesos), 'El archivo privado no tiene el formato esperado de accesos.');
  secrets.push(...credentials.accesos.map(account => account.contrasena ?? account.password).filter(Boolean));
  await authentication();
  if (sessions.size !== 3) throw new Error('No se obtuvieron las tres sesiones necesarias para continuar.');
  await readOnly();
  try { await scenarios(); } catch (error) { await test('Preparación de escenarios independientes', () => { throw error; }); }
  await reports();
  await finish();
} catch (error) {
  results.push({ nombre: 'Preparación de la comprobación', estado: 'fallo', mensaje: redact(error?.message || error) });
}
const summary = { fecha_utc: new Date().toISOString(), api, solo_lectura: !writes, prefijo_datos_prueba: writes ? prefix : null,
  duracion_segundos: Number(((Date.now() - began) / 1000).toFixed(2)), total: results.length,
  correctas: results.filter(test => test.estado === 'correcto').length,
  fallos: results.filter(test => test.estado === 'fallo').length,
  omitidas: results.filter(test => test.estado === 'omitido').length,
  registros_creados_en_base_pruebas: created, pruebas: results };
await mkdir(join(root, '.local'), { recursive: true });
await writeFile(join(root, '.local', 'pruebas-integracion.json'), JSON.stringify(summary, null, 2), 'utf8');
console.log(JSON.stringify({ total: summary.total, correctas: summary.correctas, fallos: summary.fallos, omitidas: summary.omitidas,
  duracion_segundos: summary.duracion_segundos, informe: '.local/pruebas-integracion.json' }));
for (const result of results.filter(test => test.estado === 'fallo')) console.error(`${result.nombre}: ${result.mensaje}`);
if (summary.fallos) process.exitCode = 1;
