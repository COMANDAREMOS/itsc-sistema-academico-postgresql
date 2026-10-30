-- Persistent rules specific to the ITSC academic model.
-- These functions do not access any other database or the old application.

CREATE FUNCTION validar_asistencia() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  duracion integer;
  estado_sesion varchar(32);
BEGIN
  SELECT floor(extract(epoch FROM (fin-inicio))/60)::integer, estado
    INTO duracion, estado_sesion FROM sesiones WHERE id=NEW.sesion_id;
  IF duracion IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='La sesión no existe.';
  END IF;
  IF estado_sesion <> 'REALIZADA' THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='La asistencia requiere una sesión realizada.';
  END IF;
  IF NEW.minutos_presentes < 0 OR NEW.minutos_presentes > duracion THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='La asistencia no puede superar la duración de la sesión.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validar_asistencia_insert BEFORE INSERT ON asistencias_sesion
FOR EACH ROW EXECUTE FUNCTION validar_asistencia();
CREATE TRIGGER validar_asistencia_update BEFORE UPDATE ON asistencias_sesion
FOR EACH ROW EXECUTE FUNCTION validar_asistencia();

CREATE FUNCTION validar_recuperacion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  matricula_correcta integer;
  limite integer;
BEGIN
  SELECT i.matricula_id, CASE WHEN c.regimen='ANUAL' THEN 3 ELSE 2 END
    INTO matricula_correcta, limite
    FROM inscripciones i JOIN carreras c ON c.id=i.carrera_id
    WHERE i.id=NEW.inscripcion_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='La inscripción no existe.';
  END IF;
  -- Serialize recoveries for a single enrollment before checking the limit.
  PERFORM id FROM matriculas WHERE id=matricula_correcta FOR UPDATE;
  IF NEW.matricula_id <> matricula_correcta THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='La matrícula de la recuperación es incorrecta.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM resultados_finales
    WHERE inscripcion_id=NEW.inscripcion_id AND estado='REPROBADO'
      AND promedio>=40 AND promedio<61) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='No cumple las condiciones de recuperación.';
  END IF;
  IF (SELECT count(*) FROM recuperaciones WHERE matricula_id=matricula_correcta)>=limite THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Supera el máximo de materias en recuperación.';
  END IF;
  NEW.nota_registrada := CASE WHEN NEW.nota_prueba>=61 THEN 61 ELSE NEW.nota_prueba END;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validar_recuperacion BEFORE INSERT ON recuperaciones
FOR EACH ROW EXECUTE FUNCTION validar_recuperacion();

CREATE FUNCTION proteger_recuperacion() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='23514',
    MESSAGE='La recuperación es definitiva y requiere rectificación administrativa.';
END;
$$;

CREATE TRIGGER no_editar_recuperacion BEFORE UPDATE ON recuperaciones
FOR EACH ROW EXECUTE FUNCTION proteger_recuperacion();
CREATE TRIGGER no_borrar_recuperacion BEFORE DELETE ON recuperaciones
FOR EACH ROW EXECUTE FUNCTION proteger_recuperacion();

CREATE VIEW v_saldos AS
SELECT c.id AS cargo_id, c.matricula_id, c.concepto, c.monto AS cargo,
       coalesce(sum(p.monto),0)::decimal(10,2) AS pagado,
       (c.monto-coalesce(sum(p.monto),0))::decimal(10,2) AS saldo
FROM cargos c LEFT JOIN pagos p ON p.cargo_id=c.id
GROUP BY c.id,c.matricula_id,c.concepto,c.monto;

CREATE VIEW v_listado_academico AS
SELECT e.registro, concat(e.nombres,' ',e.apellidos) AS estudiante,
       c.nombre AS carrera, p.nombre AS periodo, m.nombre AS materia,
       o.paralelo,o.turno,concat(d.nombres,' ',d.apellidos) AS docente
FROM inscripciones i
JOIN matriculas mt ON mt.id=i.matricula_id
JOIN estudiantes e ON e.id=mt.estudiante_id
JOIN carreras c ON c.id=i.carrera_id
JOIN periodos p ON p.id=i.periodo_id
JOIN ofertas o ON o.id=i.oferta_id
JOIN materias m ON m.id=o.materia_id
JOIN docentes d ON d.id=o.docente_id;

CREATE VIEW v_boletin_final AS
SELECT i.id AS inscripcion_id,e.registro,
       concat(e.nombres,' ',e.apellidos) AS estudiante,ma.nombre AS materia,
       r.promedio,r.porcentaje_asistencia,r.excepcion_documentada,
       CASE WHEN re.nota_prueba>=61 THEN 61 ELSE r.promedio END AS nota_final,
       CASE WHEN re.nota_prueba>=61 THEN 'APROBADO_RECUPERACION' ELSE r.estado END AS resultado,
       re.nota_prueba AS nota_prueba_recuperacion
FROM resultados_finales r
JOIN inscripciones i ON i.id=r.inscripcion_id
JOIN matriculas m ON m.id=i.matricula_id
JOIN estudiantes e ON e.id=m.estudiante_id
JOIN ofertas o ON o.id=i.oferta_id
JOIN materias ma ON ma.id=o.materia_id
LEFT JOIN recuperaciones re ON re.inscripcion_id=i.id;
