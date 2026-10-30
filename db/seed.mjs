import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

// Only the new PostgreSQL URL is used. The old application is never opened.
if (!process.env.DATABASE_URL) throw new Error('Falta DATABASE_URL para la base PostgreSQL nueva.');
const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter });
const catalogue = JSON.parse(await readFile(new URL('./catalogo-demo.json', import.meta.url), 'utf8'));
const metadata = JSON.parse(await readFile(new URL('./schema-metadata.json', import.meta.url), 'utf8'));
const seedMarker = 'DEMO ITSC PostgreSQL - RM0189/2023';
const date = value => new Date(value.length === 10 ? `${value}T00:00:00.000Z` : value);
const time = value => new Date(`1970-01-01T${value}:00.000Z`);

function typedRows(table, rows) {
  const dates = metadata[table].fields.filter(f => f.prisma_type === 'DateTime').map(f => f.name);
  return rows.map(row => Object.fromEntries(Object.entries(row).map(([key, value]) =>
    [key, value !== null && dates.includes(key) ? date(value.replace(' ', 'T') + (value.includes(' ') ? 'Z' : '')) : value])));
}

async function seed() {
  const existing = await prisma.estudiantes.count();
  const marker = await prisma.reglas_evaluacion.findUnique({ where: { id: 1 } });
  if (marker?.nombre === seedMarker) {
    console.log(JSON.stringify({ estado: 'sin_cambios', motivo: 'La demostración ya estaba instalada; se conservaron todos los registros existentes.' }));
    return;
  }
  const otherData = await Promise.all(['docentes', 'carreras', 'materias', 'matriculas', 'periodos'].map(table => prisma[table].count()));
  if (existing || otherData.some(Boolean) || marker) {
    throw new Error('La base contiene datos ajenos a esta demostración. No se modificó ni se reemplazó ningún registro.');
  }

  const result = await prisma.$transaction(async tx => {
    await tx.reglas_evaluacion.create({ data: {
      id: 1, nombre: seedMarker,
      fuente: 'Referencia del práctico: R.M.0189/2023, artículos13–18. Reglas conservadas del sistema académico de demostración.',
    } });
    await tx.estudiantes.createMany({ data: typedRows('estudiantes', catalogue.estudiantes) });
    await tx.docentes.createMany({ data: typedRows('docentes', catalogue.docentes) });
    await tx.carreras.createMany({ data: catalogue.carreras });

    const subjects = [...catalogue.materias];
    let nextSubjectId = Math.max(...subjects.map(subject => subject.id)) + 1;
    // Four additional careers are expressly marked as demonstration data.
    const extraSubjects = {
      9: ['Fundamentos de redes', 'Sistemas operativos', 'Matemática aplicada', 'Redes locales', 'Administración de servidores', 'Seguridad de redes'],
      10: ['Dibujo y composición', 'Diseño digital', 'Comunicación visual', 'Identidad gráfica', 'Diseño editorial', 'Producción multimedia'],
      11: ['Administración general', 'Contabilidad básica', 'Matemática financiera', 'Gestión de personal', 'Mercadotecnia', 'Emprendimiento'],
      12: ['Fundamentos de electricidad', 'Energía y medio ambiente', 'Matemática técnica', 'Sistemas fotovoltaicos', 'Energía eólica', 'Eficiencia energética'],
    };
    for (const [careerId, names] of Object.entries(extraSubjects)) {
      names.forEach((name, index) => subjects.push({
        id: nextSubjectId++, carrera_id: Number(careerId), codigo: `DEMO-${careerId}-${index + 1}`,
        nombre: `${name} (demostración)`, nivel_curso: index < 3 ? 1 : 2,
        horas_semanales: 4, fuente_url: 'Datos ficticios del práctico; no representan un plan oficial.',
      }));
    }
    await tx.materias.createMany({ data: subjects });
    await tx.planes_estudio.createMany({ data: catalogue.carreras.map(career => ({
      id: career.id, carrera_id: career.id,
      denominacion: career.id > 8 ? 'Plan completo de demostración académica' : 'Catálogo del práctico - cohorte de demostración',
      cohorte: 'DEMO-2026', regla_id: 1,
    })) });
    await tx.plan_materias.createMany({ data: subjects.map(subject => ({
      plan_id: subject.carrera_id, materia_id: subject.id, carrera_id: subject.carrera_id,
    })) });
    await tx.periodos.createMany({ data: [
      { id: 1, nombre: 'GESTIÓN 2026', fecha_inicio: date('2026-02-02'), fecha_fin: date('2026-11-30') },
      { id: 2, nombre: 'GESTIÓN 2027', fecha_inicio: date('2027-02-01'), fecha_fin: date('2027-11-30') },
    ] });
    await tx.aulas.createMany({ data: [
      { id: 1, codigo: 'AULA-101', capacidad: 40 },
      { id: 2, codigo: 'AULA-102', capacidad: 35 },
      { id: 3, codigo: 'LAB-SISTEMAS', capacidad: 35 },
      { id: 4, codigo: 'LAB-ELECTRICIDAD', capacidad: 30 },
    ] });
    const groups = [
      { id: 1, periodo_id: 1, carrera_id: 1, curso: 1, paralelo: 'A', turno: 'MAÑANA', cupo: 35, tutor_id: 1, estado: 'ACTIVO' },
      { id: 2, periodo_id: 1, carrera_id: 2, curso: 1, paralelo: 'A', turno: 'NOCHE', cupo: 30, tutor_id: 2, estado: 'ACTIVO' },
      { id: 3, periodo_id: 2, carrera_id: 1, curso: 1, paralelo: 'A', turno: 'MAÑANA', cupo: 35, tutor_id: 1, estado: 'ACTIVO' },
      { id: 4, periodo_id: 2, carrera_id: 3, curso: 1, paralelo: 'B', turno: 'TARDE', cupo: 25, tutor_id: 3, estado: 'ACTIVO' },
    ];
    await tx.grupos.createMany({ data: groups });
    const offers = [], groupSubjects = [], schedules = [];
    for (const group of groups) {
      const groupCourses = subjects.filter(subject => subject.carrera_id === group.carrera_id && subject.nivel_curso === 1).slice(0, 3);
      for (let index = 0; index < groupCourses.length; index++) {
        const offerId = offers.length + 1;
        offers.push({ id: offerId, materia_id: groupCourses[index].id, carrera_id: group.carrera_id,
          periodo_id: group.periodo_id, docente_id: (group.carrera_id - 1) * 3 + index + 1,
          paralelo: group.paralelo, turno: group.turno, cupo: group.cupo });
        groupSubjects.push({ id: offerId, grupo_id: group.id, oferta_id: offerId });
        const start = group.turno === 'NOCHE' ? '19:00' : group.turno === 'TARDE' ? '14:00' : '08:00';
        const end = group.turno === 'NOCHE' ? '20:40' : group.turno === 'TARDE' ? '15:40' : '09:40';
        schedules.push({ id: offerId, oferta_id: offerId, aula_id: group.id === 4 ? 4 : group.id === 2 ? 2 : 3,
          dia: index + 1, hora_inicio: time(start), hora_fin: time(end) });
      }
    }
    await tx.ofertas.createMany({ data: offers });
    await tx.grupo_materias.createMany({ data: groupSubjects });
    await tx.horarios.createMany({ data: schedules });
    const students = [...catalogue.estudiantes].sort((a, b) => a.id - b.id).slice(0, 50);
    const enrollments = students.map((student, index) => ({
      id: index + 1, estudiante_id: student.id, carrera_id: index < 30 ? 1 : 2,
      periodo_id: 1, fecha: date('2026-02-02'), estado: 'ACTIVA', plan_id: index < 30 ? 1 : 2,
    }));
    await tx.matriculas.createMany({ data: enrollments });
    await tx.grupo_integrantes.createMany({ data: enrollments.map(enrollment => ({
      id: enrollment.id, grupo_id: enrollment.carrera_id === 1 ? 1 : 2, matricula_id: enrollment.id,
    })) });
    const inscriptions = [];
    for (const enrollment of enrollments) {
      for (const offer of offers.filter(offer => offer.periodo_id === 1 && offer.carrera_id === enrollment.carrera_id)) {
        inscriptions.push({ id: inscriptions.length + 1, matricula_id: enrollment.id, oferta_id: offer.id,
          carrera_id: enrollment.carrera_id, periodo_id: 1, fecha: date('2026-02-02'), estado: 'ACTIVA' });
      }
    }
    await tx.inscripciones.createMany({ data: inscriptions });
    const evaluations = offers.flatMap(offer => [
      { id: offer.id * 2 - 1, oferta_id: offer.id, nombre: 'Práctica integral', componente: 'PRACTICA', peso: 100 },
      { id: offer.id * 2, oferta_id: offer.id, nombre: 'Evaluación teórica', componente: 'TEORIA', peso: 100 },
    ]);
    await tx.evaluaciones.createMany({ data: evaluations });
    const sessions = offers.filter(offer => offer.periodo_id === 1).map(offer => {
      const schedule = schedules.find(schedule => schedule.oferta_id === offer.id);
      const day = String(19 + schedule.dia).padStart(2, '0');
      return { id: offer.id, oferta_id: offer.id,
        inicio: date(`2026-07-${day}T${schedule.hora_inicio.toISOString().slice(11, 19)}Z`),
        fin: date(`2026-07-${day}T${schedule.hora_fin.toISOString().slice(11, 19)}Z`), estado: 'REALIZADA' };
    });
    await tx.sesiones.createMany({ data: sessions });
    const grades = [], attendance = [];
    for (const inscription of inscriptions) {
      const lowGrade = inscription.matricula_id === 1;
      for (const evaluation of evaluations.filter(evaluation => evaluation.oferta_id === inscription.oferta_id)) {
        grades.push({ inscripcion_id: inscription.id, evaluacion_id: evaluation.id, oferta_id: inscription.oferta_id,
          nota: lowGrade ? (evaluation.componente === 'PRACTICA' ? 50 : 60) : 65 + (inscription.matricula_id * 7 + evaluation.id) % 31 });
      }
      attendance.push({ inscripcion_id: inscription.id, sesion_id: inscription.oferta_id, oferta_id: inscription.oferta_id,
        minutos_presentes: inscription.matricula_id % 7 === 0 ? 80 : 100 });
    }
    await tx.calificaciones.createMany({ data: grades });
    await tx.asistencias_sesion.createMany({ data: attendance });
    await tx.cargos.createMany({ data: enrollments.map(enrollment => ({
      id: enrollment.id, matricula_id: enrollment.id,
      concepto: 'Matrícula y materiales (importe ficticio de demostración)', monto: 350, vencimiento: date('2026-11-15'),
    })) });
    await tx.pagos.createMany({ data: enrollments.slice(0, 20).map(enrollment => ({
      id: enrollment.id, cargo_id: enrollment.id, recibo: `DEMO-2026-${String(enrollment.id).padStart(4, '0')}`,
      fecha: date('2026-07-20'), monto: 100, metodo: enrollment.id % 2 ? 'EFECTIVO' : 'QR',
    })) });
    const documentTypes = ['Fotocopia diploma de bachiller', 'Fotocopia cédula de identidad', 'Fotocopia certificado de nacimiento',
      'Documento de tipo sanguíneo', 'Boletín de calificación', 'Carnet de estudiante'];
    await tx.tipos_documento.createMany({ data: documentTypes.map((nombre, index) => ({ id: index + 1, nombre })) });
    await tx.documentos_matricula.createMany({ data: enrollments.flatMap(enrollment => [1, 2].map(type => ({
      id: (enrollment.id - 1) * 2 + type, matricula_id: enrollment.id, tipo_documento_id: type,
      estado: type === 2 || enrollment.id % 3 !== 0 ? 'RECIBIDO' : 'PENDIENTE',
      fecha_recepcion: type === 2 || enrollment.id % 3 !== 0 ? date('2026-02-02') : null,
      observacion: 'Registro ficticio para el práctico.',
    }))) });
    await tx.tramites.createMany({ data: [
      { id: 1, matricula_id: 1, tipo: 'PRORROGA_DIPLOMA', fecha: date('2026-07-20'), estado: 'SOLICITADO', detalle: 'Solicitud ficticia de ampliación de plazo.' },
      { id: 2, matricula_id: 2, tipo: 'OTRO', fecha: date('2026-07-21'), estado: 'EN_REVISION', detalle: 'Solicitud ficticia de certificado de estudios.' },
    ] });
    await tx.pasantias.createMany({ data: [
      { id: 1, matricula_id: 1, tutor_id: 1, empresa: 'Tecnología Cruceña Demo S.R.L. (ficticia)',
        fecha_inicio: date('2026-08-03'), fecha_fin: date('2026-09-30'), horas: 160, estado: 'CONCLUIDA' },
      { id: 2, matricula_id: 31, tutor_id: 2, empresa: 'Consultora Contable Demo (ficticia)',
        fecha_inicio: date('2026-10-01'), fecha_fin: null, horas: 80, estado: 'EN_CURSO' },
    ] });
    const modalities = ['Proyecto de grado', 'Examen de grado', 'Proyecto sociocomunitario productivo',
      'Proyecto de emprendimiento productivo', 'Trabajo dirigido externo', 'Excelencia académica'];
    await tx.modalidades_graduacion.createMany({ data: modalities.map((nombre, index) => ({ id: index + 1, nombre })) });
    await tx.proyectos_graduacion.create({ data: { id: 1, matricula_id: 1, modalidad_id: 1, tutor_id: 1,
      titulo: 'Sistema de inventario para una empresa ficticia (demostración)', estado: 'PROPUESTO' } });

    // Keep generated IDs valid after importing the fictional catalogue IDs.
    for (const [table, spec] of Object.entries(metadata)) {
      if (spec.fields.some(field => field.name === 'id' && field.auto)) {
        await tx.$queryRawUnsafe(`SELECT setval(pg_get_serial_sequence('"${table}"','id'), coalesce((SELECT max(id) FROM "${table}"),0)+1, false)`);
      }
    }
    return { estudiantes: catalogue.estudiantes.length, docentes: catalogue.docentes.length, carreras: catalogue.carreras.length,
      materias: subjects.length, planes: catalogue.carreras.length, gestiones: 2, grupos: groups.length,
      matriculas: enrollments.length, inscripciones: inscriptions.length, ofertas: offers.length, calificaciones: grades.length };
  }, { maxWait: 10000, timeout: 120000 });
  console.log(JSON.stringify({ estado: 'demostracion_creada', ...result }));
}

try { await seed(); }
catch (error) { console.error(error instanceof Error ? error.message : 'No se pudo preparar la demostración.'); process.exitCode = 1; }
finally { await prisma.$disconnect(); }
