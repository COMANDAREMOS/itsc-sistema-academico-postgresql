import 'dotenv/config';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// All statements are static: no table names, SQL fragments or values received
// from HTTP are interpolated into this pipeline. Only schema dw is modified.
const dimensions = [
  `INSERT INTO dw.dim_gestion(gestion_id,nombre,fecha_inicio,fecha_fin)
   SELECT id,nombre,fecha_inicio,fecha_fin FROM public.periodos
   ON CONFLICT(gestion_id) DO UPDATE SET nombre=EXCLUDED.nombre,
     fecha_inicio=EXCLUDED.fecha_inicio,fecha_fin=EXCLUDED.fecha_fin`,
  `INSERT INTO dw.dim_carrera(carrera_id,codigo,nombre,nivel,regimen)
   SELECT id,codigo,nombre,nivel,regimen FROM public.carreras
   ON CONFLICT(carrera_id) DO UPDATE SET codigo=EXCLUDED.codigo,nombre=EXCLUDED.nombre,
     nivel=EXCLUDED.nivel,regimen=EXCLUDED.regimen`,
  `INSERT INTO dw.dim_estudiante(estudiante_id,registro,nombres,apellidos)
   SELECT id,registro,nombres,apellidos FROM public.estudiantes
   ON CONFLICT(estudiante_id) DO UPDATE SET registro=EXCLUDED.registro,
     nombres=EXCLUDED.nombres,apellidos=EXCLUDED.apellidos`,
  `INSERT INTO dw.dim_docente(docente_id,nombres,apellidos,especialidad)
   SELECT id,nombres,apellidos,especialidad FROM public.docentes
   ON CONFLICT(docente_id) DO UPDATE SET nombres=EXCLUDED.nombres,
     apellidos=EXCLUDED.apellidos,especialidad=EXCLUDED.especialidad`,
  `INSERT INTO dw.dim_materia(materia_id,carrera_id,codigo,nombre,nivel_curso)
   SELECT id,carrera_id,codigo,nombre,nivel_curso FROM public.materias
   ON CONFLICT(materia_id) DO UPDATE SET carrera_id=EXCLUDED.carrera_id,
     codigo=EXCLUDED.codigo,nombre=EXCLUDED.nombre,nivel_curso=EXCLUDED.nivel_curso`,
  `WITH limites AS (
     SELECT min(fecha)::date AS desde,max(fecha)::date AS hasta FROM (
       SELECT fecha_inicio AS fecha FROM public.periodos
       UNION ALL SELECT fecha_fin FROM public.periodos
       UNION ALL SELECT fecha FROM public.matriculas
       UNION ALL SELECT fecha FROM public.pagos
       UNION ALL SELECT fecha::date FROM public.resultados_finales
     ) origen
   ), dias AS (
     SELECT serie::date AS fecha FROM limites,
       LATERAL generate_series(desde,hasta,interval '1 day') serie
   )
   INSERT INTO dw.dim_tiempo(fecha,anio,mes,dia,trimestre,dia_semana,mes_nombre)
   SELECT fecha,extract(year FROM fecha)::integer,extract(month FROM fecha)::integer,
     extract(day FROM fecha)::integer,extract(quarter FROM fecha)::integer,
     extract(isodow FROM fecha)::integer,
     (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[extract(month FROM fecha)::integer]
   FROM dias
   ON CONFLICT(fecha) DO UPDATE SET anio=EXCLUDED.anio,mes=EXCLUDED.mes,
     dia=EXCLUDED.dia,trimestre=EXCLUDED.trimestre,dia_semana=EXCLUDED.dia_semana,
     mes_nombre=EXCLUDED.mes_nombre`,
];

const facts = [
  `INSERT INTO dw.fact_matriculas(matricula_id,gestion_id,carrera_id,estudiante_id,fecha,estado,cantidad)
   SELECT id,periodo_id,carrera_id,estudiante_id,fecha,estado,1 FROM public.matriculas
   ON CONFLICT(matricula_id) DO UPDATE SET gestion_id=EXCLUDED.gestion_id,
     carrera_id=EXCLUDED.carrera_id,estudiante_id=EXCLUDED.estudiante_id,
     fecha=EXCLUDED.fecha,estado=EXCLUDED.estado,cantidad=EXCLUDED.cantidad`,
  `INSERT INTO dw.fact_resultados(inscripcion_id,matricula_id,gestion_id,carrera_id,
     estudiante_id,docente_id,materia_id,fecha,promedio,asistencia,nota_final,resultado,aprobado,recuperacion)
   SELECT i.id,i.matricula_id,i.periodo_id,i.carrera_id,mt.estudiante_id,o.docente_id,
     o.materia_id,r.fecha::date,r.promedio,r.porcentaje_asistencia,v.nota_final,v.resultado,
     CASE WHEN v.resultado IN('APROBADO','APROBADO_RECUPERACION') THEN 1 ELSE 0 END,
     CASE WHEN v.nota_prueba_recuperacion IS NOT NULL THEN 1 ELSE 0 END
   FROM public.resultados_finales r
   JOIN public.inscripciones i ON i.id=r.inscripcion_id
   JOIN public.matriculas mt ON mt.id=i.matricula_id
   JOIN public.ofertas o ON o.id=i.oferta_id
   JOIN public.v_boletin_final v ON v.inscripcion_id=i.id
   ON CONFLICT(inscripcion_id) DO UPDATE SET matricula_id=EXCLUDED.matricula_id,
     gestion_id=EXCLUDED.gestion_id,carrera_id=EXCLUDED.carrera_id,
     estudiante_id=EXCLUDED.estudiante_id,docente_id=EXCLUDED.docente_id,
     materia_id=EXCLUDED.materia_id,fecha=EXCLUDED.fecha,promedio=EXCLUDED.promedio,
     asistencia=EXCLUDED.asistencia,nota_final=EXCLUDED.nota_final,
     resultado=EXCLUDED.resultado,aprobado=EXCLUDED.aprobado,recuperacion=EXCLUDED.recuperacion`,
  `INSERT INTO dw.fact_pagos(pago_id,matricula_id,cargo_id,gestion_id,carrera_id,
     estudiante_id,fecha,monto,metodo,recibo)
   SELECT p.id,c.matricula_id,c.id,mt.periodo_id,mt.carrera_id,mt.estudiante_id,
     p.fecha,p.monto,p.metodo,p.recibo
   FROM public.pagos p JOIN public.cargos c ON c.id=p.cargo_id
   JOIN public.matriculas mt ON mt.id=c.matricula_id
   ON CONFLICT(pago_id) DO UPDATE SET matricula_id=EXCLUDED.matricula_id,
     cargo_id=EXCLUDED.cargo_id,gestion_id=EXCLUDED.gestion_id,
     carrera_id=EXCLUDED.carrera_id,estudiante_id=EXCLUDED.estudiante_id,
     fecha=EXCLUDED.fecha,monto=EXCLUDED.monto,metodo=EXCLUDED.metodo,recibo=EXCLUDED.recibo`,
];

const staleRows = [
  `DELETE FROM dw.fact_resultados f WHERE NOT EXISTS(SELECT 1 FROM public.resultados_finales r WHERE r.inscripcion_id=f.inscripcion_id)`,
  `DELETE FROM dw.fact_pagos f WHERE NOT EXISTS(SELECT 1 FROM public.pagos p WHERE p.id=f.pago_id)`,
  `DELETE FROM dw.fact_matriculas f WHERE NOT EXISTS(SELECT 1 FROM public.matriculas m WHERE m.id=f.matricula_id)`,
  `DELETE FROM dw.dim_materia d WHERE NOT EXISTS(SELECT 1 FROM public.materias m WHERE m.id=d.materia_id)`,
  `DELETE FROM dw.dim_docente d WHERE NOT EXISTS(SELECT 1 FROM public.docentes p WHERE p.id=d.docente_id)`,
  `DELETE FROM dw.dim_estudiante d WHERE NOT EXISTS(SELECT 1 FROM public.estudiantes p WHERE p.id=d.estudiante_id)`,
  `DELETE FROM dw.dim_carrera d WHERE NOT EXISTS(SELECT 1 FROM public.carreras p WHERE p.id=d.carrera_id)`,
  `DELETE FROM dw.dim_gestion d WHERE NOT EXISTS(SELECT 1 FROM public.periodos p WHERE p.id=d.gestion_id)`,
];

/** Refresh the analytical star without modifying the public operational tables. */
export async function runEtl(prisma) {
  const execution = await prisma.dw_etl_ejecuciones.create({ data: { estado: 'EN_CURSO' } });
  try {
    return await prisma.$transaction(async tx => {
      // The academic application uses the same transaction lock for its writes.
      await tx.$queryRawUnsafe('SELECT pg_advisory_xact_lock(74824601)::text');
      for (const statement of [...dimensions, ...facts, ...staleRows]) await tx.$executeRawUnsafe(statement);
      const [counts] = await tx.$queryRawUnsafe(`SELECT
        ((SELECT count(*) FROM dw.dim_gestion)+(SELECT count(*) FROM dw.dim_carrera)+
         (SELECT count(*) FROM dw.dim_estudiante)+(SELECT count(*) FROM dw.dim_docente)+
         (SELECT count(*) FROM dw.dim_materia)+(SELECT count(*) FROM dw.dim_tiempo))::integer AS dimensiones,
        (SELECT count(*)::integer FROM dw.fact_matriculas) AS matriculas,
        (SELECT count(*)::integer FROM dw.fact_resultados) AS resultados,
        (SELECT count(*)::integer FROM dw.fact_pagos) AS pagos`);
      const finished = new Date();
      const job = await tx.dw_etl_ejecuciones.update({ where: { id: execution.id }, data: {
        fin: finished, estado: 'COMPLETADO', ...counts,
        detalle: { origen: 'public', destino: 'dw', estrategia: 'upsert',
          granos: { matriculas: 'una fila por matrícula', resultados: 'una fila por inscripción con cierre', pagos: 'una fila por pago' } },
      } });
      return { id: job.id, estado: job.estado, inicio: job.inicio, fin: job.fin, ...counts,
        message: 'Almacén analítico actualizado correctamente.' };
    }, { isolationLevel: 'RepeatableRead', maxWait: 15000, timeout: 120000 });
  } catch (error) {
    await prisma.dw_etl_ejecuciones.update({ where: { id: execution.id }, data: {
      fin: new Date(), estado: 'ERROR', detalle: { mensaje: 'La actualización analítica se revirtió sin modificar los datos operativos.' },
    } }).catch(() => {});
    throw error;
  }
}

// This module can be imported by NestJS without starting a second connection.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.env.DATABASE_URL) throw new Error('Falta DATABASE_URL para actualizar el almacén de PostgreSQL.');
  const { PrismaClient } = await import('@prisma/client');
  const { PrismaPg } = await import('@prisma/adapter-pg');
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }) });
  try { console.log(JSON.stringify(await runEtl(prisma))); }
  catch { console.error('No se pudo actualizar el almacén analítico. Revisa las migraciones y la conexión PostgreSQL.'); process.exitCode = 1; }
  finally { await prisma.$disconnect(); }
}
