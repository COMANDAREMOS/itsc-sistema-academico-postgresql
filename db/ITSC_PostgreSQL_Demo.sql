--
-- PostgreSQL database dump
--

\restrict 22gI9LU6gkgBctCdHnMX0xVWAbMlGpgm2ns5QbNcnt674LMA5dVJvXoVKpbkljP

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: dw; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA dw;


--
-- Name: proteger_recuperacion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proteger_recuperacion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='23514',
    MESSAGE='La recuperación es definitiva y requiere rectificación administrativa.';
END;
$$;


--
-- Name: validar_asistencia(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_asistencia() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: validar_recuperacion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_recuperacion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: dim_carrera; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.dim_carrera (
    carrera_id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(120) NOT NULL,
    nivel character varying(50) NOT NULL,
    regimen character varying(32) NOT NULL
);


--
-- Name: dim_docente; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.dim_docente (
    docente_id integer NOT NULL,
    nombres character varying(80) NOT NULL,
    apellidos character varying(100) NOT NULL,
    especialidad character varying(120) NOT NULL
);


--
-- Name: dim_estudiante; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.dim_estudiante (
    estudiante_id integer NOT NULL,
    registro character varying(20) NOT NULL,
    nombres character varying(80) NOT NULL,
    apellidos character varying(100) NOT NULL
);


--
-- Name: dim_gestion; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.dim_gestion (
    gestion_id integer NOT NULL,
    nombre character varying(30) NOT NULL,
    fecha_inicio date NOT NULL,
    fecha_fin date NOT NULL,
    CONSTRAINT dim_gestion_fechas CHECK ((fecha_fin >= fecha_inicio))
);


--
-- Name: dim_materia; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.dim_materia (
    materia_id integer NOT NULL,
    carrera_id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(120) NOT NULL,
    nivel_curso integer NOT NULL
);


--
-- Name: dim_tiempo; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.dim_tiempo (
    fecha date NOT NULL,
    anio integer NOT NULL,
    mes integer NOT NULL,
    dia integer NOT NULL,
    trimestre integer NOT NULL,
    dia_semana integer NOT NULL,
    mes_nombre character varying(20) NOT NULL,
    CONSTRAINT dim_tiempo_dia_check CHECK (((dia >= 1) AND (dia <= 31))),
    CONSTRAINT dim_tiempo_dia_semana_check CHECK (((dia_semana >= 1) AND (dia_semana <= 7))),
    CONSTRAINT dim_tiempo_mes_check CHECK (((mes >= 1) AND (mes <= 12))),
    CONSTRAINT dim_tiempo_trimestre_check CHECK (((trimestre >= 1) AND (trimestre <= 4)))
);


--
-- Name: etl_ejecuciones; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.etl_ejecuciones (
    id integer NOT NULL,
    inicio timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fin timestamp(3) without time zone,
    estado character varying(32) DEFAULT 'EN_CURSO'::character varying NOT NULL,
    dimensiones integer DEFAULT 0 NOT NULL,
    matriculas integer DEFAULT 0 NOT NULL,
    resultados integer DEFAULT 0 NOT NULL,
    pagos integer DEFAULT 0 NOT NULL,
    detalle jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT etl_ejecuciones_estado_check CHECK (((estado)::text = ANY ((ARRAY['EN_CURSO'::character varying, 'COMPLETADO'::character varying, 'ERROR'::character varying])::text[])))
);


--
-- Name: etl_ejecuciones_id_seq; Type: SEQUENCE; Schema: dw; Owner: -
--

ALTER TABLE dw.etl_ejecuciones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dw.etl_ejecuciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: fact_matriculas; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.fact_matriculas (
    matricula_id integer NOT NULL,
    gestion_id integer NOT NULL,
    carrera_id integer NOT NULL,
    estudiante_id integer NOT NULL,
    fecha date NOT NULL,
    estado character varying(32) NOT NULL,
    cantidad integer DEFAULT 1 NOT NULL,
    CONSTRAINT fact_matriculas_cantidad_check CHECK ((cantidad = 1))
);


--
-- Name: fact_pagos; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.fact_pagos (
    pago_id integer NOT NULL,
    matricula_id integer NOT NULL,
    cargo_id integer NOT NULL,
    gestion_id integer NOT NULL,
    carrera_id integer NOT NULL,
    estudiante_id integer NOT NULL,
    fecha date NOT NULL,
    monto numeric(10,2) NOT NULL,
    metodo character varying(32) NOT NULL,
    recibo character varying(30) NOT NULL,
    CONSTRAINT fact_pagos_monto_check CHECK ((monto > (0)::numeric))
);


--
-- Name: fact_resultados; Type: TABLE; Schema: dw; Owner: -
--

CREATE TABLE dw.fact_resultados (
    inscripcion_id integer NOT NULL,
    matricula_id integer NOT NULL,
    gestion_id integer NOT NULL,
    carrera_id integer NOT NULL,
    estudiante_id integer NOT NULL,
    docente_id integer NOT NULL,
    materia_id integer NOT NULL,
    fecha date NOT NULL,
    promedio numeric(8,5) NOT NULL,
    asistencia numeric(8,5) NOT NULL,
    nota_final numeric(8,5) NOT NULL,
    resultado character varying(32) NOT NULL,
    aprobado integer NOT NULL,
    recuperacion integer NOT NULL,
    CONSTRAINT fact_resultados_aprobado_check CHECK ((aprobado = ANY (ARRAY[0, 1]))),
    CONSTRAINT fact_resultados_recuperacion_check CHECK ((recuperacion = ANY (ARRAY[0, 1])))
);


--
-- Name: v_matriculas_por_gestion_carrera; Type: VIEW; Schema: dw; Owner: -
--

CREATE VIEW dw.v_matriculas_por_gestion_carrera AS
 SELECT g.gestion_id,
    g.nombre AS gestion,
    c.carrera_id,
    c.nombre AS carrera,
    (count(*))::integer AS total,
    (count(DISTINCT f.estudiante_id))::integer AS estudiantes,
    (sum(
        CASE
            WHEN ((f.estado)::text = 'ACTIVA'::text) THEN f.cantidad
            ELSE 0
        END))::integer AS activas
   FROM ((dw.fact_matriculas f
     JOIN dw.dim_gestion g ON ((g.gestion_id = f.gestion_id)))
     JOIN dw.dim_carrera c ON ((c.carrera_id = f.carrera_id)))
  GROUP BY g.gestion_id, g.nombre, c.carrera_id, c.nombre;


--
-- Name: v_recaudacion_mensual; Type: VIEW; Schema: dw; Owner: -
--

CREATE VIEW dw.v_recaudacion_mensual AS
 SELECT to_char((t.fecha)::timestamp with time zone, 'YYYY-MM'::text) AS mes,
    t.anio,
    t.mes AS mes_numero,
    t.mes_nombre,
    g.gestion_id,
    g.nombre AS gestion,
    c.carrera_id,
    c.nombre AS carrera,
    (count(*))::integer AS pagos,
    sum(f.monto) AS total
   FROM (((dw.fact_pagos f
     JOIN dw.dim_tiempo t ON ((t.fecha = f.fecha)))
     JOIN dw.dim_gestion g ON ((g.gestion_id = f.gestion_id)))
     JOIN dw.dim_carrera c ON ((c.carrera_id = f.carrera_id)))
  GROUP BY (to_char((t.fecha)::timestamp with time zone, 'YYYY-MM'::text)), t.anio, t.mes, t.mes_nombre, g.gestion_id, g.nombre, c.carrera_id, c.nombre;


--
-- Name: v_rendimiento_por_carrera; Type: VIEW; Schema: dw; Owner: -
--

CREATE VIEW dw.v_rendimiento_por_carrera AS
 SELECT g.gestion_id,
    g.nombre AS gestion,
    c.carrera_id,
    c.nombre AS carrera,
    (count(*))::integer AS inscripciones,
    (sum(f.aprobado))::integer AS aprobados,
    round(avg(f.nota_final), 2) AS promedio,
    round(avg(f.asistencia), 2) AS asistencia_promedio,
    round(((100.0 * (sum(f.aprobado))::numeric) / (NULLIF(count(*), 0))::numeric), 2) AS tasa_aprobacion
   FROM ((dw.fact_resultados f
     JOIN dw.dim_gestion g ON ((g.gestion_id = f.gestion_id)))
     JOIN dw.dim_carrera c ON ((c.carrera_id = f.carrera_id)))
  GROUP BY g.gestion_id, g.nombre, c.carrera_id, c.nombre;


--
-- Name: _prisma_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._prisma_migrations (
    id character varying(36) NOT NULL,
    checksum character varying(64) NOT NULL,
    finished_at timestamp with time zone,
    migration_name character varying(255) NOT NULL,
    logs text,
    rolled_back_at timestamp with time zone,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    applied_steps_count integer DEFAULT 0 NOT NULL
);


--
-- Name: app_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_auditoria (
    id integer NOT NULL,
    usuario_id integer NOT NULL,
    accion character varying(60) NOT NULL,
    entidad character varying(80) NOT NULL,
    registro_id character varying(50),
    fecha timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT app_auditoria_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT app_auditoria_usuario_id_nonnegative CHECK ((usuario_id >= 0))
);


--
-- Name: app_auditoria_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.app_auditoria ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.app_auditoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_intentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_intentos (
    clave character(64) NOT NULL,
    fallos integer DEFAULT 0 NOT NULL,
    ultimo timestamp(0) without time zone NOT NULL
);


--
-- Name: app_usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_usuarios (
    id integer NOT NULL,
    usuario character varying(60) NOT NULL,
    nombre character varying(120) NOT NULL,
    password_hash character varying(255) NOT NULL,
    rol character varying(32) NOT NULL,
    docente_id integer,
    activo integer DEFAULT 1 NOT NULL,
    CONSTRAINT "app_usuarios_CONSTRAINT_1" CHECK ((((rol)::text <> 'DOCENTE'::text) OR (docente_id IS NOT NULL))),
    CONSTRAINT app_usuarios_activo_boolean CHECK ((activo = ANY (ARRAY[0, 1]))),
    CONSTRAINT app_usuarios_docente_id_nonnegative CHECK ((docente_id >= 0)),
    CONSTRAINT app_usuarios_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT app_usuarios_rol_enum CHECK (((rol)::text = ANY ((ARRAY['ADMIN'::character varying, 'DOCENTE'::character varying, 'CAJA'::character varying])::text[])))
);


--
-- Name: app_usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.app_usuarios ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.app_usuarios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asistencias_demo_historicas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistencias_demo_historicas (
    id integer NOT NULL,
    inscripcion_id integer NOT NULL,
    fecha date NOT NULL,
    estado character varying(32) NOT NULL,
    CONSTRAINT asistencias_demo_historicas_estado_enum CHECK (((estado)::text = ANY ((ARRAY['PRESENTE'::character varying, 'FALTA'::character varying, 'ATRASO'::character varying, 'JUSTIFICADA'::character varying])::text[]))),
    CONSTRAINT asistencias_demo_historicas_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT asistencias_demo_historicas_inscripcion_id_nonnegative CHECK ((inscripcion_id >= 0))
);


--
-- Name: asistencias_demo_historicas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.asistencias_demo_historicas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.asistencias_demo_historicas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asistencias_sesion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistencias_sesion (
    inscripcion_id integer NOT NULL,
    sesion_id integer NOT NULL,
    oferta_id integer NOT NULL,
    minutos_presentes integer NOT NULL,
    CONSTRAINT asistencias_sesion_inscripcion_id_nonnegative CHECK ((inscripcion_id >= 0)),
    CONSTRAINT asistencias_sesion_minutos_presentes_nonnegative CHECK ((minutos_presentes >= 0)),
    CONSTRAINT asistencias_sesion_oferta_id_nonnegative CHECK ((oferta_id >= 0)),
    CONSTRAINT asistencias_sesion_sesion_id_nonnegative CHECK ((sesion_id >= 0))
);


--
-- Name: aulas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aulas (
    id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    capacidad integer NOT NULL,
    CONSTRAINT aulas_capacidad_nonnegative CHECK ((capacidad >= 0)),
    CONSTRAINT aulas_id_nonnegative CHECK ((id >= 0))
);


--
-- Name: aulas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.aulas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.aulas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: calificaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calificaciones (
    inscripcion_id integer NOT NULL,
    evaluacion_id integer NOT NULL,
    oferta_id integer NOT NULL,
    nota numeric(5,2) NOT NULL,
    CONSTRAINT calificaciones_evaluacion_id_nonnegative CHECK ((evaluacion_id >= 0)),
    CONSTRAINT calificaciones_inscripcion_id_nonnegative CHECK ((inscripcion_id >= 0)),
    CONSTRAINT calificaciones_nota_check CHECK (((nota >= (1)::numeric) AND (nota <= (100)::numeric))),
    CONSTRAINT calificaciones_oferta_id_nonnegative CHECK ((oferta_id >= 0))
);


--
-- Name: cargos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cargos (
    id integer NOT NULL,
    matricula_id integer NOT NULL,
    concepto character varying(120) NOT NULL,
    monto numeric(10,2) NOT NULL,
    vencimiento date NOT NULL,
    CONSTRAINT "cargos_CONSTRAINT_1" CHECK ((monto > (0)::numeric)),
    CONSTRAINT cargos_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT cargos_matricula_id_nonnegative CHECK ((matricula_id >= 0))
);


--
-- Name: cargos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.cargos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cargos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: carreras; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.carreras (
    id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(120) NOT NULL,
    nivel character varying(50) DEFAULT 'Técnico Superior'::character varying NOT NULL,
    duracion_anios integer DEFAULT 3 NOT NULL,
    regimen character varying(32) NOT NULL,
    fuente_url character varying(500) NOT NULL,
    activa integer DEFAULT 1 NOT NULL,
    CONSTRAINT carreras_activa_boolean CHECK ((activa = ANY (ARRAY[0, 1]))),
    CONSTRAINT carreras_duracion_anios_nonnegative CHECK ((duracion_anios >= 0)),
    CONSTRAINT carreras_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT carreras_regimen_enum CHECK (((regimen)::text = ANY ((ARRAY['ANUAL'::character varying, 'SEMESTRAL'::character varying])::text[])))
);


--
-- Name: carreras_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.carreras ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.carreras_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cierres_oferta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cierres_oferta (
    oferta_id integer NOT NULL,
    minutos_carga integer NOT NULL,
    cerrado_por character varying(120) NOT NULL,
    fecha timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT cierres_oferta_minutos_carga_check CHECK ((minutos_carga > 0)),
    CONSTRAINT cierres_oferta_minutos_carga_nonnegative CHECK ((minutos_carga >= 0)),
    CONSTRAINT cierres_oferta_oferta_id_nonnegative CHECK ((oferta_id >= 0))
);


--
-- Name: defensas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.defensas (
    id integer NOT NULL,
    proyecto_id integer NOT NULL,
    fecha timestamp(0) without time zone NOT NULL,
    aula_id integer,
    nota numeric(5,2),
    acta character varying(50),
    CONSTRAINT defensas_aula_id_nonnegative CHECK ((aula_id >= 0)),
    CONSTRAINT defensas_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT defensas_nota_check CHECK (((nota >= (0)::numeric) AND (nota <= (100)::numeric))),
    CONSTRAINT defensas_proyecto_id_nonnegative CHECK ((proyecto_id >= 0))
);


--
-- Name: defensas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.defensas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.defensas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: docentes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.docentes (
    id integer NOT NULL,
    documento character varying(25) NOT NULL,
    nombres character varying(80) NOT NULL,
    apellidos character varying(100) NOT NULL,
    especialidad character varying(120) NOT NULL,
    telefono character varying(25),
    correo character varying(150),
    CONSTRAINT docentes_id_nonnegative CHECK ((id >= 0))
);


--
-- Name: docentes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.docentes ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.docentes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: documentos_matricula; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documentos_matricula (
    id integer NOT NULL,
    matricula_id integer NOT NULL,
    tipo_documento_id integer NOT NULL,
    estado character varying(32) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    fecha_recepcion date,
    observacion character varying(250),
    CONSTRAINT documentos_matricula_estado_enum CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'RECIBIDO'::character varying, 'OBSERVADO'::character varying])::text[]))),
    CONSTRAINT documentos_matricula_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT documentos_matricula_matricula_id_nonnegative CHECK ((matricula_id >= 0)),
    CONSTRAINT documentos_matricula_tipo_documento_id_nonnegative CHECK ((tipo_documento_id >= 0))
);


--
-- Name: documentos_matricula_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.documentos_matricula ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.documentos_matricula_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: estudiantes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estudiantes (
    id integer NOT NULL,
    registro character varying(20) NOT NULL,
    documento character varying(25) NOT NULL,
    nombres character varying(80) NOT NULL,
    apellidos character varying(100) NOT NULL,
    fecha_nacimiento date NOT NULL,
    telefono character varying(25),
    correo character varying(150),
    direccion character varying(200),
    fecha_registro timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT estudiantes_id_nonnegative CHECK ((id >= 0))
);


--
-- Name: estudiantes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.estudiantes ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.estudiantes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: evaluaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluaciones (
    id integer NOT NULL,
    oferta_id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    componente character varying(32) NOT NULL,
    peso numeric(6,3) NOT NULL,
    CONSTRAINT evaluaciones_componente_enum CHECK (((componente)::text = ANY ((ARRAY['PRACTICA'::character varying, 'TEORIA'::character varying])::text[]))),
    CONSTRAINT evaluaciones_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT evaluaciones_oferta_id_nonnegative CHECK ((oferta_id >= 0)),
    CONSTRAINT evaluaciones_peso_check CHECK (((peso > (0)::numeric) AND (peso <= (100)::numeric)))
);


--
-- Name: evaluaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.evaluaciones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.evaluaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: excepciones_asistencia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.excepciones_asistencia (
    inscripcion_id integer NOT NULL,
    documento character varying(250) NOT NULL,
    resolucion character varying(100) NOT NULL,
    aprobada_por character varying(120) NOT NULL,
    fecha date NOT NULL,
    CONSTRAINT "excepciones_asistencia_CONSTRAINT_1" CHECK (((octet_length(TRIM(BOTH FROM documento)) > 0) AND (octet_length(TRIM(BOTH FROM resolucion)) > 0))),
    CONSTRAINT excepciones_asistencia_inscripcion_id_nonnegative CHECK ((inscripcion_id >= 0))
);


--
-- Name: grupo_integrantes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupo_integrantes (
    id integer NOT NULL,
    grupo_id integer NOT NULL,
    matricula_id integer NOT NULL,
    fecha timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT grupo_integrantes_grupo_id_nonnegative CHECK ((grupo_id >= 0)),
    CONSTRAINT grupo_integrantes_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT grupo_integrantes_matricula_id_nonnegative CHECK ((matricula_id >= 0))
);


--
-- Name: grupo_integrantes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grupo_integrantes ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.grupo_integrantes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grupo_materias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupo_materias (
    id integer NOT NULL,
    grupo_id integer NOT NULL,
    oferta_id integer NOT NULL,
    CONSTRAINT grupo_materias_grupo_id_nonnegative CHECK ((grupo_id >= 0)),
    CONSTRAINT grupo_materias_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT grupo_materias_oferta_id_nonnegative CHECK ((oferta_id >= 0))
);


--
-- Name: grupo_materias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grupo_materias ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.grupo_materias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: grupos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupos (
    id integer NOT NULL,
    periodo_id integer NOT NULL,
    carrera_id integer NOT NULL,
    curso integer NOT NULL,
    paralelo character varying(20) NOT NULL,
    turno character varying(32) NOT NULL,
    cupo integer NOT NULL,
    tutor_id integer,
    estado character varying(32) DEFAULT 'ACTIVO'::character varying NOT NULL,
    CONSTRAINT "grupos_CONSTRAINT_1" CHECK (((curso >= 1) AND (curso <= 6))),
    CONSTRAINT "grupos_CONSTRAINT_2" CHECK (((cupo >= 1) AND (cupo <= 1000))),
    CONSTRAINT grupos_carrera_id_nonnegative CHECK ((carrera_id >= 0)),
    CONSTRAINT grupos_cupo_nonnegative CHECK ((cupo >= 0)),
    CONSTRAINT grupos_curso_nonnegative CHECK ((curso >= 0)),
    CONSTRAINT grupos_estado_enum CHECK (((estado)::text = ANY ((ARRAY['ACTIVO'::character varying, 'CERRADO'::character varying])::text[]))),
    CONSTRAINT grupos_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT grupos_periodo_id_nonnegative CHECK ((periodo_id >= 0)),
    CONSTRAINT grupos_turno_enum CHECK (((turno)::text = ANY ((ARRAY['MAÑANA'::character varying, 'TARDE'::character varying, 'NOCHE'::character varying])::text[]))),
    CONSTRAINT grupos_tutor_id_nonnegative CHECK ((tutor_id >= 0))
);


--
-- Name: grupos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.grupos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.grupos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: horarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.horarios (
    id integer NOT NULL,
    oferta_id integer NOT NULL,
    aula_id integer NOT NULL,
    dia integer NOT NULL,
    hora_inicio time(0) without time zone NOT NULL,
    hora_fin time(0) without time zone NOT NULL,
    CONSTRAINT "horarios_CONSTRAINT_1" CHECK (((dia >= 1) AND (dia <= 7))),
    CONSTRAINT "horarios_CONSTRAINT_2" CHECK ((hora_fin > hora_inicio)),
    CONSTRAINT horarios_aula_id_nonnegative CHECK ((aula_id >= 0)),
    CONSTRAINT horarios_dia_nonnegative CHECK ((dia >= 0)),
    CONSTRAINT horarios_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT horarios_oferta_id_nonnegative CHECK ((oferta_id >= 0))
);


--
-- Name: horarios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.horarios ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.horarios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inscripciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inscripciones (
    id integer NOT NULL,
    matricula_id integer NOT NULL,
    oferta_id integer NOT NULL,
    carrera_id integer NOT NULL,
    periodo_id integer NOT NULL,
    fecha date NOT NULL,
    estado character varying(32) DEFAULT 'ACTIVA'::character varying NOT NULL,
    CONSTRAINT inscripciones_carrera_id_nonnegative CHECK ((carrera_id >= 0)),
    CONSTRAINT inscripciones_estado_enum CHECK (((estado)::text = ANY ((ARRAY['ACTIVA'::character varying, 'RETIRADA'::character varying, 'CONCLUIDA'::character varying])::text[]))),
    CONSTRAINT inscripciones_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT inscripciones_matricula_id_nonnegative CHECK ((matricula_id >= 0)),
    CONSTRAINT inscripciones_oferta_id_nonnegative CHECK ((oferta_id >= 0)),
    CONSTRAINT inscripciones_periodo_id_nonnegative CHECK ((periodo_id >= 0))
);


--
-- Name: inscripciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inscripciones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inscripciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: materias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.materias (
    id integer NOT NULL,
    carrera_id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(120) NOT NULL,
    nivel_curso integer NOT NULL,
    horas_semanales integer,
    fuente_url character varying(500) NOT NULL,
    CONSTRAINT materias_carrera_id_nonnegative CHECK ((carrera_id >= 0)),
    CONSTRAINT materias_horas_semanales_nonnegative CHECK ((horas_semanales >= 0)),
    CONSTRAINT materias_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT materias_nivel_curso_nonnegative CHECK ((nivel_curso >= 0))
);


--
-- Name: materias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.materias ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.materias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: matriculas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.matriculas (
    id integer NOT NULL,
    estudiante_id integer NOT NULL,
    carrera_id integer NOT NULL,
    periodo_id integer NOT NULL,
    fecha date NOT NULL,
    estado character varying(32) DEFAULT 'ACTIVA'::character varying NOT NULL,
    plan_id integer NOT NULL,
    CONSTRAINT matriculas_carrera_id_nonnegative CHECK ((carrera_id >= 0)),
    CONSTRAINT matriculas_estado_enum CHECK (((estado)::text = ANY ((ARRAY['ACTIVA'::character varying, 'RETIRADA'::character varying, 'CONCLUIDA'::character varying])::text[]))),
    CONSTRAINT matriculas_estudiante_id_nonnegative CHECK ((estudiante_id >= 0)),
    CONSTRAINT matriculas_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT matriculas_periodo_id_nonnegative CHECK ((periodo_id >= 0)),
    CONSTRAINT matriculas_plan_id_nonnegative CHECK ((plan_id >= 0))
);


--
-- Name: matriculas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.matriculas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.matriculas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: modalidades_graduacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.modalidades_graduacion (
    id integer NOT NULL,
    nombre character varying(120) NOT NULL,
    CONSTRAINT modalidades_graduacion_id_nonnegative CHECK ((id >= 0))
);


--
-- Name: modalidades_graduacion_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.modalidades_graduacion ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.modalidades_graduacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notas_demo_historicas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notas_demo_historicas (
    id integer NOT NULL,
    inscripcion_id integer NOT NULL,
    evaluacion character varying(80) NOT NULL,
    nota numeric(5,2) NOT NULL,
    fecha date NOT NULL,
    CONSTRAINT "notas_demo_historicas_CONSTRAINT_1" CHECK (((nota >= (0)::numeric) AND (nota <= (100)::numeric))),
    CONSTRAINT notas_demo_historicas_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT notas_demo_historicas_inscripcion_id_nonnegative CHECK ((inscripcion_id >= 0))
);


--
-- Name: notas_demo_historicas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notas_demo_historicas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.notas_demo_historicas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ofertas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ofertas (
    id integer NOT NULL,
    materia_id integer NOT NULL,
    carrera_id integer NOT NULL,
    periodo_id integer NOT NULL,
    docente_id integer NOT NULL,
    paralelo character varying(10) NOT NULL,
    turno character varying(32) NOT NULL,
    cupo integer NOT NULL,
    CONSTRAINT ofertas_carrera_id_nonnegative CHECK ((carrera_id >= 0)),
    CONSTRAINT ofertas_cupo_nonnegative CHECK ((cupo >= 0)),
    CONSTRAINT ofertas_docente_id_nonnegative CHECK ((docente_id >= 0)),
    CONSTRAINT ofertas_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT ofertas_materia_id_nonnegative CHECK ((materia_id >= 0)),
    CONSTRAINT ofertas_periodo_id_nonnegative CHECK ((periodo_id >= 0)),
    CONSTRAINT ofertas_turno_enum CHECK (((turno)::text = ANY ((ARRAY['MAÑANA'::character varying, 'TARDE'::character varying, 'NOCHE'::character varying])::text[])))
);


--
-- Name: ofertas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ofertas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.ofertas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pagos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pagos (
    id integer NOT NULL,
    cargo_id integer NOT NULL,
    recibo character varying(30) NOT NULL,
    fecha date NOT NULL,
    monto numeric(10,2) NOT NULL,
    metodo character varying(32) NOT NULL,
    CONSTRAINT "pagos_CONSTRAINT_1" CHECK ((monto > (0)::numeric)),
    CONSTRAINT pagos_cargo_id_nonnegative CHECK ((cargo_id >= 0)),
    CONSTRAINT pagos_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT pagos_metodo_enum CHECK (((metodo)::text = ANY ((ARRAY['EFECTIVO'::character varying, 'TRANSFERENCIA'::character varying, 'QR'::character varying])::text[])))
);


--
-- Name: pagos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.pagos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.pagos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pasantias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pasantias (
    id integer NOT NULL,
    matricula_id integer NOT NULL,
    tutor_id integer,
    empresa character varying(150) NOT NULL,
    fecha_inicio date NOT NULL,
    fecha_fin date,
    horas integer,
    estado character varying(32) NOT NULL,
    CONSTRAINT "pasantias_CONSTRAINT_1" CHECK (((fecha_fin IS NULL) OR (fecha_fin >= fecha_inicio))),
    CONSTRAINT pasantias_estado_enum CHECK (((estado)::text = ANY ((ARRAY['SOLICITADA'::character varying, 'EN_CURSO'::character varying, 'CONCLUIDA'::character varying])::text[]))),
    CONSTRAINT pasantias_horas_nonnegative CHECK ((horas >= 0)),
    CONSTRAINT pasantias_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT pasantias_matricula_id_nonnegative CHECK ((matricula_id >= 0)),
    CONSTRAINT pasantias_tutor_id_nonnegative CHECK ((tutor_id >= 0))
);


--
-- Name: pasantias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.pasantias ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.pasantias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: periodos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.periodos (
    id integer NOT NULL,
    nombre character varying(30) NOT NULL,
    fecha_inicio date NOT NULL,
    fecha_fin date NOT NULL,
    CONSTRAINT "periodos_CONSTRAINT_1" CHECK ((fecha_fin >= fecha_inicio)),
    CONSTRAINT periodos_id_nonnegative CHECK ((id >= 0))
);


--
-- Name: periodos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.periodos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.periodos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: plan_materias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_materias (
    plan_id integer NOT NULL,
    materia_id integer NOT NULL,
    carrera_id integer NOT NULL,
    CONSTRAINT plan_materias_carrera_id_nonnegative CHECK ((carrera_id >= 0)),
    CONSTRAINT plan_materias_materia_id_nonnegative CHECK ((materia_id >= 0)),
    CONSTRAINT plan_materias_plan_id_nonnegative CHECK ((plan_id >= 0))
);


--
-- Name: planes_estudio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planes_estudio (
    id integer NOT NULL,
    carrera_id integer NOT NULL,
    denominacion character varying(100) NOT NULL,
    cohorte character varying(30) NOT NULL,
    regla_id integer NOT NULL,
    CONSTRAINT planes_estudio_carrera_id_nonnegative CHECK ((carrera_id >= 0)),
    CONSTRAINT planes_estudio_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT planes_estudio_regla_id_nonnegative CHECK ((regla_id >= 0))
);


--
-- Name: planes_estudio_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.planes_estudio ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.planes_estudio_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prerrequisitos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prerrequisitos (
    plan_id integer NOT NULL,
    materia_id integer NOT NULL,
    requerida_id integer NOT NULL,
    CONSTRAINT "prerrequisitos_CONSTRAINT_1" CHECK ((materia_id <> requerida_id)),
    CONSTRAINT prerrequisitos_materia_id_nonnegative CHECK ((materia_id >= 0)),
    CONSTRAINT prerrequisitos_plan_id_nonnegative CHECK ((plan_id >= 0)),
    CONSTRAINT prerrequisitos_requerida_id_nonnegative CHECK ((requerida_id >= 0))
);


--
-- Name: proyectos_graduacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proyectos_graduacion (
    id integer NOT NULL,
    matricula_id integer NOT NULL,
    modalidad_id integer NOT NULL,
    tutor_id integer,
    titulo character varying(250) NOT NULL,
    estado character varying(32) NOT NULL,
    CONSTRAINT proyectos_graduacion_estado_enum CHECK (((estado)::text = ANY ((ARRAY['PROPUESTO'::character varying, 'EN_DESARROLLO'::character varying, 'DEFENDIDO'::character varying, 'APROBADO'::character varying])::text[]))),
    CONSTRAINT proyectos_graduacion_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT proyectos_graduacion_matricula_id_nonnegative CHECK ((matricula_id >= 0)),
    CONSTRAINT proyectos_graduacion_modalidad_id_nonnegative CHECK ((modalidad_id >= 0)),
    CONSTRAINT proyectos_graduacion_tutor_id_nonnegative CHECK ((tutor_id >= 0))
);


--
-- Name: proyectos_graduacion_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.proyectos_graduacion ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.proyectos_graduacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recuperaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recuperaciones (
    inscripcion_id integer NOT NULL,
    matricula_id integer NOT NULL,
    nota_prueba numeric(5,2) NOT NULL,
    nota_registrada numeric(5,2) NOT NULL,
    fecha date NOT NULL,
    CONSTRAINT recuperaciones_inscripcion_id_nonnegative CHECK ((inscripcion_id >= 0)),
    CONSTRAINT recuperaciones_matricula_id_nonnegative CHECK ((matricula_id >= 0)),
    CONSTRAINT recuperaciones_nota_prueba_check CHECK (((nota_prueba >= (1)::numeric) AND (nota_prueba <= (100)::numeric)))
);


--
-- Name: reglas_evaluacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reglas_evaluacion (
    id integer NOT NULL,
    nombre character varying(120) NOT NULL,
    fuente character varying(500) NOT NULL,
    minimo numeric(5,2) DEFAULT 1.00 NOT NULL,
    maximo numeric(5,2) DEFAULT 100.00 NOT NULL,
    aprobacion numeric(5,2) DEFAULT 61.00 NOT NULL,
    practica numeric(4,3) DEFAULT 0.700 NOT NULL,
    teoria numeric(4,3) DEFAULT 0.300 NOT NULL,
    asistencia numeric(5,2) DEFAULT 80.00 NOT NULL,
    acceso_recuperacion numeric(5,2) DEFAULT 40.00 NOT NULL,
    max_rec_anual integer DEFAULT 3 NOT NULL,
    max_rec_semestral integer DEFAULT 2 NOT NULL,
    CONSTRAINT reglas_evaluacion_acceso_recuperacion_check CHECK ((acceso_recuperacion = (40)::numeric)),
    CONSTRAINT reglas_evaluacion_aprobacion_check CHECK ((aprobacion = (61)::numeric)),
    CONSTRAINT reglas_evaluacion_asistencia_check CHECK ((asistencia = (80)::numeric)),
    CONSTRAINT reglas_evaluacion_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT reglas_evaluacion_max_rec_anual_check CHECK ((max_rec_anual = 3)),
    CONSTRAINT reglas_evaluacion_max_rec_semestral_check CHECK ((max_rec_semestral = 2)),
    CONSTRAINT reglas_evaluacion_maximo_check CHECK ((maximo = (100)::numeric)),
    CONSTRAINT reglas_evaluacion_minimo_check CHECK ((minimo = (1)::numeric)),
    CONSTRAINT reglas_evaluacion_practica_check CHECK ((practica = 0.700)),
    CONSTRAINT reglas_evaluacion_teoria_check CHECK ((teoria = 0.300))
);


--
-- Name: resultados_finales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resultados_finales (
    inscripcion_id integer NOT NULL,
    regla_id integer NOT NULL,
    promedio numeric(8,5) NOT NULL,
    porcentaje_asistencia numeric(8,5) NOT NULL,
    excepcion_documentada integer NOT NULL,
    estado character varying(32) NOT NULL,
    fecha timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT resultados_finales_estado_enum CHECK (((estado)::text = ANY ((ARRAY['APROBADO'::character varying, 'REPROBADO'::character varying, 'REPROBADO_ASISTENCIA'::character varying])::text[]))),
    CONSTRAINT resultados_finales_excepcion_documentada_boolean CHECK ((excepcion_documentada = ANY (ARRAY[0, 1]))),
    CONSTRAINT resultados_finales_inscripcion_id_nonnegative CHECK ((inscripcion_id >= 0)),
    CONSTRAINT resultados_finales_regla_id_nonnegative CHECK ((regla_id >= 0))
);


--
-- Name: sesiones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sesiones (
    id integer NOT NULL,
    oferta_id integer NOT NULL,
    inicio timestamp(0) without time zone NOT NULL,
    fin timestamp(0) without time zone NOT NULL,
    estado character varying(32) DEFAULT 'PROGRAMADA'::character varying NOT NULL,
    CONSTRAINT "sesiones_CONSTRAINT_1" CHECK ((fin > inicio)),
    CONSTRAINT sesiones_estado_enum CHECK (((estado)::text = ANY ((ARRAY['PROGRAMADA'::character varying, 'REALIZADA'::character varying, 'CANCELADA'::character varying])::text[]))),
    CONSTRAINT sesiones_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT sesiones_oferta_id_nonnegative CHECK ((oferta_id >= 0))
);


--
-- Name: sesiones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sesiones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sesiones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipos_documento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipos_documento (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    CONSTRAINT tipos_documento_id_nonnegative CHECK ((id >= 0))
);


--
-- Name: tipos_documento_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tipos_documento ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipos_documento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tramites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tramites (
    id integer NOT NULL,
    matricula_id integer NOT NULL,
    tipo character varying(32) NOT NULL,
    fecha date NOT NULL,
    estado character varying(32) NOT NULL,
    detalle text,
    CONSTRAINT tramites_estado_enum CHECK (((estado)::text = ANY ((ARRAY['SOLICITADO'::character varying, 'EN_REVISION'::character varying, 'APROBADO'::character varying, 'RECHAZADO'::character varying])::text[]))),
    CONSTRAINT tramites_id_nonnegative CHECK ((id >= 0)),
    CONSTRAINT tramites_matricula_id_nonnegative CHECK ((matricula_id >= 0)),
    CONSTRAINT tramites_tipo_enum CHECK (((tipo)::text = ANY ((ARRAY['CAMBIO_CARRERA'::character varying, 'MATERIA_REPROBADA'::character varying, 'PRORROGA_DIPLOMA'::character varying, 'OTRO'::character varying])::text[])))
);


--
-- Name: tramites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tramites ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tramites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tribunales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tribunales (
    defensa_id integer NOT NULL,
    docente_id integer NOT NULL,
    funcion character varying(50) NOT NULL,
    CONSTRAINT tribunales_defensa_id_nonnegative CHECK ((defensa_id >= 0)),
    CONSTRAINT tribunales_docente_id_nonnegative CHECK ((docente_id >= 0))
);


--
-- Name: v_boletin_final; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_boletin_final AS
 SELECT i.id AS inscripcion_id,
    e.registro,
    concat(e.nombres, ' ', e.apellidos) AS estudiante,
    ma.nombre AS materia,
    r.promedio,
    r.porcentaje_asistencia,
    r.excepcion_documentada,
        CASE
            WHEN (re.nota_prueba >= (61)::numeric) THEN (61)::numeric
            ELSE r.promedio
        END AS nota_final,
        CASE
            WHEN (re.nota_prueba >= (61)::numeric) THEN 'APROBADO_RECUPERACION'::character varying
            ELSE r.estado
        END AS resultado,
    re.nota_prueba AS nota_prueba_recuperacion
   FROM ((((((public.resultados_finales r
     JOIN public.inscripciones i ON ((i.id = r.inscripcion_id)))
     JOIN public.matriculas m ON ((m.id = i.matricula_id)))
     JOIN public.estudiantes e ON ((e.id = m.estudiante_id)))
     JOIN public.ofertas o ON ((o.id = i.oferta_id)))
     JOIN public.materias ma ON ((ma.id = o.materia_id)))
     LEFT JOIN public.recuperaciones re ON ((re.inscripcion_id = i.id)));


--
-- Name: v_listado_academico; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_listado_academico AS
 SELECT e.registro,
    concat(e.nombres, ' ', e.apellidos) AS estudiante,
    c.nombre AS carrera,
    p.nombre AS periodo,
    m.nombre AS materia,
    o.paralelo,
    o.turno,
    concat(d.nombres, ' ', d.apellidos) AS docente
   FROM (((((((public.inscripciones i
     JOIN public.matriculas mt ON ((mt.id = i.matricula_id)))
     JOIN public.estudiantes e ON ((e.id = mt.estudiante_id)))
     JOIN public.carreras c ON ((c.id = i.carrera_id)))
     JOIN public.periodos p ON ((p.id = i.periodo_id)))
     JOIN public.ofertas o ON ((o.id = i.oferta_id)))
     JOIN public.materias m ON ((m.id = o.materia_id)))
     JOIN public.docentes d ON ((d.id = o.docente_id)));


--
-- Name: v_saldos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_saldos AS
 SELECT c.id AS cargo_id,
    c.matricula_id,
    c.concepto,
    c.monto AS cargo,
    (COALESCE(sum(p.monto), (0)::numeric))::numeric(10,2) AS pagado,
    ((c.monto - COALESCE(sum(p.monto), (0)::numeric)))::numeric(10,2) AS saldo
   FROM (public.cargos c
     LEFT JOIN public.pagos p ON ((p.cargo_id = c.id)))
  GROUP BY c.id, c.matricula_id, c.concepto, c.monto;


--
-- Data for Name: dim_carrera; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.dim_carrera (carrera_id, codigo, nombre, nivel, regimen) FROM stdin;
1	SIS	Sistemas Informáticos	Técnico Superior	ANUAL
2	CON	Contaduría General	Técnico Superior	ANUAL
3	ELE	Electricidad Industrial	Técnico Superior	SEMESTRAL
4	QUI	Química Industrial	Técnico Superior	SEMESTRAL
5	MIN	Mecánica Industrial	Técnico Superior	SEMESTRAL
6	MAU	Mecánica Automotriz	Técnico Superior	SEMESTRAL
7	ELN	Electrónica	Técnico Superior	SEMESTRAL
8	CCV	Construcción Civil	Técnico Superior	SEMESTRAL
9	DEMO-C01	Redes y Telecomunicaciones (demostración)	Técnico Superior	SEMESTRAL
10	DEMO-C02	Diseño Gráfico (demostración)	Técnico Superior	SEMESTRAL
11	DEMO-C03	Administración de Empresas (demostración)	Técnico Superior	SEMESTRAL
12	DEMO-C04	Energías Renovables (demostración)	Técnico Superior	SEMESTRAL
\.


--
-- Data for Name: dim_docente; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.dim_docente (docente_id, nombres, apellidos, especialidad) FROM stdin;
1	Lucía	Vargas Molina	Informática
2	Andrés	Paredes Lima	Contabilidad
3	Camila	Ortiz Rivas	Electricidad
4	Javier Adrián	Aguilar Ortega	Sistemas Informáticos
5	Andrés Luis	Medina Torres	Contaduría General
6	Valeria Javier	Navarro Gutiérrez	Electricidad Industrial
7	Camila Camila	Ríos Apaza	Química Industrial
8	Lucía Daniela	Rivera Montes	Mecánica Industrial
9	Mariana Andrea	Apaza Mendoza	Mecánica Automotriz
10	Daniela Carolina	Pinto Soto	Electrónica
11	Sofía Victoria	Molina Vega	Construcción Civil
12	Paola Mauricio	Aguilar Rivera	Redes y Telecomunicaciones
13	Andrea Ricardo	Medina Mamani	Diseño Gráfico
14	Gabriela Lorena	Navarro Villarroel	Administración de Empresas
15	Natalia Gabriel	Ríos Castro	Energías Renovables
16	Carolina Santiago	Rivera Morales	Sistemas Informáticos
17	Fernanda Nicolás	Apaza Ríos	Contaduría General
18	Isabel Alejandro	Pinto Escobar	Electricidad Industrial
19	Victoria Carlos	Molina Soria	Química Industrial
20	Elena Valeria	Aguilar Vargas	Mecánica Industrial
21	Rodrigo Mariana	Medina Romero	Mecánica Automotriz
22	Mauricio Paola	Navarro Navarro	Electrónica
23	Eduardo Natalia	Ríos López	Construcción Civil
24	Pablo Isabel	Rivera Quispe	Redes y Telecomunicaciones
25	Ricardo Rodrigo	Apaza Arias	Diseño Gráfico
26	Patricia Pablo	Pinto Flores	Administración de Empresas
27	Claudia Claudia	Molina Medina	Energías Renovables
28	Lorena Rosa	Aguilar Cabrera	Sistemas Informáticos
29	Verónica Daniel	Medina Castillo	Contaduría General
30	Rosa Diego	Navarro Condori	Electricidad Industrial
31	Gabriel Sebastián	Ríos Delgado	Química Industrial
32	Mateo Miguel	Rivera Aguilar	Mecánica Industrial
33	Daniel Andrés	Apaza Herrera	Mecánica Automotriz
34	Santiago Lucía	Pinto Suárez	Electrónica
35	Samuel Sofía	Molina Valdez	Construcción Civil
36	Diego Gabriela	Aguilar Choque	Redes y Telecomunicaciones
37	Nicolás Fernanda	Medina Molina	Diseño Gráfico
38	Adrián Elena	Navarro Salazar	Administración de Empresas
39	Sebastián Eduardo	Ríos Paredes	Energías Renovables
40	Alejandro Patricia	Rivera Cruz	Sistemas Informáticos
41	Luis Verónica	Apaza Fernández	Contaduría General
42	Miguel Mateo	Pinto Pinto	Electricidad Industrial
43	Carlos Samuel	Molina Rojas	Química Industrial
44	Javier Adrián	Aguilar Ortega	Mecánica Industrial
45	Andrés Luis	Medina Torres	Mecánica Automotriz
46	Valeria Javier	Navarro Gutiérrez	Electrónica
47	Camila Camila	Ríos Apaza	Construcción Civil
48	Lucía Daniela	Rivera Montes	Redes y Telecomunicaciones
49	Mariana Andrea	Apaza Mendoza	Diseño Gráfico
50	Daniela Carolina	Pinto Soto	Administración de Empresas
51	Sofía Victoria	Molina Vega	Energías Renovables
52	Paola Mauricio	Aguilar Rivera	Sistemas Informáticos
53	Andrea Ricardo	Medina Mamani	Contaduría General
54	Gabriela Lorena	Navarro Villarroel	Electricidad Industrial
55	Natalia Gabriel	Ríos Castro	Química Industrial
56	Carolina Santiago	Rivera Morales	Mecánica Industrial
57	Fernanda Nicolás	Apaza Ríos	Mecánica Automotriz
58	Isabel Alejandro	Pinto Escobar	Electrónica
59	Victoria Carlos	Molina Soria	Construcción Civil
60	Elena Valeria	Aguilar Vargas	Redes y Telecomunicaciones
61	Rodrigo Mariana	Medina Romero	Diseño Gráfico
62	Mauricio Paola	Navarro Navarro	Administración de Empresas
63	Eduardo Natalia	Ríos López	Energías Renovables
64	Pablo Isabel	Rivera Quispe	Sistemas Informáticos
65	Ricardo Rodrigo	Apaza Arias	Contaduría General
66	Patricia Pablo	Pinto Flores	Electricidad Industrial
67	Claudia Claudia	Molina Medina	Química Industrial
68	Lorena Rosa	Aguilar Cabrera	Mecánica Industrial
69	Verónica Daniel	Medina Castillo	Mecánica Automotriz
70	Rosa Diego	Navarro Condori	Electrónica
71	Gabriel Sebastián	Ríos Delgado	Construcción Civil
72	Mateo Miguel	Rivera Aguilar	Redes y Telecomunicaciones
73	Daniel Andrés	Apaza Herrera	Diseño Gráfico
74	Santiago Lucía	Pinto Suárez	Administración de Empresas
75	Samuel Sofía	Molina Valdez	Energías Renovables
76	Diego Gabriela	Aguilar Choque	Sistemas Informáticos
77	Nicolás Fernanda	Medina Molina	Contaduría General
78	Adrián Elena	Navarro Salazar	Electricidad Industrial
79	Sebastián Eduardo	Ríos Paredes	Química Industrial
80	Alejandro Patricia	Rivera Cruz	Mecánica Industrial
\.


--
-- Data for Name: dim_estudiante; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.dim_estudiante (estudiante_id, registro, nombres, apellidos) FROM stdin;
838	DEMO-E-00833	Eduardo Isabel	Ríos Escobar
1	EST-001	Mateo	Rojas Salvatierra
2	EST-002	Valeria	Méndez Suárez
3	EST-003	Bruno	Castro Aguilar
5	DEMO-fbc571	Elena	Salvatierra Demo
6	DEMO-E-00001	Gabriel Adrián	Molina Flores
7	DEMO-E-00002	Mateo Adrián	Molina Medina
8	DEMO-E-00003	Daniel Adrián	Molina Cabrera
9	DEMO-E-00004	Santiago Adrián	Molina Castillo
10	DEMO-E-00005	Samuel Adrián	Molina Condori
11	DEMO-E-00006	Diego Adrián	Molina Delgado
12	DEMO-E-00007	Nicolás Adrián	Molina Aguilar
13	DEMO-E-00008	Adrián Adrián	Molina Herrera
14	DEMO-E-00009	Sebastián Adrián	Molina Suárez
15	DEMO-E-00010	Alejandro Adrián	Molina Valdez
16	DEMO-E-00011	Luis Adrián	Molina Choque
17	DEMO-E-00012	Miguel Adrián	Molina Molina
18	DEMO-E-00013	Carlos Adrián	Molina Salazar
19	DEMO-E-00014	Javier Adrián	Molina Paredes
20	DEMO-E-00015	Andrés Adrián	Molina Cruz
21	DEMO-E-00016	Valeria Adrián	Molina Fernández
22	DEMO-E-00017	Camila Adrián	Molina Pinto
23	DEMO-E-00018	Lucía Adrián	Molina Rojas
24	DEMO-E-00019	Mariana Adrián	Molina Ortega
25	DEMO-E-00020	Daniela Adrián	Molina Torres
26	DEMO-E-00021	Sofía Adrián	Molina Gutiérrez
27	DEMO-E-00022	Paola Adrián	Molina Apaza
28	DEMO-E-00023	Andrea Adrián	Molina Montes
29	DEMO-E-00024	Gabriela Adrián	Molina Mendoza
30	DEMO-E-00025	Natalia Adrián	Molina Soto
31	DEMO-E-00026	Carolina Adrián	Molina Vega
32	DEMO-E-00027	Fernanda Adrián	Molina Rivera
33	DEMO-E-00028	Isabel Adrián	Molina Mamani
34	DEMO-E-00029	Victoria Adrián	Molina Villarroel
35	DEMO-E-00030	Elena Adrián	Molina Castro
36	DEMO-E-00031	Rodrigo Adrián	Molina Morales
37	DEMO-E-00032	Mauricio Adrián	Molina Ríos
38	DEMO-E-00033	Eduardo Adrián	Molina Escobar
39	DEMO-E-00034	Pablo Adrián	Molina Soria
40	DEMO-E-00035	Ricardo Adrián	Molina Vargas
41	DEMO-E-00036	Patricia Adrián	Molina Romero
42	DEMO-E-00037	Claudia Adrián	Molina Navarro
43	DEMO-E-00038	Lorena Adrián	Molina López
44	DEMO-E-00039	Verónica Adrián	Molina Quispe
45	DEMO-E-00040	Rosa Adrián	Molina Arias
46	DEMO-E-00041	Gabriel Sebastián	Vargas Flores
47	DEMO-E-00042	Mateo Sebastián	Vargas Medina
48	DEMO-E-00043	Daniel Sebastián	Vargas Cabrera
49	DEMO-E-00044	Santiago Sebastián	Vargas Castillo
50	DEMO-E-00045	Samuel Sebastián	Vargas Condori
51	DEMO-E-00046	Diego Sebastián	Vargas Delgado
52	DEMO-E-00047	Nicolás Sebastián	Vargas Aguilar
53	DEMO-E-00048	Adrián Sebastián	Vargas Herrera
54	DEMO-E-00049	Sebastián Sebastián	Vargas Suárez
55	DEMO-E-00050	Alejandro Sebastián	Vargas Valdez
56	DEMO-E-00051	Luis Sebastián	Vargas Choque
57	DEMO-E-00052	Miguel Sebastián	Vargas Molina
58	DEMO-E-00053	Carlos Sebastián	Vargas Salazar
59	DEMO-E-00054	Javier Sebastián	Vargas Paredes
60	DEMO-E-00055	Andrés Sebastián	Vargas Cruz
61	DEMO-E-00056	Valeria Sebastián	Vargas Fernández
62	DEMO-E-00057	Camila Sebastián	Vargas Pinto
63	DEMO-E-00058	Lucía Sebastián	Vargas Rojas
64	DEMO-E-00059	Mariana Sebastián	Vargas Ortega
65	DEMO-E-00060	Daniela Sebastián	Vargas Torres
66	DEMO-E-00061	Sofía Sebastián	Vargas Gutiérrez
67	DEMO-E-00062	Paola Sebastián	Vargas Apaza
68	DEMO-E-00063	Andrea Sebastián	Vargas Montes
69	DEMO-E-00064	Gabriela Sebastián	Vargas Mendoza
70	DEMO-E-00065	Natalia Sebastián	Vargas Soto
71	DEMO-E-00066	Carolina Sebastián	Vargas Vega
72	DEMO-E-00067	Fernanda Sebastián	Vargas Rivera
73	DEMO-E-00068	Isabel Sebastián	Vargas Mamani
74	DEMO-E-00069	Victoria Sebastián	Vargas Villarroel
75	DEMO-E-00070	Elena Sebastián	Vargas Castro
76	DEMO-E-00071	Rodrigo Sebastián	Vargas Morales
77	DEMO-E-00072	Mauricio Sebastián	Vargas Ríos
78	DEMO-E-00073	Eduardo Sebastián	Vargas Escobar
79	DEMO-E-00074	Pablo Sebastián	Vargas Soria
80	DEMO-E-00075	Ricardo Sebastián	Vargas Vargas
81	DEMO-E-00076	Patricia Sebastián	Vargas Romero
82	DEMO-E-00077	Claudia Sebastián	Vargas Navarro
83	DEMO-E-00078	Lorena Sebastián	Vargas López
84	DEMO-E-00079	Verónica Sebastián	Vargas Quispe
85	DEMO-E-00080	Rosa Sebastián	Vargas Arias
86	DEMO-E-00081	Gabriel Alejandro	Rojas Flores
87	DEMO-E-00082	Mateo Alejandro	Rojas Medina
88	DEMO-E-00083	Daniel Alejandro	Rojas Cabrera
89	DEMO-E-00084	Santiago Alejandro	Rojas Castillo
90	DEMO-E-00085	Samuel Alejandro	Rojas Condori
91	DEMO-E-00086	Diego Alejandro	Rojas Delgado
92	DEMO-E-00087	Nicolás Alejandro	Rojas Aguilar
93	DEMO-E-00088	Adrián Alejandro	Rojas Herrera
94	DEMO-E-00089	Sebastián Alejandro	Rojas Suárez
95	DEMO-E-00090	Alejandro Alejandro	Rojas Valdez
96	DEMO-E-00091	Luis Alejandro	Rojas Choque
97	DEMO-E-00092	Miguel Alejandro	Rojas Molina
98	DEMO-E-00093	Carlos Alejandro	Rojas Salazar
99	DEMO-E-00094	Javier Alejandro	Rojas Paredes
100	DEMO-E-00095	Andrés Alejandro	Rojas Cruz
101	DEMO-E-00096	Valeria Alejandro	Rojas Fernández
102	DEMO-E-00097	Camila Alejandro	Rojas Pinto
103	DEMO-E-00098	Lucía Alejandro	Rojas Rojas
104	DEMO-E-00099	Mariana Alejandro	Rojas Ortega
105	DEMO-E-00100	Daniela Alejandro	Rojas Torres
106	DEMO-E-00101	Sofía Alejandro	Rojas Gutiérrez
107	DEMO-E-00102	Paola Alejandro	Rojas Apaza
108	DEMO-E-00103	Andrea Alejandro	Rojas Montes
109	DEMO-E-00104	Gabriela Alejandro	Rojas Mendoza
110	DEMO-E-00105	Natalia Alejandro	Rojas Soto
111	DEMO-E-00106	Carolina Alejandro	Rojas Vega
112	DEMO-E-00107	Fernanda Alejandro	Rojas Rivera
113	DEMO-E-00108	Isabel Alejandro	Rojas Mamani
114	DEMO-E-00109	Victoria Alejandro	Rojas Villarroel
115	DEMO-E-00110	Elena Alejandro	Rojas Castro
116	DEMO-E-00111	Rodrigo Alejandro	Rojas Morales
117	DEMO-E-00112	Mauricio Alejandro	Rojas Ríos
118	DEMO-E-00113	Eduardo Alejandro	Rojas Escobar
119	DEMO-E-00114	Pablo Alejandro	Rojas Soria
120	DEMO-E-00115	Ricardo Alejandro	Rojas Vargas
121	DEMO-E-00116	Patricia Alejandro	Rojas Romero
122	DEMO-E-00117	Claudia Alejandro	Rojas Navarro
123	DEMO-E-00118	Lorena Alejandro	Rojas López
124	DEMO-E-00119	Verónica Alejandro	Rojas Quispe
125	DEMO-E-00120	Rosa Alejandro	Rojas Arias
126	DEMO-E-00121	Gabriel Luis	Flores Flores
127	DEMO-E-00122	Mateo Luis	Flores Medina
128	DEMO-E-00123	Daniel Luis	Flores Cabrera
129	DEMO-E-00124	Santiago Luis	Flores Castillo
130	DEMO-E-00125	Samuel Luis	Flores Condori
131	DEMO-E-00126	Diego Luis	Flores Delgado
132	DEMO-E-00127	Nicolás Luis	Flores Aguilar
133	DEMO-E-00128	Adrián Luis	Flores Herrera
134	DEMO-E-00129	Sebastián Luis	Flores Suárez
135	DEMO-E-00130	Alejandro Luis	Flores Valdez
136	DEMO-E-00131	Luis Luis	Flores Choque
137	DEMO-E-00132	Miguel Luis	Flores Molina
138	DEMO-E-00133	Carlos Luis	Flores Salazar
139	DEMO-E-00134	Javier Luis	Flores Paredes
140	DEMO-E-00135	Andrés Luis	Flores Cruz
141	DEMO-E-00136	Valeria Luis	Flores Fernández
142	DEMO-E-00137	Camila Luis	Flores Pinto
143	DEMO-E-00138	Lucía Luis	Flores Rojas
144	DEMO-E-00139	Mariana Luis	Flores Ortega
145	DEMO-E-00140	Daniela Luis	Flores Torres
146	DEMO-E-00141	Sofía Luis	Flores Gutiérrez
147	DEMO-E-00142	Paola Luis	Flores Apaza
148	DEMO-E-00143	Andrea Luis	Flores Montes
149	DEMO-E-00144	Gabriela Luis	Flores Mendoza
150	DEMO-E-00145	Natalia Luis	Flores Soto
151	DEMO-E-00146	Carolina Luis	Flores Vega
152	DEMO-E-00147	Fernanda Luis	Flores Rivera
153	DEMO-E-00148	Isabel Luis	Flores Mamani
154	DEMO-E-00149	Victoria Luis	Flores Villarroel
155	DEMO-E-00150	Elena Luis	Flores Castro
156	DEMO-E-00151	Rodrigo Luis	Flores Morales
157	DEMO-E-00152	Mauricio Luis	Flores Ríos
158	DEMO-E-00153	Eduardo Luis	Flores Escobar
159	DEMO-E-00154	Pablo Luis	Flores Soria
160	DEMO-E-00155	Ricardo Luis	Flores Vargas
161	DEMO-E-00156	Patricia Luis	Flores Romero
162	DEMO-E-00157	Claudia Luis	Flores Navarro
163	DEMO-E-00158	Lorena Luis	Flores López
164	DEMO-E-00159	Verónica Luis	Flores Quispe
165	DEMO-E-00160	Rosa Luis	Flores Arias
166	DEMO-E-00161	Gabriel Miguel	Mendoza Flores
167	DEMO-E-00162	Mateo Miguel	Mendoza Medina
168	DEMO-E-00163	Daniel Miguel	Mendoza Cabrera
169	DEMO-E-00164	Santiago Miguel	Mendoza Castillo
170	DEMO-E-00165	Samuel Miguel	Mendoza Condori
171	DEMO-E-00166	Diego Miguel	Mendoza Delgado
172	DEMO-E-00167	Nicolás Miguel	Mendoza Aguilar
173	DEMO-E-00168	Adrián Miguel	Mendoza Herrera
174	DEMO-E-00169	Sebastián Miguel	Mendoza Suárez
175	DEMO-E-00170	Alejandro Miguel	Mendoza Valdez
176	DEMO-E-00171	Luis Miguel	Mendoza Choque
177	DEMO-E-00172	Miguel Miguel	Mendoza Molina
178	DEMO-E-00173	Carlos Miguel	Mendoza Salazar
179	DEMO-E-00174	Javier Miguel	Mendoza Paredes
180	DEMO-E-00175	Andrés Miguel	Mendoza Cruz
181	DEMO-E-00176	Valeria Miguel	Mendoza Fernández
182	DEMO-E-00177	Camila Miguel	Mendoza Pinto
183	DEMO-E-00178	Lucía Miguel	Mendoza Rojas
184	DEMO-E-00179	Mariana Miguel	Mendoza Ortega
185	DEMO-E-00180	Daniela Miguel	Mendoza Torres
186	DEMO-E-00181	Sofía Miguel	Mendoza Gutiérrez
187	DEMO-E-00182	Paola Miguel	Mendoza Apaza
188	DEMO-E-00183	Andrea Miguel	Mendoza Montes
189	DEMO-E-00184	Gabriela Miguel	Mendoza Mendoza
190	DEMO-E-00185	Natalia Miguel	Mendoza Soto
191	DEMO-E-00186	Carolina Miguel	Mendoza Vega
192	DEMO-E-00187	Fernanda Miguel	Mendoza Rivera
193	DEMO-E-00188	Isabel Miguel	Mendoza Mamani
194	DEMO-E-00189	Victoria Miguel	Mendoza Villarroel
195	DEMO-E-00190	Elena Miguel	Mendoza Castro
196	DEMO-E-00191	Rodrigo Miguel	Mendoza Morales
197	DEMO-E-00192	Mauricio Miguel	Mendoza Ríos
198	DEMO-E-00193	Eduardo Miguel	Mendoza Escobar
199	DEMO-E-00194	Pablo Miguel	Mendoza Soria
200	DEMO-E-00195	Ricardo Miguel	Mendoza Vargas
201	DEMO-E-00196	Patricia Miguel	Mendoza Romero
202	DEMO-E-00197	Claudia Miguel	Mendoza Navarro
203	DEMO-E-00198	Lorena Miguel	Mendoza López
204	DEMO-E-00199	Verónica Miguel	Mendoza Quispe
205	DEMO-E-00200	Rosa Miguel	Mendoza Arias
206	DEMO-E-00201	Gabriel Carlos	Aguilar Flores
207	DEMO-E-00202	Mateo Carlos	Aguilar Medina
208	DEMO-E-00203	Daniel Carlos	Aguilar Cabrera
209	DEMO-E-00204	Santiago Carlos	Aguilar Castillo
210	DEMO-E-00205	Samuel Carlos	Aguilar Condori
211	DEMO-E-00206	Diego Carlos	Aguilar Delgado
212	DEMO-E-00207	Nicolás Carlos	Aguilar Aguilar
213	DEMO-E-00208	Adrián Carlos	Aguilar Herrera
214	DEMO-E-00209	Sebastián Carlos	Aguilar Suárez
215	DEMO-E-00210	Alejandro Carlos	Aguilar Valdez
216	DEMO-E-00211	Luis Carlos	Aguilar Choque
217	DEMO-E-00212	Miguel Carlos	Aguilar Molina
218	DEMO-E-00213	Carlos Carlos	Aguilar Salazar
219	DEMO-E-00214	Javier Carlos	Aguilar Paredes
220	DEMO-E-00215	Andrés Carlos	Aguilar Cruz
221	DEMO-E-00216	Valeria Carlos	Aguilar Fernández
222	DEMO-E-00217	Camila Carlos	Aguilar Pinto
223	DEMO-E-00218	Lucía Carlos	Aguilar Rojas
224	DEMO-E-00219	Mariana Carlos	Aguilar Ortega
225	DEMO-E-00220	Daniela Carlos	Aguilar Torres
226	DEMO-E-00221	Sofía Carlos	Aguilar Gutiérrez
227	DEMO-E-00222	Paola Carlos	Aguilar Apaza
228	DEMO-E-00223	Andrea Carlos	Aguilar Montes
229	DEMO-E-00224	Gabriela Carlos	Aguilar Mendoza
230	DEMO-E-00225	Natalia Carlos	Aguilar Soto
231	DEMO-E-00226	Carolina Carlos	Aguilar Vega
232	DEMO-E-00227	Fernanda Carlos	Aguilar Rivera
233	DEMO-E-00228	Isabel Carlos	Aguilar Mamani
234	DEMO-E-00229	Victoria Carlos	Aguilar Villarroel
235	DEMO-E-00230	Elena Carlos	Aguilar Castro
236	DEMO-E-00231	Rodrigo Carlos	Aguilar Morales
237	DEMO-E-00232	Mauricio Carlos	Aguilar Ríos
238	DEMO-E-00233	Eduardo Carlos	Aguilar Escobar
239	DEMO-E-00234	Pablo Carlos	Aguilar Soria
240	DEMO-E-00235	Ricardo Carlos	Aguilar Vargas
241	DEMO-E-00236	Patricia Carlos	Aguilar Romero
242	DEMO-E-00237	Claudia Carlos	Aguilar Navarro
243	DEMO-E-00238	Lorena Carlos	Aguilar López
244	DEMO-E-00239	Verónica Carlos	Aguilar Quispe
245	DEMO-E-00240	Rosa Carlos	Aguilar Arias
246	DEMO-E-00241	Gabriel Javier	Castro Flores
247	DEMO-E-00242	Mateo Javier	Castro Medina
248	DEMO-E-00243	Daniel Javier	Castro Cabrera
249	DEMO-E-00244	Santiago Javier	Castro Castillo
250	DEMO-E-00245	Samuel Javier	Castro Condori
251	DEMO-E-00246	Diego Javier	Castro Delgado
252	DEMO-E-00247	Nicolás Javier	Castro Aguilar
253	DEMO-E-00248	Adrián Javier	Castro Herrera
254	DEMO-E-00249	Sebastián Javier	Castro Suárez
255	DEMO-E-00250	Alejandro Javier	Castro Valdez
256	DEMO-E-00251	Luis Javier	Castro Choque
257	DEMO-E-00252	Miguel Javier	Castro Molina
258	DEMO-E-00253	Carlos Javier	Castro Salazar
259	DEMO-E-00254	Javier Javier	Castro Paredes
260	DEMO-E-00255	Andrés Javier	Castro Cruz
261	DEMO-E-00256	Valeria Javier	Castro Fernández
262	DEMO-E-00257	Camila Javier	Castro Pinto
263	DEMO-E-00258	Lucía Javier	Castro Rojas
264	DEMO-E-00259	Mariana Javier	Castro Ortega
265	DEMO-E-00260	Daniela Javier	Castro Torres
266	DEMO-E-00261	Sofía Javier	Castro Gutiérrez
267	DEMO-E-00262	Paola Javier	Castro Apaza
268	DEMO-E-00263	Andrea Javier	Castro Montes
269	DEMO-E-00264	Gabriela Javier	Castro Mendoza
270	DEMO-E-00265	Natalia Javier	Castro Soto
271	DEMO-E-00266	Carolina Javier	Castro Vega
272	DEMO-E-00267	Fernanda Javier	Castro Rivera
273	DEMO-E-00268	Isabel Javier	Castro Mamani
274	DEMO-E-00269	Victoria Javier	Castro Villarroel
275	DEMO-E-00270	Elena Javier	Castro Castro
276	DEMO-E-00271	Rodrigo Javier	Castro Morales
277	DEMO-E-00272	Mauricio Javier	Castro Ríos
278	DEMO-E-00273	Eduardo Javier	Castro Escobar
279	DEMO-E-00274	Pablo Javier	Castro Soria
280	DEMO-E-00275	Ricardo Javier	Castro Vargas
281	DEMO-E-00276	Patricia Javier	Castro Romero
282	DEMO-E-00277	Claudia Javier	Castro Navarro
283	DEMO-E-00278	Lorena Javier	Castro López
284	DEMO-E-00279	Verónica Javier	Castro Quispe
285	DEMO-E-00280	Rosa Javier	Castro Arias
286	DEMO-E-00281	Gabriel Andrés	Salazar Flores
287	DEMO-E-00282	Mateo Andrés	Salazar Medina
288	DEMO-E-00283	Daniel Andrés	Salazar Cabrera
289	DEMO-E-00284	Santiago Andrés	Salazar Castillo
290	DEMO-E-00285	Samuel Andrés	Salazar Condori
291	DEMO-E-00286	Diego Andrés	Salazar Delgado
292	DEMO-E-00287	Nicolás Andrés	Salazar Aguilar
293	DEMO-E-00288	Adrián Andrés	Salazar Herrera
294	DEMO-E-00289	Sebastián Andrés	Salazar Suárez
295	DEMO-E-00290	Alejandro Andrés	Salazar Valdez
296	DEMO-E-00291	Luis Andrés	Salazar Choque
297	DEMO-E-00292	Miguel Andrés	Salazar Molina
298	DEMO-E-00293	Carlos Andrés	Salazar Salazar
299	DEMO-E-00294	Javier Andrés	Salazar Paredes
300	DEMO-E-00295	Andrés Andrés	Salazar Cruz
301	DEMO-E-00296	Valeria Andrés	Salazar Fernández
302	DEMO-E-00297	Camila Andrés	Salazar Pinto
303	DEMO-E-00298	Lucía Andrés	Salazar Rojas
304	DEMO-E-00299	Mariana Andrés	Salazar Ortega
305	DEMO-E-00300	Daniela Andrés	Salazar Torres
306	DEMO-E-00301	Sofía Andrés	Salazar Gutiérrez
307	DEMO-E-00302	Paola Andrés	Salazar Apaza
308	DEMO-E-00303	Andrea Andrés	Salazar Montes
309	DEMO-E-00304	Gabriela Andrés	Salazar Mendoza
310	DEMO-E-00305	Natalia Andrés	Salazar Soto
311	DEMO-E-00306	Carolina Andrés	Salazar Vega
312	DEMO-E-00307	Fernanda Andrés	Salazar Rivera
313	DEMO-E-00308	Isabel Andrés	Salazar Mamani
314	DEMO-E-00309	Victoria Andrés	Salazar Villarroel
315	DEMO-E-00310	Elena Andrés	Salazar Castro
316	DEMO-E-00311	Rodrigo Andrés	Salazar Morales
317	DEMO-E-00312	Mauricio Andrés	Salazar Ríos
318	DEMO-E-00313	Eduardo Andrés	Salazar Escobar
319	DEMO-E-00314	Pablo Andrés	Salazar Soria
320	DEMO-E-00315	Ricardo Andrés	Salazar Vargas
321	DEMO-E-00316	Patricia Andrés	Salazar Romero
322	DEMO-E-00317	Claudia Andrés	Salazar Navarro
323	DEMO-E-00318	Lorena Andrés	Salazar López
324	DEMO-E-00319	Verónica Andrés	Salazar Quispe
325	DEMO-E-00320	Rosa Andrés	Salazar Arias
326	DEMO-E-00321	Gabriel Valeria	Romero Flores
327	DEMO-E-00322	Mateo Valeria	Romero Medina
328	DEMO-E-00323	Daniel Valeria	Romero Cabrera
329	DEMO-E-00324	Santiago Valeria	Romero Castillo
330	DEMO-E-00325	Samuel Valeria	Romero Condori
331	DEMO-E-00326	Diego Valeria	Romero Delgado
332	DEMO-E-00327	Nicolás Valeria	Romero Aguilar
333	DEMO-E-00328	Adrián Valeria	Romero Herrera
334	DEMO-E-00329	Sebastián Valeria	Romero Suárez
335	DEMO-E-00330	Alejandro Valeria	Romero Valdez
336	DEMO-E-00331	Luis Valeria	Romero Choque
337	DEMO-E-00332	Miguel Valeria	Romero Molina
338	DEMO-E-00333	Carlos Valeria	Romero Salazar
339	DEMO-E-00334	Javier Valeria	Romero Paredes
340	DEMO-E-00335	Andrés Valeria	Romero Cruz
341	DEMO-E-00336	Valeria Valeria	Romero Fernández
342	DEMO-E-00337	Camila Valeria	Romero Pinto
343	DEMO-E-00338	Lucía Valeria	Romero Rojas
344	DEMO-E-00339	Mariana Valeria	Romero Ortega
345	DEMO-E-00340	Daniela Valeria	Romero Torres
346	DEMO-E-00341	Sofía Valeria	Romero Gutiérrez
347	DEMO-E-00342	Paola Valeria	Romero Apaza
348	DEMO-E-00343	Andrea Valeria	Romero Montes
349	DEMO-E-00344	Gabriela Valeria	Romero Mendoza
350	DEMO-E-00345	Natalia Valeria	Romero Soto
351	DEMO-E-00346	Carolina Valeria	Romero Vega
352	DEMO-E-00347	Fernanda Valeria	Romero Rivera
353	DEMO-E-00348	Isabel Valeria	Romero Mamani
354	DEMO-E-00349	Victoria Valeria	Romero Villarroel
355	DEMO-E-00350	Elena Valeria	Romero Castro
356	DEMO-E-00351	Rodrigo Valeria	Romero Morales
357	DEMO-E-00352	Mauricio Valeria	Romero Ríos
358	DEMO-E-00353	Eduardo Valeria	Romero Escobar
359	DEMO-E-00354	Pablo Valeria	Romero Soria
360	DEMO-E-00355	Ricardo Valeria	Romero Vargas
361	DEMO-E-00356	Patricia Valeria	Romero Romero
362	DEMO-E-00357	Claudia Valeria	Romero Navarro
363	DEMO-E-00358	Lorena Valeria	Romero López
364	DEMO-E-00359	Verónica Valeria	Romero Quispe
365	DEMO-E-00360	Rosa Valeria	Romero Arias
366	DEMO-E-00361	Gabriel Camila	Ortega Flores
367	DEMO-E-00362	Mateo Camila	Ortega Medina
368	DEMO-E-00363	Daniel Camila	Ortega Cabrera
369	DEMO-E-00364	Santiago Camila	Ortega Castillo
370	DEMO-E-00365	Samuel Camila	Ortega Condori
371	DEMO-E-00366	Diego Camila	Ortega Delgado
372	DEMO-E-00367	Nicolás Camila	Ortega Aguilar
373	DEMO-E-00368	Adrián Camila	Ortega Herrera
374	DEMO-E-00369	Sebastián Camila	Ortega Suárez
375	DEMO-E-00370	Alejandro Camila	Ortega Valdez
376	DEMO-E-00371	Luis Camila	Ortega Choque
377	DEMO-E-00372	Miguel Camila	Ortega Molina
378	DEMO-E-00373	Carlos Camila	Ortega Salazar
379	DEMO-E-00374	Javier Camila	Ortega Paredes
380	DEMO-E-00375	Andrés Camila	Ortega Cruz
381	DEMO-E-00376	Valeria Camila	Ortega Fernández
382	DEMO-E-00377	Camila Camila	Ortega Pinto
383	DEMO-E-00378	Lucía Camila	Ortega Rojas
384	DEMO-E-00379	Mariana Camila	Ortega Ortega
385	DEMO-E-00380	Daniela Camila	Ortega Torres
386	DEMO-E-00381	Sofía Camila	Ortega Gutiérrez
387	DEMO-E-00382	Paola Camila	Ortega Apaza
388	DEMO-E-00383	Andrea Camila	Ortega Montes
389	DEMO-E-00384	Gabriela Camila	Ortega Mendoza
390	DEMO-E-00385	Natalia Camila	Ortega Soto
391	DEMO-E-00386	Carolina Camila	Ortega Vega
392	DEMO-E-00387	Fernanda Camila	Ortega Rivera
393	DEMO-E-00388	Isabel Camila	Ortega Mamani
394	DEMO-E-00389	Victoria Camila	Ortega Villarroel
395	DEMO-E-00390	Elena Camila	Ortega Castro
396	DEMO-E-00391	Rodrigo Camila	Ortega Morales
397	DEMO-E-00392	Mauricio Camila	Ortega Ríos
398	DEMO-E-00393	Eduardo Camila	Ortega Escobar
399	DEMO-E-00394	Pablo Camila	Ortega Soria
400	DEMO-E-00395	Ricardo Camila	Ortega Vargas
401	DEMO-E-00396	Patricia Camila	Ortega Romero
402	DEMO-E-00397	Claudia Camila	Ortega Navarro
403	DEMO-E-00398	Lorena Camila	Ortega López
404	DEMO-E-00399	Verónica Camila	Ortega Quispe
405	DEMO-E-00400	Rosa Camila	Ortega Arias
406	DEMO-E-00401	Gabriel Lucía	Medina Flores
407	DEMO-E-00402	Mateo Lucía	Medina Medina
408	DEMO-E-00403	Daniel Lucía	Medina Cabrera
409	DEMO-E-00404	Santiago Lucía	Medina Castillo
410	DEMO-E-00405	Samuel Lucía	Medina Condori
411	DEMO-E-00406	Diego Lucía	Medina Delgado
412	DEMO-E-00407	Nicolás Lucía	Medina Aguilar
413	DEMO-E-00408	Adrián Lucía	Medina Herrera
414	DEMO-E-00409	Sebastián Lucía	Medina Suárez
415	DEMO-E-00410	Alejandro Lucía	Medina Valdez
416	DEMO-E-00411	Luis Lucía	Medina Choque
417	DEMO-E-00412	Miguel Lucía	Medina Molina
418	DEMO-E-00413	Carlos Lucía	Medina Salazar
419	DEMO-E-00414	Javier Lucía	Medina Paredes
420	DEMO-E-00415	Andrés Lucía	Medina Cruz
421	DEMO-E-00416	Valeria Lucía	Medina Fernández
422	DEMO-E-00417	Camila Lucía	Medina Pinto
423	DEMO-E-00418	Lucía Lucía	Medina Rojas
424	DEMO-E-00419	Mariana Lucía	Medina Ortega
425	DEMO-E-00420	Daniela Lucía	Medina Torres
426	DEMO-E-00421	Sofía Lucía	Medina Gutiérrez
427	DEMO-E-00422	Paola Lucía	Medina Apaza
428	DEMO-E-00423	Andrea Lucía	Medina Montes
429	DEMO-E-00424	Gabriela Lucía	Medina Mendoza
430	DEMO-E-00425	Natalia Lucía	Medina Soto
431	DEMO-E-00426	Carolina Lucía	Medina Vega
432	DEMO-E-00427	Fernanda Lucía	Medina Rivera
433	DEMO-E-00428	Isabel Lucía	Medina Mamani
434	DEMO-E-00429	Victoria Lucía	Medina Villarroel
435	DEMO-E-00430	Elena Lucía	Medina Castro
436	DEMO-E-00431	Rodrigo Lucía	Medina Morales
437	DEMO-E-00432	Mauricio Lucía	Medina Ríos
438	DEMO-E-00433	Eduardo Lucía	Medina Escobar
439	DEMO-E-00434	Pablo Lucía	Medina Soria
440	DEMO-E-00435	Ricardo Lucía	Medina Vargas
441	DEMO-E-00436	Patricia Lucía	Medina Romero
442	DEMO-E-00437	Claudia Lucía	Medina Navarro
443	DEMO-E-00438	Lorena Lucía	Medina López
444	DEMO-E-00439	Verónica Lucía	Medina Quispe
445	DEMO-E-00440	Rosa Lucía	Medina Arias
446	DEMO-E-00441	Gabriel Mariana	Soto Flores
447	DEMO-E-00442	Mateo Mariana	Soto Medina
448	DEMO-E-00443	Daniel Mariana	Soto Cabrera
449	DEMO-E-00444	Santiago Mariana	Soto Castillo
450	DEMO-E-00445	Samuel Mariana	Soto Condori
451	DEMO-E-00446	Diego Mariana	Soto Delgado
452	DEMO-E-00447	Nicolás Mariana	Soto Aguilar
453	DEMO-E-00448	Adrián Mariana	Soto Herrera
454	DEMO-E-00449	Sebastián Mariana	Soto Suárez
455	DEMO-E-00450	Alejandro Mariana	Soto Valdez
456	DEMO-E-00451	Luis Mariana	Soto Choque
457	DEMO-E-00452	Miguel Mariana	Soto Molina
458	DEMO-E-00453	Carlos Mariana	Soto Salazar
459	DEMO-E-00454	Javier Mariana	Soto Paredes
460	DEMO-E-00455	Andrés Mariana	Soto Cruz
461	DEMO-E-00456	Valeria Mariana	Soto Fernández
462	DEMO-E-00457	Camila Mariana	Soto Pinto
463	DEMO-E-00458	Lucía Mariana	Soto Rojas
464	DEMO-E-00459	Mariana Mariana	Soto Ortega
465	DEMO-E-00460	Daniela Mariana	Soto Torres
466	DEMO-E-00461	Sofía Mariana	Soto Gutiérrez
467	DEMO-E-00462	Paola Mariana	Soto Apaza
468	DEMO-E-00463	Andrea Mariana	Soto Montes
469	DEMO-E-00464	Gabriela Mariana	Soto Mendoza
470	DEMO-E-00465	Natalia Mariana	Soto Soto
471	DEMO-E-00466	Carolina Mariana	Soto Vega
472	DEMO-E-00467	Fernanda Mariana	Soto Rivera
473	DEMO-E-00468	Isabel Mariana	Soto Mamani
474	DEMO-E-00469	Victoria Mariana	Soto Villarroel
475	DEMO-E-00470	Elena Mariana	Soto Castro
476	DEMO-E-00471	Rodrigo Mariana	Soto Morales
477	DEMO-E-00472	Mauricio Mariana	Soto Ríos
478	DEMO-E-00473	Eduardo Mariana	Soto Escobar
479	DEMO-E-00474	Pablo Mariana	Soto Soria
480	DEMO-E-00475	Ricardo Mariana	Soto Vargas
481	DEMO-E-00476	Patricia Mariana	Soto Romero
482	DEMO-E-00477	Claudia Mariana	Soto Navarro
483	DEMO-E-00478	Lorena Mariana	Soto López
484	DEMO-E-00479	Verónica Mariana	Soto Quispe
485	DEMO-E-00480	Rosa Mariana	Soto Arias
486	DEMO-E-00481	Gabriel Daniela	Herrera Flores
487	DEMO-E-00482	Mateo Daniela	Herrera Medina
488	DEMO-E-00483	Daniel Daniela	Herrera Cabrera
489	DEMO-E-00484	Santiago Daniela	Herrera Castillo
490	DEMO-E-00485	Samuel Daniela	Herrera Condori
491	DEMO-E-00486	Diego Daniela	Herrera Delgado
492	DEMO-E-00487	Nicolás Daniela	Herrera Aguilar
493	DEMO-E-00488	Adrián Daniela	Herrera Herrera
494	DEMO-E-00489	Sebastián Daniela	Herrera Suárez
495	DEMO-E-00490	Alejandro Daniela	Herrera Valdez
496	DEMO-E-00491	Luis Daniela	Herrera Choque
497	DEMO-E-00492	Miguel Daniela	Herrera Molina
498	DEMO-E-00493	Carlos Daniela	Herrera Salazar
499	DEMO-E-00494	Javier Daniela	Herrera Paredes
500	DEMO-E-00495	Andrés Daniela	Herrera Cruz
501	DEMO-E-00496	Valeria Daniela	Herrera Fernández
502	DEMO-E-00497	Camila Daniela	Herrera Pinto
503	DEMO-E-00498	Lucía Daniela	Herrera Rojas
504	DEMO-E-00499	Mariana Daniela	Herrera Ortega
505	DEMO-E-00500	Daniela Daniela	Herrera Torres
506	DEMO-E-00501	Sofía Daniela	Herrera Gutiérrez
507	DEMO-E-00502	Paola Daniela	Herrera Apaza
508	DEMO-E-00503	Andrea Daniela	Herrera Montes
509	DEMO-E-00504	Gabriela Daniela	Herrera Mendoza
510	DEMO-E-00505	Natalia Daniela	Herrera Soto
511	DEMO-E-00506	Carolina Daniela	Herrera Vega
512	DEMO-E-00507	Fernanda Daniela	Herrera Rivera
513	DEMO-E-00508	Isabel Daniela	Herrera Mamani
514	DEMO-E-00509	Victoria Daniela	Herrera Villarroel
515	DEMO-E-00510	Elena Daniela	Herrera Castro
516	DEMO-E-00511	Rodrigo Daniela	Herrera Morales
517	DEMO-E-00512	Mauricio Daniela	Herrera Ríos
518	DEMO-E-00513	Eduardo Daniela	Herrera Escobar
519	DEMO-E-00514	Pablo Daniela	Herrera Soria
520	DEMO-E-00515	Ricardo Daniela	Herrera Vargas
521	DEMO-E-00516	Patricia Daniela	Herrera Romero
522	DEMO-E-00517	Claudia Daniela	Herrera Navarro
523	DEMO-E-00518	Lorena Daniela	Herrera López
524	DEMO-E-00519	Verónica Daniela	Herrera Quispe
525	DEMO-E-00520	Rosa Daniela	Herrera Arias
526	DEMO-E-00521	Gabriel Sofía	Morales Flores
527	DEMO-E-00522	Mateo Sofía	Morales Medina
528	DEMO-E-00523	Daniel Sofía	Morales Cabrera
529	DEMO-E-00524	Santiago Sofía	Morales Castillo
530	DEMO-E-00525	Samuel Sofía	Morales Condori
531	DEMO-E-00526	Diego Sofía	Morales Delgado
532	DEMO-E-00527	Nicolás Sofía	Morales Aguilar
533	DEMO-E-00528	Adrián Sofía	Morales Herrera
534	DEMO-E-00529	Sebastián Sofía	Morales Suárez
535	DEMO-E-00530	Alejandro Sofía	Morales Valdez
536	DEMO-E-00531	Luis Sofía	Morales Choque
537	DEMO-E-00532	Miguel Sofía	Morales Molina
538	DEMO-E-00533	Carlos Sofía	Morales Salazar
539	DEMO-E-00534	Javier Sofía	Morales Paredes
540	DEMO-E-00535	Andrés Sofía	Morales Cruz
541	DEMO-E-00536	Valeria Sofía	Morales Fernández
542	DEMO-E-00537	Camila Sofía	Morales Pinto
543	DEMO-E-00538	Lucía Sofía	Morales Rojas
544	DEMO-E-00539	Mariana Sofía	Morales Ortega
545	DEMO-E-00540	Daniela Sofía	Morales Torres
546	DEMO-E-00541	Sofía Sofía	Morales Gutiérrez
547	DEMO-E-00542	Paola Sofía	Morales Apaza
548	DEMO-E-00543	Andrea Sofía	Morales Montes
549	DEMO-E-00544	Gabriela Sofía	Morales Mendoza
550	DEMO-E-00545	Natalia Sofía	Morales Soto
551	DEMO-E-00546	Carolina Sofía	Morales Vega
552	DEMO-E-00547	Fernanda Sofía	Morales Rivera
553	DEMO-E-00548	Isabel Sofía	Morales Mamani
554	DEMO-E-00549	Victoria Sofía	Morales Villarroel
555	DEMO-E-00550	Elena Sofía	Morales Castro
556	DEMO-E-00551	Rodrigo Sofía	Morales Morales
557	DEMO-E-00552	Mauricio Sofía	Morales Ríos
558	DEMO-E-00553	Eduardo Sofía	Morales Escobar
559	DEMO-E-00554	Pablo Sofía	Morales Soria
560	DEMO-E-00555	Ricardo Sofía	Morales Vargas
561	DEMO-E-00556	Patricia Sofía	Morales Romero
562	DEMO-E-00557	Claudia Sofía	Morales Navarro
563	DEMO-E-00558	Lorena Sofía	Morales López
564	DEMO-E-00559	Verónica Sofía	Morales Quispe
565	DEMO-E-00560	Rosa Sofía	Morales Arias
566	DEMO-E-00561	Gabriel Paola	Paredes Flores
567	DEMO-E-00562	Mateo Paola	Paredes Medina
568	DEMO-E-00563	Daniel Paola	Paredes Cabrera
569	DEMO-E-00564	Santiago Paola	Paredes Castillo
570	DEMO-E-00565	Samuel Paola	Paredes Condori
571	DEMO-E-00566	Diego Paola	Paredes Delgado
572	DEMO-E-00567	Nicolás Paola	Paredes Aguilar
573	DEMO-E-00568	Adrián Paola	Paredes Herrera
574	DEMO-E-00569	Sebastián Paola	Paredes Suárez
575	DEMO-E-00570	Alejandro Paola	Paredes Valdez
576	DEMO-E-00571	Luis Paola	Paredes Choque
577	DEMO-E-00572	Miguel Paola	Paredes Molina
578	DEMO-E-00573	Carlos Paola	Paredes Salazar
579	DEMO-E-00574	Javier Paola	Paredes Paredes
580	DEMO-E-00575	Andrés Paola	Paredes Cruz
581	DEMO-E-00576	Valeria Paola	Paredes Fernández
582	DEMO-E-00577	Camila Paola	Paredes Pinto
583	DEMO-E-00578	Lucía Paola	Paredes Rojas
584	DEMO-E-00579	Mariana Paola	Paredes Ortega
585	DEMO-E-00580	Daniela Paola	Paredes Torres
586	DEMO-E-00581	Sofía Paola	Paredes Gutiérrez
587	DEMO-E-00582	Paola Paola	Paredes Apaza
588	DEMO-E-00583	Andrea Paola	Paredes Montes
589	DEMO-E-00584	Gabriela Paola	Paredes Mendoza
590	DEMO-E-00585	Natalia Paola	Paredes Soto
591	DEMO-E-00586	Carolina Paola	Paredes Vega
592	DEMO-E-00587	Fernanda Paola	Paredes Rivera
593	DEMO-E-00588	Isabel Paola	Paredes Mamani
594	DEMO-E-00589	Victoria Paola	Paredes Villarroel
595	DEMO-E-00590	Elena Paola	Paredes Castro
596	DEMO-E-00591	Rodrigo Paola	Paredes Morales
597	DEMO-E-00592	Mauricio Paola	Paredes Ríos
598	DEMO-E-00593	Eduardo Paola	Paredes Escobar
599	DEMO-E-00594	Pablo Paola	Paredes Soria
600	DEMO-E-00595	Ricardo Paola	Paredes Vargas
601	DEMO-E-00596	Patricia Paola	Paredes Romero
602	DEMO-E-00597	Claudia Paola	Paredes Navarro
603	DEMO-E-00598	Lorena Paola	Paredes López
604	DEMO-E-00599	Verónica Paola	Paredes Quispe
605	DEMO-E-00600	Rosa Paola	Paredes Arias
606	DEMO-E-00601	Gabriel Andrea	Navarro Flores
607	DEMO-E-00602	Mateo Andrea	Navarro Medina
608	DEMO-E-00603	Daniel Andrea	Navarro Cabrera
609	DEMO-E-00604	Santiago Andrea	Navarro Castillo
610	DEMO-E-00605	Samuel Andrea	Navarro Condori
611	DEMO-E-00606	Diego Andrea	Navarro Delgado
612	DEMO-E-00607	Nicolás Andrea	Navarro Aguilar
613	DEMO-E-00608	Adrián Andrea	Navarro Herrera
614	DEMO-E-00609	Sebastián Andrea	Navarro Suárez
615	DEMO-E-00610	Alejandro Andrea	Navarro Valdez
616	DEMO-E-00611	Luis Andrea	Navarro Choque
617	DEMO-E-00612	Miguel Andrea	Navarro Molina
618	DEMO-E-00613	Carlos Andrea	Navarro Salazar
619	DEMO-E-00614	Javier Andrea	Navarro Paredes
620	DEMO-E-00615	Andrés Andrea	Navarro Cruz
621	DEMO-E-00616	Valeria Andrea	Navarro Fernández
622	DEMO-E-00617	Camila Andrea	Navarro Pinto
623	DEMO-E-00618	Lucía Andrea	Navarro Rojas
624	DEMO-E-00619	Mariana Andrea	Navarro Ortega
625	DEMO-E-00620	Daniela Andrea	Navarro Torres
626	DEMO-E-00621	Sofía Andrea	Navarro Gutiérrez
627	DEMO-E-00622	Paola Andrea	Navarro Apaza
628	DEMO-E-00623	Andrea Andrea	Navarro Montes
629	DEMO-E-00624	Gabriela Andrea	Navarro Mendoza
630	DEMO-E-00625	Natalia Andrea	Navarro Soto
631	DEMO-E-00626	Carolina Andrea	Navarro Vega
632	DEMO-E-00627	Fernanda Andrea	Navarro Rivera
633	DEMO-E-00628	Isabel Andrea	Navarro Mamani
634	DEMO-E-00629	Victoria Andrea	Navarro Villarroel
635	DEMO-E-00630	Elena Andrea	Navarro Castro
636	DEMO-E-00631	Rodrigo Andrea	Navarro Morales
637	DEMO-E-00632	Mauricio Andrea	Navarro Ríos
638	DEMO-E-00633	Eduardo Andrea	Navarro Escobar
639	DEMO-E-00634	Pablo Andrea	Navarro Soria
640	DEMO-E-00635	Ricardo Andrea	Navarro Vargas
641	DEMO-E-00636	Patricia Andrea	Navarro Romero
642	DEMO-E-00637	Claudia Andrea	Navarro Navarro
643	DEMO-E-00638	Lorena Andrea	Navarro López
644	DEMO-E-00639	Verónica Andrea	Navarro Quispe
645	DEMO-E-00640	Rosa Andrea	Navarro Arias
646	DEMO-E-00641	Gabriel Gabriela	Torres Flores
647	DEMO-E-00642	Mateo Gabriela	Torres Medina
648	DEMO-E-00643	Daniel Gabriela	Torres Cabrera
649	DEMO-E-00644	Santiago Gabriela	Torres Castillo
650	DEMO-E-00645	Samuel Gabriela	Torres Condori
651	DEMO-E-00646	Diego Gabriela	Torres Delgado
652	DEMO-E-00647	Nicolás Gabriela	Torres Aguilar
653	DEMO-E-00648	Adrián Gabriela	Torres Herrera
654	DEMO-E-00649	Sebastián Gabriela	Torres Suárez
655	DEMO-E-00650	Alejandro Gabriela	Torres Valdez
656	DEMO-E-00651	Luis Gabriela	Torres Choque
657	DEMO-E-00652	Miguel Gabriela	Torres Molina
658	DEMO-E-00653	Carlos Gabriela	Torres Salazar
659	DEMO-E-00654	Javier Gabriela	Torres Paredes
660	DEMO-E-00655	Andrés Gabriela	Torres Cruz
661	DEMO-E-00656	Valeria Gabriela	Torres Fernández
662	DEMO-E-00657	Camila Gabriela	Torres Pinto
663	DEMO-E-00658	Lucía Gabriela	Torres Rojas
664	DEMO-E-00659	Mariana Gabriela	Torres Ortega
665	DEMO-E-00660	Daniela Gabriela	Torres Torres
666	DEMO-E-00661	Sofía Gabriela	Torres Gutiérrez
667	DEMO-E-00662	Paola Gabriela	Torres Apaza
668	DEMO-E-00663	Andrea Gabriela	Torres Montes
669	DEMO-E-00664	Gabriela Gabriela	Torres Mendoza
670	DEMO-E-00665	Natalia Gabriela	Torres Soto
671	DEMO-E-00666	Carolina Gabriela	Torres Vega
672	DEMO-E-00667	Fernanda Gabriela	Torres Rivera
673	DEMO-E-00668	Isabel Gabriela	Torres Mamani
674	DEMO-E-00669	Victoria Gabriela	Torres Villarroel
675	DEMO-E-00670	Elena Gabriela	Torres Castro
676	DEMO-E-00671	Rodrigo Gabriela	Torres Morales
677	DEMO-E-00672	Mauricio Gabriela	Torres Ríos
678	DEMO-E-00673	Eduardo Gabriela	Torres Escobar
679	DEMO-E-00674	Pablo Gabriela	Torres Soria
680	DEMO-E-00675	Ricardo Gabriela	Torres Vargas
681	DEMO-E-00676	Patricia Gabriela	Torres Romero
682	DEMO-E-00677	Claudia Gabriela	Torres Navarro
683	DEMO-E-00678	Lorena Gabriela	Torres López
684	DEMO-E-00679	Verónica Gabriela	Torres Quispe
685	DEMO-E-00680	Rosa Gabriela	Torres Arias
686	DEMO-E-00681	Gabriel Natalia	Cabrera Flores
687	DEMO-E-00682	Mateo Natalia	Cabrera Medina
688	DEMO-E-00683	Daniel Natalia	Cabrera Cabrera
689	DEMO-E-00684	Santiago Natalia	Cabrera Castillo
690	DEMO-E-00685	Samuel Natalia	Cabrera Condori
691	DEMO-E-00686	Diego Natalia	Cabrera Delgado
692	DEMO-E-00687	Nicolás Natalia	Cabrera Aguilar
693	DEMO-E-00688	Adrián Natalia	Cabrera Herrera
694	DEMO-E-00689	Sebastián Natalia	Cabrera Suárez
695	DEMO-E-00690	Alejandro Natalia	Cabrera Valdez
696	DEMO-E-00691	Luis Natalia	Cabrera Choque
697	DEMO-E-00692	Miguel Natalia	Cabrera Molina
698	DEMO-E-00693	Carlos Natalia	Cabrera Salazar
699	DEMO-E-00694	Javier Natalia	Cabrera Paredes
700	DEMO-E-00695	Andrés Natalia	Cabrera Cruz
701	DEMO-E-00696	Valeria Natalia	Cabrera Fernández
702	DEMO-E-00697	Camila Natalia	Cabrera Pinto
703	DEMO-E-00698	Lucía Natalia	Cabrera Rojas
704	DEMO-E-00699	Mariana Natalia	Cabrera Ortega
705	DEMO-E-00700	Daniela Natalia	Cabrera Torres
706	DEMO-E-00701	Sofía Natalia	Cabrera Gutiérrez
707	DEMO-E-00702	Paola Natalia	Cabrera Apaza
708	DEMO-E-00703	Andrea Natalia	Cabrera Montes
709	DEMO-E-00704	Gabriela Natalia	Cabrera Mendoza
710	DEMO-E-00705	Natalia Natalia	Cabrera Soto
711	DEMO-E-00706	Carolina Natalia	Cabrera Vega
712	DEMO-E-00707	Fernanda Natalia	Cabrera Rivera
713	DEMO-E-00708	Isabel Natalia	Cabrera Mamani
714	DEMO-E-00709	Victoria Natalia	Cabrera Villarroel
715	DEMO-E-00710	Elena Natalia	Cabrera Castro
716	DEMO-E-00711	Rodrigo Natalia	Cabrera Morales
717	DEMO-E-00712	Mauricio Natalia	Cabrera Ríos
718	DEMO-E-00713	Eduardo Natalia	Cabrera Escobar
719	DEMO-E-00714	Pablo Natalia	Cabrera Soria
720	DEMO-E-00715	Ricardo Natalia	Cabrera Vargas
721	DEMO-E-00716	Patricia Natalia	Cabrera Romero
722	DEMO-E-00717	Claudia Natalia	Cabrera Navarro
723	DEMO-E-00718	Lorena Natalia	Cabrera López
724	DEMO-E-00719	Verónica Natalia	Cabrera Quispe
725	DEMO-E-00720	Rosa Natalia	Cabrera Arias
726	DEMO-E-00721	Gabriel Carolina	Vega Flores
727	DEMO-E-00722	Mateo Carolina	Vega Medina
728	DEMO-E-00723	Daniel Carolina	Vega Cabrera
729	DEMO-E-00724	Santiago Carolina	Vega Castillo
730	DEMO-E-00725	Samuel Carolina	Vega Condori
731	DEMO-E-00726	Diego Carolina	Vega Delgado
732	DEMO-E-00727	Nicolás Carolina	Vega Aguilar
733	DEMO-E-00728	Adrián Carolina	Vega Herrera
734	DEMO-E-00729	Sebastián Carolina	Vega Suárez
735	DEMO-E-00730	Alejandro Carolina	Vega Valdez
736	DEMO-E-00731	Luis Carolina	Vega Choque
737	DEMO-E-00732	Miguel Carolina	Vega Molina
738	DEMO-E-00733	Carlos Carolina	Vega Salazar
739	DEMO-E-00734	Javier Carolina	Vega Paredes
740	DEMO-E-00735	Andrés Carolina	Vega Cruz
741	DEMO-E-00736	Valeria Carolina	Vega Fernández
742	DEMO-E-00737	Camila Carolina	Vega Pinto
743	DEMO-E-00738	Lucía Carolina	Vega Rojas
744	DEMO-E-00739	Mariana Carolina	Vega Ortega
745	DEMO-E-00740	Daniela Carolina	Vega Torres
746	DEMO-E-00741	Sofía Carolina	Vega Gutiérrez
747	DEMO-E-00742	Paola Carolina	Vega Apaza
748	DEMO-E-00743	Andrea Carolina	Vega Montes
749	DEMO-E-00744	Gabriela Carolina	Vega Mendoza
750	DEMO-E-00745	Natalia Carolina	Vega Soto
751	DEMO-E-00746	Carolina Carolina	Vega Vega
752	DEMO-E-00747	Fernanda Carolina	Vega Rivera
753	DEMO-E-00748	Isabel Carolina	Vega Mamani
754	DEMO-E-00749	Victoria Carolina	Vega Villarroel
755	DEMO-E-00750	Elena Carolina	Vega Castro
756	DEMO-E-00751	Rodrigo Carolina	Vega Morales
757	DEMO-E-00752	Mauricio Carolina	Vega Ríos
758	DEMO-E-00753	Eduardo Carolina	Vega Escobar
759	DEMO-E-00754	Pablo Carolina	Vega Soria
760	DEMO-E-00755	Ricardo Carolina	Vega Vargas
761	DEMO-E-00756	Patricia Carolina	Vega Romero
762	DEMO-E-00757	Claudia Carolina	Vega Navarro
763	DEMO-E-00758	Lorena Carolina	Vega López
764	DEMO-E-00759	Verónica Carolina	Vega Quispe
765	DEMO-E-00760	Rosa Carolina	Vega Arias
766	DEMO-E-00761	Gabriel Fernanda	Suárez Flores
767	DEMO-E-00762	Mateo Fernanda	Suárez Medina
768	DEMO-E-00763	Daniel Fernanda	Suárez Cabrera
769	DEMO-E-00764	Santiago Fernanda	Suárez Castillo
770	DEMO-E-00765	Samuel Fernanda	Suárez Condori
771	DEMO-E-00766	Diego Fernanda	Suárez Delgado
772	DEMO-E-00767	Nicolás Fernanda	Suárez Aguilar
773	DEMO-E-00768	Adrián Fernanda	Suárez Herrera
774	DEMO-E-00769	Sebastián Fernanda	Suárez Suárez
775	DEMO-E-00770	Alejandro Fernanda	Suárez Valdez
776	DEMO-E-00771	Luis Fernanda	Suárez Choque
777	DEMO-E-00772	Miguel Fernanda	Suárez Molina
778	DEMO-E-00773	Carlos Fernanda	Suárez Salazar
779	DEMO-E-00774	Javier Fernanda	Suárez Paredes
780	DEMO-E-00775	Andrés Fernanda	Suárez Cruz
781	DEMO-E-00776	Valeria Fernanda	Suárez Fernández
782	DEMO-E-00777	Camila Fernanda	Suárez Pinto
783	DEMO-E-00778	Lucía Fernanda	Suárez Rojas
784	DEMO-E-00779	Mariana Fernanda	Suárez Ortega
785	DEMO-E-00780	Daniela Fernanda	Suárez Torres
786	DEMO-E-00781	Sofía Fernanda	Suárez Gutiérrez
787	DEMO-E-00782	Paola Fernanda	Suárez Apaza
788	DEMO-E-00783	Andrea Fernanda	Suárez Montes
789	DEMO-E-00784	Gabriela Fernanda	Suárez Mendoza
790	DEMO-E-00785	Natalia Fernanda	Suárez Soto
791	DEMO-E-00786	Carolina Fernanda	Suárez Vega
792	DEMO-E-00787	Fernanda Fernanda	Suárez Rivera
793	DEMO-E-00788	Isabel Fernanda	Suárez Mamani
794	DEMO-E-00789	Victoria Fernanda	Suárez Villarroel
795	DEMO-E-00790	Elena Fernanda	Suárez Castro
796	DEMO-E-00791	Rodrigo Fernanda	Suárez Morales
797	DEMO-E-00792	Mauricio Fernanda	Suárez Ríos
798	DEMO-E-00793	Eduardo Fernanda	Suárez Escobar
799	DEMO-E-00794	Pablo Fernanda	Suárez Soria
800	DEMO-E-00795	Ricardo Fernanda	Suárez Vargas
801	DEMO-E-00796	Patricia Fernanda	Suárez Romero
802	DEMO-E-00797	Claudia Fernanda	Suárez Navarro
803	DEMO-E-00798	Lorena Fernanda	Suárez López
804	DEMO-E-00799	Verónica Fernanda	Suárez Quispe
805	DEMO-E-00800	Rosa Fernanda	Suárez Arias
806	DEMO-E-00801	Gabriel Isabel	Ríos Flores
807	DEMO-E-00802	Mateo Isabel	Ríos Medina
808	DEMO-E-00803	Daniel Isabel	Ríos Cabrera
809	DEMO-E-00804	Santiago Isabel	Ríos Castillo
810	DEMO-E-00805	Samuel Isabel	Ríos Condori
811	DEMO-E-00806	Diego Isabel	Ríos Delgado
812	DEMO-E-00807	Nicolás Isabel	Ríos Aguilar
813	DEMO-E-00808	Adrián Isabel	Ríos Herrera
814	DEMO-E-00809	Sebastián Isabel	Ríos Suárez
815	DEMO-E-00810	Alejandro Isabel	Ríos Valdez
816	DEMO-E-00811	Luis Isabel	Ríos Choque
817	DEMO-E-00812	Miguel Isabel	Ríos Molina
818	DEMO-E-00813	Carlos Isabel	Ríos Salazar
819	DEMO-E-00814	Javier Isabel	Ríos Paredes
820	DEMO-E-00815	Andrés Isabel	Ríos Cruz
821	DEMO-E-00816	Valeria Isabel	Ríos Fernández
822	DEMO-E-00817	Camila Isabel	Ríos Pinto
823	DEMO-E-00818	Lucía Isabel	Ríos Rojas
824	DEMO-E-00819	Mariana Isabel	Ríos Ortega
825	DEMO-E-00820	Daniela Isabel	Ríos Torres
826	DEMO-E-00821	Sofía Isabel	Ríos Gutiérrez
827	DEMO-E-00822	Paola Isabel	Ríos Apaza
828	DEMO-E-00823	Andrea Isabel	Ríos Montes
829	DEMO-E-00824	Gabriela Isabel	Ríos Mendoza
830	DEMO-E-00825	Natalia Isabel	Ríos Soto
831	DEMO-E-00826	Carolina Isabel	Ríos Vega
832	DEMO-E-00827	Fernanda Isabel	Ríos Rivera
833	DEMO-E-00828	Isabel Isabel	Ríos Mamani
834	DEMO-E-00829	Victoria Isabel	Ríos Villarroel
835	DEMO-E-00830	Elena Isabel	Ríos Castro
836	DEMO-E-00831	Rodrigo Isabel	Ríos Morales
837	DEMO-E-00832	Mauricio Isabel	Ríos Ríos
839	DEMO-E-00834	Pablo Isabel	Ríos Soria
840	DEMO-E-00835	Ricardo Isabel	Ríos Vargas
841	DEMO-E-00836	Patricia Isabel	Ríos Romero
842	DEMO-E-00837	Claudia Isabel	Ríos Navarro
843	DEMO-E-00838	Lorena Isabel	Ríos López
844	DEMO-E-00839	Verónica Isabel	Ríos Quispe
845	DEMO-E-00840	Rosa Isabel	Ríos Arias
846	DEMO-E-00841	Gabriel Victoria	Cruz Flores
847	DEMO-E-00842	Mateo Victoria	Cruz Medina
848	DEMO-E-00843	Daniel Victoria	Cruz Cabrera
849	DEMO-E-00844	Santiago Victoria	Cruz Castillo
850	DEMO-E-00845	Samuel Victoria	Cruz Condori
851	DEMO-E-00846	Diego Victoria	Cruz Delgado
852	DEMO-E-00847	Nicolás Victoria	Cruz Aguilar
853	DEMO-E-00848	Adrián Victoria	Cruz Herrera
854	DEMO-E-00849	Sebastián Victoria	Cruz Suárez
855	DEMO-E-00850	Alejandro Victoria	Cruz Valdez
856	DEMO-E-00851	Luis Victoria	Cruz Choque
857	DEMO-E-00852	Miguel Victoria	Cruz Molina
858	DEMO-E-00853	Carlos Victoria	Cruz Salazar
859	DEMO-E-00854	Javier Victoria	Cruz Paredes
860	DEMO-E-00855	Andrés Victoria	Cruz Cruz
861	DEMO-E-00856	Valeria Victoria	Cruz Fernández
862	DEMO-E-00857	Camila Victoria	Cruz Pinto
863	DEMO-E-00858	Lucía Victoria	Cruz Rojas
864	DEMO-E-00859	Mariana Victoria	Cruz Ortega
865	DEMO-E-00860	Daniela Victoria	Cruz Torres
866	DEMO-E-00861	Sofía Victoria	Cruz Gutiérrez
867	DEMO-E-00862	Paola Victoria	Cruz Apaza
868	DEMO-E-00863	Andrea Victoria	Cruz Montes
869	DEMO-E-00864	Gabriela Victoria	Cruz Mendoza
870	DEMO-E-00865	Natalia Victoria	Cruz Soto
871	DEMO-E-00866	Carolina Victoria	Cruz Vega
872	DEMO-E-00867	Fernanda Victoria	Cruz Rivera
873	DEMO-E-00868	Isabel Victoria	Cruz Mamani
874	DEMO-E-00869	Victoria Victoria	Cruz Villarroel
875	DEMO-E-00870	Elena Victoria	Cruz Castro
876	DEMO-E-00871	Rodrigo Victoria	Cruz Morales
877	DEMO-E-00872	Mauricio Victoria	Cruz Ríos
878	DEMO-E-00873	Eduardo Victoria	Cruz Escobar
879	DEMO-E-00874	Pablo Victoria	Cruz Soria
880	DEMO-E-00875	Ricardo Victoria	Cruz Vargas
881	DEMO-E-00876	Patricia Victoria	Cruz Romero
882	DEMO-E-00877	Claudia Victoria	Cruz Navarro
883	DEMO-E-00878	Lorena Victoria	Cruz López
884	DEMO-E-00879	Verónica Victoria	Cruz Quispe
885	DEMO-E-00880	Rosa Victoria	Cruz Arias
886	DEMO-E-00881	Gabriel Elena	López Flores
887	DEMO-E-00882	Mateo Elena	López Medina
888	DEMO-E-00883	Daniel Elena	López Cabrera
889	DEMO-E-00884	Santiago Elena	López Castillo
890	DEMO-E-00885	Samuel Elena	López Condori
891	DEMO-E-00886	Diego Elena	López Delgado
892	DEMO-E-00887	Nicolás Elena	López Aguilar
893	DEMO-E-00888	Adrián Elena	López Herrera
894	DEMO-E-00889	Sebastián Elena	López Suárez
895	DEMO-E-00890	Alejandro Elena	López Valdez
896	DEMO-E-00891	Luis Elena	López Choque
897	DEMO-E-00892	Miguel Elena	López Molina
898	DEMO-E-00893	Carlos Elena	López Salazar
899	DEMO-E-00894	Javier Elena	López Paredes
900	DEMO-E-00895	Andrés Elena	López Cruz
901	DEMO-E-00896	Valeria Elena	López Fernández
902	DEMO-E-00897	Camila Elena	López Pinto
903	DEMO-E-00898	Lucía Elena	López Rojas
904	DEMO-E-00899	Mariana Elena	López Ortega
905	DEMO-E-00900	Daniela Elena	López Torres
906	DEMO-E-00901	Sofía Elena	López Gutiérrez
907	DEMO-E-00902	Paola Elena	López Apaza
908	DEMO-E-00903	Andrea Elena	López Montes
909	DEMO-E-00904	Gabriela Elena	López Mendoza
910	DEMO-E-00905	Natalia Elena	López Soto
911	DEMO-E-00906	Carolina Elena	López Vega
912	DEMO-E-00907	Fernanda Elena	López Rivera
913	DEMO-E-00908	Isabel Elena	López Mamani
914	DEMO-E-00909	Victoria Elena	López Villarroel
915	DEMO-E-00910	Elena Elena	López Castro
916	DEMO-E-00911	Rodrigo Elena	López Morales
917	DEMO-E-00912	Mauricio Elena	López Ríos
918	DEMO-E-00913	Eduardo Elena	López Escobar
919	DEMO-E-00914	Pablo Elena	López Soria
920	DEMO-E-00915	Ricardo Elena	López Vargas
921	DEMO-E-00916	Patricia Elena	López Romero
922	DEMO-E-00917	Claudia Elena	López Navarro
923	DEMO-E-00918	Lorena Elena	López López
924	DEMO-E-00919	Verónica Elena	López Quispe
925	DEMO-E-00920	Rosa Elena	López Arias
926	DEMO-E-00921	Gabriel Rodrigo	Gutiérrez Flores
927	DEMO-E-00922	Mateo Rodrigo	Gutiérrez Medina
928	DEMO-E-00923	Daniel Rodrigo	Gutiérrez Cabrera
929	DEMO-E-00924	Santiago Rodrigo	Gutiérrez Castillo
930	DEMO-E-00925	Samuel Rodrigo	Gutiérrez Condori
931	DEMO-E-00926	Diego Rodrigo	Gutiérrez Delgado
932	DEMO-E-00927	Nicolás Rodrigo	Gutiérrez Aguilar
933	DEMO-E-00928	Adrián Rodrigo	Gutiérrez Herrera
934	DEMO-E-00929	Sebastián Rodrigo	Gutiérrez Suárez
935	DEMO-E-00930	Alejandro Rodrigo	Gutiérrez Valdez
936	DEMO-E-00931	Luis Rodrigo	Gutiérrez Choque
937	DEMO-E-00932	Miguel Rodrigo	Gutiérrez Molina
938	DEMO-E-00933	Carlos Rodrigo	Gutiérrez Salazar
939	DEMO-E-00934	Javier Rodrigo	Gutiérrez Paredes
940	DEMO-E-00935	Andrés Rodrigo	Gutiérrez Cruz
941	DEMO-E-00936	Valeria Rodrigo	Gutiérrez Fernández
942	DEMO-E-00937	Camila Rodrigo	Gutiérrez Pinto
943	DEMO-E-00938	Lucía Rodrigo	Gutiérrez Rojas
944	DEMO-E-00939	Mariana Rodrigo	Gutiérrez Ortega
945	DEMO-E-00940	Daniela Rodrigo	Gutiérrez Torres
946	DEMO-E-00941	Sofía Rodrigo	Gutiérrez Gutiérrez
947	DEMO-E-00942	Paola Rodrigo	Gutiérrez Apaza
948	DEMO-E-00943	Andrea Rodrigo	Gutiérrez Montes
949	DEMO-E-00944	Gabriela Rodrigo	Gutiérrez Mendoza
950	DEMO-E-00945	Natalia Rodrigo	Gutiérrez Soto
951	DEMO-E-00946	Carolina Rodrigo	Gutiérrez Vega
952	DEMO-E-00947	Fernanda Rodrigo	Gutiérrez Rivera
953	DEMO-E-00948	Isabel Rodrigo	Gutiérrez Mamani
954	DEMO-E-00949	Victoria Rodrigo	Gutiérrez Villarroel
955	DEMO-E-00950	Elena Rodrigo	Gutiérrez Castro
956	DEMO-E-00951	Rodrigo Rodrigo	Gutiérrez Morales
957	DEMO-E-00952	Mauricio Rodrigo	Gutiérrez Ríos
958	DEMO-E-00953	Eduardo Rodrigo	Gutiérrez Escobar
959	DEMO-E-00954	Pablo Rodrigo	Gutiérrez Soria
960	DEMO-E-00955	Ricardo Rodrigo	Gutiérrez Vargas
961	DEMO-E-00956	Patricia Rodrigo	Gutiérrez Romero
962	DEMO-E-00957	Claudia Rodrigo	Gutiérrez Navarro
963	DEMO-E-00958	Lorena Rodrigo	Gutiérrez López
964	DEMO-E-00959	Verónica Rodrigo	Gutiérrez Quispe
965	DEMO-E-00960	Rosa Rodrigo	Gutiérrez Arias
966	DEMO-E-00961	Gabriel Mauricio	Castillo Flores
967	DEMO-E-00962	Mateo Mauricio	Castillo Medina
968	DEMO-E-00963	Daniel Mauricio	Castillo Cabrera
969	DEMO-E-00964	Santiago Mauricio	Castillo Castillo
970	DEMO-E-00965	Samuel Mauricio	Castillo Condori
971	DEMO-E-00966	Diego Mauricio	Castillo Delgado
972	DEMO-E-00967	Nicolás Mauricio	Castillo Aguilar
973	DEMO-E-00968	Adrián Mauricio	Castillo Herrera
974	DEMO-E-00969	Sebastián Mauricio	Castillo Suárez
975	DEMO-E-00970	Alejandro Mauricio	Castillo Valdez
976	DEMO-E-00971	Luis Mauricio	Castillo Choque
977	DEMO-E-00972	Miguel Mauricio	Castillo Molina
978	DEMO-E-00973	Carlos Mauricio	Castillo Salazar
979	DEMO-E-00974	Javier Mauricio	Castillo Paredes
980	DEMO-E-00975	Andrés Mauricio	Castillo Cruz
981	DEMO-E-00976	Valeria Mauricio	Castillo Fernández
982	DEMO-E-00977	Camila Mauricio	Castillo Pinto
983	DEMO-E-00978	Lucía Mauricio	Castillo Rojas
984	DEMO-E-00979	Mariana Mauricio	Castillo Ortega
985	DEMO-E-00980	Daniela Mauricio	Castillo Torres
986	DEMO-E-00981	Sofía Mauricio	Castillo Gutiérrez
987	DEMO-E-00982	Paola Mauricio	Castillo Apaza
988	DEMO-E-00983	Andrea Mauricio	Castillo Montes
989	DEMO-E-00984	Gabriela Mauricio	Castillo Mendoza
990	DEMO-E-00985	Natalia Mauricio	Castillo Soto
991	DEMO-E-00986	Carolina Mauricio	Castillo Vega
992	DEMO-E-00987	Fernanda Mauricio	Castillo Rivera
993	DEMO-E-00988	Isabel Mauricio	Castillo Mamani
994	DEMO-E-00989	Victoria Mauricio	Castillo Villarroel
995	DEMO-E-00990	Elena Mauricio	Castillo Castro
996	DEMO-E-00991	Rodrigo Mauricio	Castillo Morales
997	DEMO-E-00992	Mauricio Mauricio	Castillo Ríos
998	DEMO-E-00993	Eduardo Mauricio	Castillo Escobar
999	DEMO-E-00994	Pablo Mauricio	Castillo Soria
1000	DEMO-E-00995	Ricardo Mauricio	Castillo Vargas
1001	DEMO-E-00996	Patricia Mauricio	Castillo Romero
\.


--
-- Data for Name: dim_gestion; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.dim_gestion (gestion_id, nombre, fecha_inicio, fecha_fin) FROM stdin;
1	GESTIÓN 2026	2026-02-02	2026-11-30
2	GESTIÓN 2027	2027-02-01	2027-11-30
\.


--
-- Data for Name: dim_materia; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.dim_materia (materia_id, carrera_id, codigo, nombre, nivel_curso) FROM stdin;
1	1	MPI-101	MATEMÁTICA PARA LA INFORMÁTICA	1
2	1	PRG-102	PROGRAMACIÓN I	1
3	1	INT-103	INGLES TÉCNICO	1
4	1	HDC-104	HARDWARE DE COMPUTADORAS	1
5	1	TSO-105	TALLLER DE SISTEMAS OPERATIVOS	1
6	1	OTM-106	OFIMATICA Y TECNOLOGÍA MULTIMEDIA	1
7	1	DPW-107	DISEÑO Y PROGRAMACIÓN WEB I	1
8	1	ETD-201	ESTADÍSTICA	2
9	1	PRG-202	PROGRAMACIÓN II	2
10	1	EDD-203	ESTRUCTURA DE DATOS	2
11	1	RDC-204	REDES DE COMPUTADORAS I	2
12	1	PDM-205	PROGRAMACIÓN PARA DISPOSITIVOS MÓVILES I	2
13	1	ADS-206	ANÁLISIS Y DISEÑO DE SISTEMAS I	2
14	1	DPW-207	DISEÑO Y PROGRAMACIÓN WEB II	2
15	1	BDD-208	BASE DE DATOS I	2
207	7	INT-200	INGLES TECNICO	2
16	1	EMP-301	EMPRENDIMIENTO PRODUCTIVO	3
17	1	DPW-302	DISEÑO Y PROGRAMACIÓN WEB III	3
18	1	GMC-303	GESTIÓN Y MEJORAMIENTO DE LA CALIDAD DEL SOFTWARE	3
19	1	RDC-304	REDES DE COMPUTADORAS II	3
20	1	TMG-305	TALLER MODALIDAD DE GRADUACIÓN	3
21	1	ADS-306	ANÁLISIS Y DISEÑO DE SISTEMAS II	3
22	1	PDM-307	PROGRAMACIÓN PARA DISPOSITIVOS MÓVILES II	3
23	1	BDD-308	BASE DE DATOS II	3
24	2	CON-101	CONTABILIDAD I	1
25	2	MAF-102	MATEMÁTICA FINANCIERA	1
26	2	ICO-103	INFORMÁTICA CONTABLE	1
27	2	ADG-104	ADMINISTRACION GENERAL	1
28	2	LSA-105	LEGISLACION LABORAL Y SEGURIDAD SOCIAL APLICADA	1
29	2	EGA-106	ECONOMIA GENERAL APLICADA	1
30	2	DCM-107	DOCUMENTOS COMERCIALES Y MERCANTILES	1
31	2	ESA-108	ESTADISTICA APLICADA	1
32	2	INT-109	INGLES TECNICO	1
33	2	CON-201	CONTABILIDAD II	2
34	2	COC-202	CONTABILIDAD DE COSTOS I	2
35	2	COS-203	CONTABILIDAD DE SOCIEDADES	2
36	2	CDS-204	CONTABILIDAD DE SEGUROS	2
37	2	CBC-205	CONTABILIDAD BANCARIA Y COOPERATIVAS	2
38	2	EMP-206	EMPRENDIMIENTO PRODUCTIVO	2
39	2	SIT-207	SISTEMA TRIBUTARIO	2
40	2	COA-301	CONTABILIDAD AGROPECUARIA	3
41	2	COC-302	CONTABILIDAD DE COSTOS II	3
42	2	COG-303	CONTABILIAD GUBERNAMENTAL	3
43	2	CEP-304	CONTABILIDAD EXTRACTIVA (MINERA, PETROLERA Y FORESTAL)	3
44	2	CHS-305	CONTABILIDAD DE SERVICIOS (CONSTRUCCION, HOTELERIA Y TRANSPORTE)	3
45	2	GCI-306	GABINETE CONTABLE INFORMATICO	3
46	2	AEF-307	ANALISIS E INTERPRETACIONES DE ESTADOS FINANCIEROS	3
47	2	TMG-308	TALLER DE MODALIDAD DE GRADUACION	3
48	3	SIM-100	SEGURIDAD OCUPACIONAL Y MEDIO AMBIENTE	1
49	3	CEL-100	CIRCUITOS ELECTRICOS Y LABORATORIO I	1
50	3	IET-100	INSTALACIONES ELECTRICAS Y TALLER I	1
51	3	DIE-100	DIBUJO DE ESPECIALIDAD	1
52	3	TEM-100	TALLER ELECTROMECANICO	1
53	3	MAA-100	MATEMATICA APLICADA	1
54	3	CEL-200	CIRCUITOS ELECTRICOS Y LABORATORIO II	2
55	3	IET-200	INSTALACIONES ELECTRICAS Y TALLER II	2
56	3	MLT-200	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER I	2
57	3	FIA-200	FISICA APLICADA	2
58	3	INT-200	INGLES TECNICO I	2
59	3	AUE-300	AUTOMATISMOS ELECTRICOS I	3
60	3	INM-300	INSTRUMENTACION Y MEDIDAS	3
61	3	MLT-300	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER II	3
62	3	ELA-300	ELECTRONICA ANALOGICA	3
63	3	ENA-300	ENERGIAS ALTERNATIVAS I	3
64	3	EDA-300	ELECTRICIDAD DEL AUTOMOVIL	3
65	3	EMP-300	EMPRENDIMIENTO PRODUCTIVO I	3
66	3	AUE-400	AUTOMATISMOS ELECTRICOS II	4
67	3	CEE-400	CENTRALES ELECTRICAS	4
68	3	MLT-400	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER III	4
69	3	ELD-400	ELECTRONICA DIGITAL	4
70	3	ENA-400	ENERGIAS ALTERNATIVAS II	4
71	3	SIR-400	SISTEMAS DE REFRIGERACION	4
72	3	EMP-400	EMPRENDIMIENTO PRODUCTIVO II	4
73	3	CLP-500	CONTROLADORES LOGICOS PROGRAMABLES	5
74	3	RED-500	REDES DE DISTRIBUCION	5
75	3	MLT-500	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER IV	5
76	3	ELP-500	ELECTRONICA DE POTENCIA	5
77	3	REI-500	REFRIGERACION INDUSTRIAL	5
78	3	TMG-500	TALLER DE MODADLIDAD DE GRADUACION I	5
79	3	SIS-600	SISTEMAS SCADA	6
80	3	ELN-600	ELECTRONEUMATICA	6
81	3	LIT-600	LINEAS DE TRANSMISION	6
82	3	SUP-600	SUBESTACIONES DE POTENCIA	6
83	3	MCC-600	MICROCONTROLADORES	6
84	3	TMG-600	TALLER DE MODADLIDAD DE GRADUACION II	6
85	4	QCG-100	QUÍMICA GENERAL I	1
86	4	QCO-100	QUÍMICA ORGÁNICA I	1
87	4	EPQ-100	ELABORACIÓN DE PRODUCTOS QUÍMICOS I	1
88	4	FIA-100	FÍSICA APLICADA	1
89	4	MAA-100	MATEMÁTICA APLICADA	1
90	4	INT-100	INGLÉS TÉCNCIO I	1
91	4	HSI-200	HIGIENE, SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE	2
92	4	QCG-200	QUÍMICA GENERAL II	2
93	4	QCO-200	QUÍMICA ORGÁNICA II	2
94	4	QCI-200	QUÍMICA INORGÁNICA	2
95	4	EDE-200	ESTADISTICA APLICADA Y DISEÑO DE EXPERIMENTOS	2
96	4	INT-200	INGLÉS TÉCNCIO II	2
97	4	ANQ-300	ANÁLISIS QUÍMICO I	3
98	4	EPQ-300	ELABORACIÓN DE PRODUCTOS QUÍMICOS II	3
99	4	BMI-300	BROMATOLOGÍA Y MICROBIOLOGÍA INDUSTRIAL I	3
100	4	ELQ-300	ELECTROQUÍMICA	3
101	4	FIQ-300	FISICOQUÍMICA APLICADA	3
102	4	EMP-300	EMPRENDIMIENTO PRODUCTIVO I	3
103	4	ANQ-400	ANÁLISIS QUÍMICO II	4
104	4	BMI-400	BROMATOLOGÍA Y MICROBIOLOGÍA INDUSTRIAL II	4
105	4	OPU-400	OPERACIONES UNITARIAS I	4
106	4	TDI-400	TERMODINÁMICA INDUSTRIAL	4
107	4	INC-400	INSTRUMENTACION Y CONTROL	4
108	4	EMP-400	EMPRENDIMIENTO PRODUCTIVO II	4
109	4	AAI-500	ANÁLISIS APLICADO INORGÁNICO	5
110	4	ANI-500	ANALISIS INSTRUMENTAL I	5
111	4	CCI-500	CONTROL DE CALIDAD EN LA INDUSTRIA	5
112	4	OPU-500	OPERACIONES UNITARIAS II	5
113	4	PQI-500	PROCESOS QUÍMICOS ORGANICOS E INORGÁNICOS	5
114	4	AAO-600	ANALISIS APLICADO ORGÁNICO	6
115	4	ANI-600	ANALISIS INSTRUMENTAL II	6
116	4	TPG-600	TECNOLOGÍA DEL PETROLEO Y GAS	6
117	4	OPU-600	OPERACIONES UNITARIAS III	6
118	4	TMG-600	TALLER DE MODALIDAD DE GRADUCIÓN	6
119	5	SMA-100	SEGURIDAD OCUPACIONAL Y MEDIO AMBIENTE	1
120	5	FAL-100	FISICA APLICADA Y LABORATORIO	1
121	5	DIC-100	DIBUJO TECNICO Y CAD	1
122	5	MAM-100	MATEMATICA APLICADA A LA MECANICA	1
123	5	MEI-100	METROLOGIA INDUSTRIAL	1
124	5	TTM-100	TECNOLOGIA Y TALLER MECANICO I	1
125	5	ELE-200	ELECTROTECNIA Y ELECTRONICA BASICA	2
126	5	DCM-200	DIBUJO MECANICO EN CAD	2
127	5	SOL-200	SOLDADURA INDUSTRIAL I	2
128	5	TTM-200	TECNOLOGIA Y TALLER MECANICO II	2
129	5	TTT-200	TRATAMIENTO TERMICO Y TECNOLOGIA DE LOS MATERIALES	2
130	5	AEC-300	AUTOMATISMOS ELECTRICOS Y CONTROL	3
131	5	REM-300	RESISTENCIA DE MATERIALES	3
132	5	TTM-300	TECNOLOGIA Y TALLER MECANICO III	3
133	5	SOL-300	SOLDADURA INDUSTRIAL II	3
134	5	MOC-300	MODELADO EN CAD	3
135	5	INT-400	INGLES TECNICO	4
136	5	EMM-400	ELEMENTOS Y MECANISMOS DE MAQUINAS	4
137	5	NEH-400	NEUMATICA E HIDRAULICA	4
138	5	TTM-400	TECNOLIGIA Y TALLER MECANICO IV	4
139	5	SOL-400	SOLDADURA INDUSTRIAL III	4
140	5	CNC-400	CONTROL NUMERICO COMPUTARIZADO I	4
141	5	ENH-500	ELECTRONEUMATICA - ELECTROHIDRAULICA	5
142	5	CNC-500	CONTROL NUMERICO COMPUTARIZADO II	5
143	5	SOL-500	SOLDADURA INDUSTRIAL IV	5
144	5	DIM-500	DISEÑO DE MAQUINAS	5
145	5	PPM-500	PROCESOS DE MANUFACTURA Y MATRICERIA	5
146	5	EMP-500	EMPRENDIMIENTO PRODUCTIVO I	5
147	5	TMG-500	TALLER DE MODALIDAD DE GRADUACION I	5
148	5	AII-600	AUTOMATIZACION E INSTRUMENTACION INDUSTRIAL	6
149	5	SMR-600	SISTEMAS MECATRONICOS Y ROBOTICA INDUSTRIAL	6
150	5	MEI-600	MANTENIMIENTO DE EQUIPOS INDUSTRIALES	6
151	5	ESM-600	ESTRUCTURAS METALICAS	6
152	5	MCM-600	MANUFACTURA Y CONSTRUCCION DE MAQUINAS	6
153	5	EMP-600	EMPRENDIMIENTO PRODUCTIVO II	6
154	5	TMG-600	TALLER DE MODALIDAD DE GRADUACION II	6
155	6	SOM-100	SEGURIDAD OCUPACIONAL Y MEDIO AMBIENTE	1
156	6	MOG-100	MOTORES A GASOLINA I	1
157	6	ELA-100	ELECTRICIDAD AUTOMOTRIZ I	1
158	6	MAA-100	MATEMATICA AUTOMOTRIZ	1
159	6	MEA-100	METROLOGIA AUTOMOTRIZ	1
160	6	DTA-100	DIBUJO TECNICO AUTOMOTRIZ I	1
161	6	QUA-100	QUIMICA AUTOMOTRIZ	1
162	6	INT-200	INGLES TECNICO	2
163	6	MOG-200	MOTORES A GASOLINA II	2
164	6	ELA-200	ELECTRICIDAD AUTOMOTRIZ II	2
165	6	CHS-200	CHAPERIA Y SOLDADURA	2
166	6	FIS-200	FISICA AUTOMOTRIZ	2
167	6	DTA-200	DIBUJO TECNICO AUTOMOTRIZ II	2
168	6	MOG-300	MOTORES A GASOLINA III	3
169	6	ELA-300	ELECTRICIDAD AUTOMOTRIZ III	3
170	6	MOD-300	MOTORES DIESEL I	3
171	6	ETA-300	ELECTRONICA AUTOMOTRIZ I	3
172	6	TER-300	TERMODINAMICA	3
173	6	TRA-300	TRANSMISIONES I	3
174	6	MOG-400	MOTORES A GASOLINA IV	4
175	6	IAG-400	INYECCION A GASOLINA I	4
176	6	MOD-400	MOTORES DIESEL II	4
177	6	ETA-400	ELECTRONICA AUTOMOTRIZ II	4
178	6	TRA-400	TRANSMISIONES II	4
179	6	EMP-400	EMPRENDIMIENTO PRODUCTIVO	4
180	6	IED-500	INYECCION ELECTRONICA DIESEL I	5
181	6	IAG-500	INYECCION A GASOLINA II	5
182	6	LAD-500	LABORATORIO DIESEL I	5
183	6	ETA-500	ELECTRONICA AUTOMOTRIZ III	5
184	6	NEU-500	NEUMATICA	5
185	6	TRA-500	TRANSMISIONES III	5
186	6	TMG-500	TALLER DE MODALIDAD DE GRADUACION I	5
187	6	IED-600	INYECCION ELECTRONICA DIESEL II	6
188	6	DAU-600	DIAGNOSTICO DEL AUTOMOVIL	6
189	6	LAD-600	LABORATORIO DIESEL II	6
190	6	HID-600	HIDRAULICA	6
191	6	MAP-600	MAQUINARIA AGRICOLA PESADA	6
192	6	IAG-600	INYECCION A GASOLINA III	6
193	6	TRA-600	TRANSMISIONES IV	6
194	6	TMG-600	TALLER DE MODALIDAD DE GRADUACION II	6
195	7	SIM-100	SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE I	1
196	7	ALC-100	ALGEBRA Y CALCULO	1
197	7	ACC-100	ANALISIS DE CIRCUITOS DE CORRIENTE CONTINUA	1
198	7	FIS-100	FISICA	1
199	7	INC-100	INSTRUMENTOS Y COMPONENTES	1
200	7	INE-100	INSTALACIONES ELECTRICAS	1
201	7	SIC-100	SISTEMAS CAD	1
202	7	SIM-200	SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE II	2
203	7	ACC-200	ANALISIS DE CIRCUITOS DE CORRIENTE ALTERNA	2
204	7	ELA-200	ELECTRONICA ANALOGICA	2
205	7	ELD-200	ELECTRONICA DIGITAL	2
206	7	ALE-200	ALGORITMOS Y ESTRUCTURAS	2
208	7	LTA-300	LINEAS DE TRANSMISION Y ANTENAS	3
209	7	MII-300	MAQUINAS E INSTALACIONES INDUSTRIALES	3
210	7	OAP-300	OPERACIONES Y APLICAIONES	3
211	7	SLP-300	SISTEMAS LOGICOS PROGRAMABLES	3
212	7	PRO-300	PROGRAMACION	3
213	7	EMP-300	EMPRENDIMIENTO PRODUCTIVO	3
214	7	SIT-400	SISTEMAS DE TELECOMUNICACIONES	4
215	7	ELE-400	ELECTROACUSTICA	4
216	7	ELI-400	ELECTRONICA INDUSTRIAL	4
217	7	MAE-400	MANTENIMIENTO DE EQUIPOS ELECTRONICOS	4
218	7	ARD-400	ARQUITECTURA Y REDES DE COMPUTADORAS	4
219	7	MIC-400	MICROCONTROLADORES	4
220	7	SDC-500	SISTEMAS DE CONTROL	5
221	7	AUP-500	AUTOMATAS PROGRAMABLES	5
222	7	SIN-500	SISTEMAS NEUMATICOS	5
223	7	SIT-500	SISTEMAS DE TELEFONIA	5
224	7	RGD-500	REDES Y GESTION DE DATOS	5
225	7	TMG-500	TALLER DE MODADLIDAD DE GRADUACION I	5
226	7	COD-600	CONTROL DIGITAL	6
227	7	SIS-600	SISTEMAS SCADA	6
228	7	ROI-600	ROBOTICA INDUSTRIAL	6
229	7	SEN-600	SISTEMAS ELECTRONEUMATICOS	6
230	7	FIO-600	FIBRA OPTICA	6
231	7	TMG-600	TALLER DE MODADLIDAD DE GRADUACION II	6
232	8	INT-100	INGLES TECNICO I	1
233	8	MAT-100	MATEMATICA PARA LA CONSTRUCCION	1
234	8	DIB-100	DIBUJO TECNICO	1
235	8	FIS-100	FISICA PARA LA CONSTRUCCION	1
236	8	SIM-100	SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE	1
237	8	MAC-100	MATERIALES DE CONSTRUCCION	1
238	8	INT-200	INGLES TECNICO II	2
239	8	DIB-200	DIBUJO CONSTRUCTIVO ASISTIDO POR COMPUTADORA I	2
240	8	EIS-200	ESTRUCTURAS ISOSTATICAS	2
241	8	HID-200	HIDRAULICA	2
242	8	MES-200	MECANICA DE SUELOS I	2
243	8	PCO-200	PROCESOS CONSTRUCTIVOS I	2
244	8	THO-300	TECNOLOGIA DEL HORMIGON	3
245	8	TOP-300	TOPOGRAFIA I	3
246	8	DIB-300	DIBUJO CONSTRUCTIVO ASISTIDO POR COMPUTADORA II	3
247	8	RDM-300	RESISTENCIA DE MATERIALES	3
248	8	MES-300	MECANICA DE SUELOS II	3
249	8	PCO-300	PROCESOS CONSTRUCTIVOS II	3
250	8	OSA-400	OBRAS SANITARIAS I	4
251	8	TOP-400	TOPOGRAFIA II	4
252	8	MEC-400	MAQUINARIA Y EQUIPO DE CONSTRUCCION	4
253	8	COP-400	COSTOS Y PRESUPUESTOS	4
254	8	HOA-400	HORMIGON ARMADO I	4
255	8	PCO-400	PROCESOS CONSTRUCTIVOS III	4
256	8	OSA-500	OBRAS SANITARIAS II	5
257	8	OVI-500	OBRAS VIALES	5
258	8	DAO-500	DIRECCION Y ADMINISTRACION DE OBRAS	5
259	8	HOA-500	HORMIGON ARMADO II	5
260	8	EMP-500	EMPRENDIMIENTO PRODUCTIVO I	5
261	8	TMG-500	TALLER DE MODALIDAD DE GRADUACION I	5
262	8	SEO-600	SEGUIMIENTO DE OBRAS	6
263	8	IOC-600	INSTALACIONES ESPECIALES EN OBRAS CIVILES	6
264	8	EMA-600	ESTRUCTURAS EN MADERA	6
265	8	ESM-600	ESTRUCTURAS METALICAS	6
266	8	EMP-600	EMPRENDIMIENTO PRODUCTIVO II	6
267	8	TMG-600	TALLER DE MODALIDAD DE GRADUACION II	6
268	9	DEMO-9-1	Fundamentos de redes (demostración)	1
269	9	DEMO-9-2	Sistemas operativos (demostración)	1
270	9	DEMO-9-3	Matemática aplicada (demostración)	1
271	9	DEMO-9-4	Redes locales (demostración)	2
272	9	DEMO-9-5	Administración de servidores (demostración)	2
273	9	DEMO-9-6	Seguridad de redes (demostración)	2
274	10	DEMO-10-1	Dibujo y composición (demostración)	1
275	10	DEMO-10-2	Diseño digital (demostración)	1
276	10	DEMO-10-3	Comunicación visual (demostración)	1
277	10	DEMO-10-4	Identidad gráfica (demostración)	2
278	10	DEMO-10-5	Diseño editorial (demostración)	2
279	10	DEMO-10-6	Producción multimedia (demostración)	2
280	11	DEMO-11-1	Administración general (demostración)	1
281	11	DEMO-11-2	Contabilidad básica (demostración)	1
282	11	DEMO-11-3	Matemática financiera (demostración)	1
283	11	DEMO-11-4	Gestión de personal (demostración)	2
284	11	DEMO-11-5	Mercadotecnia (demostración)	2
285	11	DEMO-11-6	Emprendimiento (demostración)	2
286	12	DEMO-12-1	Fundamentos de electricidad (demostración)	1
287	12	DEMO-12-2	Energía y medio ambiente (demostración)	1
288	12	DEMO-12-3	Matemática técnica (demostración)	1
289	12	DEMO-12-4	Sistemas fotovoltaicos (demostración)	2
290	12	DEMO-12-5	Energía eólica (demostración)	2
291	12	DEMO-12-6	Eficiencia energética (demostración)	2
\.


--
-- Data for Name: dim_tiempo; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.dim_tiempo (fecha, anio, mes, dia, trimestre, dia_semana, mes_nombre) FROM stdin;
2027-07-19	2027	7	19	3	1	Julio
2026-02-02	2026	2	2	1	1	Febrero
2026-02-03	2026	2	3	1	2	Febrero
2026-02-04	2026	2	4	1	3	Febrero
2026-02-05	2026	2	5	1	4	Febrero
2026-02-06	2026	2	6	1	5	Febrero
2026-02-07	2026	2	7	1	6	Febrero
2026-02-08	2026	2	8	1	7	Febrero
2026-02-09	2026	2	9	1	1	Febrero
2026-02-10	2026	2	10	1	2	Febrero
2026-02-11	2026	2	11	1	3	Febrero
2026-02-12	2026	2	12	1	4	Febrero
2026-02-13	2026	2	13	1	5	Febrero
2026-02-14	2026	2	14	1	6	Febrero
2026-02-15	2026	2	15	1	7	Febrero
2026-02-16	2026	2	16	1	1	Febrero
2026-02-17	2026	2	17	1	2	Febrero
2026-02-18	2026	2	18	1	3	Febrero
2026-02-19	2026	2	19	1	4	Febrero
2026-02-20	2026	2	20	1	5	Febrero
2026-02-21	2026	2	21	1	6	Febrero
2026-02-22	2026	2	22	1	7	Febrero
2026-02-23	2026	2	23	1	1	Febrero
2026-02-24	2026	2	24	1	2	Febrero
2026-02-25	2026	2	25	1	3	Febrero
2026-02-26	2026	2	26	1	4	Febrero
2026-02-27	2026	2	27	1	5	Febrero
2026-02-28	2026	2	28	1	6	Febrero
2026-03-01	2026	3	1	1	7	Marzo
2026-03-02	2026	3	2	1	1	Marzo
2026-03-03	2026	3	3	1	2	Marzo
2026-03-04	2026	3	4	1	3	Marzo
2026-03-05	2026	3	5	1	4	Marzo
2026-03-06	2026	3	6	1	5	Marzo
2026-03-07	2026	3	7	1	6	Marzo
2026-03-08	2026	3	8	1	7	Marzo
2026-03-09	2026	3	9	1	1	Marzo
2026-03-10	2026	3	10	1	2	Marzo
2026-03-11	2026	3	11	1	3	Marzo
2026-03-12	2026	3	12	1	4	Marzo
2026-03-13	2026	3	13	1	5	Marzo
2026-03-14	2026	3	14	1	6	Marzo
2026-03-15	2026	3	15	1	7	Marzo
2026-03-16	2026	3	16	1	1	Marzo
2026-03-17	2026	3	17	1	2	Marzo
2026-03-18	2026	3	18	1	3	Marzo
2026-03-19	2026	3	19	1	4	Marzo
2026-03-20	2026	3	20	1	5	Marzo
2026-03-21	2026	3	21	1	6	Marzo
2026-03-22	2026	3	22	1	7	Marzo
2026-03-23	2026	3	23	1	1	Marzo
2026-03-24	2026	3	24	1	2	Marzo
2026-03-25	2026	3	25	1	3	Marzo
2026-03-26	2026	3	26	1	4	Marzo
2026-03-27	2026	3	27	1	5	Marzo
2026-03-28	2026	3	28	1	6	Marzo
2026-03-29	2026	3	29	1	7	Marzo
2026-03-30	2026	3	30	1	1	Marzo
2026-03-31	2026	3	31	1	2	Marzo
2026-04-01	2026	4	1	2	3	Abril
2026-04-02	2026	4	2	2	4	Abril
2026-04-03	2026	4	3	2	5	Abril
2026-04-04	2026	4	4	2	6	Abril
2026-04-05	2026	4	5	2	7	Abril
2026-04-06	2026	4	6	2	1	Abril
2026-04-07	2026	4	7	2	2	Abril
2026-04-08	2026	4	8	2	3	Abril
2026-04-09	2026	4	9	2	4	Abril
2026-04-10	2026	4	10	2	5	Abril
2026-04-11	2026	4	11	2	6	Abril
2026-04-12	2026	4	12	2	7	Abril
2026-04-13	2026	4	13	2	1	Abril
2026-04-14	2026	4	14	2	2	Abril
2026-04-15	2026	4	15	2	3	Abril
2026-04-16	2026	4	16	2	4	Abril
2026-04-17	2026	4	17	2	5	Abril
2026-04-18	2026	4	18	2	6	Abril
2026-04-19	2026	4	19	2	7	Abril
2026-04-20	2026	4	20	2	1	Abril
2026-04-21	2026	4	21	2	2	Abril
2026-04-22	2026	4	22	2	3	Abril
2026-04-23	2026	4	23	2	4	Abril
2026-04-24	2026	4	24	2	5	Abril
2026-04-25	2026	4	25	2	6	Abril
2026-04-26	2026	4	26	2	7	Abril
2026-04-27	2026	4	27	2	1	Abril
2026-04-28	2026	4	28	2	2	Abril
2026-04-29	2026	4	29	2	3	Abril
2026-04-30	2026	4	30	2	4	Abril
2026-05-01	2026	5	1	2	5	Mayo
2026-05-02	2026	5	2	2	6	Mayo
2026-05-03	2026	5	3	2	7	Mayo
2026-05-04	2026	5	4	2	1	Mayo
2026-05-05	2026	5	5	2	2	Mayo
2026-05-06	2026	5	6	2	3	Mayo
2026-05-07	2026	5	7	2	4	Mayo
2026-05-08	2026	5	8	2	5	Mayo
2026-05-09	2026	5	9	2	6	Mayo
2026-05-10	2026	5	10	2	7	Mayo
2026-05-11	2026	5	11	2	1	Mayo
2026-05-12	2026	5	12	2	2	Mayo
2026-05-13	2026	5	13	2	3	Mayo
2026-05-14	2026	5	14	2	4	Mayo
2026-05-15	2026	5	15	2	5	Mayo
2026-05-16	2026	5	16	2	6	Mayo
2026-05-17	2026	5	17	2	7	Mayo
2026-05-18	2026	5	18	2	1	Mayo
2026-05-19	2026	5	19	2	2	Mayo
2026-05-20	2026	5	20	2	3	Mayo
2026-05-21	2026	5	21	2	4	Mayo
2026-05-22	2026	5	22	2	5	Mayo
2026-05-23	2026	5	23	2	6	Mayo
2026-05-24	2026	5	24	2	7	Mayo
2026-05-25	2026	5	25	2	1	Mayo
2026-05-26	2026	5	26	2	2	Mayo
2026-05-27	2026	5	27	2	3	Mayo
2026-05-28	2026	5	28	2	4	Mayo
2026-05-29	2026	5	29	2	5	Mayo
2026-05-30	2026	5	30	2	6	Mayo
2026-05-31	2026	5	31	2	7	Mayo
2026-06-01	2026	6	1	2	1	Junio
2026-06-02	2026	6	2	2	2	Junio
2026-06-03	2026	6	3	2	3	Junio
2026-06-04	2026	6	4	2	4	Junio
2026-06-05	2026	6	5	2	5	Junio
2026-06-06	2026	6	6	2	6	Junio
2026-06-07	2026	6	7	2	7	Junio
2026-06-08	2026	6	8	2	1	Junio
2026-06-09	2026	6	9	2	2	Junio
2026-06-10	2026	6	10	2	3	Junio
2026-06-11	2026	6	11	2	4	Junio
2026-06-12	2026	6	12	2	5	Junio
2026-06-13	2026	6	13	2	6	Junio
2026-06-14	2026	6	14	2	7	Junio
2026-06-15	2026	6	15	2	1	Junio
2026-06-16	2026	6	16	2	2	Junio
2026-06-17	2026	6	17	2	3	Junio
2026-06-18	2026	6	18	2	4	Junio
2026-06-19	2026	6	19	2	5	Junio
2026-06-20	2026	6	20	2	6	Junio
2026-06-21	2026	6	21	2	7	Junio
2026-06-22	2026	6	22	2	1	Junio
2026-06-23	2026	6	23	2	2	Junio
2026-06-24	2026	6	24	2	3	Junio
2026-06-25	2026	6	25	2	4	Junio
2026-06-26	2026	6	26	2	5	Junio
2026-06-27	2026	6	27	2	6	Junio
2026-06-28	2026	6	28	2	7	Junio
2026-06-29	2026	6	29	2	1	Junio
2026-06-30	2026	6	30	2	2	Junio
2026-07-01	2026	7	1	3	3	Julio
2026-07-02	2026	7	2	3	4	Julio
2026-07-03	2026	7	3	3	5	Julio
2026-07-04	2026	7	4	3	6	Julio
2026-07-05	2026	7	5	3	7	Julio
2026-07-06	2026	7	6	3	1	Julio
2026-07-07	2026	7	7	3	2	Julio
2026-07-08	2026	7	8	3	3	Julio
2026-07-09	2026	7	9	3	4	Julio
2026-07-10	2026	7	10	3	5	Julio
2026-07-11	2026	7	11	3	6	Julio
2026-07-12	2026	7	12	3	7	Julio
2026-07-13	2026	7	13	3	1	Julio
2026-07-14	2026	7	14	3	2	Julio
2026-07-15	2026	7	15	3	3	Julio
2026-07-16	2026	7	16	3	4	Julio
2026-07-17	2026	7	17	3	5	Julio
2026-07-18	2026	7	18	3	6	Julio
2026-07-19	2026	7	19	3	7	Julio
2026-07-20	2026	7	20	3	1	Julio
2026-07-21	2026	7	21	3	2	Julio
2026-07-22	2026	7	22	3	3	Julio
2026-07-23	2026	7	23	3	4	Julio
2026-07-24	2026	7	24	3	5	Julio
2026-07-25	2026	7	25	3	6	Julio
2026-07-26	2026	7	26	3	7	Julio
2026-07-27	2026	7	27	3	1	Julio
2026-07-28	2026	7	28	3	2	Julio
2026-07-29	2026	7	29	3	3	Julio
2026-07-30	2026	7	30	3	4	Julio
2026-07-31	2026	7	31	3	5	Julio
2026-08-01	2026	8	1	3	6	Agosto
2026-08-02	2026	8	2	3	7	Agosto
2026-08-03	2026	8	3	3	1	Agosto
2026-08-04	2026	8	4	3	2	Agosto
2026-08-05	2026	8	5	3	3	Agosto
2026-08-06	2026	8	6	3	4	Agosto
2026-08-07	2026	8	7	3	5	Agosto
2026-08-08	2026	8	8	3	6	Agosto
2026-08-09	2026	8	9	3	7	Agosto
2026-08-10	2026	8	10	3	1	Agosto
2026-08-11	2026	8	11	3	2	Agosto
2026-08-12	2026	8	12	3	3	Agosto
2026-08-13	2026	8	13	3	4	Agosto
2026-08-14	2026	8	14	3	5	Agosto
2026-08-15	2026	8	15	3	6	Agosto
2026-08-16	2026	8	16	3	7	Agosto
2026-08-17	2026	8	17	3	1	Agosto
2026-08-18	2026	8	18	3	2	Agosto
2026-08-19	2026	8	19	3	3	Agosto
2026-08-20	2026	8	20	3	4	Agosto
2026-08-21	2026	8	21	3	5	Agosto
2026-08-22	2026	8	22	3	6	Agosto
2026-08-23	2026	8	23	3	7	Agosto
2026-08-24	2026	8	24	3	1	Agosto
2026-08-25	2026	8	25	3	2	Agosto
2026-08-26	2026	8	26	3	3	Agosto
2026-08-27	2026	8	27	3	4	Agosto
2026-08-28	2026	8	28	3	5	Agosto
2026-08-29	2026	8	29	3	6	Agosto
2026-08-30	2026	8	30	3	7	Agosto
2026-08-31	2026	8	31	3	1	Agosto
2026-09-01	2026	9	1	3	2	Septiembre
2026-09-02	2026	9	2	3	3	Septiembre
2026-09-03	2026	9	3	3	4	Septiembre
2026-09-04	2026	9	4	3	5	Septiembre
2026-09-05	2026	9	5	3	6	Septiembre
2026-09-06	2026	9	6	3	7	Septiembre
2026-09-07	2026	9	7	3	1	Septiembre
2026-09-08	2026	9	8	3	2	Septiembre
2026-09-09	2026	9	9	3	3	Septiembre
2026-09-10	2026	9	10	3	4	Septiembre
2026-09-11	2026	9	11	3	5	Septiembre
2026-09-12	2026	9	12	3	6	Septiembre
2026-09-13	2026	9	13	3	7	Septiembre
2026-09-14	2026	9	14	3	1	Septiembre
2026-09-15	2026	9	15	3	2	Septiembre
2026-09-16	2026	9	16	3	3	Septiembre
2026-09-17	2026	9	17	3	4	Septiembre
2026-09-18	2026	9	18	3	5	Septiembre
2026-09-19	2026	9	19	3	6	Septiembre
2026-09-20	2026	9	20	3	7	Septiembre
2026-09-21	2026	9	21	3	1	Septiembre
2026-09-22	2026	9	22	3	2	Septiembre
2026-09-23	2026	9	23	3	3	Septiembre
2026-09-24	2026	9	24	3	4	Septiembre
2026-09-25	2026	9	25	3	5	Septiembre
2026-09-26	2026	9	26	3	6	Septiembre
2026-09-27	2026	9	27	3	7	Septiembre
2026-09-28	2026	9	28	3	1	Septiembre
2026-09-29	2026	9	29	3	2	Septiembre
2026-09-30	2026	9	30	3	3	Septiembre
2026-10-01	2026	10	1	4	4	Octubre
2026-10-02	2026	10	2	4	5	Octubre
2026-10-03	2026	10	3	4	6	Octubre
2026-10-04	2026	10	4	4	7	Octubre
2026-10-05	2026	10	5	4	1	Octubre
2026-10-06	2026	10	6	4	2	Octubre
2026-10-07	2026	10	7	4	3	Octubre
2026-10-08	2026	10	8	4	4	Octubre
2026-10-09	2026	10	9	4	5	Octubre
2026-10-10	2026	10	10	4	6	Octubre
2026-10-11	2026	10	11	4	7	Octubre
2026-10-12	2026	10	12	4	1	Octubre
2026-10-13	2026	10	13	4	2	Octubre
2026-10-14	2026	10	14	4	3	Octubre
2026-10-15	2026	10	15	4	4	Octubre
2026-10-16	2026	10	16	4	5	Octubre
2026-10-17	2026	10	17	4	6	Octubre
2026-10-18	2026	10	18	4	7	Octubre
2026-10-19	2026	10	19	4	1	Octubre
2026-10-20	2026	10	20	4	2	Octubre
2026-10-21	2026	10	21	4	3	Octubre
2026-10-22	2026	10	22	4	4	Octubre
2026-10-23	2026	10	23	4	5	Octubre
2026-10-24	2026	10	24	4	6	Octubre
2026-10-25	2026	10	25	4	7	Octubre
2026-10-26	2026	10	26	4	1	Octubre
2026-10-27	2026	10	27	4	2	Octubre
2026-10-28	2026	10	28	4	3	Octubre
2026-10-29	2026	10	29	4	4	Octubre
2026-10-30	2026	10	30	4	5	Octubre
2026-10-31	2026	10	31	4	6	Octubre
2026-11-01	2026	11	1	4	7	Noviembre
2026-11-02	2026	11	2	4	1	Noviembre
2026-11-03	2026	11	3	4	2	Noviembre
2026-11-04	2026	11	4	4	3	Noviembre
2026-11-05	2026	11	5	4	4	Noviembre
2026-11-06	2026	11	6	4	5	Noviembre
2026-11-07	2026	11	7	4	6	Noviembre
2026-11-08	2026	11	8	4	7	Noviembre
2026-11-09	2026	11	9	4	1	Noviembre
2026-11-10	2026	11	10	4	2	Noviembre
2026-11-11	2026	11	11	4	3	Noviembre
2026-11-12	2026	11	12	4	4	Noviembre
2026-11-13	2026	11	13	4	5	Noviembre
2026-11-14	2026	11	14	4	6	Noviembre
2026-11-15	2026	11	15	4	7	Noviembre
2026-11-16	2026	11	16	4	1	Noviembre
2026-11-17	2026	11	17	4	2	Noviembre
2026-11-18	2026	11	18	4	3	Noviembre
2026-11-19	2026	11	19	4	4	Noviembre
2026-11-20	2026	11	20	4	5	Noviembre
2026-11-21	2026	11	21	4	6	Noviembre
2026-11-22	2026	11	22	4	7	Noviembre
2026-11-23	2026	11	23	4	1	Noviembre
2026-11-24	2026	11	24	4	2	Noviembre
2026-11-25	2026	11	25	4	3	Noviembre
2026-11-26	2026	11	26	4	4	Noviembre
2026-11-27	2026	11	27	4	5	Noviembre
2026-11-28	2026	11	28	4	6	Noviembre
2026-11-29	2026	11	29	4	7	Noviembre
2026-11-30	2026	11	30	4	1	Noviembre
2026-12-01	2026	12	1	4	2	Diciembre
2026-12-02	2026	12	2	4	3	Diciembre
2026-12-03	2026	12	3	4	4	Diciembre
2026-12-04	2026	12	4	4	5	Diciembre
2026-12-05	2026	12	5	4	6	Diciembre
2026-12-06	2026	12	6	4	7	Diciembre
2026-12-07	2026	12	7	4	1	Diciembre
2026-12-08	2026	12	8	4	2	Diciembre
2026-12-09	2026	12	9	4	3	Diciembre
2026-12-10	2026	12	10	4	4	Diciembre
2026-12-11	2026	12	11	4	5	Diciembre
2026-12-12	2026	12	12	4	6	Diciembre
2026-12-13	2026	12	13	4	7	Diciembre
2026-12-14	2026	12	14	4	1	Diciembre
2026-12-15	2026	12	15	4	2	Diciembre
2026-12-16	2026	12	16	4	3	Diciembre
2026-12-17	2026	12	17	4	4	Diciembre
2026-12-18	2026	12	18	4	5	Diciembre
2026-12-19	2026	12	19	4	6	Diciembre
2026-12-20	2026	12	20	4	7	Diciembre
2026-12-21	2026	12	21	4	1	Diciembre
2026-12-22	2026	12	22	4	2	Diciembre
2026-12-23	2026	12	23	4	3	Diciembre
2026-12-24	2026	12	24	4	4	Diciembre
2026-12-25	2026	12	25	4	5	Diciembre
2026-12-26	2026	12	26	4	6	Diciembre
2026-12-27	2026	12	27	4	7	Diciembre
2026-12-28	2026	12	28	4	1	Diciembre
2026-12-29	2026	12	29	4	2	Diciembre
2026-12-30	2026	12	30	4	3	Diciembre
2026-12-31	2026	12	31	4	4	Diciembre
2027-01-01	2027	1	1	1	5	Enero
2027-01-02	2027	1	2	1	6	Enero
2027-01-03	2027	1	3	1	7	Enero
2027-01-04	2027	1	4	1	1	Enero
2027-01-05	2027	1	5	1	2	Enero
2027-01-06	2027	1	6	1	3	Enero
2027-01-07	2027	1	7	1	4	Enero
2027-01-08	2027	1	8	1	5	Enero
2027-01-09	2027	1	9	1	6	Enero
2027-01-10	2027	1	10	1	7	Enero
2027-01-11	2027	1	11	1	1	Enero
2027-01-12	2027	1	12	1	2	Enero
2027-01-13	2027	1	13	1	3	Enero
2027-01-14	2027	1	14	1	4	Enero
2027-01-15	2027	1	15	1	5	Enero
2027-01-16	2027	1	16	1	6	Enero
2027-01-17	2027	1	17	1	7	Enero
2027-01-18	2027	1	18	1	1	Enero
2027-01-19	2027	1	19	1	2	Enero
2027-01-20	2027	1	20	1	3	Enero
2027-01-21	2027	1	21	1	4	Enero
2027-01-22	2027	1	22	1	5	Enero
2027-01-23	2027	1	23	1	6	Enero
2027-01-24	2027	1	24	1	7	Enero
2027-01-25	2027	1	25	1	1	Enero
2027-01-26	2027	1	26	1	2	Enero
2027-01-27	2027	1	27	1	3	Enero
2027-01-28	2027	1	28	1	4	Enero
2027-01-29	2027	1	29	1	5	Enero
2027-01-30	2027	1	30	1	6	Enero
2027-01-31	2027	1	31	1	7	Enero
2027-02-01	2027	2	1	1	1	Febrero
2027-02-02	2027	2	2	1	2	Febrero
2027-02-03	2027	2	3	1	3	Febrero
2027-02-04	2027	2	4	1	4	Febrero
2027-02-05	2027	2	5	1	5	Febrero
2027-02-06	2027	2	6	1	6	Febrero
2027-02-07	2027	2	7	1	7	Febrero
2027-02-08	2027	2	8	1	1	Febrero
2027-02-09	2027	2	9	1	2	Febrero
2027-02-10	2027	2	10	1	3	Febrero
2027-02-11	2027	2	11	1	4	Febrero
2027-02-12	2027	2	12	1	5	Febrero
2027-02-13	2027	2	13	1	6	Febrero
2027-02-14	2027	2	14	1	7	Febrero
2027-02-15	2027	2	15	1	1	Febrero
2027-02-16	2027	2	16	1	2	Febrero
2027-02-17	2027	2	17	1	3	Febrero
2027-02-18	2027	2	18	1	4	Febrero
2027-02-19	2027	2	19	1	5	Febrero
2027-02-20	2027	2	20	1	6	Febrero
2027-02-21	2027	2	21	1	7	Febrero
2027-02-22	2027	2	22	1	1	Febrero
2027-02-23	2027	2	23	1	2	Febrero
2027-02-24	2027	2	24	1	3	Febrero
2027-02-25	2027	2	25	1	4	Febrero
2027-02-26	2027	2	26	1	5	Febrero
2027-02-27	2027	2	27	1	6	Febrero
2027-02-28	2027	2	28	1	7	Febrero
2027-03-01	2027	3	1	1	1	Marzo
2027-03-02	2027	3	2	1	2	Marzo
2027-03-03	2027	3	3	1	3	Marzo
2027-03-04	2027	3	4	1	4	Marzo
2027-03-05	2027	3	5	1	5	Marzo
2027-03-06	2027	3	6	1	6	Marzo
2027-03-07	2027	3	7	1	7	Marzo
2027-03-08	2027	3	8	1	1	Marzo
2027-03-09	2027	3	9	1	2	Marzo
2027-03-10	2027	3	10	1	3	Marzo
2027-03-11	2027	3	11	1	4	Marzo
2027-03-12	2027	3	12	1	5	Marzo
2027-03-13	2027	3	13	1	6	Marzo
2027-03-14	2027	3	14	1	7	Marzo
2027-03-15	2027	3	15	1	1	Marzo
2027-03-16	2027	3	16	1	2	Marzo
2027-03-17	2027	3	17	1	3	Marzo
2027-03-18	2027	3	18	1	4	Marzo
2027-03-19	2027	3	19	1	5	Marzo
2027-03-20	2027	3	20	1	6	Marzo
2027-03-21	2027	3	21	1	7	Marzo
2027-03-22	2027	3	22	1	1	Marzo
2027-03-23	2027	3	23	1	2	Marzo
2027-03-24	2027	3	24	1	3	Marzo
2027-03-25	2027	3	25	1	4	Marzo
2027-03-26	2027	3	26	1	5	Marzo
2027-03-27	2027	3	27	1	6	Marzo
2027-03-28	2027	3	28	1	7	Marzo
2027-03-29	2027	3	29	1	1	Marzo
2027-03-30	2027	3	30	1	2	Marzo
2027-03-31	2027	3	31	1	3	Marzo
2027-04-01	2027	4	1	2	4	Abril
2027-04-02	2027	4	2	2	5	Abril
2027-04-03	2027	4	3	2	6	Abril
2027-04-04	2027	4	4	2	7	Abril
2027-04-05	2027	4	5	2	1	Abril
2027-04-06	2027	4	6	2	2	Abril
2027-04-07	2027	4	7	2	3	Abril
2027-04-08	2027	4	8	2	4	Abril
2027-04-09	2027	4	9	2	5	Abril
2027-04-10	2027	4	10	2	6	Abril
2027-04-11	2027	4	11	2	7	Abril
2027-04-12	2027	4	12	2	1	Abril
2027-04-13	2027	4	13	2	2	Abril
2027-04-14	2027	4	14	2	3	Abril
2027-04-15	2027	4	15	2	4	Abril
2027-04-16	2027	4	16	2	5	Abril
2027-04-17	2027	4	17	2	6	Abril
2027-04-18	2027	4	18	2	7	Abril
2027-04-19	2027	4	19	2	1	Abril
2027-04-20	2027	4	20	2	2	Abril
2027-04-21	2027	4	21	2	3	Abril
2027-04-22	2027	4	22	2	4	Abril
2027-04-23	2027	4	23	2	5	Abril
2027-04-24	2027	4	24	2	6	Abril
2027-04-25	2027	4	25	2	7	Abril
2027-04-26	2027	4	26	2	1	Abril
2027-04-27	2027	4	27	2	2	Abril
2027-04-28	2027	4	28	2	3	Abril
2027-04-29	2027	4	29	2	4	Abril
2027-04-30	2027	4	30	2	5	Abril
2027-05-01	2027	5	1	2	6	Mayo
2027-05-02	2027	5	2	2	7	Mayo
2027-05-03	2027	5	3	2	1	Mayo
2027-05-04	2027	5	4	2	2	Mayo
2027-05-05	2027	5	5	2	3	Mayo
2027-05-06	2027	5	6	2	4	Mayo
2027-05-07	2027	5	7	2	5	Mayo
2027-05-08	2027	5	8	2	6	Mayo
2027-05-09	2027	5	9	2	7	Mayo
2027-05-10	2027	5	10	2	1	Mayo
2027-05-11	2027	5	11	2	2	Mayo
2027-05-12	2027	5	12	2	3	Mayo
2027-05-13	2027	5	13	2	4	Mayo
2027-05-14	2027	5	14	2	5	Mayo
2027-05-15	2027	5	15	2	6	Mayo
2027-05-16	2027	5	16	2	7	Mayo
2027-05-17	2027	5	17	2	1	Mayo
2027-05-18	2027	5	18	2	2	Mayo
2027-05-19	2027	5	19	2	3	Mayo
2027-05-20	2027	5	20	2	4	Mayo
2027-05-21	2027	5	21	2	5	Mayo
2027-05-22	2027	5	22	2	6	Mayo
2027-05-23	2027	5	23	2	7	Mayo
2027-05-24	2027	5	24	2	1	Mayo
2027-05-25	2027	5	25	2	2	Mayo
2027-05-26	2027	5	26	2	3	Mayo
2027-05-27	2027	5	27	2	4	Mayo
2027-05-28	2027	5	28	2	5	Mayo
2027-05-29	2027	5	29	2	6	Mayo
2027-05-30	2027	5	30	2	7	Mayo
2027-05-31	2027	5	31	2	1	Mayo
2027-06-01	2027	6	1	2	2	Junio
2027-06-02	2027	6	2	2	3	Junio
2027-06-03	2027	6	3	2	4	Junio
2027-06-04	2027	6	4	2	5	Junio
2027-06-05	2027	6	5	2	6	Junio
2027-06-06	2027	6	6	2	7	Junio
2027-06-07	2027	6	7	2	1	Junio
2027-06-08	2027	6	8	2	2	Junio
2027-06-09	2027	6	9	2	3	Junio
2027-06-10	2027	6	10	2	4	Junio
2027-06-11	2027	6	11	2	5	Junio
2027-06-12	2027	6	12	2	6	Junio
2027-06-13	2027	6	13	2	7	Junio
2027-06-14	2027	6	14	2	1	Junio
2027-06-15	2027	6	15	2	2	Junio
2027-06-16	2027	6	16	2	3	Junio
2027-06-17	2027	6	17	2	4	Junio
2027-06-18	2027	6	18	2	5	Junio
2027-06-19	2027	6	19	2	6	Junio
2027-06-20	2027	6	20	2	7	Junio
2027-06-21	2027	6	21	2	1	Junio
2027-06-22	2027	6	22	2	2	Junio
2027-06-23	2027	6	23	2	3	Junio
2027-06-24	2027	6	24	2	4	Junio
2027-06-25	2027	6	25	2	5	Junio
2027-06-26	2027	6	26	2	6	Junio
2027-06-27	2027	6	27	2	7	Junio
2027-06-28	2027	6	28	2	1	Junio
2027-06-29	2027	6	29	2	2	Junio
2027-06-30	2027	6	30	2	3	Junio
2027-07-01	2027	7	1	3	4	Julio
2027-07-02	2027	7	2	3	5	Julio
2027-07-03	2027	7	3	3	6	Julio
2027-07-04	2027	7	4	3	7	Julio
2027-07-05	2027	7	5	3	1	Julio
2027-07-06	2027	7	6	3	2	Julio
2027-07-07	2027	7	7	3	3	Julio
2027-07-08	2027	7	8	3	4	Julio
2027-07-09	2027	7	9	3	5	Julio
2027-07-10	2027	7	10	3	6	Julio
2027-07-11	2027	7	11	3	7	Julio
2027-07-12	2027	7	12	3	1	Julio
2027-07-13	2027	7	13	3	2	Julio
2027-07-14	2027	7	14	3	3	Julio
2027-07-15	2027	7	15	3	4	Julio
2027-07-16	2027	7	16	3	5	Julio
2027-07-17	2027	7	17	3	6	Julio
2027-07-18	2027	7	18	3	7	Julio
2027-07-20	2027	7	20	3	2	Julio
2027-07-21	2027	7	21	3	3	Julio
2027-07-22	2027	7	22	3	4	Julio
2027-07-23	2027	7	23	3	5	Julio
2027-07-24	2027	7	24	3	6	Julio
2027-07-25	2027	7	25	3	7	Julio
2027-07-26	2027	7	26	3	1	Julio
2027-07-27	2027	7	27	3	2	Julio
2027-07-28	2027	7	28	3	3	Julio
2027-07-29	2027	7	29	3	4	Julio
2027-07-30	2027	7	30	3	5	Julio
2027-07-31	2027	7	31	3	6	Julio
2027-08-01	2027	8	1	3	7	Agosto
2027-08-02	2027	8	2	3	1	Agosto
2027-08-03	2027	8	3	3	2	Agosto
2027-08-04	2027	8	4	3	3	Agosto
2027-08-05	2027	8	5	3	4	Agosto
2027-08-06	2027	8	6	3	5	Agosto
2027-08-07	2027	8	7	3	6	Agosto
2027-08-08	2027	8	8	3	7	Agosto
2027-08-09	2027	8	9	3	1	Agosto
2027-08-10	2027	8	10	3	2	Agosto
2027-08-11	2027	8	11	3	3	Agosto
2027-08-12	2027	8	12	3	4	Agosto
2027-08-13	2027	8	13	3	5	Agosto
2027-08-14	2027	8	14	3	6	Agosto
2027-08-15	2027	8	15	3	7	Agosto
2027-08-16	2027	8	16	3	1	Agosto
2027-08-17	2027	8	17	3	2	Agosto
2027-08-18	2027	8	18	3	3	Agosto
2027-08-19	2027	8	19	3	4	Agosto
2027-08-20	2027	8	20	3	5	Agosto
2027-08-21	2027	8	21	3	6	Agosto
2027-08-22	2027	8	22	3	7	Agosto
2027-08-23	2027	8	23	3	1	Agosto
2027-08-24	2027	8	24	3	2	Agosto
2027-08-25	2027	8	25	3	3	Agosto
2027-08-26	2027	8	26	3	4	Agosto
2027-08-27	2027	8	27	3	5	Agosto
2027-08-28	2027	8	28	3	6	Agosto
2027-08-29	2027	8	29	3	7	Agosto
2027-08-30	2027	8	30	3	1	Agosto
2027-08-31	2027	8	31	3	2	Agosto
2027-09-01	2027	9	1	3	3	Septiembre
2027-09-02	2027	9	2	3	4	Septiembre
2027-09-03	2027	9	3	3	5	Septiembre
2027-09-04	2027	9	4	3	6	Septiembre
2027-09-05	2027	9	5	3	7	Septiembre
2027-09-06	2027	9	6	3	1	Septiembre
2027-09-07	2027	9	7	3	2	Septiembre
2027-09-08	2027	9	8	3	3	Septiembre
2027-09-09	2027	9	9	3	4	Septiembre
2027-09-10	2027	9	10	3	5	Septiembre
2027-09-11	2027	9	11	3	6	Septiembre
2027-09-12	2027	9	12	3	7	Septiembre
2027-09-13	2027	9	13	3	1	Septiembre
2027-09-14	2027	9	14	3	2	Septiembre
2027-09-15	2027	9	15	3	3	Septiembre
2027-09-16	2027	9	16	3	4	Septiembre
2027-09-17	2027	9	17	3	5	Septiembre
2027-09-18	2027	9	18	3	6	Septiembre
2027-09-19	2027	9	19	3	7	Septiembre
2027-09-20	2027	9	20	3	1	Septiembre
2027-09-21	2027	9	21	3	2	Septiembre
2027-09-22	2027	9	22	3	3	Septiembre
2027-09-23	2027	9	23	3	4	Septiembre
2027-09-24	2027	9	24	3	5	Septiembre
2027-09-25	2027	9	25	3	6	Septiembre
2027-09-26	2027	9	26	3	7	Septiembre
2027-09-27	2027	9	27	3	1	Septiembre
2027-09-28	2027	9	28	3	2	Septiembre
2027-09-29	2027	9	29	3	3	Septiembre
2027-09-30	2027	9	30	3	4	Septiembre
2027-10-01	2027	10	1	4	5	Octubre
2027-10-02	2027	10	2	4	6	Octubre
2027-10-03	2027	10	3	4	7	Octubre
2027-10-04	2027	10	4	4	1	Octubre
2027-10-05	2027	10	5	4	2	Octubre
2027-10-06	2027	10	6	4	3	Octubre
2027-10-07	2027	10	7	4	4	Octubre
2027-10-08	2027	10	8	4	5	Octubre
2027-10-09	2027	10	9	4	6	Octubre
2027-10-10	2027	10	10	4	7	Octubre
2027-10-11	2027	10	11	4	1	Octubre
2027-10-12	2027	10	12	4	2	Octubre
2027-10-13	2027	10	13	4	3	Octubre
2027-10-14	2027	10	14	4	4	Octubre
2027-10-15	2027	10	15	4	5	Octubre
2027-10-16	2027	10	16	4	6	Octubre
2027-10-17	2027	10	17	4	7	Octubre
2027-10-18	2027	10	18	4	1	Octubre
2027-10-19	2027	10	19	4	2	Octubre
2027-10-20	2027	10	20	4	3	Octubre
2027-10-21	2027	10	21	4	4	Octubre
2027-10-22	2027	10	22	4	5	Octubre
2027-10-23	2027	10	23	4	6	Octubre
2027-10-24	2027	10	24	4	7	Octubre
2027-10-25	2027	10	25	4	1	Octubre
2027-10-26	2027	10	26	4	2	Octubre
2027-10-27	2027	10	27	4	3	Octubre
2027-10-28	2027	10	28	4	4	Octubre
2027-10-29	2027	10	29	4	5	Octubre
2027-10-30	2027	10	30	4	6	Octubre
2027-10-31	2027	10	31	4	7	Octubre
2027-11-01	2027	11	1	4	1	Noviembre
2027-11-02	2027	11	2	4	2	Noviembre
2027-11-03	2027	11	3	4	3	Noviembre
2027-11-04	2027	11	4	4	4	Noviembre
2027-11-05	2027	11	5	4	5	Noviembre
2027-11-06	2027	11	6	4	6	Noviembre
2027-11-07	2027	11	7	4	7	Noviembre
2027-11-08	2027	11	8	4	1	Noviembre
2027-11-09	2027	11	9	4	2	Noviembre
2027-11-10	2027	11	10	4	3	Noviembre
2027-11-11	2027	11	11	4	4	Noviembre
2027-11-12	2027	11	12	4	5	Noviembre
2027-11-13	2027	11	13	4	6	Noviembre
2027-11-14	2027	11	14	4	7	Noviembre
2027-11-15	2027	11	15	4	1	Noviembre
2027-11-16	2027	11	16	4	2	Noviembre
2027-11-17	2027	11	17	4	3	Noviembre
2027-11-18	2027	11	18	4	4	Noviembre
2027-11-19	2027	11	19	4	5	Noviembre
2027-11-20	2027	11	20	4	6	Noviembre
2027-11-21	2027	11	21	4	7	Noviembre
2027-11-22	2027	11	22	4	1	Noviembre
2027-11-23	2027	11	23	4	2	Noviembre
2027-11-24	2027	11	24	4	3	Noviembre
2027-11-25	2027	11	25	4	4	Noviembre
2027-11-26	2027	11	26	4	5	Noviembre
2027-11-27	2027	11	27	4	6	Noviembre
2027-11-28	2027	11	28	4	7	Noviembre
2027-11-29	2027	11	29	4	1	Noviembre
2027-11-30	2027	11	30	4	2	Noviembre
\.


--
-- Data for Name: fact_matriculas; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.fact_matriculas (matricula_id, gestion_id, carrera_id, estudiante_id, fecha, estado, cantidad) FROM stdin;
1	1	1	1	2026-02-02	ACTIVA	1
2	1	1	2	2026-02-02	ACTIVA	1
3	1	1	3	2026-02-02	ACTIVA	1
4	1	1	5	2026-02-02	ACTIVA	1
5	1	1	6	2026-02-02	ACTIVA	1
6	1	1	7	2026-02-02	ACTIVA	1
7	1	1	8	2026-02-02	ACTIVA	1
8	1	1	9	2026-02-02	ACTIVA	1
9	1	1	10	2026-02-02	ACTIVA	1
10	1	1	11	2026-02-02	ACTIVA	1
11	1	1	12	2026-02-02	ACTIVA	1
12	1	1	13	2026-02-02	ACTIVA	1
13	1	1	14	2026-02-02	ACTIVA	1
14	1	1	15	2026-02-02	ACTIVA	1
15	1	1	16	2026-02-02	ACTIVA	1
16	1	1	17	2026-02-02	ACTIVA	1
17	1	1	18	2026-02-02	ACTIVA	1
18	1	1	19	2026-02-02	ACTIVA	1
19	1	1	20	2026-02-02	ACTIVA	1
20	1	1	21	2026-02-02	ACTIVA	1
21	1	1	22	2026-02-02	ACTIVA	1
22	1	1	23	2026-02-02	ACTIVA	1
23	1	1	24	2026-02-02	ACTIVA	1
24	1	1	25	2026-02-02	ACTIVA	1
25	1	1	26	2026-02-02	ACTIVA	1
26	1	1	27	2026-02-02	ACTIVA	1
27	1	1	28	2026-02-02	ACTIVA	1
28	1	1	29	2026-02-02	ACTIVA	1
29	1	1	30	2026-02-02	ACTIVA	1
30	1	1	31	2026-02-02	ACTIVA	1
31	1	2	32	2026-02-02	ACTIVA	1
32	1	2	33	2026-02-02	ACTIVA	1
33	1	2	34	2026-02-02	ACTIVA	1
34	1	2	35	2026-02-02	ACTIVA	1
35	1	2	36	2026-02-02	ACTIVA	1
36	1	2	37	2026-02-02	ACTIVA	1
37	1	2	38	2026-02-02	ACTIVA	1
38	1	2	39	2026-02-02	ACTIVA	1
39	1	2	40	2026-02-02	ACTIVA	1
40	1	2	41	2026-02-02	ACTIVA	1
41	1	2	42	2026-02-02	ACTIVA	1
42	1	2	43	2026-02-02	ACTIVA	1
43	1	2	44	2026-02-02	ACTIVA	1
44	1	2	45	2026-02-02	ACTIVA	1
45	1	2	46	2026-02-02	ACTIVA	1
46	1	2	47	2026-02-02	ACTIVA	1
47	1	2	48	2026-02-02	ACTIVA	1
48	1	2	49	2026-02-02	ACTIVA	1
49	1	2	50	2026-02-02	ACTIVA	1
50	1	2	51	2026-02-02	ACTIVA	1
\.


--
-- Data for Name: fact_pagos; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.fact_pagos (pago_id, matricula_id, cargo_id, gestion_id, carrera_id, estudiante_id, fecha, monto, metodo, recibo) FROM stdin;
1	1	1	1	1	1	2026-07-20	100.00	EFECTIVO	DEMO-2026-0001
2	2	2	1	1	2	2026-07-20	100.00	QR	DEMO-2026-0002
3	3	3	1	1	3	2026-07-20	100.00	EFECTIVO	DEMO-2026-0003
4	4	4	1	1	5	2026-07-20	100.00	QR	DEMO-2026-0004
5	5	5	1	1	6	2026-07-20	100.00	EFECTIVO	DEMO-2026-0005
6	6	6	1	1	7	2026-07-20	100.00	QR	DEMO-2026-0006
7	7	7	1	1	8	2026-07-20	100.00	EFECTIVO	DEMO-2026-0007
8	8	8	1	1	9	2026-07-20	100.00	QR	DEMO-2026-0008
9	9	9	1	1	10	2026-07-20	100.00	EFECTIVO	DEMO-2026-0009
10	10	10	1	1	11	2026-07-20	100.00	QR	DEMO-2026-0010
11	11	11	1	1	12	2026-07-20	100.00	EFECTIVO	DEMO-2026-0011
12	12	12	1	1	13	2026-07-20	100.00	QR	DEMO-2026-0012
13	13	13	1	1	14	2026-07-20	100.00	EFECTIVO	DEMO-2026-0013
14	14	14	1	1	15	2026-07-20	100.00	QR	DEMO-2026-0014
15	15	15	1	1	16	2026-07-20	100.00	EFECTIVO	DEMO-2026-0015
16	16	16	1	1	17	2026-07-20	100.00	QR	DEMO-2026-0016
17	17	17	1	1	18	2026-07-20	100.00	EFECTIVO	DEMO-2026-0017
18	18	18	1	1	19	2026-07-20	100.00	QR	DEMO-2026-0018
19	19	19	1	1	20	2026-07-20	100.00	EFECTIVO	DEMO-2026-0019
20	20	20	1	1	21	2026-07-20	100.00	QR	DEMO-2026-0020
\.


--
-- Data for Name: fact_resultados; Type: TABLE DATA; Schema: dw; Owner: -
--

COPY dw.fact_resultados (inscripcion_id, matricula_id, gestion_id, carrera_id, estudiante_id, docente_id, materia_id, fecha, promedio, asistencia, nota_final, resultado, aprobado, recuperacion) FROM stdin;
\.


--
-- Data for Name: _prisma_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public._prisma_migrations (id, checksum, finished_at, migration_name, logs, rolled_back_at, started_at, applied_steps_count) FROM stdin;
eb168c49-b8e9-4e6f-be90-44c35889213c	a3f21359809754e24d4cef0b21e832cacb49d32bfb27dd606a27c471eea7fc48	2026-10-30 15:55:36.090889-04	202610300001_initial	\N	\N	2026-10-30 15:55:35.439596-04	1
addd7f3e-268f-4646-8269-0d00fcbd2d93	46171e40892658d440ee3864f8210c917a04caa6c3b62b0b6948a09494abb885	2026-10-30 16:16:26.849255-04	202610300002_warehouse	\N	\N	2026-10-30 16:16:26.611705-04	1
\.


--
-- Data for Name: asistencias_demo_historicas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.asistencias_demo_historicas (id, inscripcion_id, fecha, estado) FROM stdin;
\.


--
-- Data for Name: asistencias_sesion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.asistencias_sesion (inscripcion_id, sesion_id, oferta_id, minutos_presentes) FROM stdin;
1	1	1	100
2	2	2	100
3	3	3	100
4	1	1	100
5	2	2	100
6	3	3	100
7	1	1	100
8	2	2	100
9	3	3	100
10	1	1	100
11	2	2	100
12	3	3	100
13	1	1	100
14	2	2	100
15	3	3	100
16	1	1	100
17	2	2	100
18	3	3	100
19	1	1	80
20	2	2	80
21	3	3	80
22	1	1	100
23	2	2	100
24	3	3	100
25	1	1	100
26	2	2	100
27	3	3	100
28	1	1	100
29	2	2	100
30	3	3	100
31	1	1	100
32	2	2	100
33	3	3	100
34	1	1	100
35	2	2	100
36	3	3	100
37	1	1	100
38	2	2	100
39	3	3	100
40	1	1	80
41	2	2	80
42	3	3	80
43	1	1	100
44	2	2	100
45	3	3	100
46	1	1	100
47	2	2	100
48	3	3	100
49	1	1	100
50	2	2	100
51	3	3	100
52	1	1	100
53	2	2	100
54	3	3	100
55	1	1	100
56	2	2	100
57	3	3	100
58	1	1	100
59	2	2	100
60	3	3	100
61	1	1	80
62	2	2	80
63	3	3	80
64	1	1	100
65	2	2	100
66	3	3	100
67	1	1	100
68	2	2	100
69	3	3	100
70	1	1	100
71	2	2	100
72	3	3	100
73	1	1	100
74	2	2	100
75	3	3	100
76	1	1	100
77	2	2	100
78	3	3	100
79	1	1	100
80	2	2	100
81	3	3	100
82	1	1	80
83	2	2	80
84	3	3	80
85	1	1	100
86	2	2	100
87	3	3	100
88	1	1	100
89	2	2	100
90	3	3	100
91	4	4	100
92	5	5	100
93	6	6	100
94	4	4	100
95	5	5	100
96	6	6	100
97	4	4	100
98	5	5	100
99	6	6	100
100	4	4	100
101	5	5	100
102	6	6	100
103	4	4	80
104	5	5	80
105	6	6	80
106	4	4	100
107	5	5	100
108	6	6	100
109	4	4	100
110	5	5	100
111	6	6	100
112	4	4	100
113	5	5	100
114	6	6	100
115	4	4	100
116	5	5	100
117	6	6	100
118	4	4	100
119	5	5	100
120	6	6	100
121	4	4	100
122	5	5	100
123	6	6	100
124	4	4	80
125	5	5	80
126	6	6	80
127	4	4	100
128	5	5	100
129	6	6	100
130	4	4	100
131	5	5	100
132	6	6	100
133	4	4	100
134	5	5	100
135	6	6	100
136	4	4	100
137	5	5	100
138	6	6	100
139	4	4	100
140	5	5	100
141	6	6	100
142	4	4	100
143	5	5	100
144	6	6	100
145	4	4	80
146	5	5	80
147	6	6	80
148	4	4	100
149	5	5	100
150	6	6	100
\.


--
-- Data for Name: aulas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aulas (id, codigo, capacidad) FROM stdin;
1	AULA-101	40
2	AULA-102	35
3	LAB-SISTEMAS	35
4	LAB-ELECTRICIDAD	30
\.


--
-- Data for Name: calificaciones; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.calificaciones (inscripcion_id, evaluacion_id, oferta_id, nota) FROM stdin;
1	1	1	50.00
1	2	1	60.00
2	3	2	50.00
2	4	2	60.00
3	5	3	50.00
3	6	3	60.00
4	1	1	80.00
4	2	1	81.00
5	3	2	82.00
5	4	2	83.00
6	5	3	84.00
6	6	3	85.00
7	1	1	87.00
7	2	1	88.00
8	3	2	89.00
8	4	2	90.00
9	5	3	91.00
9	6	3	92.00
10	1	1	94.00
10	2	1	95.00
11	3	2	65.00
11	4	2	66.00
12	5	3	67.00
12	6	3	68.00
13	1	1	70.00
13	2	1	71.00
14	3	2	72.00
14	4	2	73.00
15	5	3	74.00
15	6	3	75.00
16	1	1	77.00
16	2	1	78.00
17	3	2	79.00
17	4	2	80.00
18	5	3	81.00
18	6	3	82.00
19	1	1	84.00
19	2	1	85.00
20	3	2	86.00
20	4	2	87.00
21	5	3	88.00
21	6	3	89.00
22	1	1	91.00
22	2	1	92.00
23	3	2	93.00
23	4	2	94.00
24	5	3	95.00
24	6	3	65.00
25	1	1	67.00
25	2	1	68.00
26	3	2	69.00
26	4	2	70.00
27	5	3	71.00
27	6	3	72.00
28	1	1	74.00
28	2	1	75.00
29	3	2	76.00
29	4	2	77.00
30	5	3	78.00
30	6	3	79.00
31	1	1	81.00
31	2	1	82.00
32	3	2	83.00
32	4	2	84.00
33	5	3	85.00
33	6	3	86.00
34	1	1	88.00
34	2	1	89.00
35	3	2	90.00
35	4	2	91.00
36	5	3	92.00
36	6	3	93.00
37	1	1	95.00
37	2	1	65.00
38	3	2	66.00
38	4	2	67.00
39	5	3	68.00
39	6	3	69.00
40	1	1	71.00
40	2	1	72.00
41	3	2	73.00
41	4	2	74.00
42	5	3	75.00
42	6	3	76.00
43	1	1	78.00
43	2	1	79.00
44	3	2	80.00
44	4	2	81.00
45	5	3	82.00
45	6	3	83.00
46	1	1	85.00
46	2	1	86.00
47	3	2	87.00
47	4	2	88.00
48	5	3	89.00
48	6	3	90.00
49	1	1	92.00
49	2	1	93.00
50	3	2	94.00
50	4	2	95.00
51	5	3	65.00
51	6	3	66.00
52	1	1	68.00
52	2	1	69.00
53	3	2	70.00
53	4	2	71.00
54	5	3	72.00
54	6	3	73.00
55	1	1	75.00
55	2	1	76.00
56	3	2	77.00
56	4	2	78.00
57	5	3	79.00
57	6	3	80.00
58	1	1	82.00
58	2	1	83.00
59	3	2	84.00
59	4	2	85.00
60	5	3	86.00
60	6	3	87.00
61	1	1	89.00
61	2	1	90.00
62	3	2	91.00
62	4	2	92.00
63	5	3	93.00
63	6	3	94.00
64	1	1	65.00
64	2	1	66.00
65	3	2	67.00
65	4	2	68.00
66	5	3	69.00
66	6	3	70.00
67	1	1	72.00
67	2	1	73.00
68	3	2	74.00
68	4	2	75.00
69	5	3	76.00
69	6	3	77.00
70	1	1	79.00
70	2	1	80.00
71	3	2	81.00
71	4	2	82.00
72	5	3	83.00
72	6	3	84.00
73	1	1	86.00
73	2	1	87.00
74	3	2	88.00
74	4	2	89.00
75	5	3	90.00
75	6	3	91.00
76	1	1	93.00
76	2	1	94.00
77	3	2	95.00
77	4	2	65.00
78	5	3	66.00
78	6	3	67.00
79	1	1	69.00
79	2	1	70.00
80	3	2	71.00
80	4	2	72.00
81	5	3	73.00
81	6	3	74.00
82	1	1	76.00
82	2	1	77.00
83	3	2	78.00
83	4	2	79.00
84	5	3	80.00
84	6	3	81.00
85	1	1	83.00
85	2	1	84.00
86	3	2	85.00
86	4	2	86.00
87	5	3	87.00
87	6	3	88.00
88	1	1	90.00
88	2	1	91.00
89	3	2	92.00
89	4	2	93.00
90	5	3	94.00
90	6	3	95.00
91	7	4	72.00
91	8	4	73.00
92	9	5	74.00
92	10	5	75.00
93	11	6	76.00
93	12	6	77.00
94	7	4	79.00
94	8	4	80.00
95	9	5	81.00
95	10	5	82.00
96	11	6	83.00
96	12	6	84.00
97	7	4	86.00
97	8	4	87.00
98	9	5	88.00
98	10	5	89.00
99	11	6	90.00
99	12	6	91.00
100	7	4	93.00
100	8	4	94.00
101	9	5	95.00
101	10	5	65.00
102	11	6	66.00
102	12	6	67.00
103	7	4	69.00
103	8	4	70.00
104	9	5	71.00
104	10	5	72.00
105	11	6	73.00
105	12	6	74.00
106	7	4	76.00
106	8	4	77.00
107	9	5	78.00
107	10	5	79.00
108	11	6	80.00
108	12	6	81.00
109	7	4	83.00
109	8	4	84.00
110	9	5	85.00
110	10	5	86.00
111	11	6	87.00
111	12	6	88.00
112	7	4	90.00
112	8	4	91.00
113	9	5	92.00
113	10	5	93.00
114	11	6	94.00
114	12	6	95.00
115	7	4	66.00
115	8	4	67.00
116	9	5	68.00
116	10	5	69.00
117	11	6	70.00
117	12	6	71.00
118	7	4	73.00
118	8	4	74.00
119	9	5	75.00
119	10	5	76.00
120	11	6	77.00
120	12	6	78.00
121	7	4	80.00
121	8	4	81.00
122	9	5	82.00
122	10	5	83.00
123	11	6	84.00
123	12	6	85.00
124	7	4	87.00
124	8	4	88.00
125	9	5	89.00
125	10	5	90.00
126	11	6	91.00
126	12	6	92.00
127	7	4	94.00
127	8	4	95.00
128	9	5	65.00
128	10	5	66.00
129	11	6	67.00
129	12	6	68.00
130	7	4	70.00
130	8	4	71.00
131	9	5	72.00
131	10	5	73.00
132	11	6	74.00
132	12	6	75.00
133	7	4	77.00
133	8	4	78.00
134	9	5	79.00
134	10	5	80.00
135	11	6	81.00
135	12	6	82.00
136	7	4	84.00
136	8	4	85.00
137	9	5	86.00
137	10	5	87.00
138	11	6	88.00
138	12	6	89.00
139	7	4	91.00
139	8	4	92.00
140	9	5	93.00
140	10	5	94.00
141	11	6	95.00
141	12	6	65.00
142	7	4	67.00
142	8	4	68.00
143	9	5	69.00
143	10	5	70.00
144	11	6	71.00
144	12	6	72.00
145	7	4	74.00
145	8	4	75.00
146	9	5	76.00
146	10	5	77.00
147	11	6	78.00
147	12	6	79.00
148	7	4	81.00
148	8	4	82.00
149	9	5	83.00
149	10	5	84.00
150	11	6	85.00
150	12	6	86.00
\.


--
-- Data for Name: cargos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cargos (id, matricula_id, concepto, monto, vencimiento) FROM stdin;
1	1	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
2	2	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
3	3	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
4	4	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
5	5	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
6	6	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
7	7	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
8	8	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
9	9	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
10	10	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
11	11	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
12	12	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
13	13	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
14	14	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
15	15	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
16	16	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
17	17	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
18	18	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
19	19	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
20	20	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
21	21	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
22	22	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
23	23	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
24	24	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
25	25	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
26	26	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
27	27	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
28	28	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
29	29	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
30	30	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
31	31	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
32	32	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
33	33	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
34	34	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
35	35	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
36	36	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
37	37	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
38	38	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
39	39	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
40	40	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
41	41	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
42	42	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
43	43	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
44	44	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
45	45	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
46	46	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
47	47	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
48	48	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
49	49	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
50	50	Matrícula y materiales (importe ficticio de demostración)	350.00	2026-11-15
\.


--
-- Data for Name: carreras; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.carreras (id, codigo, nombre, nivel, duracion_anios, regimen, fuente_url, activa) FROM stdin;
1	SIS	Sistemas Informáticos	Técnico Superior	3	ANUAL	https://www.itsc.edu.bo/index.php?Itemid=155	1
2	CON	Contaduría General	Técnico Superior	3	ANUAL	https://www.itsc.edu.bo/index.php?Itemid=156	1
3	ELE	Electricidad Industrial	Técnico Superior	3	SEMESTRAL	https://www.itsc.edu.bo/index.php?Itemid=160	1
4	QUI	Química Industrial	Técnico Superior	3	SEMESTRAL	https://www.itsc.edu.bo/index.php?Itemid=157	1
5	MIN	Mecánica Industrial	Técnico Superior	3	SEMESTRAL	https://www.itsc.edu.bo/index.php?Itemid=158	1
6	MAU	Mecánica Automotriz	Técnico Superior	3	SEMESTRAL	https://www.itsc.edu.bo/index.php?Itemid=159	1
7	ELN	Electrónica	Técnico Superior	3	SEMESTRAL	https://www.itsc.edu.bo/index.php?Itemid=161	1
8	CCV	Construcción Civil	Técnico Superior	3	SEMESTRAL	https://www.itsc.edu.bo/index.php?Itemid=162	1
9	DEMO-C01	Redes y Telecomunicaciones (demostración)	Técnico Superior	3	SEMESTRAL	urn:itsc:datos-ficticios	1
10	DEMO-C02	Diseño Gráfico (demostración)	Técnico Superior	3	SEMESTRAL	urn:itsc:datos-ficticios	1
11	DEMO-C03	Administración de Empresas (demostración)	Técnico Superior	3	SEMESTRAL	urn:itsc:datos-ficticios	1
12	DEMO-C04	Energías Renovables (demostración)	Técnico Superior	3	SEMESTRAL	urn:itsc:datos-ficticios	1
\.


--
-- Data for Name: cierres_oferta; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cierres_oferta (oferta_id, minutos_carga, cerrado_por, fecha) FROM stdin;
\.


--
-- Data for Name: defensas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.defensas (id, proyecto_id, fecha, aula_id, nota, acta) FROM stdin;
\.


--
-- Data for Name: docentes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.docentes (id, documento, nombres, apellidos, especialidad, telefono, correo) FROM stdin;
1	FICT-D01	Lucía	Vargas Molina	Informática	71000001	lucia@example.com
2	FICT-D02	Andrés	Paredes Lima	Contabilidad	71000002	andres@example.com
3	FICT-D03	Camila	Ortiz Rivas	Electricidad	71000003	camila@example.com
4	DEMO-DOC-000001	Javier Adrián	Aguilar Ortega	Sistemas Informáticos	\N	docente00001@example.invalid
5	DEMO-DOC-000002	Andrés Luis	Medina Torres	Contaduría General	\N	docente00002@example.invalid
6	DEMO-DOC-000003	Valeria Javier	Navarro Gutiérrez	Electricidad Industrial	\N	docente00003@example.invalid
7	DEMO-DOC-000004	Camila Camila	Ríos Apaza	Química Industrial	\N	docente00004@example.invalid
8	DEMO-DOC-000005	Lucía Daniela	Rivera Montes	Mecánica Industrial	\N	docente00005@example.invalid
9	DEMO-DOC-000006	Mariana Andrea	Apaza Mendoza	Mecánica Automotriz	\N	docente00006@example.invalid
10	DEMO-DOC-000007	Daniela Carolina	Pinto Soto	Electrónica	\N	docente00007@example.invalid
11	DEMO-DOC-000008	Sofía Victoria	Molina Vega	Construcción Civil	\N	docente00008@example.invalid
12	DEMO-DOC-000009	Paola Mauricio	Aguilar Rivera	Redes y Telecomunicaciones	\N	docente00009@example.invalid
13	DEMO-DOC-000010	Andrea Ricardo	Medina Mamani	Diseño Gráfico	\N	docente00010@example.invalid
14	DEMO-DOC-000011	Gabriela Lorena	Navarro Villarroel	Administración de Empresas	\N	docente00011@example.invalid
15	DEMO-DOC-000012	Natalia Gabriel	Ríos Castro	Energías Renovables	\N	docente00012@example.invalid
16	DEMO-DOC-000013	Carolina Santiago	Rivera Morales	Sistemas Informáticos	\N	docente00013@example.invalid
17	DEMO-DOC-000014	Fernanda Nicolás	Apaza Ríos	Contaduría General	\N	docente00014@example.invalid
18	DEMO-DOC-000015	Isabel Alejandro	Pinto Escobar	Electricidad Industrial	\N	docente00015@example.invalid
19	DEMO-DOC-000016	Victoria Carlos	Molina Soria	Química Industrial	\N	docente00016@example.invalid
20	DEMO-DOC-000017	Elena Valeria	Aguilar Vargas	Mecánica Industrial	\N	docente00017@example.invalid
21	DEMO-DOC-000018	Rodrigo Mariana	Medina Romero	Mecánica Automotriz	\N	docente00018@example.invalid
22	DEMO-DOC-000019	Mauricio Paola	Navarro Navarro	Electrónica	\N	docente00019@example.invalid
23	DEMO-DOC-000020	Eduardo Natalia	Ríos López	Construcción Civil	\N	docente00020@example.invalid
24	DEMO-DOC-000021	Pablo Isabel	Rivera Quispe	Redes y Telecomunicaciones	\N	docente00021@example.invalid
25	DEMO-DOC-000022	Ricardo Rodrigo	Apaza Arias	Diseño Gráfico	\N	docente00022@example.invalid
26	DEMO-DOC-000023	Patricia Pablo	Pinto Flores	Administración de Empresas	\N	docente00023@example.invalid
27	DEMO-DOC-000024	Claudia Claudia	Molina Medina	Energías Renovables	\N	docente00024@example.invalid
28	DEMO-DOC-000025	Lorena Rosa	Aguilar Cabrera	Sistemas Informáticos	\N	docente00025@example.invalid
29	DEMO-DOC-000026	Verónica Daniel	Medina Castillo	Contaduría General	\N	docente00026@example.invalid
30	DEMO-DOC-000027	Rosa Diego	Navarro Condori	Electricidad Industrial	\N	docente00027@example.invalid
31	DEMO-DOC-000028	Gabriel Sebastián	Ríos Delgado	Química Industrial	\N	docente00028@example.invalid
32	DEMO-DOC-000029	Mateo Miguel	Rivera Aguilar	Mecánica Industrial	\N	docente00029@example.invalid
33	DEMO-DOC-000030	Daniel Andrés	Apaza Herrera	Mecánica Automotriz	\N	docente00030@example.invalid
34	DEMO-DOC-000031	Santiago Lucía	Pinto Suárez	Electrónica	\N	docente00031@example.invalid
35	DEMO-DOC-000032	Samuel Sofía	Molina Valdez	Construcción Civil	\N	docente00032@example.invalid
36	DEMO-DOC-000033	Diego Gabriela	Aguilar Choque	Redes y Telecomunicaciones	\N	docente00033@example.invalid
37	DEMO-DOC-000034	Nicolás Fernanda	Medina Molina	Diseño Gráfico	\N	docente00034@example.invalid
38	DEMO-DOC-000035	Adrián Elena	Navarro Salazar	Administración de Empresas	\N	docente00035@example.invalid
39	DEMO-DOC-000036	Sebastián Eduardo	Ríos Paredes	Energías Renovables	\N	docente00036@example.invalid
40	DEMO-DOC-000037	Alejandro Patricia	Rivera Cruz	Sistemas Informáticos	\N	docente00037@example.invalid
41	DEMO-DOC-000038	Luis Verónica	Apaza Fernández	Contaduría General	\N	docente00038@example.invalid
42	DEMO-DOC-000039	Miguel Mateo	Pinto Pinto	Electricidad Industrial	\N	docente00039@example.invalid
43	DEMO-DOC-000040	Carlos Samuel	Molina Rojas	Química Industrial	\N	docente00040@example.invalid
44	DEMO-DOC-000041	Javier Adrián	Aguilar Ortega	Mecánica Industrial	\N	docente00041@example.invalid
45	DEMO-DOC-000042	Andrés Luis	Medina Torres	Mecánica Automotriz	\N	docente00042@example.invalid
46	DEMO-DOC-000043	Valeria Javier	Navarro Gutiérrez	Electrónica	\N	docente00043@example.invalid
47	DEMO-DOC-000044	Camila Camila	Ríos Apaza	Construcción Civil	\N	docente00044@example.invalid
48	DEMO-DOC-000045	Lucía Daniela	Rivera Montes	Redes y Telecomunicaciones	\N	docente00045@example.invalid
49	DEMO-DOC-000046	Mariana Andrea	Apaza Mendoza	Diseño Gráfico	\N	docente00046@example.invalid
50	DEMO-DOC-000047	Daniela Carolina	Pinto Soto	Administración de Empresas	\N	docente00047@example.invalid
51	DEMO-DOC-000048	Sofía Victoria	Molina Vega	Energías Renovables	\N	docente00048@example.invalid
52	DEMO-DOC-000049	Paola Mauricio	Aguilar Rivera	Sistemas Informáticos	\N	docente00049@example.invalid
53	DEMO-DOC-000050	Andrea Ricardo	Medina Mamani	Contaduría General	\N	docente00050@example.invalid
54	DEMO-DOC-000051	Gabriela Lorena	Navarro Villarroel	Electricidad Industrial	\N	docente00051@example.invalid
55	DEMO-DOC-000052	Natalia Gabriel	Ríos Castro	Química Industrial	\N	docente00052@example.invalid
56	DEMO-DOC-000053	Carolina Santiago	Rivera Morales	Mecánica Industrial	\N	docente00053@example.invalid
57	DEMO-DOC-000054	Fernanda Nicolás	Apaza Ríos	Mecánica Automotriz	\N	docente00054@example.invalid
58	DEMO-DOC-000055	Isabel Alejandro	Pinto Escobar	Electrónica	\N	docente00055@example.invalid
59	DEMO-DOC-000056	Victoria Carlos	Molina Soria	Construcción Civil	\N	docente00056@example.invalid
60	DEMO-DOC-000057	Elena Valeria	Aguilar Vargas	Redes y Telecomunicaciones	\N	docente00057@example.invalid
61	DEMO-DOC-000058	Rodrigo Mariana	Medina Romero	Diseño Gráfico	\N	docente00058@example.invalid
62	DEMO-DOC-000059	Mauricio Paola	Navarro Navarro	Administración de Empresas	\N	docente00059@example.invalid
63	DEMO-DOC-000060	Eduardo Natalia	Ríos López	Energías Renovables	\N	docente00060@example.invalid
64	DEMO-DOC-000061	Pablo Isabel	Rivera Quispe	Sistemas Informáticos	\N	docente00061@example.invalid
65	DEMO-DOC-000062	Ricardo Rodrigo	Apaza Arias	Contaduría General	\N	docente00062@example.invalid
66	DEMO-DOC-000063	Patricia Pablo	Pinto Flores	Electricidad Industrial	\N	docente00063@example.invalid
67	DEMO-DOC-000064	Claudia Claudia	Molina Medina	Química Industrial	\N	docente00064@example.invalid
68	DEMO-DOC-000065	Lorena Rosa	Aguilar Cabrera	Mecánica Industrial	\N	docente00065@example.invalid
69	DEMO-DOC-000066	Verónica Daniel	Medina Castillo	Mecánica Automotriz	\N	docente00066@example.invalid
70	DEMO-DOC-000067	Rosa Diego	Navarro Condori	Electrónica	\N	docente00067@example.invalid
71	DEMO-DOC-000068	Gabriel Sebastián	Ríos Delgado	Construcción Civil	\N	docente00068@example.invalid
72	DEMO-DOC-000069	Mateo Miguel	Rivera Aguilar	Redes y Telecomunicaciones	\N	docente00069@example.invalid
73	DEMO-DOC-000070	Daniel Andrés	Apaza Herrera	Diseño Gráfico	\N	docente00070@example.invalid
74	DEMO-DOC-000071	Santiago Lucía	Pinto Suárez	Administración de Empresas	\N	docente00071@example.invalid
75	DEMO-DOC-000072	Samuel Sofía	Molina Valdez	Energías Renovables	\N	docente00072@example.invalid
76	DEMO-DOC-000073	Diego Gabriela	Aguilar Choque	Sistemas Informáticos	\N	docente00073@example.invalid
77	DEMO-DOC-000074	Nicolás Fernanda	Medina Molina	Contaduría General	\N	docente00074@example.invalid
78	DEMO-DOC-000075	Adrián Elena	Navarro Salazar	Electricidad Industrial	\N	docente00075@example.invalid
79	DEMO-DOC-000076	Sebastián Eduardo	Ríos Paredes	Química Industrial	\N	docente00076@example.invalid
80	DEMO-DOC-000077	Alejandro Patricia	Rivera Cruz	Mecánica Industrial	\N	docente00077@example.invalid
\.


--
-- Data for Name: documentos_matricula; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.documentos_matricula (id, matricula_id, tipo_documento_id, estado, fecha_recepcion, observacion) FROM stdin;
1	1	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
2	1	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
3	2	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
4	2	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
5	3	1	PENDIENTE	\N	Registro ficticio para el práctico.
6	3	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
7	4	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
8	4	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
9	5	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
10	5	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
11	6	1	PENDIENTE	\N	Registro ficticio para el práctico.
12	6	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
13	7	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
14	7	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
15	8	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
16	8	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
17	9	1	PENDIENTE	\N	Registro ficticio para el práctico.
18	9	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
19	10	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
20	10	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
21	11	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
22	11	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
23	12	1	PENDIENTE	\N	Registro ficticio para el práctico.
24	12	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
25	13	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
26	13	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
27	14	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
28	14	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
29	15	1	PENDIENTE	\N	Registro ficticio para el práctico.
30	15	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
31	16	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
32	16	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
33	17	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
34	17	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
35	18	1	PENDIENTE	\N	Registro ficticio para el práctico.
36	18	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
37	19	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
38	19	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
39	20	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
40	20	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
41	21	1	PENDIENTE	\N	Registro ficticio para el práctico.
42	21	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
43	22	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
44	22	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
45	23	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
46	23	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
47	24	1	PENDIENTE	\N	Registro ficticio para el práctico.
48	24	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
49	25	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
50	25	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
51	26	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
52	26	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
53	27	1	PENDIENTE	\N	Registro ficticio para el práctico.
54	27	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
55	28	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
56	28	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
57	29	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
58	29	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
59	30	1	PENDIENTE	\N	Registro ficticio para el práctico.
60	30	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
61	31	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
62	31	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
63	32	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
64	32	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
65	33	1	PENDIENTE	\N	Registro ficticio para el práctico.
66	33	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
67	34	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
68	34	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
69	35	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
70	35	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
71	36	1	PENDIENTE	\N	Registro ficticio para el práctico.
72	36	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
73	37	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
74	37	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
75	38	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
76	38	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
77	39	1	PENDIENTE	\N	Registro ficticio para el práctico.
78	39	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
79	40	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
80	40	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
81	41	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
82	41	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
83	42	1	PENDIENTE	\N	Registro ficticio para el práctico.
84	42	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
85	43	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
86	43	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
87	44	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
88	44	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
89	45	1	PENDIENTE	\N	Registro ficticio para el práctico.
90	45	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
91	46	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
92	46	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
93	47	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
94	47	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
95	48	1	PENDIENTE	\N	Registro ficticio para el práctico.
96	48	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
97	49	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
98	49	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
99	50	1	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
100	50	2	RECIBIDO	2026-02-02	Registro ficticio para el práctico.
\.


--
-- Data for Name: estudiantes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.estudiantes (id, registro, documento, nombres, apellidos, fecha_nacimiento, telefono, correo, direccion, fecha_registro) FROM stdin;
1	EST-001	FICT-1001	Mateo	Rojas Salvatierra	2005-03-12	70000001	mateo@example.com	Calle Ficticia 10	2026-10-16 20:37:32
2	EST-002	FICT-1002	Valeria	Méndez Suárez	2004-08-21	70000002	valeria@example.com	Calle Ficticia 20	2026-10-16 20:37:32
3	EST-003	FICT-1003	Bruno	Castro Aguilar	2005-11-04	70000003	bruno@example.com	Calle Ficticia 30	2026-10-16 20:37:32
5	DEMO-fbc571	FICT-fbc571	Elena	Salvatierra Demo	2005-02-15	70000009	\N	\N	2026-10-16 20:47:53
6	DEMO-E-00001	DEMO-EST-000001	Gabriel Adrián	Molina Flores	2001-12-01	\N	estudiante00001@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
7	DEMO-E-00002	DEMO-EST-000002	Mateo Adrián	Molina Medina	2006-10-10	\N	estudiante00002@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
8	DEMO-E-00003	DEMO-EST-000003	Daniel Adrián	Molina Cabrera	1998-08-21	\N	estudiante00003@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
9	DEMO-E-00004	DEMO-EST-000004	Santiago Adrián	Molina Castillo	2006-12-26	\N	estudiante00004@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
10	DEMO-E-00005	DEMO-EST-000005	Samuel Adrián	Molina Condori	2007-07-23	\N	estudiante00005@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
11	DEMO-E-00006	DEMO-EST-000006	Diego Adrián	Molina Delgado	2006-05-10	\N	estudiante00006@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
12	DEMO-E-00007	DEMO-EST-000007	Nicolás Adrián	Molina Aguilar	2004-10-19	\N	estudiante00007@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
13	DEMO-E-00008	DEMO-EST-000008	Adrián Adrián	Molina Herrera	2000-10-09	\N	estudiante00008@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
14	DEMO-E-00009	DEMO-EST-000009	Sebastián Adrián	Molina Suárez	2003-06-19	\N	estudiante00009@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
15	DEMO-E-00010	DEMO-EST-000010	Alejandro Adrián	Molina Valdez	2002-10-09	\N	estudiante00010@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
16	DEMO-E-00011	DEMO-EST-000011	Luis Adrián	Molina Choque	1997-03-29	\N	estudiante00011@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
17	DEMO-E-00012	DEMO-EST-000012	Miguel Adrián	Molina Molina	2001-02-22	\N	estudiante00012@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
18	DEMO-E-00013	DEMO-EST-000013	Carlos Adrián	Molina Salazar	2003-04-10	\N	estudiante00013@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
19	DEMO-E-00014	DEMO-EST-000014	Javier Adrián	Molina Paredes	2001-02-14	\N	estudiante00014@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
20	DEMO-E-00015	DEMO-EST-000015	Andrés Adrián	Molina Cruz	2004-03-24	\N	estudiante00015@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
21	DEMO-E-00016	DEMO-EST-000016	Valeria Adrián	Molina Fernández	2007-01-28	\N	estudiante00016@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
22	DEMO-E-00017	DEMO-EST-000017	Camila Adrián	Molina Pinto	2005-10-17	\N	estudiante00017@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
23	DEMO-E-00018	DEMO-EST-000018	Lucía Adrián	Molina Rojas	2002-04-11	\N	estudiante00018@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
24	DEMO-E-00019	DEMO-EST-000019	Mariana Adrián	Molina Ortega	2006-05-11	\N	estudiante00019@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
25	DEMO-E-00020	DEMO-EST-000020	Daniela Adrián	Molina Torres	2005-02-11	\N	estudiante00020@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
26	DEMO-E-00021	DEMO-EST-000021	Sofía Adrián	Molina Gutiérrez	1997-10-04	\N	estudiante00021@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
27	DEMO-E-00022	DEMO-EST-000022	Paola Adrián	Molina Apaza	2005-12-27	\N	estudiante00022@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
28	DEMO-E-00023	DEMO-EST-000023	Andrea Adrián	Molina Montes	1999-06-11	\N	estudiante00023@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
29	DEMO-E-00024	DEMO-EST-000024	Gabriela Adrián	Molina Mendoza	1995-01-05	\N	estudiante00024@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
30	DEMO-E-00025	DEMO-EST-000025	Natalia Adrián	Molina Soto	2000-08-18	\N	estudiante00025@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
31	DEMO-E-00026	DEMO-EST-000026	Carolina Adrián	Molina Vega	1995-05-22	\N	estudiante00026@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
32	DEMO-E-00027	DEMO-EST-000027	Fernanda Adrián	Molina Rivera	1995-02-18	\N	estudiante00027@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
33	DEMO-E-00028	DEMO-EST-000028	Isabel Adrián	Molina Mamani	2002-08-14	\N	estudiante00028@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
34	DEMO-E-00029	DEMO-EST-000029	Victoria Adrián	Molina Villarroel	1998-02-08	\N	estudiante00029@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
35	DEMO-E-00030	DEMO-EST-000030	Elena Adrián	Molina Castro	1995-08-16	\N	estudiante00030@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
36	DEMO-E-00031	DEMO-EST-000031	Rodrigo Adrián	Molina Morales	1998-05-13	\N	estudiante00031@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
37	DEMO-E-00032	DEMO-EST-000032	Mauricio Adrián	Molina Ríos	2006-12-12	\N	estudiante00032@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
38	DEMO-E-00033	DEMO-EST-000033	Eduardo Adrián	Molina Escobar	2002-12-21	\N	estudiante00033@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
39	DEMO-E-00034	DEMO-EST-000034	Pablo Adrián	Molina Soria	2006-11-20	\N	estudiante00034@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
40	DEMO-E-00035	DEMO-EST-000035	Ricardo Adrián	Molina Vargas	2002-08-24	\N	estudiante00035@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
41	DEMO-E-00036	DEMO-EST-000036	Patricia Adrián	Molina Romero	1997-12-17	\N	estudiante00036@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
42	DEMO-E-00037	DEMO-EST-000037	Claudia Adrián	Molina Navarro	1999-09-05	\N	estudiante00037@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
43	DEMO-E-00038	DEMO-EST-000038	Lorena Adrián	Molina López	1998-01-17	\N	estudiante00038@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
44	DEMO-E-00039	DEMO-EST-000039	Verónica Adrián	Molina Quispe	2007-09-06	\N	estudiante00039@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
45	DEMO-E-00040	DEMO-EST-000040	Rosa Adrián	Molina Arias	2000-08-20	\N	estudiante00040@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
46	DEMO-E-00041	DEMO-EST-000041	Gabriel Sebastián	Vargas Flores	1996-12-09	\N	estudiante00041@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
47	DEMO-E-00042	DEMO-EST-000042	Mateo Sebastián	Vargas Medina	2000-11-03	\N	estudiante00042@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
48	DEMO-E-00043	DEMO-EST-000043	Daniel Sebastián	Vargas Cabrera	2003-01-12	\N	estudiante00043@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
49	DEMO-E-00044	DEMO-EST-000044	Santiago Sebastián	Vargas Castillo	1996-09-23	\N	estudiante00044@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
50	DEMO-E-00045	DEMO-EST-000045	Samuel Sebastián	Vargas Condori	2006-12-06	\N	estudiante00045@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
51	DEMO-E-00046	DEMO-EST-000046	Diego Sebastián	Vargas Delgado	2007-10-10	\N	estudiante00046@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
52	DEMO-E-00047	DEMO-EST-000047	Nicolás Sebastián	Vargas Aguilar	1995-09-21	\N	estudiante00047@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
53	DEMO-E-00048	DEMO-EST-000048	Adrián Sebastián	Vargas Herrera	1997-07-06	\N	estudiante00048@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
54	DEMO-E-00049	DEMO-EST-000049	Sebastián Sebastián	Vargas Suárez	1999-05-31	\N	estudiante00049@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
55	DEMO-E-00050	DEMO-EST-000050	Alejandro Sebastián	Vargas Valdez	2003-01-30	\N	estudiante00050@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
56	DEMO-E-00051	DEMO-EST-000051	Luis Sebastián	Vargas Choque	1996-06-23	\N	estudiante00051@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
57	DEMO-E-00052	DEMO-EST-000052	Miguel Sebastián	Vargas Molina	1995-02-25	\N	estudiante00052@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
58	DEMO-E-00053	DEMO-EST-000053	Carlos Sebastián	Vargas Salazar	1996-02-03	\N	estudiante00053@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
59	DEMO-E-00054	DEMO-EST-000054	Javier Sebastián	Vargas Paredes	1995-08-23	\N	estudiante00054@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
60	DEMO-E-00055	DEMO-EST-000055	Andrés Sebastián	Vargas Cruz	2006-10-27	\N	estudiante00055@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
61	DEMO-E-00056	DEMO-EST-000056	Valeria Sebastián	Vargas Fernández	2006-11-22	\N	estudiante00056@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
62	DEMO-E-00057	DEMO-EST-000057	Camila Sebastián	Vargas Pinto	1996-02-15	\N	estudiante00057@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
63	DEMO-E-00058	DEMO-EST-000058	Lucía Sebastián	Vargas Rojas	1997-12-13	\N	estudiante00058@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
64	DEMO-E-00059	DEMO-EST-000059	Mariana Sebastián	Vargas Ortega	2001-05-31	\N	estudiante00059@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
65	DEMO-E-00060	DEMO-EST-000060	Daniela Sebastián	Vargas Torres	1999-11-17	\N	estudiante00060@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
66	DEMO-E-00061	DEMO-EST-000061	Sofía Sebastián	Vargas Gutiérrez	2006-06-30	\N	estudiante00061@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
67	DEMO-E-00062	DEMO-EST-000062	Paola Sebastián	Vargas Apaza	2003-03-19	\N	estudiante00062@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
68	DEMO-E-00063	DEMO-EST-000063	Andrea Sebastián	Vargas Montes	1999-03-11	\N	estudiante00063@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
69	DEMO-E-00064	DEMO-EST-000064	Gabriela Sebastián	Vargas Mendoza	1996-03-08	\N	estudiante00064@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
70	DEMO-E-00065	DEMO-EST-000065	Natalia Sebastián	Vargas Soto	2007-02-09	\N	estudiante00065@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
71	DEMO-E-00066	DEMO-EST-000066	Carolina Sebastián	Vargas Vega	2004-11-07	\N	estudiante00066@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
72	DEMO-E-00067	DEMO-EST-000067	Fernanda Sebastián	Vargas Rivera	2000-03-14	\N	estudiante00067@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
73	DEMO-E-00068	DEMO-EST-000068	Isabel Sebastián	Vargas Mamani	1996-09-27	\N	estudiante00068@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
74	DEMO-E-00069	DEMO-EST-000069	Victoria Sebastián	Vargas Villarroel	2004-12-06	\N	estudiante00069@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
75	DEMO-E-00070	DEMO-EST-000070	Elena Sebastián	Vargas Castro	2007-01-23	\N	estudiante00070@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
76	DEMO-E-00071	DEMO-EST-000071	Rodrigo Sebastián	Vargas Morales	1996-04-15	\N	estudiante00071@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
77	DEMO-E-00072	DEMO-EST-000072	Mauricio Sebastián	Vargas Ríos	2000-09-19	\N	estudiante00072@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
78	DEMO-E-00073	DEMO-EST-000073	Eduardo Sebastián	Vargas Escobar	2004-04-12	\N	estudiante00073@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
79	DEMO-E-00074	DEMO-EST-000074	Pablo Sebastián	Vargas Soria	1999-04-05	\N	estudiante00074@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
80	DEMO-E-00075	DEMO-EST-000075	Ricardo Sebastián	Vargas Vargas	2003-12-17	\N	estudiante00075@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
81	DEMO-E-00076	DEMO-EST-000076	Patricia Sebastián	Vargas Romero	1996-03-10	\N	estudiante00076@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
82	DEMO-E-00077	DEMO-EST-000077	Claudia Sebastián	Vargas Navarro	2002-03-05	\N	estudiante00077@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
83	DEMO-E-00078	DEMO-EST-000078	Lorena Sebastián	Vargas López	2001-03-20	\N	estudiante00078@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
84	DEMO-E-00079	DEMO-EST-000079	Verónica Sebastián	Vargas Quispe	1997-09-29	\N	estudiante00079@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
85	DEMO-E-00080	DEMO-EST-000080	Rosa Sebastián	Vargas Arias	2000-03-08	\N	estudiante00080@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
86	DEMO-E-00081	DEMO-EST-000081	Gabriel Alejandro	Rojas Flores	1995-09-30	\N	estudiante00081@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
87	DEMO-E-00082	DEMO-EST-000082	Mateo Alejandro	Rojas Medina	1996-01-19	\N	estudiante00082@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
88	DEMO-E-00083	DEMO-EST-000083	Daniel Alejandro	Rojas Cabrera	1995-05-22	\N	estudiante00083@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
89	DEMO-E-00084	DEMO-EST-000084	Santiago Alejandro	Rojas Castillo	2005-01-07	\N	estudiante00084@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
90	DEMO-E-00085	DEMO-EST-000085	Samuel Alejandro	Rojas Condori	2004-06-29	\N	estudiante00085@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
91	DEMO-E-00086	DEMO-EST-000086	Diego Alejandro	Rojas Delgado	1999-08-18	\N	estudiante00086@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
92	DEMO-E-00087	DEMO-EST-000087	Nicolás Alejandro	Rojas Aguilar	1998-05-08	\N	estudiante00087@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
93	DEMO-E-00088	DEMO-EST-000088	Adrián Alejandro	Rojas Herrera	2004-12-06	\N	estudiante00088@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
94	DEMO-E-00089	DEMO-EST-000089	Sebastián Alejandro	Rojas Suárez	1997-01-27	\N	estudiante00089@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
95	DEMO-E-00090	DEMO-EST-000090	Alejandro Alejandro	Rojas Valdez	2004-07-05	\N	estudiante00090@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
96	DEMO-E-00091	DEMO-EST-000091	Luis Alejandro	Rojas Choque	2000-09-17	\N	estudiante00091@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
97	DEMO-E-00092	DEMO-EST-000092	Miguel Alejandro	Rojas Molina	2002-08-03	\N	estudiante00092@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
98	DEMO-E-00093	DEMO-EST-000093	Carlos Alejandro	Rojas Salazar	2001-12-09	\N	estudiante00093@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
99	DEMO-E-00094	DEMO-EST-000094	Javier Alejandro	Rojas Paredes	2000-11-23	\N	estudiante00094@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
100	DEMO-E-00095	DEMO-EST-000095	Andrés Alejandro	Rojas Cruz	1996-10-27	\N	estudiante00095@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
101	DEMO-E-00096	DEMO-EST-000096	Valeria Alejandro	Rojas Fernández	2002-04-20	\N	estudiante00096@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
102	DEMO-E-00097	DEMO-EST-000097	Camila Alejandro	Rojas Pinto	1997-03-03	\N	estudiante00097@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
103	DEMO-E-00098	DEMO-EST-000098	Lucía Alejandro	Rojas Rojas	2000-01-01	\N	estudiante00098@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
104	DEMO-E-00099	DEMO-EST-000099	Mariana Alejandro	Rojas Ortega	2000-01-09	\N	estudiante00099@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
105	DEMO-E-00100	DEMO-EST-000100	Daniela Alejandro	Rojas Torres	2005-01-15	\N	estudiante00100@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
106	DEMO-E-00101	DEMO-EST-000101	Sofía Alejandro	Rojas Gutiérrez	2005-02-08	\N	estudiante00101@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
107	DEMO-E-00102	DEMO-EST-000102	Paola Alejandro	Rojas Apaza	2000-09-14	\N	estudiante00102@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
108	DEMO-E-00103	DEMO-EST-000103	Andrea Alejandro	Rojas Montes	1997-08-25	\N	estudiante00103@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
109	DEMO-E-00104	DEMO-EST-000104	Gabriela Alejandro	Rojas Mendoza	2001-08-27	\N	estudiante00104@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
110	DEMO-E-00105	DEMO-EST-000105	Natalia Alejandro	Rojas Soto	2001-01-11	\N	estudiante00105@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
111	DEMO-E-00106	DEMO-EST-000106	Carolina Alejandro	Rojas Vega	2001-01-30	\N	estudiante00106@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
112	DEMO-E-00107	DEMO-EST-000107	Fernanda Alejandro	Rojas Rivera	2002-11-08	\N	estudiante00107@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
113	DEMO-E-00108	DEMO-EST-000108	Isabel Alejandro	Rojas Mamani	1997-05-08	\N	estudiante00108@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
114	DEMO-E-00109	DEMO-EST-000109	Victoria Alejandro	Rojas Villarroel	2005-02-14	\N	estudiante00109@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
115	DEMO-E-00110	DEMO-EST-000110	Elena Alejandro	Rojas Castro	2000-02-04	\N	estudiante00110@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
116	DEMO-E-00111	DEMO-EST-000111	Rodrigo Alejandro	Rojas Morales	2000-04-16	\N	estudiante00111@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
117	DEMO-E-00112	DEMO-EST-000112	Mauricio Alejandro	Rojas Ríos	2000-04-03	\N	estudiante00112@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
118	DEMO-E-00113	DEMO-EST-000113	Eduardo Alejandro	Rojas Escobar	1998-06-10	\N	estudiante00113@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
119	DEMO-E-00114	DEMO-EST-000114	Pablo Alejandro	Rojas Soria	2007-07-18	\N	estudiante00114@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
120	DEMO-E-00115	DEMO-EST-000115	Ricardo Alejandro	Rojas Vargas	1999-02-24	\N	estudiante00115@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
121	DEMO-E-00116	DEMO-EST-000116	Patricia Alejandro	Rojas Romero	2000-01-25	\N	estudiante00116@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
122	DEMO-E-00117	DEMO-EST-000117	Claudia Alejandro	Rojas Navarro	1998-12-01	\N	estudiante00117@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
123	DEMO-E-00118	DEMO-EST-000118	Lorena Alejandro	Rojas López	2002-04-09	\N	estudiante00118@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
124	DEMO-E-00119	DEMO-EST-000119	Verónica Alejandro	Rojas Quispe	2000-09-03	\N	estudiante00119@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
125	DEMO-E-00120	DEMO-EST-000120	Rosa Alejandro	Rojas Arias	1997-10-11	\N	estudiante00120@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
126	DEMO-E-00121	DEMO-EST-000121	Gabriel Luis	Flores Flores	2004-10-06	\N	estudiante00121@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
127	DEMO-E-00122	DEMO-EST-000122	Mateo Luis	Flores Medina	1996-11-04	\N	estudiante00122@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
128	DEMO-E-00123	DEMO-EST-000123	Daniel Luis	Flores Cabrera	1999-10-04	\N	estudiante00123@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
129	DEMO-E-00124	DEMO-EST-000124	Santiago Luis	Flores Castillo	2004-02-15	\N	estudiante00124@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
130	DEMO-E-00125	DEMO-EST-000125	Samuel Luis	Flores Condori	2007-09-28	\N	estudiante00125@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
131	DEMO-E-00126	DEMO-EST-000126	Diego Luis	Flores Delgado	1995-12-02	\N	estudiante00126@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
132	DEMO-E-00127	DEMO-EST-000127	Nicolás Luis	Flores Aguilar	2006-01-25	\N	estudiante00127@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
133	DEMO-E-00128	DEMO-EST-000128	Adrián Luis	Flores Herrera	2007-08-05	\N	estudiante00128@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
134	DEMO-E-00129	DEMO-EST-000129	Sebastián Luis	Flores Suárez	2002-11-01	\N	estudiante00129@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
135	DEMO-E-00130	DEMO-EST-000130	Alejandro Luis	Flores Valdez	2003-03-31	\N	estudiante00130@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
136	DEMO-E-00131	DEMO-EST-000131	Luis Luis	Flores Choque	1996-11-27	\N	estudiante00131@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
137	DEMO-E-00132	DEMO-EST-000132	Miguel Luis	Flores Molina	1996-10-08	\N	estudiante00132@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
138	DEMO-E-00133	DEMO-EST-000133	Carlos Luis	Flores Salazar	2007-08-17	\N	estudiante00133@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
139	DEMO-E-00134	DEMO-EST-000134	Javier Luis	Flores Paredes	1995-04-12	\N	estudiante00134@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
140	DEMO-E-00135	DEMO-EST-000135	Andrés Luis	Flores Cruz	1999-09-12	\N	estudiante00135@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
141	DEMO-E-00136	DEMO-EST-000136	Valeria Luis	Flores Fernández	2005-09-22	\N	estudiante00136@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
142	DEMO-E-00137	DEMO-EST-000137	Camila Luis	Flores Pinto	1998-09-02	\N	estudiante00137@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
143	DEMO-E-00138	DEMO-EST-000138	Lucía Luis	Flores Rojas	1999-09-27	\N	estudiante00138@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
144	DEMO-E-00139	DEMO-EST-000139	Mariana Luis	Flores Ortega	2004-01-19	\N	estudiante00139@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
145	DEMO-E-00140	DEMO-EST-000140	Daniela Luis	Flores Torres	1998-06-21	\N	estudiante00140@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
146	DEMO-E-00141	DEMO-EST-000141	Sofía Luis	Flores Gutiérrez	1995-11-30	\N	estudiante00141@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
147	DEMO-E-00142	DEMO-EST-000142	Paola Luis	Flores Apaza	2001-09-09	\N	estudiante00142@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
148	DEMO-E-00143	DEMO-EST-000143	Andrea Luis	Flores Montes	1997-10-11	\N	estudiante00143@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
149	DEMO-E-00144	DEMO-EST-000144	Gabriela Luis	Flores Mendoza	1997-03-28	\N	estudiante00144@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
150	DEMO-E-00145	DEMO-EST-000145	Natalia Luis	Flores Soto	1997-02-21	\N	estudiante00145@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
151	DEMO-E-00146	DEMO-EST-000146	Carolina Luis	Flores Vega	2000-04-28	\N	estudiante00146@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
152	DEMO-E-00147	DEMO-EST-000147	Fernanda Luis	Flores Rivera	1997-03-31	\N	estudiante00147@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
153	DEMO-E-00148	DEMO-EST-000148	Isabel Luis	Flores Mamani	2002-08-01	\N	estudiante00148@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
154	DEMO-E-00149	DEMO-EST-000149	Victoria Luis	Flores Villarroel	1997-10-10	\N	estudiante00149@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
155	DEMO-E-00150	DEMO-EST-000150	Elena Luis	Flores Castro	1998-04-24	\N	estudiante00150@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
156	DEMO-E-00151	DEMO-EST-000151	Rodrigo Luis	Flores Morales	2000-10-01	\N	estudiante00151@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
157	DEMO-E-00152	DEMO-EST-000152	Mauricio Luis	Flores Ríos	1998-06-05	\N	estudiante00152@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
158	DEMO-E-00153	DEMO-EST-000153	Eduardo Luis	Flores Escobar	2003-05-27	\N	estudiante00153@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
159	DEMO-E-00154	DEMO-EST-000154	Pablo Luis	Flores Soria	1995-11-28	\N	estudiante00154@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
160	DEMO-E-00155	DEMO-EST-000155	Ricardo Luis	Flores Vargas	2000-02-03	\N	estudiante00155@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
161	DEMO-E-00156	DEMO-EST-000156	Patricia Luis	Flores Romero	2006-01-31	\N	estudiante00156@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
162	DEMO-E-00157	DEMO-EST-000157	Claudia Luis	Flores Navarro	2005-12-20	\N	estudiante00157@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
163	DEMO-E-00158	DEMO-EST-000158	Lorena Luis	Flores López	2004-08-06	\N	estudiante00158@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
164	DEMO-E-00159	DEMO-EST-000159	Verónica Luis	Flores Quispe	1995-07-15	\N	estudiante00159@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
165	DEMO-E-00160	DEMO-EST-000160	Rosa Luis	Flores Arias	2001-07-14	\N	estudiante00160@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
166	DEMO-E-00161	DEMO-EST-000161	Gabriel Miguel	Mendoza Flores	2005-02-05	\N	estudiante00161@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
167	DEMO-E-00162	DEMO-EST-000162	Mateo Miguel	Mendoza Medina	2005-02-17	\N	estudiante00162@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
168	DEMO-E-00163	DEMO-EST-000163	Daniel Miguel	Mendoza Cabrera	2000-01-18	\N	estudiante00163@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
169	DEMO-E-00164	DEMO-EST-000164	Santiago Miguel	Mendoza Castillo	2004-05-20	\N	estudiante00164@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
170	DEMO-E-00165	DEMO-EST-000165	Samuel Miguel	Mendoza Condori	2000-05-23	\N	estudiante00165@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
171	DEMO-E-00166	DEMO-EST-000166	Diego Miguel	Mendoza Delgado	2006-06-30	\N	estudiante00166@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
172	DEMO-E-00167	DEMO-EST-000167	Nicolás Miguel	Mendoza Aguilar	2004-01-05	\N	estudiante00167@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
173	DEMO-E-00168	DEMO-EST-000168	Adrián Miguel	Mendoza Herrera	1998-03-16	\N	estudiante00168@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
174	DEMO-E-00169	DEMO-EST-000169	Sebastián Miguel	Mendoza Suárez	1999-04-15	\N	estudiante00169@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
175	DEMO-E-00170	DEMO-EST-000170	Alejandro Miguel	Mendoza Valdez	2005-08-11	\N	estudiante00170@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
176	DEMO-E-00171	DEMO-EST-000171	Luis Miguel	Mendoza Choque	2005-01-10	\N	estudiante00171@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
177	DEMO-E-00172	DEMO-EST-000172	Miguel Miguel	Mendoza Molina	1999-04-14	\N	estudiante00172@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
178	DEMO-E-00173	DEMO-EST-000173	Carlos Miguel	Mendoza Salazar	2000-07-18	\N	estudiante00173@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
179	DEMO-E-00174	DEMO-EST-000174	Javier Miguel	Mendoza Paredes	2003-07-02	\N	estudiante00174@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
180	DEMO-E-00175	DEMO-EST-000175	Andrés Miguel	Mendoza Cruz	1996-09-25	\N	estudiante00175@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
181	DEMO-E-00176	DEMO-EST-000176	Valeria Miguel	Mendoza Fernández	2002-11-18	\N	estudiante00176@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
182	DEMO-E-00177	DEMO-EST-000177	Camila Miguel	Mendoza Pinto	2007-08-27	\N	estudiante00177@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
183	DEMO-E-00178	DEMO-EST-000178	Lucía Miguel	Mendoza Rojas	2007-09-23	\N	estudiante00178@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
184	DEMO-E-00179	DEMO-EST-000179	Mariana Miguel	Mendoza Ortega	1995-03-18	\N	estudiante00179@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
185	DEMO-E-00180	DEMO-EST-000180	Daniela Miguel	Mendoza Torres	1999-04-18	\N	estudiante00180@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
186	DEMO-E-00181	DEMO-EST-000181	Sofía Miguel	Mendoza Gutiérrez	2003-08-05	\N	estudiante00181@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
187	DEMO-E-00182	DEMO-EST-000182	Paola Miguel	Mendoza Apaza	1999-03-15	\N	estudiante00182@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
188	DEMO-E-00183	DEMO-EST-000183	Andrea Miguel	Mendoza Montes	2000-07-20	\N	estudiante00183@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
189	DEMO-E-00184	DEMO-EST-000184	Gabriela Miguel	Mendoza Mendoza	1999-06-21	\N	estudiante00184@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
190	DEMO-E-00185	DEMO-EST-000185	Natalia Miguel	Mendoza Soto	2005-03-27	\N	estudiante00185@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
191	DEMO-E-00186	DEMO-EST-000186	Carolina Miguel	Mendoza Vega	2006-10-11	\N	estudiante00186@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
192	DEMO-E-00187	DEMO-EST-000187	Fernanda Miguel	Mendoza Rivera	2003-02-14	\N	estudiante00187@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
193	DEMO-E-00188	DEMO-EST-000188	Isabel Miguel	Mendoza Mamani	2006-04-17	\N	estudiante00188@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
194	DEMO-E-00189	DEMO-EST-000189	Victoria Miguel	Mendoza Villarroel	2007-08-09	\N	estudiante00189@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
195	DEMO-E-00190	DEMO-EST-000190	Elena Miguel	Mendoza Castro	2007-10-19	\N	estudiante00190@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
196	DEMO-E-00191	DEMO-EST-000191	Rodrigo Miguel	Mendoza Morales	2000-04-15	\N	estudiante00191@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
197	DEMO-E-00192	DEMO-EST-000192	Mauricio Miguel	Mendoza Ríos	2004-01-12	\N	estudiante00192@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
198	DEMO-E-00193	DEMO-EST-000193	Eduardo Miguel	Mendoza Escobar	1995-10-19	\N	estudiante00193@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
199	DEMO-E-00194	DEMO-EST-000194	Pablo Miguel	Mendoza Soria	2000-05-03	\N	estudiante00194@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
200	DEMO-E-00195	DEMO-EST-000195	Ricardo Miguel	Mendoza Vargas	2002-10-03	\N	estudiante00195@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
201	DEMO-E-00196	DEMO-EST-000196	Patricia Miguel	Mendoza Romero	2001-01-06	\N	estudiante00196@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
202	DEMO-E-00197	DEMO-EST-000197	Claudia Miguel	Mendoza Navarro	1999-08-22	\N	estudiante00197@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
203	DEMO-E-00198	DEMO-EST-000198	Lorena Miguel	Mendoza López	1995-04-09	\N	estudiante00198@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
204	DEMO-E-00199	DEMO-EST-000199	Verónica Miguel	Mendoza Quispe	2004-05-16	\N	estudiante00199@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
205	DEMO-E-00200	DEMO-EST-000200	Rosa Miguel	Mendoza Arias	1997-09-20	\N	estudiante00200@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
206	DEMO-E-00201	DEMO-EST-000201	Gabriel Carlos	Aguilar Flores	2002-06-07	\N	estudiante00201@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
207	DEMO-E-00202	DEMO-EST-000202	Mateo Carlos	Aguilar Medina	2003-04-23	\N	estudiante00202@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
208	DEMO-E-00203	DEMO-EST-000203	Daniel Carlos	Aguilar Cabrera	2006-04-25	\N	estudiante00203@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
209	DEMO-E-00204	DEMO-EST-000204	Santiago Carlos	Aguilar Castillo	2007-11-30	\N	estudiante00204@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
210	DEMO-E-00205	DEMO-EST-000205	Samuel Carlos	Aguilar Condori	2000-08-31	\N	estudiante00205@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
211	DEMO-E-00206	DEMO-EST-000206	Diego Carlos	Aguilar Delgado	2002-07-07	\N	estudiante00206@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
212	DEMO-E-00207	DEMO-EST-000207	Nicolás Carlos	Aguilar Aguilar	1997-10-26	\N	estudiante00207@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
213	DEMO-E-00208	DEMO-EST-000208	Adrián Carlos	Aguilar Herrera	1999-09-17	\N	estudiante00208@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
214	DEMO-E-00209	DEMO-EST-000209	Sebastián Carlos	Aguilar Suárez	1999-08-04	\N	estudiante00209@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
215	DEMO-E-00210	DEMO-EST-000210	Alejandro Carlos	Aguilar Valdez	1996-02-07	\N	estudiante00210@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
216	DEMO-E-00211	DEMO-EST-000211	Luis Carlos	Aguilar Choque	2003-12-31	\N	estudiante00211@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
217	DEMO-E-00212	DEMO-EST-000212	Miguel Carlos	Aguilar Molina	1997-08-07	\N	estudiante00212@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
218	DEMO-E-00213	DEMO-EST-000213	Carlos Carlos	Aguilar Salazar	2003-08-17	\N	estudiante00213@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
219	DEMO-E-00214	DEMO-EST-000214	Javier Carlos	Aguilar Paredes	1997-11-11	\N	estudiante00214@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
220	DEMO-E-00215	DEMO-EST-000215	Andrés Carlos	Aguilar Cruz	2002-06-09	\N	estudiante00215@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
221	DEMO-E-00216	DEMO-EST-000216	Valeria Carlos	Aguilar Fernández	2000-10-22	\N	estudiante00216@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
222	DEMO-E-00217	DEMO-EST-000217	Camila Carlos	Aguilar Pinto	2002-02-13	\N	estudiante00217@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
223	DEMO-E-00218	DEMO-EST-000218	Lucía Carlos	Aguilar Rojas	1998-10-19	\N	estudiante00218@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
224	DEMO-E-00219	DEMO-EST-000219	Mariana Carlos	Aguilar Ortega	1998-08-06	\N	estudiante00219@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
225	DEMO-E-00220	DEMO-EST-000220	Daniela Carlos	Aguilar Torres	2005-01-26	\N	estudiante00220@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
226	DEMO-E-00221	DEMO-EST-000221	Sofía Carlos	Aguilar Gutiérrez	2003-08-19	\N	estudiante00221@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
227	DEMO-E-00222	DEMO-EST-000222	Paola Carlos	Aguilar Apaza	2004-01-03	\N	estudiante00222@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
228	DEMO-E-00223	DEMO-EST-000223	Andrea Carlos	Aguilar Montes	1998-01-22	\N	estudiante00223@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
229	DEMO-E-00224	DEMO-EST-000224	Gabriela Carlos	Aguilar Mendoza	2003-05-02	\N	estudiante00224@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
230	DEMO-E-00225	DEMO-EST-000225	Natalia Carlos	Aguilar Soto	2006-01-05	\N	estudiante00225@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
231	DEMO-E-00226	DEMO-EST-000226	Carolina Carlos	Aguilar Vega	1996-06-09	\N	estudiante00226@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
232	DEMO-E-00227	DEMO-EST-000227	Fernanda Carlos	Aguilar Rivera	2006-06-24	\N	estudiante00227@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
233	DEMO-E-00228	DEMO-EST-000228	Isabel Carlos	Aguilar Mamani	1995-04-14	\N	estudiante00228@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
234	DEMO-E-00229	DEMO-EST-000229	Victoria Carlos	Aguilar Villarroel	2006-06-28	\N	estudiante00229@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
235	DEMO-E-00230	DEMO-EST-000230	Elena Carlos	Aguilar Castro	2005-06-08	\N	estudiante00230@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
236	DEMO-E-00231	DEMO-EST-000231	Rodrigo Carlos	Aguilar Morales	1996-01-31	\N	estudiante00231@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
237	DEMO-E-00232	DEMO-EST-000232	Mauricio Carlos	Aguilar Ríos	1999-11-29	\N	estudiante00232@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
238	DEMO-E-00233	DEMO-EST-000233	Eduardo Carlos	Aguilar Escobar	2004-07-23	\N	estudiante00233@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
239	DEMO-E-00234	DEMO-EST-000234	Pablo Carlos	Aguilar Soria	2006-12-04	\N	estudiante00234@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
240	DEMO-E-00235	DEMO-EST-000235	Ricardo Carlos	Aguilar Vargas	1996-04-15	\N	estudiante00235@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
241	DEMO-E-00236	DEMO-EST-000236	Patricia Carlos	Aguilar Romero	1998-12-28	\N	estudiante00236@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
242	DEMO-E-00237	DEMO-EST-000237	Claudia Carlos	Aguilar Navarro	2002-12-17	\N	estudiante00237@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
243	DEMO-E-00238	DEMO-EST-000238	Lorena Carlos	Aguilar López	1995-12-03	\N	estudiante00238@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
244	DEMO-E-00239	DEMO-EST-000239	Verónica Carlos	Aguilar Quispe	1998-05-23	\N	estudiante00239@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
245	DEMO-E-00240	DEMO-EST-000240	Rosa Carlos	Aguilar Arias	1997-02-03	\N	estudiante00240@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
246	DEMO-E-00241	DEMO-EST-000241	Gabriel Javier	Castro Flores	2006-05-28	\N	estudiante00241@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
247	DEMO-E-00242	DEMO-EST-000242	Mateo Javier	Castro Medina	2002-09-30	\N	estudiante00242@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
248	DEMO-E-00243	DEMO-EST-000243	Daniel Javier	Castro Cabrera	2003-06-04	\N	estudiante00243@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
249	DEMO-E-00244	DEMO-EST-000244	Santiago Javier	Castro Castillo	1995-08-07	\N	estudiante00244@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
250	DEMO-E-00245	DEMO-EST-000245	Samuel Javier	Castro Condori	2007-07-12	\N	estudiante00245@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
251	DEMO-E-00246	DEMO-EST-000246	Diego Javier	Castro Delgado	2007-05-15	\N	estudiante00246@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
252	DEMO-E-00247	DEMO-EST-000247	Nicolás Javier	Castro Aguilar	1998-02-28	\N	estudiante00247@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
253	DEMO-E-00248	DEMO-EST-000248	Adrián Javier	Castro Herrera	1999-11-24	\N	estudiante00248@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
254	DEMO-E-00249	DEMO-EST-000249	Sebastián Javier	Castro Suárez	2003-08-07	\N	estudiante00249@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
255	DEMO-E-00250	DEMO-EST-000250	Alejandro Javier	Castro Valdez	2006-05-31	\N	estudiante00250@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
256	DEMO-E-00251	DEMO-EST-000251	Luis Javier	Castro Choque	2001-05-02	\N	estudiante00251@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
257	DEMO-E-00252	DEMO-EST-000252	Miguel Javier	Castro Molina	1998-10-15	\N	estudiante00252@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
258	DEMO-E-00253	DEMO-EST-000253	Carlos Javier	Castro Salazar	2004-03-31	\N	estudiante00253@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
259	DEMO-E-00254	DEMO-EST-000254	Javier Javier	Castro Paredes	2005-04-01	\N	estudiante00254@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
260	DEMO-E-00255	DEMO-EST-000255	Andrés Javier	Castro Cruz	2004-11-21	\N	estudiante00255@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
261	DEMO-E-00256	DEMO-EST-000256	Valeria Javier	Castro Fernández	2002-03-28	\N	estudiante00256@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
262	DEMO-E-00257	DEMO-EST-000257	Camila Javier	Castro Pinto	1999-06-15	\N	estudiante00257@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
263	DEMO-E-00258	DEMO-EST-000258	Lucía Javier	Castro Rojas	1995-02-16	\N	estudiante00258@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
264	DEMO-E-00259	DEMO-EST-000259	Mariana Javier	Castro Ortega	1995-04-17	\N	estudiante00259@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
265	DEMO-E-00260	DEMO-EST-000260	Daniela Javier	Castro Torres	2006-08-22	\N	estudiante00260@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
266	DEMO-E-00261	DEMO-EST-000261	Sofía Javier	Castro Gutiérrez	1997-09-22	\N	estudiante00261@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
267	DEMO-E-00262	DEMO-EST-000262	Paola Javier	Castro Apaza	1998-02-08	\N	estudiante00262@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
268	DEMO-E-00263	DEMO-EST-000263	Andrea Javier	Castro Montes	2005-11-29	\N	estudiante00263@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
269	DEMO-E-00264	DEMO-EST-000264	Gabriela Javier	Castro Mendoza	2002-08-04	\N	estudiante00264@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
270	DEMO-E-00265	DEMO-EST-000265	Natalia Javier	Castro Soto	2006-11-03	\N	estudiante00265@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
271	DEMO-E-00266	DEMO-EST-000266	Carolina Javier	Castro Vega	2007-08-28	\N	estudiante00266@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
272	DEMO-E-00267	DEMO-EST-000267	Fernanda Javier	Castro Rivera	1995-10-31	\N	estudiante00267@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
273	DEMO-E-00268	DEMO-EST-000268	Isabel Javier	Castro Mamani	1995-09-09	\N	estudiante00268@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
274	DEMO-E-00269	DEMO-EST-000269	Victoria Javier	Castro Villarroel	1999-06-19	\N	estudiante00269@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
275	DEMO-E-00270	DEMO-EST-000270	Elena Javier	Castro Castro	2002-07-01	\N	estudiante00270@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
276	DEMO-E-00271	DEMO-EST-000271	Rodrigo Javier	Castro Morales	2001-03-17	\N	estudiante00271@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
277	DEMO-E-00272	DEMO-EST-000272	Mauricio Javier	Castro Ríos	1998-04-23	\N	estudiante00272@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
278	DEMO-E-00273	DEMO-EST-000273	Eduardo Javier	Castro Escobar	2006-12-26	\N	estudiante00273@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
279	DEMO-E-00274	DEMO-EST-000274	Pablo Javier	Castro Soria	1997-11-23	\N	estudiante00274@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
280	DEMO-E-00275	DEMO-EST-000275	Ricardo Javier	Castro Vargas	2003-12-27	\N	estudiante00275@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
281	DEMO-E-00276	DEMO-EST-000276	Patricia Javier	Castro Romero	1998-03-09	\N	estudiante00276@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
282	DEMO-E-00277	DEMO-EST-000277	Claudia Javier	Castro Navarro	2000-10-19	\N	estudiante00277@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
283	DEMO-E-00278	DEMO-EST-000278	Lorena Javier	Castro López	1999-08-06	\N	estudiante00278@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
284	DEMO-E-00279	DEMO-EST-000279	Verónica Javier	Castro Quispe	2006-07-13	\N	estudiante00279@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
285	DEMO-E-00280	DEMO-EST-000280	Rosa Javier	Castro Arias	2006-12-09	\N	estudiante00280@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
286	DEMO-E-00281	DEMO-EST-000281	Gabriel Andrés	Salazar Flores	2004-03-21	\N	estudiante00281@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
287	DEMO-E-00282	DEMO-EST-000282	Mateo Andrés	Salazar Medina	2000-05-30	\N	estudiante00282@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
288	DEMO-E-00283	DEMO-EST-000283	Daniel Andrés	Salazar Cabrera	2003-09-30	\N	estudiante00283@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
289	DEMO-E-00284	DEMO-EST-000284	Santiago Andrés	Salazar Castillo	1995-08-28	\N	estudiante00284@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
290	DEMO-E-00285	DEMO-EST-000285	Samuel Andrés	Salazar Condori	2004-01-10	\N	estudiante00285@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
291	DEMO-E-00286	DEMO-EST-000286	Diego Andrés	Salazar Delgado	2000-09-30	\N	estudiante00286@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
292	DEMO-E-00287	DEMO-EST-000287	Nicolás Andrés	Salazar Aguilar	2002-09-03	\N	estudiante00287@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
293	DEMO-E-00288	DEMO-EST-000288	Adrián Andrés	Salazar Herrera	1996-11-09	\N	estudiante00288@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
294	DEMO-E-00289	DEMO-EST-000289	Sebastián Andrés	Salazar Suárez	2002-02-17	\N	estudiante00289@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
295	DEMO-E-00290	DEMO-EST-000290	Alejandro Andrés	Salazar Valdez	2006-10-11	\N	estudiante00290@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
296	DEMO-E-00291	DEMO-EST-000291	Luis Andrés	Salazar Choque	2003-12-01	\N	estudiante00291@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
297	DEMO-E-00292	DEMO-EST-000292	Miguel Andrés	Salazar Molina	2002-06-23	\N	estudiante00292@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
298	DEMO-E-00293	DEMO-EST-000293	Carlos Andrés	Salazar Salazar	1995-10-20	\N	estudiante00293@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
299	DEMO-E-00294	DEMO-EST-000294	Javier Andrés	Salazar Paredes	2004-12-20	\N	estudiante00294@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
300	DEMO-E-00295	DEMO-EST-000295	Andrés Andrés	Salazar Cruz	1998-12-04	\N	estudiante00295@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
301	DEMO-E-00296	DEMO-EST-000296	Valeria Andrés	Salazar Fernández	2004-06-11	\N	estudiante00296@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
302	DEMO-E-00297	DEMO-EST-000297	Camila Andrés	Salazar Pinto	1997-07-13	\N	estudiante00297@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
303	DEMO-E-00298	DEMO-EST-000298	Lucía Andrés	Salazar Rojas	1997-04-20	\N	estudiante00298@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
304	DEMO-E-00299	DEMO-EST-000299	Mariana Andrés	Salazar Ortega	2005-07-13	\N	estudiante00299@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
305	DEMO-E-00300	DEMO-EST-000300	Daniela Andrés	Salazar Torres	2004-06-28	\N	estudiante00300@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
306	DEMO-E-00301	DEMO-EST-000301	Sofía Andrés	Salazar Gutiérrez	1998-01-31	\N	estudiante00301@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
307	DEMO-E-00302	DEMO-EST-000302	Paola Andrés	Salazar Apaza	1998-03-21	\N	estudiante00302@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
308	DEMO-E-00303	DEMO-EST-000303	Andrea Andrés	Salazar Montes	1999-01-19	\N	estudiante00303@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
309	DEMO-E-00304	DEMO-EST-000304	Gabriela Andrés	Salazar Mendoza	2006-02-02	\N	estudiante00304@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
310	DEMO-E-00305	DEMO-EST-000305	Natalia Andrés	Salazar Soto	2007-06-13	\N	estudiante00305@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
311	DEMO-E-00306	DEMO-EST-000306	Carolina Andrés	Salazar Vega	2000-07-23	\N	estudiante00306@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
312	DEMO-E-00307	DEMO-EST-000307	Fernanda Andrés	Salazar Rivera	1996-05-11	\N	estudiante00307@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
313	DEMO-E-00308	DEMO-EST-000308	Isabel Andrés	Salazar Mamani	2001-07-19	\N	estudiante00308@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
314	DEMO-E-00309	DEMO-EST-000309	Victoria Andrés	Salazar Villarroel	2004-06-13	\N	estudiante00309@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
315	DEMO-E-00310	DEMO-EST-000310	Elena Andrés	Salazar Castro	2005-04-14	\N	estudiante00310@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
316	DEMO-E-00311	DEMO-EST-000311	Rodrigo Andrés	Salazar Morales	2006-06-19	\N	estudiante00311@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
317	DEMO-E-00312	DEMO-EST-000312	Mauricio Andrés	Salazar Ríos	1996-12-21	\N	estudiante00312@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
318	DEMO-E-00313	DEMO-EST-000313	Eduardo Andrés	Salazar Escobar	1995-04-28	\N	estudiante00313@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
319	DEMO-E-00314	DEMO-EST-000314	Pablo Andrés	Salazar Soria	1998-01-15	\N	estudiante00314@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
320	DEMO-E-00315	DEMO-EST-000315	Ricardo Andrés	Salazar Vargas	1995-05-11	\N	estudiante00315@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
321	DEMO-E-00316	DEMO-EST-000316	Patricia Andrés	Salazar Romero	1997-03-09	\N	estudiante00316@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
322	DEMO-E-00317	DEMO-EST-000317	Claudia Andrés	Salazar Navarro	1998-04-23	\N	estudiante00317@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
323	DEMO-E-00318	DEMO-EST-000318	Lorena Andrés	Salazar López	1999-11-02	\N	estudiante00318@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
324	DEMO-E-00319	DEMO-EST-000319	Verónica Andrés	Salazar Quispe	1997-01-05	\N	estudiante00319@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
325	DEMO-E-00320	DEMO-EST-000320	Rosa Andrés	Salazar Arias	1998-02-12	\N	estudiante00320@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
326	DEMO-E-00321	DEMO-EST-000321	Gabriel Valeria	Romero Flores	2007-04-17	\N	estudiante00321@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
327	DEMO-E-00322	DEMO-EST-000322	Mateo Valeria	Romero Medina	2005-09-21	\N	estudiante00322@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
328	DEMO-E-00323	DEMO-EST-000323	Daniel Valeria	Romero Cabrera	2005-07-19	\N	estudiante00323@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
329	DEMO-E-00324	DEMO-EST-000324	Santiago Valeria	Romero Castillo	2001-05-31	\N	estudiante00324@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
330	DEMO-E-00325	DEMO-EST-000325	Samuel Valeria	Romero Condori	2005-08-14	\N	estudiante00325@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
331	DEMO-E-00326	DEMO-EST-000326	Diego Valeria	Romero Delgado	2006-08-23	\N	estudiante00326@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
332	DEMO-E-00327	DEMO-EST-000327	Nicolás Valeria	Romero Aguilar	2004-07-31	\N	estudiante00327@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
333	DEMO-E-00328	DEMO-EST-000328	Adrián Valeria	Romero Herrera	2001-12-07	\N	estudiante00328@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
334	DEMO-E-00329	DEMO-EST-000329	Sebastián Valeria	Romero Suárez	2000-03-28	\N	estudiante00329@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
335	DEMO-E-00330	DEMO-EST-000330	Alejandro Valeria	Romero Valdez	1999-05-17	\N	estudiante00330@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
336	DEMO-E-00331	DEMO-EST-000331	Luis Valeria	Romero Choque	2003-07-07	\N	estudiante00331@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
337	DEMO-E-00332	DEMO-EST-000332	Miguel Valeria	Romero Molina	2001-10-17	\N	estudiante00332@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
338	DEMO-E-00333	DEMO-EST-000333	Carlos Valeria	Romero Salazar	2002-06-18	\N	estudiante00333@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
339	DEMO-E-00334	DEMO-EST-000334	Javier Valeria	Romero Paredes	2007-06-04	\N	estudiante00334@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
340	DEMO-E-00335	DEMO-EST-000335	Andrés Valeria	Romero Cruz	2002-10-18	\N	estudiante00335@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
341	DEMO-E-00336	DEMO-EST-000336	Valeria Valeria	Romero Fernández	2000-04-10	\N	estudiante00336@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
342	DEMO-E-00337	DEMO-EST-000337	Camila Valeria	Romero Pinto	2000-09-13	\N	estudiante00337@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
343	DEMO-E-00338	DEMO-EST-000338	Lucía Valeria	Romero Rojas	2006-07-07	\N	estudiante00338@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
344	DEMO-E-00339	DEMO-EST-000339	Mariana Valeria	Romero Ortega	1997-11-29	\N	estudiante00339@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
345	DEMO-E-00340	DEMO-EST-000340	Daniela Valeria	Romero Torres	1998-01-20	\N	estudiante00340@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
346	DEMO-E-00341	DEMO-EST-000341	Sofía Valeria	Romero Gutiérrez	1999-02-27	\N	estudiante00341@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
347	DEMO-E-00342	DEMO-EST-000342	Paola Valeria	Romero Apaza	2004-09-04	\N	estudiante00342@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
348	DEMO-E-00343	DEMO-EST-000343	Andrea Valeria	Romero Montes	2000-08-17	\N	estudiante00343@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
349	DEMO-E-00344	DEMO-EST-000344	Gabriela Valeria	Romero Mendoza	1997-05-21	\N	estudiante00344@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
350	DEMO-E-00345	DEMO-EST-000345	Natalia Valeria	Romero Soto	2001-09-10	\N	estudiante00345@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
351	DEMO-E-00346	DEMO-EST-000346	Carolina Valeria	Romero Vega	2000-02-13	\N	estudiante00346@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
352	DEMO-E-00347	DEMO-EST-000347	Fernanda Valeria	Romero Rivera	1997-11-06	\N	estudiante00347@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
353	DEMO-E-00348	DEMO-EST-000348	Isabel Valeria	Romero Mamani	1996-06-23	\N	estudiante00348@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
354	DEMO-E-00349	DEMO-EST-000349	Victoria Valeria	Romero Villarroel	1998-11-29	\N	estudiante00349@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
355	DEMO-E-00350	DEMO-EST-000350	Elena Valeria	Romero Castro	1995-07-03	\N	estudiante00350@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
356	DEMO-E-00351	DEMO-EST-000351	Rodrigo Valeria	Romero Morales	2002-09-02	\N	estudiante00351@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
357	DEMO-E-00352	DEMO-EST-000352	Mauricio Valeria	Romero Ríos	2002-03-18	\N	estudiante00352@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
358	DEMO-E-00353	DEMO-EST-000353	Eduardo Valeria	Romero Escobar	2003-07-27	\N	estudiante00353@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
359	DEMO-E-00354	DEMO-EST-000354	Pablo Valeria	Romero Soria	2002-10-01	\N	estudiante00354@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
360	DEMO-E-00355	DEMO-EST-000355	Ricardo Valeria	Romero Vargas	1999-12-25	\N	estudiante00355@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
361	DEMO-E-00356	DEMO-EST-000356	Patricia Valeria	Romero Romero	2000-10-21	\N	estudiante00356@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
362	DEMO-E-00357	DEMO-EST-000357	Claudia Valeria	Romero Navarro	2002-06-07	\N	estudiante00357@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
363	DEMO-E-00358	DEMO-EST-000358	Lorena Valeria	Romero López	2002-01-10	\N	estudiante00358@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
364	DEMO-E-00359	DEMO-EST-000359	Verónica Valeria	Romero Quispe	2005-03-16	\N	estudiante00359@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
365	DEMO-E-00360	DEMO-EST-000360	Rosa Valeria	Romero Arias	1999-12-31	\N	estudiante00360@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
366	DEMO-E-00361	DEMO-EST-000361	Gabriel Camila	Ortega Flores	2007-04-07	\N	estudiante00361@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
367	DEMO-E-00362	DEMO-EST-000362	Mateo Camila	Ortega Medina	2000-12-15	\N	estudiante00362@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
368	DEMO-E-00363	DEMO-EST-000363	Daniel Camila	Ortega Cabrera	2000-05-28	\N	estudiante00363@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
369	DEMO-E-00364	DEMO-EST-000364	Santiago Camila	Ortega Castillo	2002-05-28	\N	estudiante00364@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
370	DEMO-E-00365	DEMO-EST-000365	Samuel Camila	Ortega Condori	1997-12-11	\N	estudiante00365@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
371	DEMO-E-00366	DEMO-EST-000366	Diego Camila	Ortega Delgado	2006-09-26	\N	estudiante00366@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
372	DEMO-E-00367	DEMO-EST-000367	Nicolás Camila	Ortega Aguilar	2000-09-08	\N	estudiante00367@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
373	DEMO-E-00368	DEMO-EST-000368	Adrián Camila	Ortega Herrera	2002-08-08	\N	estudiante00368@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
374	DEMO-E-00369	DEMO-EST-000369	Sebastián Camila	Ortega Suárez	2004-11-08	\N	estudiante00369@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
375	DEMO-E-00370	DEMO-EST-000370	Alejandro Camila	Ortega Valdez	2007-11-25	\N	estudiante00370@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
376	DEMO-E-00371	DEMO-EST-000371	Luis Camila	Ortega Choque	2007-12-14	\N	estudiante00371@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
377	DEMO-E-00372	DEMO-EST-000372	Miguel Camila	Ortega Molina	2006-10-26	\N	estudiante00372@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
378	DEMO-E-00373	DEMO-EST-000373	Carlos Camila	Ortega Salazar	2004-10-21	\N	estudiante00373@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
379	DEMO-E-00374	DEMO-EST-000374	Javier Camila	Ortega Paredes	2006-01-04	\N	estudiante00374@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
380	DEMO-E-00375	DEMO-EST-000375	Andrés Camila	Ortega Cruz	2005-06-21	\N	estudiante00375@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
381	DEMO-E-00376	DEMO-EST-000376	Valeria Camila	Ortega Fernández	1995-01-30	\N	estudiante00376@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
382	DEMO-E-00377	DEMO-EST-000377	Camila Camila	Ortega Pinto	1995-08-26	\N	estudiante00377@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
383	DEMO-E-00378	DEMO-EST-000378	Lucía Camila	Ortega Rojas	2002-08-19	\N	estudiante00378@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
384	DEMO-E-00379	DEMO-EST-000379	Mariana Camila	Ortega Ortega	1997-10-02	\N	estudiante00379@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
385	DEMO-E-00380	DEMO-EST-000380	Daniela Camila	Ortega Torres	2000-04-21	\N	estudiante00380@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
386	DEMO-E-00381	DEMO-EST-000381	Sofía Camila	Ortega Gutiérrez	2001-10-02	\N	estudiante00381@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
387	DEMO-E-00382	DEMO-EST-000382	Paola Camila	Ortega Apaza	2002-01-23	\N	estudiante00382@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
388	DEMO-E-00383	DEMO-EST-000383	Andrea Camila	Ortega Montes	1997-06-05	\N	estudiante00383@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
389	DEMO-E-00384	DEMO-EST-000384	Gabriela Camila	Ortega Mendoza	2004-10-13	\N	estudiante00384@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
390	DEMO-E-00385	DEMO-EST-000385	Natalia Camila	Ortega Soto	2005-02-02	\N	estudiante00385@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
391	DEMO-E-00386	DEMO-EST-000386	Carolina Camila	Ortega Vega	2002-07-23	\N	estudiante00386@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
392	DEMO-E-00387	DEMO-EST-000387	Fernanda Camila	Ortega Rivera	2000-04-07	\N	estudiante00387@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
393	DEMO-E-00388	DEMO-EST-000388	Isabel Camila	Ortega Mamani	2007-01-12	\N	estudiante00388@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
394	DEMO-E-00389	DEMO-EST-000389	Victoria Camila	Ortega Villarroel	1996-03-21	\N	estudiante00389@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
395	DEMO-E-00390	DEMO-EST-000390	Elena Camila	Ortega Castro	1996-03-29	\N	estudiante00390@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
396	DEMO-E-00391	DEMO-EST-000391	Rodrigo Camila	Ortega Morales	1995-06-01	\N	estudiante00391@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
397	DEMO-E-00392	DEMO-EST-000392	Mauricio Camila	Ortega Ríos	2004-07-10	\N	estudiante00392@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
398	DEMO-E-00393	DEMO-EST-000393	Eduardo Camila	Ortega Escobar	1997-04-13	\N	estudiante00393@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
399	DEMO-E-00394	DEMO-EST-000394	Pablo Camila	Ortega Soria	2000-02-28	\N	estudiante00394@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
400	DEMO-E-00395	DEMO-EST-000395	Ricardo Camila	Ortega Vargas	2006-02-14	\N	estudiante00395@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
401	DEMO-E-00396	DEMO-EST-000396	Patricia Camila	Ortega Romero	2001-08-02	\N	estudiante00396@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
402	DEMO-E-00397	DEMO-EST-000397	Claudia Camila	Ortega Navarro	2007-07-11	\N	estudiante00397@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
403	DEMO-E-00398	DEMO-EST-000398	Lorena Camila	Ortega López	2006-10-12	\N	estudiante00398@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
404	DEMO-E-00399	DEMO-EST-000399	Verónica Camila	Ortega Quispe	1996-02-11	\N	estudiante00399@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
405	DEMO-E-00400	DEMO-EST-000400	Rosa Camila	Ortega Arias	2002-03-13	\N	estudiante00400@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
406	DEMO-E-00401	DEMO-EST-000401	Gabriel Lucía	Medina Flores	2002-09-06	\N	estudiante00401@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
407	DEMO-E-00402	DEMO-EST-000402	Mateo Lucía	Medina Medina	1999-01-14	\N	estudiante00402@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
408	DEMO-E-00403	DEMO-EST-000403	Daniel Lucía	Medina Cabrera	1997-07-06	\N	estudiante00403@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
409	DEMO-E-00404	DEMO-EST-000404	Santiago Lucía	Medina Castillo	2002-02-22	\N	estudiante00404@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
410	DEMO-E-00405	DEMO-EST-000405	Samuel Lucía	Medina Condori	2003-11-08	\N	estudiante00405@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
411	DEMO-E-00406	DEMO-EST-000406	Diego Lucía	Medina Delgado	2004-06-10	\N	estudiante00406@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
412	DEMO-E-00407	DEMO-EST-000407	Nicolás Lucía	Medina Aguilar	2001-11-11	\N	estudiante00407@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
413	DEMO-E-00408	DEMO-EST-000408	Adrián Lucía	Medina Herrera	2006-12-28	\N	estudiante00408@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
414	DEMO-E-00409	DEMO-EST-000409	Sebastián Lucía	Medina Suárez	2001-06-29	\N	estudiante00409@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
415	DEMO-E-00410	DEMO-EST-000410	Alejandro Lucía	Medina Valdez	1995-05-17	\N	estudiante00410@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
416	DEMO-E-00411	DEMO-EST-000411	Luis Lucía	Medina Choque	2004-07-29	\N	estudiante00411@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
417	DEMO-E-00412	DEMO-EST-000412	Miguel Lucía	Medina Molina	1996-03-18	\N	estudiante00412@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
418	DEMO-E-00413	DEMO-EST-000413	Carlos Lucía	Medina Salazar	2003-04-24	\N	estudiante00413@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
419	DEMO-E-00414	DEMO-EST-000414	Javier Lucía	Medina Paredes	1999-02-11	\N	estudiante00414@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
420	DEMO-E-00415	DEMO-EST-000415	Andrés Lucía	Medina Cruz	2007-11-03	\N	estudiante00415@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
421	DEMO-E-00416	DEMO-EST-000416	Valeria Lucía	Medina Fernández	1999-12-30	\N	estudiante00416@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
422	DEMO-E-00417	DEMO-EST-000417	Camila Lucía	Medina Pinto	1998-02-11	\N	estudiante00417@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
423	DEMO-E-00418	DEMO-EST-000418	Lucía Lucía	Medina Rojas	2001-02-12	\N	estudiante00418@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
424	DEMO-E-00419	DEMO-EST-000419	Mariana Lucía	Medina Ortega	2007-12-27	\N	estudiante00419@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
425	DEMO-E-00420	DEMO-EST-000420	Daniela Lucía	Medina Torres	1998-03-04	\N	estudiante00420@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
426	DEMO-E-00421	DEMO-EST-000421	Sofía Lucía	Medina Gutiérrez	1996-12-04	\N	estudiante00421@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
427	DEMO-E-00422	DEMO-EST-000422	Paola Lucía	Medina Apaza	2004-09-30	\N	estudiante00422@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
428	DEMO-E-00423	DEMO-EST-000423	Andrea Lucía	Medina Montes	2007-12-12	\N	estudiante00423@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
429	DEMO-E-00424	DEMO-EST-000424	Gabriela Lucía	Medina Mendoza	2002-07-30	\N	estudiante00424@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
430	DEMO-E-00425	DEMO-EST-000425	Natalia Lucía	Medina Soto	1995-01-05	\N	estudiante00425@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
431	DEMO-E-00426	DEMO-EST-000426	Carolina Lucía	Medina Vega	2002-08-22	\N	estudiante00426@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
432	DEMO-E-00427	DEMO-EST-000427	Fernanda Lucía	Medina Rivera	1995-06-23	\N	estudiante00427@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
433	DEMO-E-00428	DEMO-EST-000428	Isabel Lucía	Medina Mamani	2001-12-21	\N	estudiante00428@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
434	DEMO-E-00429	DEMO-EST-000429	Victoria Lucía	Medina Villarroel	2001-09-12	\N	estudiante00429@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
435	DEMO-E-00430	DEMO-EST-000430	Elena Lucía	Medina Castro	2000-10-17	\N	estudiante00430@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
436	DEMO-E-00431	DEMO-EST-000431	Rodrigo Lucía	Medina Morales	2000-08-12	\N	estudiante00431@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
437	DEMO-E-00432	DEMO-EST-000432	Mauricio Lucía	Medina Ríos	1995-06-05	\N	estudiante00432@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
438	DEMO-E-00433	DEMO-EST-000433	Eduardo Lucía	Medina Escobar	1997-10-24	\N	estudiante00433@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
439	DEMO-E-00434	DEMO-EST-000434	Pablo Lucía	Medina Soria	2007-09-30	\N	estudiante00434@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
440	DEMO-E-00435	DEMO-EST-000435	Ricardo Lucía	Medina Vargas	2006-09-22	\N	estudiante00435@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
441	DEMO-E-00436	DEMO-EST-000436	Patricia Lucía	Medina Romero	1997-09-16	\N	estudiante00436@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
442	DEMO-E-00437	DEMO-EST-000437	Claudia Lucía	Medina Navarro	2002-03-23	\N	estudiante00437@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
443	DEMO-E-00438	DEMO-EST-000438	Lorena Lucía	Medina López	1995-04-07	\N	estudiante00438@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
444	DEMO-E-00439	DEMO-EST-000439	Verónica Lucía	Medina Quispe	2007-08-13	\N	estudiante00439@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
445	DEMO-E-00440	DEMO-EST-000440	Rosa Lucía	Medina Arias	2007-09-24	\N	estudiante00440@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
446	DEMO-E-00441	DEMO-EST-000441	Gabriel Mariana	Soto Flores	2004-03-02	\N	estudiante00441@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
447	DEMO-E-00442	DEMO-EST-000442	Mateo Mariana	Soto Medina	1995-03-04	\N	estudiante00442@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
448	DEMO-E-00443	DEMO-EST-000443	Daniel Mariana	Soto Cabrera	2005-02-10	\N	estudiante00443@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
449	DEMO-E-00444	DEMO-EST-000444	Santiago Mariana	Soto Castillo	2005-12-08	\N	estudiante00444@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
450	DEMO-E-00445	DEMO-EST-000445	Samuel Mariana	Soto Condori	2001-04-29	\N	estudiante00445@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
451	DEMO-E-00446	DEMO-EST-000446	Diego Mariana	Soto Delgado	2006-09-10	\N	estudiante00446@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
452	DEMO-E-00447	DEMO-EST-000447	Nicolás Mariana	Soto Aguilar	2006-05-02	\N	estudiante00447@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
453	DEMO-E-00448	DEMO-EST-000448	Adrián Mariana	Soto Herrera	2002-01-23	\N	estudiante00448@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
454	DEMO-E-00449	DEMO-EST-000449	Sebastián Mariana	Soto Suárez	2005-04-02	\N	estudiante00449@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
455	DEMO-E-00450	DEMO-EST-000450	Alejandro Mariana	Soto Valdez	1999-11-12	\N	estudiante00450@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
456	DEMO-E-00451	DEMO-EST-000451	Luis Mariana	Soto Choque	2001-09-23	\N	estudiante00451@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
457	DEMO-E-00452	DEMO-EST-000452	Miguel Mariana	Soto Molina	2005-08-26	\N	estudiante00452@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
458	DEMO-E-00453	DEMO-EST-000453	Carlos Mariana	Soto Salazar	2000-06-14	\N	estudiante00453@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
459	DEMO-E-00454	DEMO-EST-000454	Javier Mariana	Soto Paredes	1996-09-18	\N	estudiante00454@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
460	DEMO-E-00455	DEMO-EST-000455	Andrés Mariana	Soto Cruz	1995-12-12	\N	estudiante00455@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
461	DEMO-E-00456	DEMO-EST-000456	Valeria Mariana	Soto Fernández	2007-03-15	\N	estudiante00456@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
462	DEMO-E-00457	DEMO-EST-000457	Camila Mariana	Soto Pinto	2005-05-08	\N	estudiante00457@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
463	DEMO-E-00458	DEMO-EST-000458	Lucía Mariana	Soto Rojas	1996-08-31	\N	estudiante00458@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
464	DEMO-E-00459	DEMO-EST-000459	Mariana Mariana	Soto Ortega	1997-05-18	\N	estudiante00459@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
465	DEMO-E-00460	DEMO-EST-000460	Daniela Mariana	Soto Torres	2003-05-14	\N	estudiante00460@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
466	DEMO-E-00461	DEMO-EST-000461	Sofía Mariana	Soto Gutiérrez	1998-08-21	\N	estudiante00461@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
467	DEMO-E-00462	DEMO-EST-000462	Paola Mariana	Soto Apaza	1998-01-22	\N	estudiante00462@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
468	DEMO-E-00463	DEMO-EST-000463	Andrea Mariana	Soto Montes	2002-07-19	\N	estudiante00463@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
469	DEMO-E-00464	DEMO-EST-000464	Gabriela Mariana	Soto Mendoza	2000-01-21	\N	estudiante00464@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
470	DEMO-E-00465	DEMO-EST-000465	Natalia Mariana	Soto Soto	1999-07-30	\N	estudiante00465@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
471	DEMO-E-00466	DEMO-EST-000466	Carolina Mariana	Soto Vega	1998-05-07	\N	estudiante00466@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
472	DEMO-E-00467	DEMO-EST-000467	Fernanda Mariana	Soto Rivera	1995-01-04	\N	estudiante00467@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
473	DEMO-E-00468	DEMO-EST-000468	Isabel Mariana	Soto Mamani	1999-07-27	\N	estudiante00468@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
474	DEMO-E-00469	DEMO-EST-000469	Victoria Mariana	Soto Villarroel	2007-01-12	\N	estudiante00469@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
475	DEMO-E-00470	DEMO-EST-000470	Elena Mariana	Soto Castro	2004-06-26	\N	estudiante00470@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
476	DEMO-E-00471	DEMO-EST-000471	Rodrigo Mariana	Soto Morales	2007-05-09	\N	estudiante00471@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
477	DEMO-E-00472	DEMO-EST-000472	Mauricio Mariana	Soto Ríos	2007-08-02	\N	estudiante00472@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
478	DEMO-E-00473	DEMO-EST-000473	Eduardo Mariana	Soto Escobar	2007-12-01	\N	estudiante00473@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
479	DEMO-E-00474	DEMO-EST-000474	Pablo Mariana	Soto Soria	1997-10-17	\N	estudiante00474@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
480	DEMO-E-00475	DEMO-EST-000475	Ricardo Mariana	Soto Vargas	1996-11-23	\N	estudiante00475@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
481	DEMO-E-00476	DEMO-EST-000476	Patricia Mariana	Soto Romero	2007-02-12	\N	estudiante00476@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
482	DEMO-E-00477	DEMO-EST-000477	Claudia Mariana	Soto Navarro	2005-11-19	\N	estudiante00477@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
483	DEMO-E-00478	DEMO-EST-000478	Lorena Mariana	Soto López	2003-02-12	\N	estudiante00478@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
484	DEMO-E-00479	DEMO-EST-000479	Verónica Mariana	Soto Quispe	2006-05-24	\N	estudiante00479@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
485	DEMO-E-00480	DEMO-EST-000480	Rosa Mariana	Soto Arias	2006-01-08	\N	estudiante00480@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
486	DEMO-E-00481	DEMO-EST-000481	Gabriel Daniela	Herrera Flores	1998-01-29	\N	estudiante00481@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
487	DEMO-E-00482	DEMO-EST-000482	Mateo Daniela	Herrera Medina	2004-05-07	\N	estudiante00482@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
488	DEMO-E-00483	DEMO-EST-000483	Daniel Daniela	Herrera Cabrera	2002-01-11	\N	estudiante00483@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
489	DEMO-E-00484	DEMO-EST-000484	Santiago Daniela	Herrera Castillo	2005-07-01	\N	estudiante00484@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
490	DEMO-E-00485	DEMO-EST-000485	Samuel Daniela	Herrera Condori	2000-04-22	\N	estudiante00485@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
491	DEMO-E-00486	DEMO-EST-000486	Diego Daniela	Herrera Delgado	1999-07-30	\N	estudiante00486@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:09
492	DEMO-E-00487	DEMO-EST-000487	Nicolás Daniela	Herrera Aguilar	2004-07-22	\N	estudiante00487@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
493	DEMO-E-00488	DEMO-EST-000488	Adrián Daniela	Herrera Herrera	2006-09-30	\N	estudiante00488@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
494	DEMO-E-00489	DEMO-EST-000489	Sebastián Daniela	Herrera Suárez	1998-09-17	\N	estudiante00489@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
495	DEMO-E-00490	DEMO-EST-000490	Alejandro Daniela	Herrera Valdez	2004-07-16	\N	estudiante00490@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
496	DEMO-E-00491	DEMO-EST-000491	Luis Daniela	Herrera Choque	2003-12-26	\N	estudiante00491@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
497	DEMO-E-00492	DEMO-EST-000492	Miguel Daniela	Herrera Molina	2000-06-10	\N	estudiante00492@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
498	DEMO-E-00493	DEMO-EST-000493	Carlos Daniela	Herrera Salazar	2001-01-26	\N	estudiante00493@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
499	DEMO-E-00494	DEMO-EST-000494	Javier Daniela	Herrera Paredes	2004-06-08	\N	estudiante00494@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
500	DEMO-E-00495	DEMO-EST-000495	Andrés Daniela	Herrera Cruz	1996-03-09	\N	estudiante00495@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
501	DEMO-E-00496	DEMO-EST-000496	Valeria Daniela	Herrera Fernández	1995-02-25	\N	estudiante00496@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
502	DEMO-E-00497	DEMO-EST-000497	Camila Daniela	Herrera Pinto	1996-10-26	\N	estudiante00497@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
503	DEMO-E-00498	DEMO-EST-000498	Lucía Daniela	Herrera Rojas	2001-09-16	\N	estudiante00498@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
504	DEMO-E-00499	DEMO-EST-000499	Mariana Daniela	Herrera Ortega	2003-11-13	\N	estudiante00499@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
505	DEMO-E-00500	DEMO-EST-000500	Daniela Daniela	Herrera Torres	1999-03-02	\N	estudiante00500@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
506	DEMO-E-00501	DEMO-EST-000501	Sofía Daniela	Herrera Gutiérrez	2006-10-22	\N	estudiante00501@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
507	DEMO-E-00502	DEMO-EST-000502	Paola Daniela	Herrera Apaza	2000-04-22	\N	estudiante00502@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
508	DEMO-E-00503	DEMO-EST-000503	Andrea Daniela	Herrera Montes	2000-12-19	\N	estudiante00503@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
509	DEMO-E-00504	DEMO-EST-000504	Gabriela Daniela	Herrera Mendoza	2005-09-07	\N	estudiante00504@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
510	DEMO-E-00505	DEMO-EST-000505	Natalia Daniela	Herrera Soto	2001-06-16	\N	estudiante00505@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
511	DEMO-E-00506	DEMO-EST-000506	Carolina Daniela	Herrera Vega	2004-02-24	\N	estudiante00506@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
512	DEMO-E-00507	DEMO-EST-000507	Fernanda Daniela	Herrera Rivera	2002-07-08	\N	estudiante00507@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
513	DEMO-E-00508	DEMO-EST-000508	Isabel Daniela	Herrera Mamani	2007-04-28	\N	estudiante00508@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
514	DEMO-E-00509	DEMO-EST-000509	Victoria Daniela	Herrera Villarroel	2000-08-14	\N	estudiante00509@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
515	DEMO-E-00510	DEMO-EST-000510	Elena Daniela	Herrera Castro	1995-02-17	\N	estudiante00510@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
516	DEMO-E-00511	DEMO-EST-000511	Rodrigo Daniela	Herrera Morales	2003-12-01	\N	estudiante00511@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
517	DEMO-E-00512	DEMO-EST-000512	Mauricio Daniela	Herrera Ríos	2007-05-15	\N	estudiante00512@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
518	DEMO-E-00513	DEMO-EST-000513	Eduardo Daniela	Herrera Escobar	1995-02-11	\N	estudiante00513@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
519	DEMO-E-00514	DEMO-EST-000514	Pablo Daniela	Herrera Soria	1996-09-25	\N	estudiante00514@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
520	DEMO-E-00515	DEMO-EST-000515	Ricardo Daniela	Herrera Vargas	2002-05-28	\N	estudiante00515@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
521	DEMO-E-00516	DEMO-EST-000516	Patricia Daniela	Herrera Romero	1996-07-30	\N	estudiante00516@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
522	DEMO-E-00517	DEMO-EST-000517	Claudia Daniela	Herrera Navarro	2002-05-17	\N	estudiante00517@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
523	DEMO-E-00518	DEMO-EST-000518	Lorena Daniela	Herrera López	2002-01-19	\N	estudiante00518@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
524	DEMO-E-00519	DEMO-EST-000519	Verónica Daniela	Herrera Quispe	1996-05-15	\N	estudiante00519@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
525	DEMO-E-00520	DEMO-EST-000520	Rosa Daniela	Herrera Arias	2007-07-07	\N	estudiante00520@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
526	DEMO-E-00521	DEMO-EST-000521	Gabriel Sofía	Morales Flores	2007-08-27	\N	estudiante00521@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
527	DEMO-E-00522	DEMO-EST-000522	Mateo Sofía	Morales Medina	2003-11-29	\N	estudiante00522@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
528	DEMO-E-00523	DEMO-EST-000523	Daniel Sofía	Morales Cabrera	1997-05-04	\N	estudiante00523@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
529	DEMO-E-00524	DEMO-EST-000524	Santiago Sofía	Morales Castillo	1996-03-04	\N	estudiante00524@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
530	DEMO-E-00525	DEMO-EST-000525	Samuel Sofía	Morales Condori	1996-09-11	\N	estudiante00525@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
531	DEMO-E-00526	DEMO-EST-000526	Diego Sofía	Morales Delgado	2004-08-03	\N	estudiante00526@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
532	DEMO-E-00527	DEMO-EST-000527	Nicolás Sofía	Morales Aguilar	2006-10-21	\N	estudiante00527@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
533	DEMO-E-00528	DEMO-EST-000528	Adrián Sofía	Morales Herrera	2003-08-02	\N	estudiante00528@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
534	DEMO-E-00529	DEMO-EST-000529	Sebastián Sofía	Morales Suárez	2002-01-20	\N	estudiante00529@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
535	DEMO-E-00530	DEMO-EST-000530	Alejandro Sofía	Morales Valdez	2005-11-17	\N	estudiante00530@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
536	DEMO-E-00531	DEMO-EST-000531	Luis Sofía	Morales Choque	2001-10-02	\N	estudiante00531@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
537	DEMO-E-00532	DEMO-EST-000532	Miguel Sofía	Morales Molina	2004-04-01	\N	estudiante00532@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
538	DEMO-E-00533	DEMO-EST-000533	Carlos Sofía	Morales Salazar	2001-06-26	\N	estudiante00533@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
539	DEMO-E-00534	DEMO-EST-000534	Javier Sofía	Morales Paredes	2005-10-10	\N	estudiante00534@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
540	DEMO-E-00535	DEMO-EST-000535	Andrés Sofía	Morales Cruz	2001-06-18	\N	estudiante00535@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
541	DEMO-E-00536	DEMO-EST-000536	Valeria Sofía	Morales Fernández	2001-10-10	\N	estudiante00536@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
542	DEMO-E-00537	DEMO-EST-000537	Camila Sofía	Morales Pinto	1998-05-06	\N	estudiante00537@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
543	DEMO-E-00538	DEMO-EST-000538	Lucía Sofía	Morales Rojas	2007-06-01	\N	estudiante00538@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
544	DEMO-E-00539	DEMO-EST-000539	Mariana Sofía	Morales Ortega	2007-02-25	\N	estudiante00539@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
545	DEMO-E-00540	DEMO-EST-000540	Daniela Sofía	Morales Torres	1997-01-23	\N	estudiante00540@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
546	DEMO-E-00541	DEMO-EST-000541	Sofía Sofía	Morales Gutiérrez	2002-04-13	\N	estudiante00541@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
547	DEMO-E-00542	DEMO-EST-000542	Paola Sofía	Morales Apaza	2004-10-23	\N	estudiante00542@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
548	DEMO-E-00543	DEMO-EST-000543	Andrea Sofía	Morales Montes	1996-08-27	\N	estudiante00543@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
549	DEMO-E-00544	DEMO-EST-000544	Gabriela Sofía	Morales Mendoza	1995-03-01	\N	estudiante00544@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
550	DEMO-E-00545	DEMO-EST-000545	Natalia Sofía	Morales Soto	2004-05-05	\N	estudiante00545@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
551	DEMO-E-00546	DEMO-EST-000546	Carolina Sofía	Morales Vega	1997-09-09	\N	estudiante00546@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
552	DEMO-E-00547	DEMO-EST-000547	Fernanda Sofía	Morales Rivera	2006-09-29	\N	estudiante00547@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
553	DEMO-E-00548	DEMO-EST-000548	Isabel Sofía	Morales Mamani	1995-11-20	\N	estudiante00548@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
554	DEMO-E-00549	DEMO-EST-000549	Victoria Sofía	Morales Villarroel	2007-09-03	\N	estudiante00549@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
555	DEMO-E-00550	DEMO-EST-000550	Elena Sofía	Morales Castro	1999-11-02	\N	estudiante00550@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
556	DEMO-E-00551	DEMO-EST-000551	Rodrigo Sofía	Morales Morales	1998-06-25	\N	estudiante00551@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
557	DEMO-E-00552	DEMO-EST-000552	Mauricio Sofía	Morales Ríos	1996-06-17	\N	estudiante00552@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
558	DEMO-E-00553	DEMO-EST-000553	Eduardo Sofía	Morales Escobar	2005-03-29	\N	estudiante00553@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
559	DEMO-E-00554	DEMO-EST-000554	Pablo Sofía	Morales Soria	2000-09-16	\N	estudiante00554@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
560	DEMO-E-00555	DEMO-EST-000555	Ricardo Sofía	Morales Vargas	2000-01-16	\N	estudiante00555@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
561	DEMO-E-00556	DEMO-EST-000556	Patricia Sofía	Morales Romero	2001-10-15	\N	estudiante00556@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
562	DEMO-E-00557	DEMO-EST-000557	Claudia Sofía	Morales Navarro	2006-05-15	\N	estudiante00557@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
563	DEMO-E-00558	DEMO-EST-000558	Lorena Sofía	Morales López	1996-12-09	\N	estudiante00558@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
564	DEMO-E-00559	DEMO-EST-000559	Verónica Sofía	Morales Quispe	1999-08-17	\N	estudiante00559@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
565	DEMO-E-00560	DEMO-EST-000560	Rosa Sofía	Morales Arias	2004-12-10	\N	estudiante00560@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
566	DEMO-E-00561	DEMO-EST-000561	Gabriel Paola	Paredes Flores	2003-12-05	\N	estudiante00561@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
567	DEMO-E-00562	DEMO-EST-000562	Mateo Paola	Paredes Medina	1995-10-18	\N	estudiante00562@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
568	DEMO-E-00563	DEMO-EST-000563	Daniel Paola	Paredes Cabrera	2004-05-13	\N	estudiante00563@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
569	DEMO-E-00564	DEMO-EST-000564	Santiago Paola	Paredes Castillo	1998-01-10	\N	estudiante00564@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
570	DEMO-E-00565	DEMO-EST-000565	Samuel Paola	Paredes Condori	1998-06-16	\N	estudiante00565@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
571	DEMO-E-00566	DEMO-EST-000566	Diego Paola	Paredes Delgado	1999-06-05	\N	estudiante00566@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
572	DEMO-E-00567	DEMO-EST-000567	Nicolás Paola	Paredes Aguilar	2004-03-14	\N	estudiante00567@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
573	DEMO-E-00568	DEMO-EST-000568	Adrián Paola	Paredes Herrera	1999-08-09	\N	estudiante00568@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
574	DEMO-E-00569	DEMO-EST-000569	Sebastián Paola	Paredes Suárez	2007-02-08	\N	estudiante00569@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
575	DEMO-E-00570	DEMO-EST-000570	Alejandro Paola	Paredes Valdez	2003-09-25	\N	estudiante00570@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
576	DEMO-E-00571	DEMO-EST-000571	Luis Paola	Paredes Choque	2000-06-11	\N	estudiante00571@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
577	DEMO-E-00572	DEMO-EST-000572	Miguel Paola	Paredes Molina	1998-03-16	\N	estudiante00572@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
578	DEMO-E-00573	DEMO-EST-000573	Carlos Paola	Paredes Salazar	2006-05-30	\N	estudiante00573@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
579	DEMO-E-00574	DEMO-EST-000574	Javier Paola	Paredes Paredes	2007-05-18	\N	estudiante00574@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
580	DEMO-E-00575	DEMO-EST-000575	Andrés Paola	Paredes Cruz	1999-02-01	\N	estudiante00575@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
581	DEMO-E-00576	DEMO-EST-000576	Valeria Paola	Paredes Fernández	2006-03-09	\N	estudiante00576@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
582	DEMO-E-00577	DEMO-EST-000577	Camila Paola	Paredes Pinto	1996-07-29	\N	estudiante00577@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
583	DEMO-E-00578	DEMO-EST-000578	Lucía Paola	Paredes Rojas	2005-04-03	\N	estudiante00578@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
584	DEMO-E-00579	DEMO-EST-000579	Mariana Paola	Paredes Ortega	2000-02-21	\N	estudiante00579@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
585	DEMO-E-00580	DEMO-EST-000580	Daniela Paola	Paredes Torres	1999-12-16	\N	estudiante00580@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
586	DEMO-E-00581	DEMO-EST-000581	Sofía Paola	Paredes Gutiérrez	2004-01-25	\N	estudiante00581@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
587	DEMO-E-00582	DEMO-EST-000582	Paola Paola	Paredes Apaza	2006-09-08	\N	estudiante00582@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
588	DEMO-E-00583	DEMO-EST-000583	Andrea Paola	Paredes Montes	2000-06-11	\N	estudiante00583@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
589	DEMO-E-00584	DEMO-EST-000584	Gabriela Paola	Paredes Mendoza	2005-04-25	\N	estudiante00584@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
590	DEMO-E-00585	DEMO-EST-000585	Natalia Paola	Paredes Soto	1998-04-03	\N	estudiante00585@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
591	DEMO-E-00586	DEMO-EST-000586	Carolina Paola	Paredes Vega	2000-08-06	\N	estudiante00586@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
592	DEMO-E-00587	DEMO-EST-000587	Fernanda Paola	Paredes Rivera	2002-08-17	\N	estudiante00587@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
593	DEMO-E-00588	DEMO-EST-000588	Isabel Paola	Paredes Mamani	1999-01-29	\N	estudiante00588@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
594	DEMO-E-00589	DEMO-EST-000589	Victoria Paola	Paredes Villarroel	2007-04-19	\N	estudiante00589@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
595	DEMO-E-00590	DEMO-EST-000590	Elena Paola	Paredes Castro	2003-08-19	\N	estudiante00590@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
596	DEMO-E-00591	DEMO-EST-000591	Rodrigo Paola	Paredes Morales	2003-04-04	\N	estudiante00591@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
597	DEMO-E-00592	DEMO-EST-000592	Mauricio Paola	Paredes Ríos	2006-11-27	\N	estudiante00592@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
598	DEMO-E-00593	DEMO-EST-000593	Eduardo Paola	Paredes Escobar	2005-03-04	\N	estudiante00593@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
599	DEMO-E-00594	DEMO-EST-000594	Pablo Paola	Paredes Soria	1999-09-28	\N	estudiante00594@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
600	DEMO-E-00595	DEMO-EST-000595	Ricardo Paola	Paredes Vargas	2006-12-10	\N	estudiante00595@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
601	DEMO-E-00596	DEMO-EST-000596	Patricia Paola	Paredes Romero	1996-11-12	\N	estudiante00596@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
602	DEMO-E-00597	DEMO-EST-000597	Claudia Paola	Paredes Navarro	2000-07-30	\N	estudiante00597@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
603	DEMO-E-00598	DEMO-EST-000598	Lorena Paola	Paredes López	1997-01-05	\N	estudiante00598@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
604	DEMO-E-00599	DEMO-EST-000599	Verónica Paola	Paredes Quispe	1995-06-04	\N	estudiante00599@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
605	DEMO-E-00600	DEMO-EST-000600	Rosa Paola	Paredes Arias	1995-10-11	\N	estudiante00600@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
606	DEMO-E-00601	DEMO-EST-000601	Gabriel Andrea	Navarro Flores	1995-05-24	\N	estudiante00601@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
607	DEMO-E-00602	DEMO-EST-000602	Mateo Andrea	Navarro Medina	2000-10-13	\N	estudiante00602@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
608	DEMO-E-00603	DEMO-EST-000603	Daniel Andrea	Navarro Cabrera	2003-03-12	\N	estudiante00603@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
609	DEMO-E-00604	DEMO-EST-000604	Santiago Andrea	Navarro Castillo	2006-05-08	\N	estudiante00604@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
610	DEMO-E-00605	DEMO-EST-000605	Samuel Andrea	Navarro Condori	2002-02-03	\N	estudiante00605@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
611	DEMO-E-00606	DEMO-EST-000606	Diego Andrea	Navarro Delgado	1999-05-20	\N	estudiante00606@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
612	DEMO-E-00607	DEMO-EST-000607	Nicolás Andrea	Navarro Aguilar	1995-01-19	\N	estudiante00607@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
613	DEMO-E-00608	DEMO-EST-000608	Adrián Andrea	Navarro Herrera	2001-01-06	\N	estudiante00608@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
614	DEMO-E-00609	DEMO-EST-000609	Sebastián Andrea	Navarro Suárez	2006-09-25	\N	estudiante00609@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
615	DEMO-E-00610	DEMO-EST-000610	Alejandro Andrea	Navarro Valdez	2006-09-14	\N	estudiante00610@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
616	DEMO-E-00611	DEMO-EST-000611	Luis Andrea	Navarro Choque	2007-12-20	\N	estudiante00611@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
617	DEMO-E-00612	DEMO-EST-000612	Miguel Andrea	Navarro Molina	2000-04-15	\N	estudiante00612@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
618	DEMO-E-00613	DEMO-EST-000613	Carlos Andrea	Navarro Salazar	2000-06-01	\N	estudiante00613@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
619	DEMO-E-00614	DEMO-EST-000614	Javier Andrea	Navarro Paredes	1997-03-02	\N	estudiante00614@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
620	DEMO-E-00615	DEMO-EST-000615	Andrés Andrea	Navarro Cruz	2007-05-26	\N	estudiante00615@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
621	DEMO-E-00616	DEMO-EST-000616	Valeria Andrea	Navarro Fernández	1997-04-19	\N	estudiante00616@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
622	DEMO-E-00617	DEMO-EST-000617	Camila Andrea	Navarro Pinto	2007-09-22	\N	estudiante00617@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
623	DEMO-E-00618	DEMO-EST-000618	Lucía Andrea	Navarro Rojas	2006-06-16	\N	estudiante00618@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
624	DEMO-E-00619	DEMO-EST-000619	Mariana Andrea	Navarro Ortega	2005-04-07	\N	estudiante00619@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
625	DEMO-E-00620	DEMO-EST-000620	Daniela Andrea	Navarro Torres	2005-12-16	\N	estudiante00620@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
626	DEMO-E-00621	DEMO-EST-000621	Sofía Andrea	Navarro Gutiérrez	2005-03-04	\N	estudiante00621@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
627	DEMO-E-00622	DEMO-EST-000622	Paola Andrea	Navarro Apaza	1995-04-03	\N	estudiante00622@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
628	DEMO-E-00623	DEMO-EST-000623	Andrea Andrea	Navarro Montes	2002-05-02	\N	estudiante00623@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
629	DEMO-E-00624	DEMO-EST-000624	Gabriela Andrea	Navarro Mendoza	2007-03-23	\N	estudiante00624@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
630	DEMO-E-00625	DEMO-EST-000625	Natalia Andrea	Navarro Soto	2007-09-21	\N	estudiante00625@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
631	DEMO-E-00626	DEMO-EST-000626	Carolina Andrea	Navarro Vega	2006-02-15	\N	estudiante00626@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
632	DEMO-E-00627	DEMO-EST-000627	Fernanda Andrea	Navarro Rivera	2006-03-08	\N	estudiante00627@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
633	DEMO-E-00628	DEMO-EST-000628	Isabel Andrea	Navarro Mamani	2001-06-18	\N	estudiante00628@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
634	DEMO-E-00629	DEMO-EST-000629	Victoria Andrea	Navarro Villarroel	1995-06-15	\N	estudiante00629@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
635	DEMO-E-00630	DEMO-EST-000630	Elena Andrea	Navarro Castro	1998-06-12	\N	estudiante00630@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
636	DEMO-E-00631	DEMO-EST-000631	Rodrigo Andrea	Navarro Morales	2003-09-14	\N	estudiante00631@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
637	DEMO-E-00632	DEMO-EST-000632	Mauricio Andrea	Navarro Ríos	2006-01-21	\N	estudiante00632@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
638	DEMO-E-00633	DEMO-EST-000633	Eduardo Andrea	Navarro Escobar	2000-11-03	\N	estudiante00633@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
639	DEMO-E-00634	DEMO-EST-000634	Pablo Andrea	Navarro Soria	2001-08-23	\N	estudiante00634@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
640	DEMO-E-00635	DEMO-EST-000635	Ricardo Andrea	Navarro Vargas	1996-02-28	\N	estudiante00635@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
641	DEMO-E-00636	DEMO-EST-000636	Patricia Andrea	Navarro Romero	1996-02-18	\N	estudiante00636@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
642	DEMO-E-00637	DEMO-EST-000637	Claudia Andrea	Navarro Navarro	2005-09-09	\N	estudiante00637@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
643	DEMO-E-00638	DEMO-EST-000638	Lorena Andrea	Navarro López	1996-05-20	\N	estudiante00638@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
644	DEMO-E-00639	DEMO-EST-000639	Verónica Andrea	Navarro Quispe	2005-09-14	\N	estudiante00639@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
645	DEMO-E-00640	DEMO-EST-000640	Rosa Andrea	Navarro Arias	1999-09-06	\N	estudiante00640@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
646	DEMO-E-00641	DEMO-EST-000641	Gabriel Gabriela	Torres Flores	1997-02-10	\N	estudiante00641@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
647	DEMO-E-00642	DEMO-EST-000642	Mateo Gabriela	Torres Medina	1995-08-30	\N	estudiante00642@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
648	DEMO-E-00643	DEMO-EST-000643	Daniel Gabriela	Torres Cabrera	2005-09-25	\N	estudiante00643@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
649	DEMO-E-00644	DEMO-EST-000644	Santiago Gabriela	Torres Castillo	2001-07-27	\N	estudiante00644@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
650	DEMO-E-00645	DEMO-EST-000645	Samuel Gabriela	Torres Condori	1997-01-15	\N	estudiante00645@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
651	DEMO-E-00646	DEMO-EST-000646	Diego Gabriela	Torres Delgado	2001-12-10	\N	estudiante00646@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
652	DEMO-E-00647	DEMO-EST-000647	Nicolás Gabriela	Torres Aguilar	1995-10-23	\N	estudiante00647@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
653	DEMO-E-00648	DEMO-EST-000648	Adrián Gabriela	Torres Herrera	1997-05-24	\N	estudiante00648@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
654	DEMO-E-00649	DEMO-EST-000649	Sebastián Gabriela	Torres Suárez	2007-04-08	\N	estudiante00649@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
655	DEMO-E-00650	DEMO-EST-000650	Alejandro Gabriela	Torres Valdez	1998-11-18	\N	estudiante00650@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
656	DEMO-E-00651	DEMO-EST-000651	Luis Gabriela	Torres Choque	2007-01-25	\N	estudiante00651@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
657	DEMO-E-00652	DEMO-EST-000652	Miguel Gabriela	Torres Molina	1999-02-05	\N	estudiante00652@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
658	DEMO-E-00653	DEMO-EST-000653	Carlos Gabriela	Torres Salazar	1996-01-15	\N	estudiante00653@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
659	DEMO-E-00654	DEMO-EST-000654	Javier Gabriela	Torres Paredes	2006-12-06	\N	estudiante00654@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
660	DEMO-E-00655	DEMO-EST-000655	Andrés Gabriela	Torres Cruz	2004-07-11	\N	estudiante00655@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
661	DEMO-E-00656	DEMO-EST-000656	Valeria Gabriela	Torres Fernández	2001-03-07	\N	estudiante00656@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
662	DEMO-E-00657	DEMO-EST-000657	Camila Gabriela	Torres Pinto	1997-05-12	\N	estudiante00657@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
663	DEMO-E-00658	DEMO-EST-000658	Lucía Gabriela	Torres Rojas	2004-06-03	\N	estudiante00658@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
664	DEMO-E-00659	DEMO-EST-000659	Mariana Gabriela	Torres Ortega	2004-03-30	\N	estudiante00659@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
665	DEMO-E-00660	DEMO-EST-000660	Daniela Gabriela	Torres Torres	1999-12-30	\N	estudiante00660@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
666	DEMO-E-00661	DEMO-EST-000661	Sofía Gabriela	Torres Gutiérrez	2001-10-19	\N	estudiante00661@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
667	DEMO-E-00662	DEMO-EST-000662	Paola Gabriela	Torres Apaza	2003-04-29	\N	estudiante00662@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
668	DEMO-E-00663	DEMO-EST-000663	Andrea Gabriela	Torres Montes	2005-08-08	\N	estudiante00663@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
669	DEMO-E-00664	DEMO-EST-000664	Gabriela Gabriela	Torres Mendoza	1995-09-20	\N	estudiante00664@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
670	DEMO-E-00665	DEMO-EST-000665	Natalia Gabriela	Torres Soto	1995-11-04	\N	estudiante00665@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
671	DEMO-E-00666	DEMO-EST-000666	Carolina Gabriela	Torres Vega	1998-01-17	\N	estudiante00666@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
672	DEMO-E-00667	DEMO-EST-000667	Fernanda Gabriela	Torres Rivera	2004-02-01	\N	estudiante00667@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
673	DEMO-E-00668	DEMO-EST-000668	Isabel Gabriela	Torres Mamani	1998-06-01	\N	estudiante00668@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
674	DEMO-E-00669	DEMO-EST-000669	Victoria Gabriela	Torres Villarroel	2005-02-08	\N	estudiante00669@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
675	DEMO-E-00670	DEMO-EST-000670	Elena Gabriela	Torres Castro	2004-09-29	\N	estudiante00670@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
676	DEMO-E-00671	DEMO-EST-000671	Rodrigo Gabriela	Torres Morales	2006-02-19	\N	estudiante00671@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
677	DEMO-E-00672	DEMO-EST-000672	Mauricio Gabriela	Torres Ríos	1999-03-12	\N	estudiante00672@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
678	DEMO-E-00673	DEMO-EST-000673	Eduardo Gabriela	Torres Escobar	1996-06-27	\N	estudiante00673@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
679	DEMO-E-00674	DEMO-EST-000674	Pablo Gabriela	Torres Soria	2005-07-14	\N	estudiante00674@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
680	DEMO-E-00675	DEMO-EST-000675	Ricardo Gabriela	Torres Vargas	1995-07-21	\N	estudiante00675@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
681	DEMO-E-00676	DEMO-EST-000676	Patricia Gabriela	Torres Romero	2002-12-25	\N	estudiante00676@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
682	DEMO-E-00677	DEMO-EST-000677	Claudia Gabriela	Torres Navarro	2005-12-31	\N	estudiante00677@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
683	DEMO-E-00678	DEMO-EST-000678	Lorena Gabriela	Torres López	2006-09-10	\N	estudiante00678@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
684	DEMO-E-00679	DEMO-EST-000679	Verónica Gabriela	Torres Quispe	2005-09-25	\N	estudiante00679@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
685	DEMO-E-00680	DEMO-EST-000680	Rosa Gabriela	Torres Arias	1995-02-21	\N	estudiante00680@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
686	DEMO-E-00681	DEMO-EST-000681	Gabriel Natalia	Cabrera Flores	1998-07-30	\N	estudiante00681@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
687	DEMO-E-00682	DEMO-EST-000682	Mateo Natalia	Cabrera Medina	1997-07-19	\N	estudiante00682@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
688	DEMO-E-00683	DEMO-EST-000683	Daniel Natalia	Cabrera Cabrera	2001-06-24	\N	estudiante00683@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
689	DEMO-E-00684	DEMO-EST-000684	Santiago Natalia	Cabrera Castillo	1995-03-11	\N	estudiante00684@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
690	DEMO-E-00685	DEMO-EST-000685	Samuel Natalia	Cabrera Condori	2004-01-19	\N	estudiante00685@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
691	DEMO-E-00686	DEMO-EST-000686	Diego Natalia	Cabrera Delgado	2000-03-22	\N	estudiante00686@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
692	DEMO-E-00687	DEMO-EST-000687	Nicolás Natalia	Cabrera Aguilar	2000-08-16	\N	estudiante00687@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
693	DEMO-E-00688	DEMO-EST-000688	Adrián Natalia	Cabrera Herrera	1999-01-03	\N	estudiante00688@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
694	DEMO-E-00689	DEMO-EST-000689	Sebastián Natalia	Cabrera Suárez	2001-02-18	\N	estudiante00689@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
695	DEMO-E-00690	DEMO-EST-000690	Alejandro Natalia	Cabrera Valdez	2006-10-30	\N	estudiante00690@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
696	DEMO-E-00691	DEMO-EST-000691	Luis Natalia	Cabrera Choque	2001-04-04	\N	estudiante00691@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
697	DEMO-E-00692	DEMO-EST-000692	Miguel Natalia	Cabrera Molina	1997-08-31	\N	estudiante00692@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
698	DEMO-E-00693	DEMO-EST-000693	Carlos Natalia	Cabrera Salazar	1995-04-25	\N	estudiante00693@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
699	DEMO-E-00694	DEMO-EST-000694	Javier Natalia	Cabrera Paredes	2003-07-18	\N	estudiante00694@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
700	DEMO-E-00695	DEMO-EST-000695	Andrés Natalia	Cabrera Cruz	2006-07-19	\N	estudiante00695@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
701	DEMO-E-00696	DEMO-EST-000696	Valeria Natalia	Cabrera Fernández	1998-06-20	\N	estudiante00696@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
702	DEMO-E-00697	DEMO-EST-000697	Camila Natalia	Cabrera Pinto	1998-11-27	\N	estudiante00697@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
703	DEMO-E-00698	DEMO-EST-000698	Lucía Natalia	Cabrera Rojas	2007-01-17	\N	estudiante00698@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
704	DEMO-E-00699	DEMO-EST-000699	Mariana Natalia	Cabrera Ortega	2000-05-23	\N	estudiante00699@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
705	DEMO-E-00700	DEMO-EST-000700	Daniela Natalia	Cabrera Torres	1996-05-27	\N	estudiante00700@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
706	DEMO-E-00701	DEMO-EST-000701	Sofía Natalia	Cabrera Gutiérrez	2000-06-14	\N	estudiante00701@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
707	DEMO-E-00702	DEMO-EST-000702	Paola Natalia	Cabrera Apaza	2001-03-20	\N	estudiante00702@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
708	DEMO-E-00703	DEMO-EST-000703	Andrea Natalia	Cabrera Montes	1995-05-04	\N	estudiante00703@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
709	DEMO-E-00704	DEMO-EST-000704	Gabriela Natalia	Cabrera Mendoza	2005-04-21	\N	estudiante00704@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
710	DEMO-E-00705	DEMO-EST-000705	Natalia Natalia	Cabrera Soto	2006-02-05	\N	estudiante00705@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
711	DEMO-E-00706	DEMO-EST-000706	Carolina Natalia	Cabrera Vega	1996-08-20	\N	estudiante00706@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
712	DEMO-E-00707	DEMO-EST-000707	Fernanda Natalia	Cabrera Rivera	1999-06-24	\N	estudiante00707@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
713	DEMO-E-00708	DEMO-EST-000708	Isabel Natalia	Cabrera Mamani	1999-12-22	\N	estudiante00708@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
714	DEMO-E-00709	DEMO-EST-000709	Victoria Natalia	Cabrera Villarroel	2005-11-12	\N	estudiante00709@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
715	DEMO-E-00710	DEMO-EST-000710	Elena Natalia	Cabrera Castro	2001-09-26	\N	estudiante00710@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
716	DEMO-E-00711	DEMO-EST-000711	Rodrigo Natalia	Cabrera Morales	2004-12-20	\N	estudiante00711@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
717	DEMO-E-00712	DEMO-EST-000712	Mauricio Natalia	Cabrera Ríos	2004-12-02	\N	estudiante00712@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
718	DEMO-E-00713	DEMO-EST-000713	Eduardo Natalia	Cabrera Escobar	1996-04-26	\N	estudiante00713@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
719	DEMO-E-00714	DEMO-EST-000714	Pablo Natalia	Cabrera Soria	1996-01-12	\N	estudiante00714@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
720	DEMO-E-00715	DEMO-EST-000715	Ricardo Natalia	Cabrera Vargas	1997-06-22	\N	estudiante00715@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
721	DEMO-E-00716	DEMO-EST-000716	Patricia Natalia	Cabrera Romero	1996-01-14	\N	estudiante00716@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
722	DEMO-E-00717	DEMO-EST-000717	Claudia Natalia	Cabrera Navarro	1999-12-16	\N	estudiante00717@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
723	DEMO-E-00718	DEMO-EST-000718	Lorena Natalia	Cabrera López	2005-02-28	\N	estudiante00718@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
724	DEMO-E-00719	DEMO-EST-000719	Verónica Natalia	Cabrera Quispe	2004-05-13	\N	estudiante00719@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
725	DEMO-E-00720	DEMO-EST-000720	Rosa Natalia	Cabrera Arias	1995-09-03	\N	estudiante00720@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
726	DEMO-E-00721	DEMO-EST-000721	Gabriel Carolina	Vega Flores	1997-12-10	\N	estudiante00721@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
727	DEMO-E-00722	DEMO-EST-000722	Mateo Carolina	Vega Medina	2004-08-29	\N	estudiante00722@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
728	DEMO-E-00723	DEMO-EST-000723	Daniel Carolina	Vega Cabrera	2005-05-23	\N	estudiante00723@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
729	DEMO-E-00724	DEMO-EST-000724	Santiago Carolina	Vega Castillo	1999-12-26	\N	estudiante00724@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
730	DEMO-E-00725	DEMO-EST-000725	Samuel Carolina	Vega Condori	1996-07-13	\N	estudiante00725@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
731	DEMO-E-00726	DEMO-EST-000726	Diego Carolina	Vega Delgado	1995-11-23	\N	estudiante00726@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
732	DEMO-E-00727	DEMO-EST-000727	Nicolás Carolina	Vega Aguilar	2004-12-30	\N	estudiante00727@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
733	DEMO-E-00728	DEMO-EST-000728	Adrián Carolina	Vega Herrera	2005-02-18	\N	estudiante00728@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
734	DEMO-E-00729	DEMO-EST-000729	Sebastián Carolina	Vega Suárez	2000-11-05	\N	estudiante00729@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
735	DEMO-E-00730	DEMO-EST-000730	Alejandro Carolina	Vega Valdez	2003-12-12	\N	estudiante00730@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
736	DEMO-E-00731	DEMO-EST-000731	Luis Carolina	Vega Choque	1997-07-25	\N	estudiante00731@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
737	DEMO-E-00732	DEMO-EST-000732	Miguel Carolina	Vega Molina	2005-09-25	\N	estudiante00732@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
738	DEMO-E-00733	DEMO-EST-000733	Carlos Carolina	Vega Salazar	2003-12-19	\N	estudiante00733@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
739	DEMO-E-00734	DEMO-EST-000734	Javier Carolina	Vega Paredes	1998-10-10	\N	estudiante00734@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
740	DEMO-E-00735	DEMO-EST-000735	Andrés Carolina	Vega Cruz	1999-09-29	\N	estudiante00735@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
741	DEMO-E-00736	DEMO-EST-000736	Valeria Carolina	Vega Fernández	2005-08-08	\N	estudiante00736@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
742	DEMO-E-00737	DEMO-EST-000737	Camila Carolina	Vega Pinto	2000-01-25	\N	estudiante00737@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
743	DEMO-E-00738	DEMO-EST-000738	Lucía Carolina	Vega Rojas	2006-10-01	\N	estudiante00738@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
744	DEMO-E-00739	DEMO-EST-000739	Mariana Carolina	Vega Ortega	1997-06-25	\N	estudiante00739@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
745	DEMO-E-00740	DEMO-EST-000740	Daniela Carolina	Vega Torres	2002-04-07	\N	estudiante00740@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
746	DEMO-E-00741	DEMO-EST-000741	Sofía Carolina	Vega Gutiérrez	2002-04-09	\N	estudiante00741@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
747	DEMO-E-00742	DEMO-EST-000742	Paola Carolina	Vega Apaza	2005-05-31	\N	estudiante00742@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
748	DEMO-E-00743	DEMO-EST-000743	Andrea Carolina	Vega Montes	1997-10-07	\N	estudiante00743@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
749	DEMO-E-00744	DEMO-EST-000744	Gabriela Carolina	Vega Mendoza	2005-08-15	\N	estudiante00744@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
750	DEMO-E-00745	DEMO-EST-000745	Natalia Carolina	Vega Soto	1999-01-25	\N	estudiante00745@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
751	DEMO-E-00746	DEMO-EST-000746	Carolina Carolina	Vega Vega	1996-07-16	\N	estudiante00746@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
752	DEMO-E-00747	DEMO-EST-000747	Fernanda Carolina	Vega Rivera	2007-10-01	\N	estudiante00747@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
753	DEMO-E-00748	DEMO-EST-000748	Isabel Carolina	Vega Mamani	2002-11-06	\N	estudiante00748@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
754	DEMO-E-00749	DEMO-EST-000749	Victoria Carolina	Vega Villarroel	2005-10-12	\N	estudiante00749@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
755	DEMO-E-00750	DEMO-EST-000750	Elena Carolina	Vega Castro	2006-01-09	\N	estudiante00750@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
756	DEMO-E-00751	DEMO-EST-000751	Rodrigo Carolina	Vega Morales	2005-11-04	\N	estudiante00751@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
757	DEMO-E-00752	DEMO-EST-000752	Mauricio Carolina	Vega Ríos	2003-08-07	\N	estudiante00752@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
758	DEMO-E-00753	DEMO-EST-000753	Eduardo Carolina	Vega Escobar	1996-04-05	\N	estudiante00753@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
759	DEMO-E-00754	DEMO-EST-000754	Pablo Carolina	Vega Soria	1997-09-23	\N	estudiante00754@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
760	DEMO-E-00755	DEMO-EST-000755	Ricardo Carolina	Vega Vargas	1995-12-22	\N	estudiante00755@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
761	DEMO-E-00756	DEMO-EST-000756	Patricia Carolina	Vega Romero	2006-03-24	\N	estudiante00756@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
762	DEMO-E-00757	DEMO-EST-000757	Claudia Carolina	Vega Navarro	2001-11-17	\N	estudiante00757@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
763	DEMO-E-00758	DEMO-EST-000758	Lorena Carolina	Vega López	2004-12-27	\N	estudiante00758@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
764	DEMO-E-00759	DEMO-EST-000759	Verónica Carolina	Vega Quispe	2003-10-17	\N	estudiante00759@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
765	DEMO-E-00760	DEMO-EST-000760	Rosa Carolina	Vega Arias	2006-04-19	\N	estudiante00760@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
766	DEMO-E-00761	DEMO-EST-000761	Gabriel Fernanda	Suárez Flores	2006-12-05	\N	estudiante00761@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
767	DEMO-E-00762	DEMO-EST-000762	Mateo Fernanda	Suárez Medina	2004-12-03	\N	estudiante00762@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
768	DEMO-E-00763	DEMO-EST-000763	Daniel Fernanda	Suárez Cabrera	2003-04-03	\N	estudiante00763@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
769	DEMO-E-00764	DEMO-EST-000764	Santiago Fernanda	Suárez Castillo	1997-11-25	\N	estudiante00764@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
770	DEMO-E-00765	DEMO-EST-000765	Samuel Fernanda	Suárez Condori	1999-10-04	\N	estudiante00765@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
771	DEMO-E-00766	DEMO-EST-000766	Diego Fernanda	Suárez Delgado	2006-01-23	\N	estudiante00766@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
772	DEMO-E-00767	DEMO-EST-000767	Nicolás Fernanda	Suárez Aguilar	2002-12-20	\N	estudiante00767@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
773	DEMO-E-00768	DEMO-EST-000768	Adrián Fernanda	Suárez Herrera	2003-03-09	\N	estudiante00768@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
774	DEMO-E-00769	DEMO-EST-000769	Sebastián Fernanda	Suárez Suárez	2003-04-17	\N	estudiante00769@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
775	DEMO-E-00770	DEMO-EST-000770	Alejandro Fernanda	Suárez Valdez	1998-10-06	\N	estudiante00770@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
776	DEMO-E-00771	DEMO-EST-000771	Luis Fernanda	Suárez Choque	2002-01-20	\N	estudiante00771@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
777	DEMO-E-00772	DEMO-EST-000772	Miguel Fernanda	Suárez Molina	2006-12-04	\N	estudiante00772@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
778	DEMO-E-00773	DEMO-EST-000773	Carlos Fernanda	Suárez Salazar	2000-01-03	\N	estudiante00773@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
779	DEMO-E-00774	DEMO-EST-000774	Javier Fernanda	Suárez Paredes	2004-04-16	\N	estudiante00774@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
780	DEMO-E-00775	DEMO-EST-000775	Andrés Fernanda	Suárez Cruz	2000-06-28	\N	estudiante00775@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
781	DEMO-E-00776	DEMO-EST-000776	Valeria Fernanda	Suárez Fernández	2004-12-17	\N	estudiante00776@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
782	DEMO-E-00777	DEMO-EST-000777	Camila Fernanda	Suárez Pinto	2006-08-31	\N	estudiante00777@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
783	DEMO-E-00778	DEMO-EST-000778	Lucía Fernanda	Suárez Rojas	1995-07-12	\N	estudiante00778@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
784	DEMO-E-00779	DEMO-EST-000779	Mariana Fernanda	Suárez Ortega	2006-06-10	\N	estudiante00779@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
785	DEMO-E-00780	DEMO-EST-000780	Daniela Fernanda	Suárez Torres	2002-04-25	\N	estudiante00780@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
786	DEMO-E-00781	DEMO-EST-000781	Sofía Fernanda	Suárez Gutiérrez	2003-01-25	\N	estudiante00781@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
787	DEMO-E-00782	DEMO-EST-000782	Paola Fernanda	Suárez Apaza	1996-10-01	\N	estudiante00782@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
788	DEMO-E-00783	DEMO-EST-000783	Andrea Fernanda	Suárez Montes	1996-02-02	\N	estudiante00783@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
789	DEMO-E-00784	DEMO-EST-000784	Gabriela Fernanda	Suárez Mendoza	2002-03-28	\N	estudiante00784@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
790	DEMO-E-00785	DEMO-EST-000785	Natalia Fernanda	Suárez Soto	1996-08-24	\N	estudiante00785@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
791	DEMO-E-00786	DEMO-EST-000786	Carolina Fernanda	Suárez Vega	1997-05-16	\N	estudiante00786@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
792	DEMO-E-00787	DEMO-EST-000787	Fernanda Fernanda	Suárez Rivera	1999-08-28	\N	estudiante00787@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
793	DEMO-E-00788	DEMO-EST-000788	Isabel Fernanda	Suárez Mamani	2004-03-22	\N	estudiante00788@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
794	DEMO-E-00789	DEMO-EST-000789	Victoria Fernanda	Suárez Villarroel	2003-07-22	\N	estudiante00789@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
795	DEMO-E-00790	DEMO-EST-000790	Elena Fernanda	Suárez Castro	1997-09-20	\N	estudiante00790@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
796	DEMO-E-00791	DEMO-EST-000791	Rodrigo Fernanda	Suárez Morales	2006-08-01	\N	estudiante00791@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
797	DEMO-E-00792	DEMO-EST-000792	Mauricio Fernanda	Suárez Ríos	2000-11-17	\N	estudiante00792@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
798	DEMO-E-00793	DEMO-EST-000793	Eduardo Fernanda	Suárez Escobar	1999-10-17	\N	estudiante00793@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
799	DEMO-E-00794	DEMO-EST-000794	Pablo Fernanda	Suárez Soria	1995-06-11	\N	estudiante00794@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
800	DEMO-E-00795	DEMO-EST-000795	Ricardo Fernanda	Suárez Vargas	2001-10-21	\N	estudiante00795@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
801	DEMO-E-00796	DEMO-EST-000796	Patricia Fernanda	Suárez Romero	2007-05-13	\N	estudiante00796@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
802	DEMO-E-00797	DEMO-EST-000797	Claudia Fernanda	Suárez Navarro	1997-01-08	\N	estudiante00797@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
803	DEMO-E-00798	DEMO-EST-000798	Lorena Fernanda	Suárez López	1995-01-17	\N	estudiante00798@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
804	DEMO-E-00799	DEMO-EST-000799	Verónica Fernanda	Suárez Quispe	2001-08-30	\N	estudiante00799@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
805	DEMO-E-00800	DEMO-EST-000800	Rosa Fernanda	Suárez Arias	2007-05-31	\N	estudiante00800@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
806	DEMO-E-00801	DEMO-EST-000801	Gabriel Isabel	Ríos Flores	2000-02-26	\N	estudiante00801@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
807	DEMO-E-00802	DEMO-EST-000802	Mateo Isabel	Ríos Medina	2006-07-08	\N	estudiante00802@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
808	DEMO-E-00803	DEMO-EST-000803	Daniel Isabel	Ríos Cabrera	1996-03-04	\N	estudiante00803@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
809	DEMO-E-00804	DEMO-EST-000804	Santiago Isabel	Ríos Castillo	2002-09-24	\N	estudiante00804@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
810	DEMO-E-00805	DEMO-EST-000805	Samuel Isabel	Ríos Condori	2003-02-22	\N	estudiante00805@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
811	DEMO-E-00806	DEMO-EST-000806	Diego Isabel	Ríos Delgado	2001-12-31	\N	estudiante00806@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
812	DEMO-E-00807	DEMO-EST-000807	Nicolás Isabel	Ríos Aguilar	1996-03-09	\N	estudiante00807@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
813	DEMO-E-00808	DEMO-EST-000808	Adrián Isabel	Ríos Herrera	2005-02-05	\N	estudiante00808@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
814	DEMO-E-00809	DEMO-EST-000809	Sebastián Isabel	Ríos Suárez	1999-09-01	\N	estudiante00809@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
815	DEMO-E-00810	DEMO-EST-000810	Alejandro Isabel	Ríos Valdez	1998-12-03	\N	estudiante00810@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
816	DEMO-E-00811	DEMO-EST-000811	Luis Isabel	Ríos Choque	2002-09-07	\N	estudiante00811@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
817	DEMO-E-00812	DEMO-EST-000812	Miguel Isabel	Ríos Molina	2001-01-10	\N	estudiante00812@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
818	DEMO-E-00813	DEMO-EST-000813	Carlos Isabel	Ríos Salazar	2000-12-01	\N	estudiante00813@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
819	DEMO-E-00814	DEMO-EST-000814	Javier Isabel	Ríos Paredes	2006-11-22	\N	estudiante00814@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
820	DEMO-E-00815	DEMO-EST-000815	Andrés Isabel	Ríos Cruz	2006-09-18	\N	estudiante00815@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
821	DEMO-E-00816	DEMO-EST-000816	Valeria Isabel	Ríos Fernández	1995-06-18	\N	estudiante00816@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
822	DEMO-E-00817	DEMO-EST-000817	Camila Isabel	Ríos Pinto	1996-06-18	\N	estudiante00817@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
823	DEMO-E-00818	DEMO-EST-000818	Lucía Isabel	Ríos Rojas	2004-01-02	\N	estudiante00818@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
824	DEMO-E-00819	DEMO-EST-000819	Mariana Isabel	Ríos Ortega	2006-06-21	\N	estudiante00819@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
825	DEMO-E-00820	DEMO-EST-000820	Daniela Isabel	Ríos Torres	2001-03-03	\N	estudiante00820@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
826	DEMO-E-00821	DEMO-EST-000821	Sofía Isabel	Ríos Gutiérrez	2004-09-04	\N	estudiante00821@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
827	DEMO-E-00822	DEMO-EST-000822	Paola Isabel	Ríos Apaza	1998-04-07	\N	estudiante00822@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
828	DEMO-E-00823	DEMO-EST-000823	Andrea Isabel	Ríos Montes	2002-09-18	\N	estudiante00823@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
829	DEMO-E-00824	DEMO-EST-000824	Gabriela Isabel	Ríos Mendoza	1996-10-08	\N	estudiante00824@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
830	DEMO-E-00825	DEMO-EST-000825	Natalia Isabel	Ríos Soto	1998-12-28	\N	estudiante00825@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
831	DEMO-E-00826	DEMO-EST-000826	Carolina Isabel	Ríos Vega	2003-11-15	\N	estudiante00826@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
832	DEMO-E-00827	DEMO-EST-000827	Fernanda Isabel	Ríos Rivera	1997-11-01	\N	estudiante00827@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
833	DEMO-E-00828	DEMO-EST-000828	Isabel Isabel	Ríos Mamani	2001-05-02	\N	estudiante00828@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
834	DEMO-E-00829	DEMO-EST-000829	Victoria Isabel	Ríos Villarroel	1995-08-04	\N	estudiante00829@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
835	DEMO-E-00830	DEMO-EST-000830	Elena Isabel	Ríos Castro	2006-01-20	\N	estudiante00830@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
836	DEMO-E-00831	DEMO-EST-000831	Rodrigo Isabel	Ríos Morales	2006-06-03	\N	estudiante00831@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
837	DEMO-E-00832	DEMO-EST-000832	Mauricio Isabel	Ríos Ríos	2000-11-05	\N	estudiante00832@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
838	DEMO-E-00833	DEMO-EST-000833	Eduardo Isabel	Ríos Escobar	2004-10-02	\N	estudiante00833@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
839	DEMO-E-00834	DEMO-EST-000834	Pablo Isabel	Ríos Soria	1995-08-25	\N	estudiante00834@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
840	DEMO-E-00835	DEMO-EST-000835	Ricardo Isabel	Ríos Vargas	1995-03-30	\N	estudiante00835@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
841	DEMO-E-00836	DEMO-EST-000836	Patricia Isabel	Ríos Romero	1998-12-11	\N	estudiante00836@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
842	DEMO-E-00837	DEMO-EST-000837	Claudia Isabel	Ríos Navarro	2005-10-26	\N	estudiante00837@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
843	DEMO-E-00838	DEMO-EST-000838	Lorena Isabel	Ríos López	1997-08-23	\N	estudiante00838@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
844	DEMO-E-00839	DEMO-EST-000839	Verónica Isabel	Ríos Quispe	2004-04-10	\N	estudiante00839@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
845	DEMO-E-00840	DEMO-EST-000840	Rosa Isabel	Ríos Arias	2002-12-21	\N	estudiante00840@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
846	DEMO-E-00841	DEMO-EST-000841	Gabriel Victoria	Cruz Flores	2002-05-24	\N	estudiante00841@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
847	DEMO-E-00842	DEMO-EST-000842	Mateo Victoria	Cruz Medina	2000-01-16	\N	estudiante00842@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
848	DEMO-E-00843	DEMO-EST-000843	Daniel Victoria	Cruz Cabrera	1996-12-20	\N	estudiante00843@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
849	DEMO-E-00844	DEMO-EST-000844	Santiago Victoria	Cruz Castillo	2001-04-12	\N	estudiante00844@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
850	DEMO-E-00845	DEMO-EST-000845	Samuel Victoria	Cruz Condori	1995-02-01	\N	estudiante00845@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
851	DEMO-E-00846	DEMO-EST-000846	Diego Victoria	Cruz Delgado	1998-07-23	\N	estudiante00846@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
852	DEMO-E-00847	DEMO-EST-000847	Nicolás Victoria	Cruz Aguilar	2004-05-31	\N	estudiante00847@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
853	DEMO-E-00848	DEMO-EST-000848	Adrián Victoria	Cruz Herrera	2006-01-06	\N	estudiante00848@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
854	DEMO-E-00849	DEMO-EST-000849	Sebastián Victoria	Cruz Suárez	1999-11-29	\N	estudiante00849@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
855	DEMO-E-00850	DEMO-EST-000850	Alejandro Victoria	Cruz Valdez	1999-01-03	\N	estudiante00850@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
856	DEMO-E-00851	DEMO-EST-000851	Luis Victoria	Cruz Choque	2002-04-08	\N	estudiante00851@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
857	DEMO-E-00852	DEMO-EST-000852	Miguel Victoria	Cruz Molina	1997-02-19	\N	estudiante00852@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
858	DEMO-E-00853	DEMO-EST-000853	Carlos Victoria	Cruz Salazar	2007-04-02	\N	estudiante00853@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
859	DEMO-E-00854	DEMO-EST-000854	Javier Victoria	Cruz Paredes	2005-08-09	\N	estudiante00854@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
860	DEMO-E-00855	DEMO-EST-000855	Andrés Victoria	Cruz Cruz	2000-08-08	\N	estudiante00855@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
861	DEMO-E-00856	DEMO-EST-000856	Valeria Victoria	Cruz Fernández	2003-07-25	\N	estudiante00856@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
862	DEMO-E-00857	DEMO-EST-000857	Camila Victoria	Cruz Pinto	1998-11-15	\N	estudiante00857@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
863	DEMO-E-00858	DEMO-EST-000858	Lucía Victoria	Cruz Rojas	2006-03-22	\N	estudiante00858@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
864	DEMO-E-00859	DEMO-EST-000859	Mariana Victoria	Cruz Ortega	1998-06-18	\N	estudiante00859@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
865	DEMO-E-00860	DEMO-EST-000860	Daniela Victoria	Cruz Torres	1996-04-02	\N	estudiante00860@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
866	DEMO-E-00861	DEMO-EST-000861	Sofía Victoria	Cruz Gutiérrez	2002-08-14	\N	estudiante00861@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
867	DEMO-E-00862	DEMO-EST-000862	Paola Victoria	Cruz Apaza	2007-08-16	\N	estudiante00862@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
868	DEMO-E-00863	DEMO-EST-000863	Andrea Victoria	Cruz Montes	2002-06-25	\N	estudiante00863@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
869	DEMO-E-00864	DEMO-EST-000864	Gabriela Victoria	Cruz Mendoza	2005-08-21	\N	estudiante00864@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
870	DEMO-E-00865	DEMO-EST-000865	Natalia Victoria	Cruz Soto	1997-01-30	\N	estudiante00865@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
871	DEMO-E-00866	DEMO-EST-000866	Carolina Victoria	Cruz Vega	1997-07-13	\N	estudiante00866@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
872	DEMO-E-00867	DEMO-EST-000867	Fernanda Victoria	Cruz Rivera	2002-07-29	\N	estudiante00867@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
873	DEMO-E-00868	DEMO-EST-000868	Isabel Victoria	Cruz Mamani	1998-02-06	\N	estudiante00868@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
874	DEMO-E-00869	DEMO-EST-000869	Victoria Victoria	Cruz Villarroel	2003-11-06	\N	estudiante00869@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
875	DEMO-E-00870	DEMO-EST-000870	Elena Victoria	Cruz Castro	2005-11-21	\N	estudiante00870@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
876	DEMO-E-00871	DEMO-EST-000871	Rodrigo Victoria	Cruz Morales	2000-07-01	\N	estudiante00871@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
877	DEMO-E-00872	DEMO-EST-000872	Mauricio Victoria	Cruz Ríos	1996-02-29	\N	estudiante00872@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
878	DEMO-E-00873	DEMO-EST-000873	Eduardo Victoria	Cruz Escobar	1999-11-20	\N	estudiante00873@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
879	DEMO-E-00874	DEMO-EST-000874	Pablo Victoria	Cruz Soria	2000-12-26	\N	estudiante00874@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
880	DEMO-E-00875	DEMO-EST-000875	Ricardo Victoria	Cruz Vargas	1996-06-18	\N	estudiante00875@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
881	DEMO-E-00876	DEMO-EST-000876	Patricia Victoria	Cruz Romero	2002-08-25	\N	estudiante00876@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
882	DEMO-E-00877	DEMO-EST-000877	Claudia Victoria	Cruz Navarro	2000-11-24	\N	estudiante00877@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
883	DEMO-E-00878	DEMO-EST-000878	Lorena Victoria	Cruz López	1999-06-27	\N	estudiante00878@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
884	DEMO-E-00879	DEMO-EST-000879	Verónica Victoria	Cruz Quispe	2003-08-12	\N	estudiante00879@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
885	DEMO-E-00880	DEMO-EST-000880	Rosa Victoria	Cruz Arias	2000-04-22	\N	estudiante00880@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
886	DEMO-E-00881	DEMO-EST-000881	Gabriel Elena	López Flores	1997-08-16	\N	estudiante00881@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
887	DEMO-E-00882	DEMO-EST-000882	Mateo Elena	López Medina	2007-12-25	\N	estudiante00882@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
888	DEMO-E-00883	DEMO-EST-000883	Daniel Elena	López Cabrera	2002-08-03	\N	estudiante00883@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
889	DEMO-E-00884	DEMO-EST-000884	Santiago Elena	López Castillo	2000-10-05	\N	estudiante00884@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
890	DEMO-E-00885	DEMO-EST-000885	Samuel Elena	López Condori	2004-05-30	\N	estudiante00885@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
891	DEMO-E-00886	DEMO-EST-000886	Diego Elena	López Delgado	1997-03-27	\N	estudiante00886@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
892	DEMO-E-00887	DEMO-EST-000887	Nicolás Elena	López Aguilar	2003-01-04	\N	estudiante00887@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
893	DEMO-E-00888	DEMO-EST-000888	Adrián Elena	López Herrera	2006-10-09	\N	estudiante00888@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
894	DEMO-E-00889	DEMO-EST-000889	Sebastián Elena	López Suárez	2001-09-17	\N	estudiante00889@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
895	DEMO-E-00890	DEMO-EST-000890	Alejandro Elena	López Valdez	1999-11-04	\N	estudiante00890@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
896	DEMO-E-00891	DEMO-EST-000891	Luis Elena	López Choque	1998-05-07	\N	estudiante00891@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
897	DEMO-E-00892	DEMO-EST-000892	Miguel Elena	López Molina	1998-05-06	\N	estudiante00892@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
898	DEMO-E-00893	DEMO-EST-000893	Carlos Elena	López Salazar	2004-06-22	\N	estudiante00893@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
899	DEMO-E-00894	DEMO-EST-000894	Javier Elena	López Paredes	2004-03-13	\N	estudiante00894@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
900	DEMO-E-00895	DEMO-EST-000895	Andrés Elena	López Cruz	2003-12-14	\N	estudiante00895@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
901	DEMO-E-00896	DEMO-EST-000896	Valeria Elena	López Fernández	1999-04-29	\N	estudiante00896@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
902	DEMO-E-00897	DEMO-EST-000897	Camila Elena	López Pinto	1996-05-15	\N	estudiante00897@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
903	DEMO-E-00898	DEMO-EST-000898	Lucía Elena	López Rojas	2002-12-08	\N	estudiante00898@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
904	DEMO-E-00899	DEMO-EST-000899	Mariana Elena	López Ortega	1997-04-05	\N	estudiante00899@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
905	DEMO-E-00900	DEMO-EST-000900	Daniela Elena	López Torres	2007-03-30	\N	estudiante00900@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
906	DEMO-E-00901	DEMO-EST-000901	Sofía Elena	López Gutiérrez	1997-06-18	\N	estudiante00901@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
907	DEMO-E-00902	DEMO-EST-000902	Paola Elena	López Apaza	1996-07-03	\N	estudiante00902@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
908	DEMO-E-00903	DEMO-EST-000903	Andrea Elena	López Montes	1995-10-25	\N	estudiante00903@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
909	DEMO-E-00904	DEMO-EST-000904	Gabriela Elena	López Mendoza	2001-10-16	\N	estudiante00904@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
910	DEMO-E-00905	DEMO-EST-000905	Natalia Elena	López Soto	1998-11-26	\N	estudiante00905@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
911	DEMO-E-00906	DEMO-EST-000906	Carolina Elena	López Vega	1996-01-16	\N	estudiante00906@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
912	DEMO-E-00907	DEMO-EST-000907	Fernanda Elena	López Rivera	1996-12-24	\N	estudiante00907@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
913	DEMO-E-00908	DEMO-EST-000908	Isabel Elena	López Mamani	2002-03-13	\N	estudiante00908@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
914	DEMO-E-00909	DEMO-EST-000909	Victoria Elena	López Villarroel	1995-11-08	\N	estudiante00909@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
915	DEMO-E-00910	DEMO-EST-000910	Elena Elena	López Castro	2004-11-26	\N	estudiante00910@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
916	DEMO-E-00911	DEMO-EST-000911	Rodrigo Elena	López Morales	2007-06-27	\N	estudiante00911@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
917	DEMO-E-00912	DEMO-EST-000912	Mauricio Elena	López Ríos	1995-05-05	\N	estudiante00912@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
918	DEMO-E-00913	DEMO-EST-000913	Eduardo Elena	López Escobar	2001-04-20	\N	estudiante00913@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
919	DEMO-E-00914	DEMO-EST-000914	Pablo Elena	López Soria	2006-08-29	\N	estudiante00914@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
920	DEMO-E-00915	DEMO-EST-000915	Ricardo Elena	López Vargas	1998-12-30	\N	estudiante00915@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
921	DEMO-E-00916	DEMO-EST-000916	Patricia Elena	López Romero	2004-10-21	\N	estudiante00916@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
922	DEMO-E-00917	DEMO-EST-000917	Claudia Elena	López Navarro	2000-05-20	\N	estudiante00917@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
923	DEMO-E-00918	DEMO-EST-000918	Lorena Elena	López López	1999-11-30	\N	estudiante00918@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
924	DEMO-E-00919	DEMO-EST-000919	Verónica Elena	López Quispe	2001-12-20	\N	estudiante00919@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
925	DEMO-E-00920	DEMO-EST-000920	Rosa Elena	López Arias	1999-05-13	\N	estudiante00920@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
926	DEMO-E-00921	DEMO-EST-000921	Gabriel Rodrigo	Gutiérrez Flores	2005-01-15	\N	estudiante00921@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
927	DEMO-E-00922	DEMO-EST-000922	Mateo Rodrigo	Gutiérrez Medina	1998-09-08	\N	estudiante00922@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
928	DEMO-E-00923	DEMO-EST-000923	Daniel Rodrigo	Gutiérrez Cabrera	2007-01-23	\N	estudiante00923@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
929	DEMO-E-00924	DEMO-EST-000924	Santiago Rodrigo	Gutiérrez Castillo	2005-08-16	\N	estudiante00924@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
930	DEMO-E-00925	DEMO-EST-000925	Samuel Rodrigo	Gutiérrez Condori	1999-08-02	\N	estudiante00925@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
931	DEMO-E-00926	DEMO-EST-000926	Diego Rodrigo	Gutiérrez Delgado	1999-02-05	\N	estudiante00926@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
932	DEMO-E-00927	DEMO-EST-000927	Nicolás Rodrigo	Gutiérrez Aguilar	2001-02-16	\N	estudiante00927@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
933	DEMO-E-00928	DEMO-EST-000928	Adrián Rodrigo	Gutiérrez Herrera	2005-11-12	\N	estudiante00928@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
934	DEMO-E-00929	DEMO-EST-000929	Sebastián Rodrigo	Gutiérrez Suárez	2006-01-21	\N	estudiante00929@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
935	DEMO-E-00930	DEMO-EST-000930	Alejandro Rodrigo	Gutiérrez Valdez	2005-07-25	\N	estudiante00930@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
936	DEMO-E-00931	DEMO-EST-000931	Luis Rodrigo	Gutiérrez Choque	2007-01-05	\N	estudiante00931@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
937	DEMO-E-00932	DEMO-EST-000932	Miguel Rodrigo	Gutiérrez Molina	1997-08-17	\N	estudiante00932@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
938	DEMO-E-00933	DEMO-EST-000933	Carlos Rodrigo	Gutiérrez Salazar	2003-03-16	\N	estudiante00933@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
939	DEMO-E-00934	DEMO-EST-000934	Javier Rodrigo	Gutiérrez Paredes	2003-11-30	\N	estudiante00934@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
940	DEMO-E-00935	DEMO-EST-000935	Andrés Rodrigo	Gutiérrez Cruz	2001-03-17	\N	estudiante00935@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
941	DEMO-E-00936	DEMO-EST-000936	Valeria Rodrigo	Gutiérrez Fernández	1999-10-03	\N	estudiante00936@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
942	DEMO-E-00937	DEMO-EST-000937	Camila Rodrigo	Gutiérrez Pinto	1995-02-25	\N	estudiante00937@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
943	DEMO-E-00938	DEMO-EST-000938	Lucía Rodrigo	Gutiérrez Rojas	2000-04-30	\N	estudiante00938@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
944	DEMO-E-00939	DEMO-EST-000939	Mariana Rodrigo	Gutiérrez Ortega	1998-07-06	\N	estudiante00939@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
945	DEMO-E-00940	DEMO-EST-000940	Daniela Rodrigo	Gutiérrez Torres	2005-03-03	\N	estudiante00940@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
946	DEMO-E-00941	DEMO-EST-000941	Sofía Rodrigo	Gutiérrez Gutiérrez	2004-01-20	\N	estudiante00941@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
947	DEMO-E-00942	DEMO-EST-000942	Paola Rodrigo	Gutiérrez Apaza	2006-08-22	\N	estudiante00942@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
948	DEMO-E-00943	DEMO-EST-000943	Andrea Rodrigo	Gutiérrez Montes	2002-06-13	\N	estudiante00943@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
949	DEMO-E-00944	DEMO-EST-000944	Gabriela Rodrigo	Gutiérrez Mendoza	2005-11-10	\N	estudiante00944@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
950	DEMO-E-00945	DEMO-EST-000945	Natalia Rodrigo	Gutiérrez Soto	2003-09-22	\N	estudiante00945@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
951	DEMO-E-00946	DEMO-EST-000946	Carolina Rodrigo	Gutiérrez Vega	2000-11-20	\N	estudiante00946@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
952	DEMO-E-00947	DEMO-EST-000947	Fernanda Rodrigo	Gutiérrez Rivera	2002-04-09	\N	estudiante00947@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
953	DEMO-E-00948	DEMO-EST-000948	Isabel Rodrigo	Gutiérrez Mamani	1996-05-21	\N	estudiante00948@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
954	DEMO-E-00949	DEMO-EST-000949	Victoria Rodrigo	Gutiérrez Villarroel	2000-12-07	\N	estudiante00949@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
955	DEMO-E-00950	DEMO-EST-000950	Elena Rodrigo	Gutiérrez Castro	2003-04-30	\N	estudiante00950@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
956	DEMO-E-00951	DEMO-EST-000951	Rodrigo Rodrigo	Gutiérrez Morales	2005-07-02	\N	estudiante00951@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
957	DEMO-E-00952	DEMO-EST-000952	Mauricio Rodrigo	Gutiérrez Ríos	2003-02-10	\N	estudiante00952@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
958	DEMO-E-00953	DEMO-EST-000953	Eduardo Rodrigo	Gutiérrez Escobar	2003-08-25	\N	estudiante00953@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
959	DEMO-E-00954	DEMO-EST-000954	Pablo Rodrigo	Gutiérrez Soria	1995-07-03	\N	estudiante00954@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
960	DEMO-E-00955	DEMO-EST-000955	Ricardo Rodrigo	Gutiérrez Vargas	2001-11-09	\N	estudiante00955@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
961	DEMO-E-00956	DEMO-EST-000956	Patricia Rodrigo	Gutiérrez Romero	2006-07-26	\N	estudiante00956@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
962	DEMO-E-00957	DEMO-EST-000957	Claudia Rodrigo	Gutiérrez Navarro	2000-09-08	\N	estudiante00957@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
963	DEMO-E-00958	DEMO-EST-000958	Lorena Rodrigo	Gutiérrez López	2002-12-14	\N	estudiante00958@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
964	DEMO-E-00959	DEMO-EST-000959	Verónica Rodrigo	Gutiérrez Quispe	1996-07-01	\N	estudiante00959@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
965	DEMO-E-00960	DEMO-EST-000960	Rosa Rodrigo	Gutiérrez Arias	1996-05-09	\N	estudiante00960@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
966	DEMO-E-00961	DEMO-EST-000961	Gabriel Mauricio	Castillo Flores	2003-06-22	\N	estudiante00961@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
967	DEMO-E-00962	DEMO-EST-000962	Mateo Mauricio	Castillo Medina	2001-05-24	\N	estudiante00962@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
968	DEMO-E-00963	DEMO-EST-000963	Daniel Mauricio	Castillo Cabrera	2000-02-19	\N	estudiante00963@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
969	DEMO-E-00964	DEMO-EST-000964	Santiago Mauricio	Castillo Castillo	2004-08-04	\N	estudiante00964@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
970	DEMO-E-00965	DEMO-EST-000965	Samuel Mauricio	Castillo Condori	2000-02-28	\N	estudiante00965@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
971	DEMO-E-00966	DEMO-EST-000966	Diego Mauricio	Castillo Delgado	2005-04-02	\N	estudiante00966@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
972	DEMO-E-00967	DEMO-EST-000967	Nicolás Mauricio	Castillo Aguilar	1997-06-30	\N	estudiante00967@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
973	DEMO-E-00968	DEMO-EST-000968	Adrián Mauricio	Castillo Herrera	2005-01-23	\N	estudiante00968@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
974	DEMO-E-00969	DEMO-EST-000969	Sebastián Mauricio	Castillo Suárez	1996-03-15	\N	estudiante00969@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
975	DEMO-E-00970	DEMO-EST-000970	Alejandro Mauricio	Castillo Valdez	1999-06-07	\N	estudiante00970@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
976	DEMO-E-00971	DEMO-EST-000971	Luis Mauricio	Castillo Choque	1995-04-17	\N	estudiante00971@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
977	DEMO-E-00972	DEMO-EST-000972	Miguel Mauricio	Castillo Molina	2003-03-28	\N	estudiante00972@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
978	DEMO-E-00973	DEMO-EST-000973	Carlos Mauricio	Castillo Salazar	2006-11-18	\N	estudiante00973@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
979	DEMO-E-00974	DEMO-EST-000974	Javier Mauricio	Castillo Paredes	2001-02-25	\N	estudiante00974@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
980	DEMO-E-00975	DEMO-EST-000975	Andrés Mauricio	Castillo Cruz	1996-06-11	\N	estudiante00975@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
981	DEMO-E-00976	DEMO-EST-000976	Valeria Mauricio	Castillo Fernández	2005-03-27	\N	estudiante00976@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
982	DEMO-E-00977	DEMO-EST-000977	Camila Mauricio	Castillo Pinto	1995-06-28	\N	estudiante00977@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
983	DEMO-E-00978	DEMO-EST-000978	Lucía Mauricio	Castillo Rojas	1999-02-01	\N	estudiante00978@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
984	DEMO-E-00979	DEMO-EST-000979	Mariana Mauricio	Castillo Ortega	2003-01-08	\N	estudiante00979@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
985	DEMO-E-00980	DEMO-EST-000980	Daniela Mauricio	Castillo Torres	2000-08-20	\N	estudiante00980@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
986	DEMO-E-00981	DEMO-EST-000981	Sofía Mauricio	Castillo Gutiérrez	1998-09-20	\N	estudiante00981@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
987	DEMO-E-00982	DEMO-EST-000982	Paola Mauricio	Castillo Apaza	2006-02-05	\N	estudiante00982@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
988	DEMO-E-00983	DEMO-EST-000983	Andrea Mauricio	Castillo Montes	1996-07-11	\N	estudiante00983@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
989	DEMO-E-00984	DEMO-EST-000984	Gabriela Mauricio	Castillo Mendoza	2001-05-23	\N	estudiante00984@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
990	DEMO-E-00985	DEMO-EST-000985	Natalia Mauricio	Castillo Soto	1997-02-06	\N	estudiante00985@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
991	DEMO-E-00986	DEMO-EST-000986	Carolina Mauricio	Castillo Vega	1998-12-05	\N	estudiante00986@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
992	DEMO-E-00987	DEMO-EST-000987	Fernanda Mauricio	Castillo Rivera	1999-01-03	\N	estudiante00987@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
993	DEMO-E-00988	DEMO-EST-000988	Isabel Mauricio	Castillo Mamani	2001-05-20	\N	estudiante00988@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
994	DEMO-E-00989	DEMO-EST-000989	Victoria Mauricio	Castillo Villarroel	2000-07-30	\N	estudiante00989@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
995	DEMO-E-00990	DEMO-EST-000990	Elena Mauricio	Castillo Castro	2000-11-07	\N	estudiante00990@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
996	DEMO-E-00991	DEMO-EST-000991	Rodrigo Mauricio	Castillo Morales	1996-04-16	\N	estudiante00991@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
997	DEMO-E-00992	DEMO-EST-000992	Mauricio Mauricio	Castillo Ríos	1998-11-18	\N	estudiante00992@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
998	DEMO-E-00993	DEMO-EST-000993	Eduardo Mauricio	Castillo Escobar	1996-10-01	\N	estudiante00993@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
999	DEMO-E-00994	DEMO-EST-000994	Pablo Mauricio	Castillo Soria	2002-09-16	\N	estudiante00994@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
1000	DEMO-E-00995	DEMO-EST-000995	Ricardo Mauricio	Castillo Vargas	2002-04-04	\N	estudiante00995@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
1001	DEMO-E-00996	DEMO-EST-000996	Patricia Mauricio	Castillo Romero	1997-11-06	\N	estudiante00996@example.invalid	Dirección ficticia de demostración	2026-10-30 00:43:10
\.


--
-- Data for Name: evaluaciones; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.evaluaciones (id, oferta_id, nombre, componente, peso) FROM stdin;
1	1	Práctica integral	PRACTICA	100.000
2	1	Evaluación teórica	TEORIA	100.000
3	2	Práctica integral	PRACTICA	100.000
4	2	Evaluación teórica	TEORIA	100.000
5	3	Práctica integral	PRACTICA	100.000
6	3	Evaluación teórica	TEORIA	100.000
7	4	Práctica integral	PRACTICA	100.000
8	4	Evaluación teórica	TEORIA	100.000
9	5	Práctica integral	PRACTICA	100.000
10	5	Evaluación teórica	TEORIA	100.000
11	6	Práctica integral	PRACTICA	100.000
12	6	Evaluación teórica	TEORIA	100.000
13	7	Práctica integral	PRACTICA	100.000
14	7	Evaluación teórica	TEORIA	100.000
15	8	Práctica integral	PRACTICA	100.000
16	8	Evaluación teórica	TEORIA	100.000
17	9	Práctica integral	PRACTICA	100.000
18	9	Evaluación teórica	TEORIA	100.000
19	10	Práctica integral	PRACTICA	100.000
20	10	Evaluación teórica	TEORIA	100.000
21	11	Práctica integral	PRACTICA	100.000
22	11	Evaluación teórica	TEORIA	100.000
23	12	Práctica integral	PRACTICA	100.000
24	12	Evaluación teórica	TEORIA	100.000
\.


--
-- Data for Name: excepciones_asistencia; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.excepciones_asistencia (inscripcion_id, documento, resolucion, aprobada_por, fecha) FROM stdin;
\.


--
-- Data for Name: grupo_integrantes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.grupo_integrantes (id, grupo_id, matricula_id, fecha) FROM stdin;
1	1	1	2026-10-30 19:55:37
2	1	2	2026-10-30 19:55:37
3	1	3	2026-10-30 19:55:37
4	1	4	2026-10-30 19:55:37
5	1	5	2026-10-30 19:55:37
6	1	6	2026-10-30 19:55:37
7	1	7	2026-10-30 19:55:37
8	1	8	2026-10-30 19:55:37
9	1	9	2026-10-30 19:55:37
10	1	10	2026-10-30 19:55:37
11	1	11	2026-10-30 19:55:37
12	1	12	2026-10-30 19:55:37
13	1	13	2026-10-30 19:55:37
14	1	14	2026-10-30 19:55:37
15	1	15	2026-10-30 19:55:37
16	1	16	2026-10-30 19:55:37
17	1	17	2026-10-30 19:55:37
18	1	18	2026-10-30 19:55:37
19	1	19	2026-10-30 19:55:37
20	1	20	2026-10-30 19:55:37
21	1	21	2026-10-30 19:55:37
22	1	22	2026-10-30 19:55:37
23	1	23	2026-10-30 19:55:37
24	1	24	2026-10-30 19:55:37
25	1	25	2026-10-30 19:55:37
26	1	26	2026-10-30 19:55:37
27	1	27	2026-10-30 19:55:37
28	1	28	2026-10-30 19:55:37
29	1	29	2026-10-30 19:55:37
30	1	30	2026-10-30 19:55:37
31	2	31	2026-10-30 19:55:37
32	2	32	2026-10-30 19:55:37
33	2	33	2026-10-30 19:55:37
34	2	34	2026-10-30 19:55:37
35	2	35	2026-10-30 19:55:37
36	2	36	2026-10-30 19:55:37
37	2	37	2026-10-30 19:55:37
38	2	38	2026-10-30 19:55:37
39	2	39	2026-10-30 19:55:37
40	2	40	2026-10-30 19:55:37
41	2	41	2026-10-30 19:55:37
42	2	42	2026-10-30 19:55:37
43	2	43	2026-10-30 19:55:37
44	2	44	2026-10-30 19:55:37
45	2	45	2026-10-30 19:55:37
46	2	46	2026-10-30 19:55:37
47	2	47	2026-10-30 19:55:37
48	2	48	2026-10-30 19:55:37
49	2	49	2026-10-30 19:55:37
50	2	50	2026-10-30 19:55:37
\.


--
-- Data for Name: grupo_materias; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.grupo_materias (id, grupo_id, oferta_id) FROM stdin;
1	1	1
2	1	2
3	1	3
4	2	4
5	2	5
6	2	6
7	3	7
8	3	8
9	3	9
10	4	10
11	4	11
12	4	12
\.


--
-- Data for Name: grupos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.grupos (id, periodo_id, carrera_id, curso, paralelo, turno, cupo, tutor_id, estado) FROM stdin;
1	1	1	1	A	MAÑANA	35	1	ACTIVO
2	1	2	1	A	NOCHE	30	2	ACTIVO
3	2	1	1	A	MAÑANA	35	1	ACTIVO
4	2	3	1	B	TARDE	25	3	ACTIVO
\.


--
-- Data for Name: horarios; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.horarios (id, oferta_id, aula_id, dia, hora_inicio, hora_fin) FROM stdin;
1	1	3	1	08:00:00	09:40:00
2	2	3	2	08:00:00	09:40:00
3	3	3	3	08:00:00	09:40:00
4	4	2	1	19:00:00	20:40:00
5	5	2	2	19:00:00	20:40:00
6	6	2	3	19:00:00	20:40:00
7	7	3	1	08:00:00	09:40:00
8	8	3	2	08:00:00	09:40:00
9	9	3	3	08:00:00	09:40:00
10	10	4	1	14:00:00	15:40:00
11	11	4	2	14:00:00	15:40:00
12	12	4	3	14:00:00	15:40:00
\.


--
-- Data for Name: inscripciones; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inscripciones (id, matricula_id, oferta_id, carrera_id, periodo_id, fecha, estado) FROM stdin;
1	1	1	1	1	2026-02-02	ACTIVA
2	1	2	1	1	2026-02-02	ACTIVA
3	1	3	1	1	2026-02-02	ACTIVA
4	2	1	1	1	2026-02-02	ACTIVA
5	2	2	1	1	2026-02-02	ACTIVA
6	2	3	1	1	2026-02-02	ACTIVA
7	3	1	1	1	2026-02-02	ACTIVA
8	3	2	1	1	2026-02-02	ACTIVA
9	3	3	1	1	2026-02-02	ACTIVA
10	4	1	1	1	2026-02-02	ACTIVA
11	4	2	1	1	2026-02-02	ACTIVA
12	4	3	1	1	2026-02-02	ACTIVA
13	5	1	1	1	2026-02-02	ACTIVA
14	5	2	1	1	2026-02-02	ACTIVA
15	5	3	1	1	2026-02-02	ACTIVA
16	6	1	1	1	2026-02-02	ACTIVA
17	6	2	1	1	2026-02-02	ACTIVA
18	6	3	1	1	2026-02-02	ACTIVA
19	7	1	1	1	2026-02-02	ACTIVA
20	7	2	1	1	2026-02-02	ACTIVA
21	7	3	1	1	2026-02-02	ACTIVA
22	8	1	1	1	2026-02-02	ACTIVA
23	8	2	1	1	2026-02-02	ACTIVA
24	8	3	1	1	2026-02-02	ACTIVA
25	9	1	1	1	2026-02-02	ACTIVA
26	9	2	1	1	2026-02-02	ACTIVA
27	9	3	1	1	2026-02-02	ACTIVA
28	10	1	1	1	2026-02-02	ACTIVA
29	10	2	1	1	2026-02-02	ACTIVA
30	10	3	1	1	2026-02-02	ACTIVA
31	11	1	1	1	2026-02-02	ACTIVA
32	11	2	1	1	2026-02-02	ACTIVA
33	11	3	1	1	2026-02-02	ACTIVA
34	12	1	1	1	2026-02-02	ACTIVA
35	12	2	1	1	2026-02-02	ACTIVA
36	12	3	1	1	2026-02-02	ACTIVA
37	13	1	1	1	2026-02-02	ACTIVA
38	13	2	1	1	2026-02-02	ACTIVA
39	13	3	1	1	2026-02-02	ACTIVA
40	14	1	1	1	2026-02-02	ACTIVA
41	14	2	1	1	2026-02-02	ACTIVA
42	14	3	1	1	2026-02-02	ACTIVA
43	15	1	1	1	2026-02-02	ACTIVA
44	15	2	1	1	2026-02-02	ACTIVA
45	15	3	1	1	2026-02-02	ACTIVA
46	16	1	1	1	2026-02-02	ACTIVA
47	16	2	1	1	2026-02-02	ACTIVA
48	16	3	1	1	2026-02-02	ACTIVA
49	17	1	1	1	2026-02-02	ACTIVA
50	17	2	1	1	2026-02-02	ACTIVA
51	17	3	1	1	2026-02-02	ACTIVA
52	18	1	1	1	2026-02-02	ACTIVA
53	18	2	1	1	2026-02-02	ACTIVA
54	18	3	1	1	2026-02-02	ACTIVA
55	19	1	1	1	2026-02-02	ACTIVA
56	19	2	1	1	2026-02-02	ACTIVA
57	19	3	1	1	2026-02-02	ACTIVA
58	20	1	1	1	2026-02-02	ACTIVA
59	20	2	1	1	2026-02-02	ACTIVA
60	20	3	1	1	2026-02-02	ACTIVA
61	21	1	1	1	2026-02-02	ACTIVA
62	21	2	1	1	2026-02-02	ACTIVA
63	21	3	1	1	2026-02-02	ACTIVA
64	22	1	1	1	2026-02-02	ACTIVA
65	22	2	1	1	2026-02-02	ACTIVA
66	22	3	1	1	2026-02-02	ACTIVA
67	23	1	1	1	2026-02-02	ACTIVA
68	23	2	1	1	2026-02-02	ACTIVA
69	23	3	1	1	2026-02-02	ACTIVA
70	24	1	1	1	2026-02-02	ACTIVA
71	24	2	1	1	2026-02-02	ACTIVA
72	24	3	1	1	2026-02-02	ACTIVA
73	25	1	1	1	2026-02-02	ACTIVA
74	25	2	1	1	2026-02-02	ACTIVA
75	25	3	1	1	2026-02-02	ACTIVA
76	26	1	1	1	2026-02-02	ACTIVA
77	26	2	1	1	2026-02-02	ACTIVA
78	26	3	1	1	2026-02-02	ACTIVA
79	27	1	1	1	2026-02-02	ACTIVA
80	27	2	1	1	2026-02-02	ACTIVA
81	27	3	1	1	2026-02-02	ACTIVA
82	28	1	1	1	2026-02-02	ACTIVA
83	28	2	1	1	2026-02-02	ACTIVA
84	28	3	1	1	2026-02-02	ACTIVA
85	29	1	1	1	2026-02-02	ACTIVA
86	29	2	1	1	2026-02-02	ACTIVA
87	29	3	1	1	2026-02-02	ACTIVA
88	30	1	1	1	2026-02-02	ACTIVA
89	30	2	1	1	2026-02-02	ACTIVA
90	30	3	1	1	2026-02-02	ACTIVA
91	31	4	2	1	2026-02-02	ACTIVA
92	31	5	2	1	2026-02-02	ACTIVA
93	31	6	2	1	2026-02-02	ACTIVA
94	32	4	2	1	2026-02-02	ACTIVA
95	32	5	2	1	2026-02-02	ACTIVA
96	32	6	2	1	2026-02-02	ACTIVA
97	33	4	2	1	2026-02-02	ACTIVA
98	33	5	2	1	2026-02-02	ACTIVA
99	33	6	2	1	2026-02-02	ACTIVA
100	34	4	2	1	2026-02-02	ACTIVA
101	34	5	2	1	2026-02-02	ACTIVA
102	34	6	2	1	2026-02-02	ACTIVA
103	35	4	2	1	2026-02-02	ACTIVA
104	35	5	2	1	2026-02-02	ACTIVA
105	35	6	2	1	2026-02-02	ACTIVA
106	36	4	2	1	2026-02-02	ACTIVA
107	36	5	2	1	2026-02-02	ACTIVA
108	36	6	2	1	2026-02-02	ACTIVA
109	37	4	2	1	2026-02-02	ACTIVA
110	37	5	2	1	2026-02-02	ACTIVA
111	37	6	2	1	2026-02-02	ACTIVA
112	38	4	2	1	2026-02-02	ACTIVA
113	38	5	2	1	2026-02-02	ACTIVA
114	38	6	2	1	2026-02-02	ACTIVA
115	39	4	2	1	2026-02-02	ACTIVA
116	39	5	2	1	2026-02-02	ACTIVA
117	39	6	2	1	2026-02-02	ACTIVA
118	40	4	2	1	2026-02-02	ACTIVA
119	40	5	2	1	2026-02-02	ACTIVA
120	40	6	2	1	2026-02-02	ACTIVA
121	41	4	2	1	2026-02-02	ACTIVA
122	41	5	2	1	2026-02-02	ACTIVA
123	41	6	2	1	2026-02-02	ACTIVA
124	42	4	2	1	2026-02-02	ACTIVA
125	42	5	2	1	2026-02-02	ACTIVA
126	42	6	2	1	2026-02-02	ACTIVA
127	43	4	2	1	2026-02-02	ACTIVA
128	43	5	2	1	2026-02-02	ACTIVA
129	43	6	2	1	2026-02-02	ACTIVA
130	44	4	2	1	2026-02-02	ACTIVA
131	44	5	2	1	2026-02-02	ACTIVA
132	44	6	2	1	2026-02-02	ACTIVA
133	45	4	2	1	2026-02-02	ACTIVA
134	45	5	2	1	2026-02-02	ACTIVA
135	45	6	2	1	2026-02-02	ACTIVA
136	46	4	2	1	2026-02-02	ACTIVA
137	46	5	2	1	2026-02-02	ACTIVA
138	46	6	2	1	2026-02-02	ACTIVA
139	47	4	2	1	2026-02-02	ACTIVA
140	47	5	2	1	2026-02-02	ACTIVA
141	47	6	2	1	2026-02-02	ACTIVA
142	48	4	2	1	2026-02-02	ACTIVA
143	48	5	2	1	2026-02-02	ACTIVA
144	48	6	2	1	2026-02-02	ACTIVA
145	49	4	2	1	2026-02-02	ACTIVA
146	49	5	2	1	2026-02-02	ACTIVA
147	49	6	2	1	2026-02-02	ACTIVA
148	50	4	2	1	2026-02-02	ACTIVA
149	50	5	2	1	2026-02-02	ACTIVA
150	50	6	2	1	2026-02-02	ACTIVA
\.


--
-- Data for Name: materias; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.materias (id, carrera_id, codigo, nombre, nivel_curso, horas_semanales, fuente_url) FROM stdin;
1	1	MPI-101	MATEMÁTICA PARA LA INFORMÁTICA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=155
2	1	PRG-102	PROGRAMACIÓN I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=155
3	1	INT-103	INGLES TÉCNICO	1	\N	https://www.itsc.edu.bo/index.php?Itemid=155
4	1	HDC-104	HARDWARE DE COMPUTADORAS	1	\N	https://www.itsc.edu.bo/index.php?Itemid=155
5	1	TSO-105	TALLLER DE SISTEMAS OPERATIVOS	1	\N	https://www.itsc.edu.bo/index.php?Itemid=155
6	1	OTM-106	OFIMATICA Y TECNOLOGÍA MULTIMEDIA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=155
7	1	DPW-107	DISEÑO Y PROGRAMACIÓN WEB I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=155
8	1	ETD-201	ESTADÍSTICA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
9	1	PRG-202	PROGRAMACIÓN II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
10	1	EDD-203	ESTRUCTURA DE DATOS	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
11	1	RDC-204	REDES DE COMPUTADORAS I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
12	1	PDM-205	PROGRAMACIÓN PARA DISPOSITIVOS MÓVILES I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
13	1	ADS-206	ANÁLISIS Y DISEÑO DE SISTEMAS I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
14	1	DPW-207	DISEÑO Y PROGRAMACIÓN WEB II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
15	1	BDD-208	BASE DE DATOS I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=155
16	1	EMP-301	EMPRENDIMIENTO PRODUCTIVO	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
17	1	DPW-302	DISEÑO Y PROGRAMACIÓN WEB III	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
18	1	GMC-303	GESTIÓN Y MEJORAMIENTO DE LA CALIDAD DEL SOFTWARE	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
19	1	RDC-304	REDES DE COMPUTADORAS II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
20	1	TMG-305	TALLER MODALIDAD DE GRADUACIÓN	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
21	1	ADS-306	ANÁLISIS Y DISEÑO DE SISTEMAS II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
22	1	PDM-307	PROGRAMACIÓN PARA DISPOSITIVOS MÓVILES II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
23	1	BDD-308	BASE DE DATOS II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=155
24	2	CON-101	CONTABILIDAD I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
25	2	MAF-102	MATEMÁTICA FINANCIERA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
26	2	ICO-103	INFORMÁTICA CONTABLE	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
27	2	ADG-104	ADMINISTRACION GENERAL	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
28	2	LSA-105	LEGISLACION LABORAL Y SEGURIDAD SOCIAL APLICADA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
29	2	EGA-106	ECONOMIA GENERAL APLICADA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
30	2	DCM-107	DOCUMENTOS COMERCIALES Y MERCANTILES	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
31	2	ESA-108	ESTADISTICA APLICADA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
32	2	INT-109	INGLES TECNICO	1	\N	https://www.itsc.edu.bo/index.php?Itemid=156
33	2	CON-201	CONTABILIDAD II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=156
34	2	COC-202	CONTABILIDAD DE COSTOS I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=156
35	2	COS-203	CONTABILIDAD DE SOCIEDADES	2	\N	https://www.itsc.edu.bo/index.php?Itemid=156
36	2	CDS-204	CONTABILIDAD DE SEGUROS	2	\N	https://www.itsc.edu.bo/index.php?Itemid=156
37	2	CBC-205	CONTABILIDAD BANCARIA Y COOPERATIVAS	2	\N	https://www.itsc.edu.bo/index.php?Itemid=156
38	2	EMP-206	EMPRENDIMIENTO PRODUCTIVO	2	\N	https://www.itsc.edu.bo/index.php?Itemid=156
39	2	SIT-207	SISTEMA TRIBUTARIO	2	\N	https://www.itsc.edu.bo/index.php?Itemid=156
40	2	COA-301	CONTABILIDAD AGROPECUARIA	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
41	2	COC-302	CONTABILIDAD DE COSTOS II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
42	2	COG-303	CONTABILIAD GUBERNAMENTAL	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
43	2	CEP-304	CONTABILIDAD EXTRACTIVA (MINERA, PETROLERA Y FORESTAL)	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
44	2	CHS-305	CONTABILIDAD DE SERVICIOS (CONSTRUCCION, HOTELERIA Y TRANSPORTE)	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
45	2	GCI-306	GABINETE CONTABLE INFORMATICO	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
46	2	AEF-307	ANALISIS E INTERPRETACIONES DE ESTADOS FINANCIEROS	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
47	2	TMG-308	TALLER DE MODALIDAD DE GRADUACION	3	\N	https://www.itsc.edu.bo/index.php?Itemid=156
48	3	SIM-100	SEGURIDAD OCUPACIONAL Y MEDIO AMBIENTE	1	\N	https://www.itsc.edu.bo/index.php?Itemid=160
49	3	CEL-100	CIRCUITOS ELECTRICOS Y LABORATORIO I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=160
50	3	IET-100	INSTALACIONES ELECTRICAS Y TALLER I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=160
51	3	DIE-100	DIBUJO DE ESPECIALIDAD	1	\N	https://www.itsc.edu.bo/index.php?Itemid=160
52	3	TEM-100	TALLER ELECTROMECANICO	1	\N	https://www.itsc.edu.bo/index.php?Itemid=160
53	3	MAA-100	MATEMATICA APLICADA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=160
54	3	CEL-200	CIRCUITOS ELECTRICOS Y LABORATORIO II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=160
55	3	IET-200	INSTALACIONES ELECTRICAS Y TALLER II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=160
56	3	MLT-200	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=160
57	3	FIA-200	FISICA APLICADA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=160
58	3	INT-200	INGLES TECNICO I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=160
59	3	AUE-300	AUTOMATISMOS ELECTRICOS I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=160
60	3	INM-300	INSTRUMENTACION Y MEDIDAS	3	\N	https://www.itsc.edu.bo/index.php?Itemid=160
61	3	MLT-300	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=160
62	3	ELA-300	ELECTRONICA ANALOGICA	3	\N	https://www.itsc.edu.bo/index.php?Itemid=160
63	3	ENA-300	ENERGIAS ALTERNATIVAS I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=160
64	3	EDA-300	ELECTRICIDAD DEL AUTOMOVIL	3	\N	https://www.itsc.edu.bo/index.php?Itemid=160
65	3	EMP-300	EMPRENDIMIENTO PRODUCTIVO I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=160
66	3	AUE-400	AUTOMATISMOS ELECTRICOS II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=160
67	3	CEE-400	CENTRALES ELECTRICAS	4	\N	https://www.itsc.edu.bo/index.php?Itemid=160
68	3	MLT-400	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER III	4	\N	https://www.itsc.edu.bo/index.php?Itemid=160
69	3	ELD-400	ELECTRONICA DIGITAL	4	\N	https://www.itsc.edu.bo/index.php?Itemid=160
70	3	ENA-400	ENERGIAS ALTERNATIVAS II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=160
71	3	SIR-400	SISTEMAS DE REFRIGERACION	4	\N	https://www.itsc.edu.bo/index.php?Itemid=160
72	3	EMP-400	EMPRENDIMIENTO PRODUCTIVO II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=160
73	3	CLP-500	CONTROLADORES LOGICOS PROGRAMABLES	5	\N	https://www.itsc.edu.bo/index.php?Itemid=160
74	3	RED-500	REDES DE DISTRIBUCION	5	\N	https://www.itsc.edu.bo/index.php?Itemid=160
75	3	MLT-500	MAQUINAS ELECTRICAS, LABORATORIO Y TALLER IV	5	\N	https://www.itsc.edu.bo/index.php?Itemid=160
76	3	ELP-500	ELECTRONICA DE POTENCIA	5	\N	https://www.itsc.edu.bo/index.php?Itemid=160
77	3	REI-500	REFRIGERACION INDUSTRIAL	5	\N	https://www.itsc.edu.bo/index.php?Itemid=160
78	3	TMG-500	TALLER DE MODADLIDAD DE GRADUACION I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=160
79	3	SIS-600	SISTEMAS SCADA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=160
80	3	ELN-600	ELECTRONEUMATICA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=160
81	3	LIT-600	LINEAS DE TRANSMISION	6	\N	https://www.itsc.edu.bo/index.php?Itemid=160
82	3	SUP-600	SUBESTACIONES DE POTENCIA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=160
83	3	MCC-600	MICROCONTROLADORES	6	\N	https://www.itsc.edu.bo/index.php?Itemid=160
84	3	TMG-600	TALLER DE MODADLIDAD DE GRADUACION II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=160
85	4	QCG-100	QUÍMICA GENERAL I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=157
86	4	QCO-100	QUÍMICA ORGÁNICA I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=157
87	4	EPQ-100	ELABORACIÓN DE PRODUCTOS QUÍMICOS I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=157
88	4	FIA-100	FÍSICA APLICADA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=157
89	4	MAA-100	MATEMÁTICA APLICADA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=157
90	4	INT-100	INGLÉS TÉCNCIO I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=157
91	4	HSI-200	HIGIENE, SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE	2	\N	https://www.itsc.edu.bo/index.php?Itemid=157
92	4	QCG-200	QUÍMICA GENERAL II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=157
93	4	QCO-200	QUÍMICA ORGÁNICA II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=157
94	4	QCI-200	QUÍMICA INORGÁNICA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=157
95	4	EDE-200	ESTADISTICA APLICADA Y DISEÑO DE EXPERIMENTOS	2	\N	https://www.itsc.edu.bo/index.php?Itemid=157
96	4	INT-200	INGLÉS TÉCNCIO II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=157
97	4	ANQ-300	ANÁLISIS QUÍMICO I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=157
98	4	EPQ-300	ELABORACIÓN DE PRODUCTOS QUÍMICOS II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=157
99	4	BMI-300	BROMATOLOGÍA Y MICROBIOLOGÍA INDUSTRIAL I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=157
100	4	ELQ-300	ELECTROQUÍMICA	3	\N	https://www.itsc.edu.bo/index.php?Itemid=157
101	4	FIQ-300	FISICOQUÍMICA APLICADA	3	\N	https://www.itsc.edu.bo/index.php?Itemid=157
102	4	EMP-300	EMPRENDIMIENTO PRODUCTIVO I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=157
103	4	ANQ-400	ANÁLISIS QUÍMICO II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=157
104	4	BMI-400	BROMATOLOGÍA Y MICROBIOLOGÍA INDUSTRIAL II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=157
105	4	OPU-400	OPERACIONES UNITARIAS I	4	\N	https://www.itsc.edu.bo/index.php?Itemid=157
106	4	TDI-400	TERMODINÁMICA INDUSTRIAL	4	\N	https://www.itsc.edu.bo/index.php?Itemid=157
107	4	INC-400	INSTRUMENTACION Y CONTROL	4	\N	https://www.itsc.edu.bo/index.php?Itemid=157
108	4	EMP-400	EMPRENDIMIENTO PRODUCTIVO II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=157
109	4	AAI-500	ANÁLISIS APLICADO INORGÁNICO	5	\N	https://www.itsc.edu.bo/index.php?Itemid=157
110	4	ANI-500	ANALISIS INSTRUMENTAL I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=157
111	4	CCI-500	CONTROL DE CALIDAD EN LA INDUSTRIA	5	\N	https://www.itsc.edu.bo/index.php?Itemid=157
112	4	OPU-500	OPERACIONES UNITARIAS II	5	\N	https://www.itsc.edu.bo/index.php?Itemid=157
113	4	PQI-500	PROCESOS QUÍMICOS ORGANICOS E INORGÁNICOS	5	\N	https://www.itsc.edu.bo/index.php?Itemid=157
114	4	AAO-600	ANALISIS APLICADO ORGÁNICO	6	\N	https://www.itsc.edu.bo/index.php?Itemid=157
115	4	ANI-600	ANALISIS INSTRUMENTAL II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=157
116	4	TPG-600	TECNOLOGÍA DEL PETROLEO Y GAS	6	\N	https://www.itsc.edu.bo/index.php?Itemid=157
117	4	OPU-600	OPERACIONES UNITARIAS III	6	\N	https://www.itsc.edu.bo/index.php?Itemid=157
118	4	TMG-600	TALLER DE MODALIDAD DE GRADUCIÓN	6	\N	https://www.itsc.edu.bo/index.php?Itemid=157
119	5	SMA-100	SEGURIDAD OCUPACIONAL Y MEDIO AMBIENTE	1	\N	https://www.itsc.edu.bo/index.php?Itemid=158
120	5	FAL-100	FISICA APLICADA Y LABORATORIO	1	\N	https://www.itsc.edu.bo/index.php?Itemid=158
121	5	DIC-100	DIBUJO TECNICO Y CAD	1	\N	https://www.itsc.edu.bo/index.php?Itemid=158
122	5	MAM-100	MATEMATICA APLICADA A LA MECANICA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=158
123	5	MEI-100	METROLOGIA INDUSTRIAL	1	\N	https://www.itsc.edu.bo/index.php?Itemid=158
124	5	TTM-100	TECNOLOGIA Y TALLER MECANICO I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=158
125	5	ELE-200	ELECTROTECNIA Y ELECTRONICA BASICA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=158
126	5	DCM-200	DIBUJO MECANICO EN CAD	2	\N	https://www.itsc.edu.bo/index.php?Itemid=158
127	5	SOL-200	SOLDADURA INDUSTRIAL I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=158
128	5	TTM-200	TECNOLOGIA Y TALLER MECANICO II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=158
129	5	TTT-200	TRATAMIENTO TERMICO Y TECNOLOGIA DE LOS MATERIALES	2	\N	https://www.itsc.edu.bo/index.php?Itemid=158
130	5	AEC-300	AUTOMATISMOS ELECTRICOS Y CONTROL	3	\N	https://www.itsc.edu.bo/index.php?Itemid=158
131	5	REM-300	RESISTENCIA DE MATERIALES	3	\N	https://www.itsc.edu.bo/index.php?Itemid=158
132	5	TTM-300	TECNOLOGIA Y TALLER MECANICO III	3	\N	https://www.itsc.edu.bo/index.php?Itemid=158
133	5	SOL-300	SOLDADURA INDUSTRIAL II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=158
134	5	MOC-300	MODELADO EN CAD	3	\N	https://www.itsc.edu.bo/index.php?Itemid=158
135	5	INT-400	INGLES TECNICO	4	\N	https://www.itsc.edu.bo/index.php?Itemid=158
136	5	EMM-400	ELEMENTOS Y MECANISMOS DE MAQUINAS	4	\N	https://www.itsc.edu.bo/index.php?Itemid=158
137	5	NEH-400	NEUMATICA E HIDRAULICA	4	\N	https://www.itsc.edu.bo/index.php?Itemid=158
138	5	TTM-400	TECNOLIGIA Y TALLER MECANICO IV	4	\N	https://www.itsc.edu.bo/index.php?Itemid=158
139	5	SOL-400	SOLDADURA INDUSTRIAL III	4	\N	https://www.itsc.edu.bo/index.php?Itemid=158
140	5	CNC-400	CONTROL NUMERICO COMPUTARIZADO I	4	\N	https://www.itsc.edu.bo/index.php?Itemid=158
141	5	ENH-500	ELECTRONEUMATICA - ELECTROHIDRAULICA	5	\N	https://www.itsc.edu.bo/index.php?Itemid=158
142	5	CNC-500	CONTROL NUMERICO COMPUTARIZADO II	5	\N	https://www.itsc.edu.bo/index.php?Itemid=158
143	5	SOL-500	SOLDADURA INDUSTRIAL IV	5	\N	https://www.itsc.edu.bo/index.php?Itemid=158
144	5	DIM-500	DISEÑO DE MAQUINAS	5	\N	https://www.itsc.edu.bo/index.php?Itemid=158
145	5	PPM-500	PROCESOS DE MANUFACTURA Y MATRICERIA	5	\N	https://www.itsc.edu.bo/index.php?Itemid=158
146	5	EMP-500	EMPRENDIMIENTO PRODUCTIVO I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=158
147	5	TMG-500	TALLER DE MODALIDAD DE GRADUACION I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=158
148	5	AII-600	AUTOMATIZACION E INSTRUMENTACION INDUSTRIAL	6	\N	https://www.itsc.edu.bo/index.php?Itemid=158
149	5	SMR-600	SISTEMAS MECATRONICOS Y ROBOTICA INDUSTRIAL	6	\N	https://www.itsc.edu.bo/index.php?Itemid=158
150	5	MEI-600	MANTENIMIENTO DE EQUIPOS INDUSTRIALES	6	\N	https://www.itsc.edu.bo/index.php?Itemid=158
151	5	ESM-600	ESTRUCTURAS METALICAS	6	\N	https://www.itsc.edu.bo/index.php?Itemid=158
152	5	MCM-600	MANUFACTURA Y CONSTRUCCION DE MAQUINAS	6	\N	https://www.itsc.edu.bo/index.php?Itemid=158
153	5	EMP-600	EMPRENDIMIENTO PRODUCTIVO II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=158
154	5	TMG-600	TALLER DE MODALIDAD DE GRADUACION II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=158
155	6	SOM-100	SEGURIDAD OCUPACIONAL Y MEDIO AMBIENTE	1	\N	https://www.itsc.edu.bo/index.php?Itemid=159
156	6	MOG-100	MOTORES A GASOLINA I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=159
157	6	ELA-100	ELECTRICIDAD AUTOMOTRIZ I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=159
158	6	MAA-100	MATEMATICA AUTOMOTRIZ	1	\N	https://www.itsc.edu.bo/index.php?Itemid=159
159	6	MEA-100	METROLOGIA AUTOMOTRIZ	1	\N	https://www.itsc.edu.bo/index.php?Itemid=159
160	6	DTA-100	DIBUJO TECNICO AUTOMOTRIZ I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=159
161	6	QUA-100	QUIMICA AUTOMOTRIZ	1	\N	https://www.itsc.edu.bo/index.php?Itemid=159
162	6	INT-200	INGLES TECNICO	2	\N	https://www.itsc.edu.bo/index.php?Itemid=159
163	6	MOG-200	MOTORES A GASOLINA II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=159
164	6	ELA-200	ELECTRICIDAD AUTOMOTRIZ II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=159
165	6	CHS-200	CHAPERIA Y SOLDADURA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=159
166	6	FIS-200	FISICA AUTOMOTRIZ	2	\N	https://www.itsc.edu.bo/index.php?Itemid=159
167	6	DTA-200	DIBUJO TECNICO AUTOMOTRIZ II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=159
168	6	MOG-300	MOTORES A GASOLINA III	3	\N	https://www.itsc.edu.bo/index.php?Itemid=159
169	6	ELA-300	ELECTRICIDAD AUTOMOTRIZ III	3	\N	https://www.itsc.edu.bo/index.php?Itemid=159
170	6	MOD-300	MOTORES DIESEL I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=159
171	6	ETA-300	ELECTRONICA AUTOMOTRIZ I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=159
172	6	TER-300	TERMODINAMICA	3	\N	https://www.itsc.edu.bo/index.php?Itemid=159
173	6	TRA-300	TRANSMISIONES I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=159
174	6	MOG-400	MOTORES A GASOLINA IV	4	\N	https://www.itsc.edu.bo/index.php?Itemid=159
175	6	IAG-400	INYECCION A GASOLINA I	4	\N	https://www.itsc.edu.bo/index.php?Itemid=159
176	6	MOD-400	MOTORES DIESEL II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=159
177	6	ETA-400	ELECTRONICA AUTOMOTRIZ II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=159
178	6	TRA-400	TRANSMISIONES II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=159
179	6	EMP-400	EMPRENDIMIENTO PRODUCTIVO	4	\N	https://www.itsc.edu.bo/index.php?Itemid=159
180	6	IED-500	INYECCION ELECTRONICA DIESEL I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=159
181	6	IAG-500	INYECCION A GASOLINA II	5	\N	https://www.itsc.edu.bo/index.php?Itemid=159
182	6	LAD-500	LABORATORIO DIESEL I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=159
183	6	ETA-500	ELECTRONICA AUTOMOTRIZ III	5	\N	https://www.itsc.edu.bo/index.php?Itemid=159
184	6	NEU-500	NEUMATICA	5	\N	https://www.itsc.edu.bo/index.php?Itemid=159
185	6	TRA-500	TRANSMISIONES III	5	\N	https://www.itsc.edu.bo/index.php?Itemid=159
186	6	TMG-500	TALLER DE MODALIDAD DE GRADUACION I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=159
187	6	IED-600	INYECCION ELECTRONICA DIESEL II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
188	6	DAU-600	DIAGNOSTICO DEL AUTOMOVIL	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
189	6	LAD-600	LABORATORIO DIESEL II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
190	6	HID-600	HIDRAULICA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
191	6	MAP-600	MAQUINARIA AGRICOLA PESADA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
192	6	IAG-600	INYECCION A GASOLINA III	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
193	6	TRA-600	TRANSMISIONES IV	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
194	6	TMG-600	TALLER DE MODALIDAD DE GRADUACION II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=159
195	7	SIM-100	SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=161
196	7	ALC-100	ALGEBRA Y CALCULO	1	\N	https://www.itsc.edu.bo/index.php?Itemid=161
197	7	ACC-100	ANALISIS DE CIRCUITOS DE CORRIENTE CONTINUA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=161
198	7	FIS-100	FISICA	1	\N	https://www.itsc.edu.bo/index.php?Itemid=161
199	7	INC-100	INSTRUMENTOS Y COMPONENTES	1	\N	https://www.itsc.edu.bo/index.php?Itemid=161
200	7	INE-100	INSTALACIONES ELECTRICAS	1	\N	https://www.itsc.edu.bo/index.php?Itemid=161
201	7	SIC-100	SISTEMAS CAD	1	\N	https://www.itsc.edu.bo/index.php?Itemid=161
202	7	SIM-200	SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=161
203	7	ACC-200	ANALISIS DE CIRCUITOS DE CORRIENTE ALTERNA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=161
204	7	ELA-200	ELECTRONICA ANALOGICA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=161
205	7	ELD-200	ELECTRONICA DIGITAL	2	\N	https://www.itsc.edu.bo/index.php?Itemid=161
206	7	ALE-200	ALGORITMOS Y ESTRUCTURAS	2	\N	https://www.itsc.edu.bo/index.php?Itemid=161
207	7	INT-200	INGLES TECNICO	2	\N	https://www.itsc.edu.bo/index.php?Itemid=161
208	7	LTA-300	LINEAS DE TRANSMISION Y ANTENAS	3	\N	https://www.itsc.edu.bo/index.php?Itemid=161
209	7	MII-300	MAQUINAS E INSTALACIONES INDUSTRIALES	3	\N	https://www.itsc.edu.bo/index.php?Itemid=161
210	7	OAP-300	OPERACIONES Y APLICAIONES	3	\N	https://www.itsc.edu.bo/index.php?Itemid=161
211	7	SLP-300	SISTEMAS LOGICOS PROGRAMABLES	3	\N	https://www.itsc.edu.bo/index.php?Itemid=161
212	7	PRO-300	PROGRAMACION	3	\N	https://www.itsc.edu.bo/index.php?Itemid=161
213	7	EMP-300	EMPRENDIMIENTO PRODUCTIVO	3	\N	https://www.itsc.edu.bo/index.php?Itemid=161
214	7	SIT-400	SISTEMAS DE TELECOMUNICACIONES	4	\N	https://www.itsc.edu.bo/index.php?Itemid=161
215	7	ELE-400	ELECTROACUSTICA	4	\N	https://www.itsc.edu.bo/index.php?Itemid=161
216	7	ELI-400	ELECTRONICA INDUSTRIAL	4	\N	https://www.itsc.edu.bo/index.php?Itemid=161
217	7	MAE-400	MANTENIMIENTO DE EQUIPOS ELECTRONICOS	4	\N	https://www.itsc.edu.bo/index.php?Itemid=161
218	7	ARD-400	ARQUITECTURA Y REDES DE COMPUTADORAS	4	\N	https://www.itsc.edu.bo/index.php?Itemid=161
219	7	MIC-400	MICROCONTROLADORES	4	\N	https://www.itsc.edu.bo/index.php?Itemid=161
220	7	SDC-500	SISTEMAS DE CONTROL	5	\N	https://www.itsc.edu.bo/index.php?Itemid=161
221	7	AUP-500	AUTOMATAS PROGRAMABLES	5	\N	https://www.itsc.edu.bo/index.php?Itemid=161
222	7	SIN-500	SISTEMAS NEUMATICOS	5	\N	https://www.itsc.edu.bo/index.php?Itemid=161
223	7	SIT-500	SISTEMAS DE TELEFONIA	5	\N	https://www.itsc.edu.bo/index.php?Itemid=161
224	7	RGD-500	REDES Y GESTION DE DATOS	5	\N	https://www.itsc.edu.bo/index.php?Itemid=161
225	7	TMG-500	TALLER DE MODADLIDAD DE GRADUACION I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=161
226	7	COD-600	CONTROL DIGITAL	6	\N	https://www.itsc.edu.bo/index.php?Itemid=161
227	7	SIS-600	SISTEMAS SCADA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=161
228	7	ROI-600	ROBOTICA INDUSTRIAL	6	\N	https://www.itsc.edu.bo/index.php?Itemid=161
229	7	SEN-600	SISTEMAS ELECTRONEUMATICOS	6	\N	https://www.itsc.edu.bo/index.php?Itemid=161
230	7	FIO-600	FIBRA OPTICA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=161
231	7	TMG-600	TALLER DE MODADLIDAD DE GRADUACION II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=161
232	8	INT-100	INGLES TECNICO I	1	\N	https://www.itsc.edu.bo/index.php?Itemid=162
233	8	MAT-100	MATEMATICA PARA LA CONSTRUCCION	1	\N	https://www.itsc.edu.bo/index.php?Itemid=162
234	8	DIB-100	DIBUJO TECNICO	1	\N	https://www.itsc.edu.bo/index.php?Itemid=162
235	8	FIS-100	FISICA PARA LA CONSTRUCCION	1	\N	https://www.itsc.edu.bo/index.php?Itemid=162
236	8	SIM-100	SEGURIDAD INDUSTRIAL Y MEDIO AMBIENTE	1	\N	https://www.itsc.edu.bo/index.php?Itemid=162
237	8	MAC-100	MATERIALES DE CONSTRUCCION	1	\N	https://www.itsc.edu.bo/index.php?Itemid=162
238	8	INT-200	INGLES TECNICO II	2	\N	https://www.itsc.edu.bo/index.php?Itemid=162
239	8	DIB-200	DIBUJO CONSTRUCTIVO ASISTIDO POR COMPUTADORA I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=162
240	8	EIS-200	ESTRUCTURAS ISOSTATICAS	2	\N	https://www.itsc.edu.bo/index.php?Itemid=162
241	8	HID-200	HIDRAULICA	2	\N	https://www.itsc.edu.bo/index.php?Itemid=162
242	8	MES-200	MECANICA DE SUELOS I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=162
243	8	PCO-200	PROCESOS CONSTRUCTIVOS I	2	\N	https://www.itsc.edu.bo/index.php?Itemid=162
244	8	THO-300	TECNOLOGIA DEL HORMIGON	3	\N	https://www.itsc.edu.bo/index.php?Itemid=162
245	8	TOP-300	TOPOGRAFIA I	3	\N	https://www.itsc.edu.bo/index.php?Itemid=162
246	8	DIB-300	DIBUJO CONSTRUCTIVO ASISTIDO POR COMPUTADORA II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=162
247	8	RDM-300	RESISTENCIA DE MATERIALES	3	\N	https://www.itsc.edu.bo/index.php?Itemid=162
248	8	MES-300	MECANICA DE SUELOS II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=162
249	8	PCO-300	PROCESOS CONSTRUCTIVOS II	3	\N	https://www.itsc.edu.bo/index.php?Itemid=162
250	8	OSA-400	OBRAS SANITARIAS I	4	\N	https://www.itsc.edu.bo/index.php?Itemid=162
251	8	TOP-400	TOPOGRAFIA II	4	\N	https://www.itsc.edu.bo/index.php?Itemid=162
252	8	MEC-400	MAQUINARIA Y EQUIPO DE CONSTRUCCION	4	\N	https://www.itsc.edu.bo/index.php?Itemid=162
253	8	COP-400	COSTOS Y PRESUPUESTOS	4	\N	https://www.itsc.edu.bo/index.php?Itemid=162
254	8	HOA-400	HORMIGON ARMADO I	4	\N	https://www.itsc.edu.bo/index.php?Itemid=162
255	8	PCO-400	PROCESOS CONSTRUCTIVOS III	4	\N	https://www.itsc.edu.bo/index.php?Itemid=162
256	8	OSA-500	OBRAS SANITARIAS II	5	\N	https://www.itsc.edu.bo/index.php?Itemid=162
257	8	OVI-500	OBRAS VIALES	5	\N	https://www.itsc.edu.bo/index.php?Itemid=162
258	8	DAO-500	DIRECCION Y ADMINISTRACION DE OBRAS	5	\N	https://www.itsc.edu.bo/index.php?Itemid=162
259	8	HOA-500	HORMIGON ARMADO II	5	\N	https://www.itsc.edu.bo/index.php?Itemid=162
260	8	EMP-500	EMPRENDIMIENTO PRODUCTIVO I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=162
261	8	TMG-500	TALLER DE MODALIDAD DE GRADUACION I	5	\N	https://www.itsc.edu.bo/index.php?Itemid=162
262	8	SEO-600	SEGUIMIENTO DE OBRAS	6	\N	https://www.itsc.edu.bo/index.php?Itemid=162
263	8	IOC-600	INSTALACIONES ESPECIALES EN OBRAS CIVILES	6	\N	https://www.itsc.edu.bo/index.php?Itemid=162
264	8	EMA-600	ESTRUCTURAS EN MADERA	6	\N	https://www.itsc.edu.bo/index.php?Itemid=162
265	8	ESM-600	ESTRUCTURAS METALICAS	6	\N	https://www.itsc.edu.bo/index.php?Itemid=162
266	8	EMP-600	EMPRENDIMIENTO PRODUCTIVO II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=162
267	8	TMG-600	TALLER DE MODALIDAD DE GRADUACION II	6	\N	https://www.itsc.edu.bo/index.php?Itemid=162
268	9	DEMO-9-1	Fundamentos de redes (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
269	9	DEMO-9-2	Sistemas operativos (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
270	9	DEMO-9-3	Matemática aplicada (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
271	9	DEMO-9-4	Redes locales (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
272	9	DEMO-9-5	Administración de servidores (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
273	9	DEMO-9-6	Seguridad de redes (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
274	10	DEMO-10-1	Dibujo y composición (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
275	10	DEMO-10-2	Diseño digital (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
276	10	DEMO-10-3	Comunicación visual (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
277	10	DEMO-10-4	Identidad gráfica (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
278	10	DEMO-10-5	Diseño editorial (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
279	10	DEMO-10-6	Producción multimedia (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
280	11	DEMO-11-1	Administración general (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
281	11	DEMO-11-2	Contabilidad básica (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
282	11	DEMO-11-3	Matemática financiera (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
283	11	DEMO-11-4	Gestión de personal (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
284	11	DEMO-11-5	Mercadotecnia (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
285	11	DEMO-11-6	Emprendimiento (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
286	12	DEMO-12-1	Fundamentos de electricidad (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
287	12	DEMO-12-2	Energía y medio ambiente (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
288	12	DEMO-12-3	Matemática técnica (demostración)	1	4	Datos ficticios del práctico; no representan un plan oficial.
289	12	DEMO-12-4	Sistemas fotovoltaicos (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
290	12	DEMO-12-5	Energía eólica (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
291	12	DEMO-12-6	Eficiencia energética (demostración)	2	4	Datos ficticios del práctico; no representan un plan oficial.
\.


--
-- Data for Name: matriculas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.matriculas (id, estudiante_id, carrera_id, periodo_id, fecha, estado, plan_id) FROM stdin;
1	1	1	1	2026-02-02	ACTIVA	1
2	2	1	1	2026-02-02	ACTIVA	1
3	3	1	1	2026-02-02	ACTIVA	1
4	5	1	1	2026-02-02	ACTIVA	1
5	6	1	1	2026-02-02	ACTIVA	1
6	7	1	1	2026-02-02	ACTIVA	1
7	8	1	1	2026-02-02	ACTIVA	1
8	9	1	1	2026-02-02	ACTIVA	1
9	10	1	1	2026-02-02	ACTIVA	1
10	11	1	1	2026-02-02	ACTIVA	1
11	12	1	1	2026-02-02	ACTIVA	1
12	13	1	1	2026-02-02	ACTIVA	1
13	14	1	1	2026-02-02	ACTIVA	1
14	15	1	1	2026-02-02	ACTIVA	1
15	16	1	1	2026-02-02	ACTIVA	1
16	17	1	1	2026-02-02	ACTIVA	1
17	18	1	1	2026-02-02	ACTIVA	1
18	19	1	1	2026-02-02	ACTIVA	1
19	20	1	1	2026-02-02	ACTIVA	1
20	21	1	1	2026-02-02	ACTIVA	1
21	22	1	1	2026-02-02	ACTIVA	1
22	23	1	1	2026-02-02	ACTIVA	1
23	24	1	1	2026-02-02	ACTIVA	1
24	25	1	1	2026-02-02	ACTIVA	1
25	26	1	1	2026-02-02	ACTIVA	1
26	27	1	1	2026-02-02	ACTIVA	1
27	28	1	1	2026-02-02	ACTIVA	1
28	29	1	1	2026-02-02	ACTIVA	1
29	30	1	1	2026-02-02	ACTIVA	1
30	31	1	1	2026-02-02	ACTIVA	1
31	32	2	1	2026-02-02	ACTIVA	2
32	33	2	1	2026-02-02	ACTIVA	2
33	34	2	1	2026-02-02	ACTIVA	2
34	35	2	1	2026-02-02	ACTIVA	2
35	36	2	1	2026-02-02	ACTIVA	2
36	37	2	1	2026-02-02	ACTIVA	2
37	38	2	1	2026-02-02	ACTIVA	2
38	39	2	1	2026-02-02	ACTIVA	2
39	40	2	1	2026-02-02	ACTIVA	2
40	41	2	1	2026-02-02	ACTIVA	2
41	42	2	1	2026-02-02	ACTIVA	2
42	43	2	1	2026-02-02	ACTIVA	2
43	44	2	1	2026-02-02	ACTIVA	2
44	45	2	1	2026-02-02	ACTIVA	2
45	46	2	1	2026-02-02	ACTIVA	2
46	47	2	1	2026-02-02	ACTIVA	2
47	48	2	1	2026-02-02	ACTIVA	2
48	49	2	1	2026-02-02	ACTIVA	2
49	50	2	1	2026-02-02	ACTIVA	2
50	51	2	1	2026-02-02	ACTIVA	2
\.


--
-- Data for Name: modalidades_graduacion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.modalidades_graduacion (id, nombre) FROM stdin;
1	Proyecto de grado
2	Examen de grado
3	Proyecto sociocomunitario productivo
4	Proyecto de emprendimiento productivo
5	Trabajo dirigido externo
6	Excelencia académica
\.


--
-- Data for Name: notas_demo_historicas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notas_demo_historicas (id, inscripcion_id, evaluacion, nota, fecha) FROM stdin;
\.


--
-- Data for Name: ofertas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ofertas (id, materia_id, carrera_id, periodo_id, docente_id, paralelo, turno, cupo) FROM stdin;
1	1	1	1	1	A	MAÑANA	35
2	2	1	1	2	A	MAÑANA	35
3	3	1	1	3	A	MAÑANA	35
4	24	2	1	4	A	NOCHE	30
5	25	2	1	5	A	NOCHE	30
6	26	2	1	6	A	NOCHE	30
7	1	1	2	1	A	MAÑANA	35
8	2	1	2	2	A	MAÑANA	35
9	3	1	2	3	A	MAÑANA	35
10	48	3	2	7	B	TARDE	25
11	49	3	2	8	B	TARDE	25
12	50	3	2	9	B	TARDE	25
\.


--
-- Data for Name: pagos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pagos (id, cargo_id, recibo, fecha, monto, metodo) FROM stdin;
1	1	DEMO-2026-0001	2026-07-20	100.00	EFECTIVO
2	2	DEMO-2026-0002	2026-07-20	100.00	QR
3	3	DEMO-2026-0003	2026-07-20	100.00	EFECTIVO
4	4	DEMO-2026-0004	2026-07-20	100.00	QR
5	5	DEMO-2026-0005	2026-07-20	100.00	EFECTIVO
6	6	DEMO-2026-0006	2026-07-20	100.00	QR
7	7	DEMO-2026-0007	2026-07-20	100.00	EFECTIVO
8	8	DEMO-2026-0008	2026-07-20	100.00	QR
9	9	DEMO-2026-0009	2026-07-20	100.00	EFECTIVO
10	10	DEMO-2026-0010	2026-07-20	100.00	QR
11	11	DEMO-2026-0011	2026-07-20	100.00	EFECTIVO
12	12	DEMO-2026-0012	2026-07-20	100.00	QR
13	13	DEMO-2026-0013	2026-07-20	100.00	EFECTIVO
14	14	DEMO-2026-0014	2026-07-20	100.00	QR
15	15	DEMO-2026-0015	2026-07-20	100.00	EFECTIVO
16	16	DEMO-2026-0016	2026-07-20	100.00	QR
17	17	DEMO-2026-0017	2026-07-20	100.00	EFECTIVO
18	18	DEMO-2026-0018	2026-07-20	100.00	QR
19	19	DEMO-2026-0019	2026-07-20	100.00	EFECTIVO
20	20	DEMO-2026-0020	2026-07-20	100.00	QR
\.


--
-- Data for Name: pasantias; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pasantias (id, matricula_id, tutor_id, empresa, fecha_inicio, fecha_fin, horas, estado) FROM stdin;
1	1	1	Tecnología Cruceña Demo S.R.L. (ficticia)	2026-08-03	2026-09-30	160	CONCLUIDA
2	31	2	Consultora Contable Demo (ficticia)	2026-10-01	\N	80	EN_CURSO
\.


--
-- Data for Name: periodos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.periodos (id, nombre, fecha_inicio, fecha_fin) FROM stdin;
1	GESTIÓN 2026	2026-02-02	2026-11-30
2	GESTIÓN 2027	2027-02-01	2027-11-30
\.


--
-- Data for Name: plan_materias; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.plan_materias (plan_id, materia_id, carrera_id) FROM stdin;
1	1	1
1	2	1
1	3	1
1	4	1
1	5	1
1	6	1
1	7	1
1	8	1
1	9	1
1	10	1
1	11	1
1	12	1
1	13	1
1	14	1
1	15	1
1	16	1
1	17	1
1	18	1
1	19	1
1	20	1
1	21	1
1	22	1
1	23	1
2	24	2
2	25	2
2	26	2
2	27	2
2	28	2
2	29	2
2	30	2
2	31	2
2	32	2
2	33	2
2	34	2
2	35	2
2	36	2
2	37	2
2	38	2
2	39	2
2	40	2
2	41	2
2	42	2
2	43	2
2	44	2
2	45	2
2	46	2
2	47	2
3	48	3
3	49	3
3	50	3
3	51	3
3	52	3
3	53	3
3	54	3
3	55	3
3	56	3
3	57	3
3	58	3
3	59	3
3	60	3
3	61	3
3	62	3
3	63	3
3	64	3
3	65	3
3	66	3
3	67	3
3	68	3
3	69	3
3	70	3
3	71	3
3	72	3
3	73	3
3	74	3
3	75	3
3	76	3
3	77	3
3	78	3
3	79	3
3	80	3
3	81	3
3	82	3
3	83	3
3	84	3
4	85	4
4	86	4
4	87	4
4	88	4
4	89	4
4	90	4
4	91	4
4	92	4
4	93	4
4	94	4
4	95	4
4	96	4
4	97	4
4	98	4
4	99	4
4	100	4
4	101	4
4	102	4
4	103	4
4	104	4
4	105	4
4	106	4
4	107	4
4	108	4
4	109	4
4	110	4
4	111	4
4	112	4
4	113	4
4	114	4
4	115	4
4	116	4
4	117	4
4	118	4
5	119	5
5	120	5
5	121	5
5	122	5
5	123	5
5	124	5
5	125	5
5	126	5
5	127	5
5	128	5
5	129	5
5	130	5
5	131	5
5	132	5
5	133	5
5	134	5
5	135	5
5	136	5
5	137	5
5	138	5
5	139	5
5	140	5
5	141	5
5	142	5
5	143	5
5	144	5
5	145	5
5	146	5
5	147	5
5	148	5
5	149	5
5	150	5
5	151	5
5	152	5
5	153	5
5	154	5
6	155	6
6	156	6
6	157	6
6	158	6
6	159	6
6	160	6
6	161	6
6	162	6
6	163	6
6	164	6
6	165	6
6	166	6
6	167	6
6	168	6
6	169	6
6	170	6
6	171	6
6	172	6
6	173	6
6	174	6
6	175	6
6	176	6
6	177	6
6	178	6
6	179	6
6	180	6
6	181	6
6	182	6
6	183	6
6	184	6
6	185	6
6	186	6
6	187	6
6	188	6
6	189	6
6	190	6
6	191	6
6	192	6
6	193	6
6	194	6
7	195	7
7	196	7
7	197	7
7	198	7
7	199	7
7	200	7
7	201	7
7	202	7
7	203	7
7	204	7
7	205	7
7	206	7
7	207	7
7	208	7
7	209	7
7	210	7
7	211	7
7	212	7
7	213	7
7	214	7
7	215	7
7	216	7
7	217	7
7	218	7
7	219	7
7	220	7
7	221	7
7	222	7
7	223	7
7	224	7
7	225	7
7	226	7
7	227	7
7	228	7
7	229	7
7	230	7
7	231	7
8	232	8
8	233	8
8	234	8
8	235	8
8	236	8
8	237	8
8	238	8
8	239	8
8	240	8
8	241	8
8	242	8
8	243	8
8	244	8
8	245	8
8	246	8
8	247	8
8	248	8
8	249	8
8	250	8
8	251	8
8	252	8
8	253	8
8	254	8
8	255	8
8	256	8
8	257	8
8	258	8
8	259	8
8	260	8
8	261	8
8	262	8
8	263	8
8	264	8
8	265	8
8	266	8
8	267	8
9	268	9
9	269	9
9	270	9
9	271	9
9	272	9
9	273	9
10	274	10
10	275	10
10	276	10
10	277	10
10	278	10
10	279	10
11	280	11
11	281	11
11	282	11
11	283	11
11	284	11
11	285	11
12	286	12
12	287	12
12	288	12
12	289	12
12	290	12
12	291	12
\.


--
-- Data for Name: planes_estudio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.planes_estudio (id, carrera_id, denominacion, cohorte, regla_id) FROM stdin;
1	1	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
2	2	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
3	3	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
4	4	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
5	5	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
6	6	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
7	7	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
8	8	Catálogo del práctico - cohorte de demostración	DEMO-2026	1
9	9	Plan completo de demostración académica	DEMO-2026	1
10	10	Plan completo de demostración académica	DEMO-2026	1
11	11	Plan completo de demostración académica	DEMO-2026	1
12	12	Plan completo de demostración académica	DEMO-2026	1
\.


--
-- Data for Name: prerrequisitos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prerrequisitos (plan_id, materia_id, requerida_id) FROM stdin;
\.


--
-- Data for Name: proyectos_graduacion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.proyectos_graduacion (id, matricula_id, modalidad_id, tutor_id, titulo, estado) FROM stdin;
1	1	1	1	Sistema de inventario para una empresa ficticia (demostración)	PROPUESTO
\.


--
-- Data for Name: recuperaciones; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recuperaciones (inscripcion_id, matricula_id, nota_prueba, nota_registrada, fecha) FROM stdin;
\.


--
-- Data for Name: reglas_evaluacion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reglas_evaluacion (id, nombre, fuente, minimo, maximo, aprobacion, practica, teoria, asistencia, acceso_recuperacion, max_rec_anual, max_rec_semestral) FROM stdin;
1	DEMO ITSC PostgreSQL - RM0189/2023	Referencia del práctico: R.M.0189/2023, artículos13–18. Reglas conservadas del sistema académico de demostración.	1.00	100.00	61.00	0.700	0.300	80.00	40.00	3	2
\.


--
-- Data for Name: resultados_finales; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.resultados_finales (inscripcion_id, regla_id, promedio, porcentaje_asistencia, excepcion_documentada, estado, fecha) FROM stdin;
\.


--
-- Data for Name: sesiones; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sesiones (id, oferta_id, inicio, fin, estado) FROM stdin;
1	1	2026-07-20 08:00:00	2026-07-20 09:40:00	REALIZADA
2	2	2026-07-21 08:00:00	2026-07-21 09:40:00	REALIZADA
3	3	2026-07-22 08:00:00	2026-07-22 09:40:00	REALIZADA
4	4	2026-07-20 19:00:00	2026-07-20 20:40:00	REALIZADA
5	5	2026-07-21 19:00:00	2026-07-21 20:40:00	REALIZADA
6	6	2026-07-22 19:00:00	2026-07-22 20:40:00	REALIZADA
\.


--
-- Data for Name: tipos_documento; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipos_documento (id, nombre) FROM stdin;
1	Fotocopia diploma de bachiller
2	Fotocopia cédula de identidad
3	Fotocopia certificado de nacimiento
4	Documento de tipo sanguíneo
5	Boletín de calificación
6	Carnet de estudiante
\.


--
-- Data for Name: tramites; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tramites (id, matricula_id, tipo, fecha, estado, detalle) FROM stdin;
1	1	PRORROGA_DIPLOMA	2026-07-20	SOLICITADO	Solicitud ficticia de ampliación de plazo.
2	2	OTRO	2026-07-21	EN_REVISION	Solicitud ficticia de certificado de estudios.
\.


--
-- Data for Name: tribunales; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tribunales (defensa_id, docente_id, funcion) FROM stdin;
\.


--
-- Name: etl_ejecuciones_id_seq; Type: SEQUENCE SET; Schema: dw; Owner: -
--

SELECT pg_catalog.setval('dw.etl_ejecuciones_id_seq', 2, true);


--
-- Name: app_auditoria_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_auditoria_id_seq', 7, true);


--
-- Name: app_usuarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_usuarios_id_seq', 3, true);


--
-- Name: asistencias_demo_historicas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.asistencias_demo_historicas_id_seq', 1, false);


--
-- Name: aulas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.aulas_id_seq', 5, false);


--
-- Name: cargos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cargos_id_seq', 51, false);


--
-- Name: carreras_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.carreras_id_seq', 13, false);


--
-- Name: defensas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.defensas_id_seq', 1, false);


--
-- Name: docentes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.docentes_id_seq', 81, false);


--
-- Name: documentos_matricula_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.documentos_matricula_id_seq', 101, false);


--
-- Name: estudiantes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.estudiantes_id_seq', 1002, false);


--
-- Name: evaluaciones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.evaluaciones_id_seq', 25, false);


--
-- Name: grupo_integrantes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.grupo_integrantes_id_seq', 51, false);


--
-- Name: grupo_materias_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.grupo_materias_id_seq', 13, false);


--
-- Name: grupos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.grupos_id_seq', 5, false);


--
-- Name: horarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.horarios_id_seq', 13, false);


--
-- Name: inscripciones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inscripciones_id_seq', 151, false);


--
-- Name: materias_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.materias_id_seq', 292, false);


--
-- Name: matriculas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.matriculas_id_seq', 51, false);


--
-- Name: modalidades_graduacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.modalidades_graduacion_id_seq', 7, false);


--
-- Name: notas_demo_historicas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notas_demo_historicas_id_seq', 1, false);


--
-- Name: ofertas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ofertas_id_seq', 13, false);


--
-- Name: pagos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pagos_id_seq', 21, false);


--
-- Name: pasantias_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pasantias_id_seq', 3, false);


--
-- Name: periodos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.periodos_id_seq', 3, false);


--
-- Name: planes_estudio_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.planes_estudio_id_seq', 13, false);


--
-- Name: proyectos_graduacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.proyectos_graduacion_id_seq', 2, false);


--
-- Name: sesiones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sesiones_id_seq', 7, false);


--
-- Name: tipos_documento_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.tipos_documento_id_seq', 7, false);


--
-- Name: tramites_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.tramites_id_seq', 3, false);


--
-- Name: dim_carrera dim_carrera_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.dim_carrera
    ADD CONSTRAINT dim_carrera_pkey PRIMARY KEY (carrera_id);


--
-- Name: dim_docente dim_docente_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.dim_docente
    ADD CONSTRAINT dim_docente_pkey PRIMARY KEY (docente_id);


--
-- Name: dim_estudiante dim_estudiante_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.dim_estudiante
    ADD CONSTRAINT dim_estudiante_pkey PRIMARY KEY (estudiante_id);


--
-- Name: dim_gestion dim_gestion_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.dim_gestion
    ADD CONSTRAINT dim_gestion_pkey PRIMARY KEY (gestion_id);


--
-- Name: dim_materia dim_materia_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.dim_materia
    ADD CONSTRAINT dim_materia_pkey PRIMARY KEY (materia_id);


--
-- Name: dim_tiempo dim_tiempo_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.dim_tiempo
    ADD CONSTRAINT dim_tiempo_pkey PRIMARY KEY (fecha);


--
-- Name: etl_ejecuciones etl_ejecuciones_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.etl_ejecuciones
    ADD CONSTRAINT etl_ejecuciones_pkey PRIMARY KEY (id);


--
-- Name: fact_matriculas fact_matriculas_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_matriculas
    ADD CONSTRAINT fact_matriculas_pkey PRIMARY KEY (matricula_id);


--
-- Name: fact_pagos fact_pagos_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_pagos
    ADD CONSTRAINT fact_pagos_pkey PRIMARY KEY (pago_id);


--
-- Name: fact_resultados fact_resultados_pkey; Type: CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_resultados
    ADD CONSTRAINT fact_resultados_pkey PRIMARY KEY (inscripcion_id);


--
-- Name: _prisma_migrations _prisma_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._prisma_migrations
    ADD CONSTRAINT _prisma_migrations_pkey PRIMARY KEY (id);


--
-- Name: app_auditoria app_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_auditoria
    ADD CONSTRAINT app_auditoria_pkey PRIMARY KEY (id);


--
-- Name: app_intentos app_intentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_intentos
    ADD CONSTRAINT app_intentos_pkey PRIMARY KEY (clave);


--
-- Name: app_usuarios app_usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_usuarios
    ADD CONSTRAINT app_usuarios_pkey PRIMARY KEY (id);


--
-- Name: app_usuarios app_usuarios_usuario_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_usuarios
    ADD CONSTRAINT app_usuarios_usuario_key UNIQUE (usuario);


--
-- Name: asistencias_demo_historicas asistencias_demo_historicas_inscripcion_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_demo_historicas
    ADD CONSTRAINT asistencias_demo_historicas_inscripcion_id_key UNIQUE (inscripcion_id, fecha);


--
-- Name: asistencias_demo_historicas asistencias_demo_historicas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_demo_historicas
    ADD CONSTRAINT asistencias_demo_historicas_pkey PRIMARY KEY (id);


--
-- Name: asistencias_sesion asistencias_sesion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_sesion
    ADD CONSTRAINT asistencias_sesion_pkey PRIMARY KEY (inscripcion_id, sesion_id);


--
-- Name: aulas aulas_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aulas
    ADD CONSTRAINT aulas_codigo_key UNIQUE (codigo);


--
-- Name: aulas aulas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aulas
    ADD CONSTRAINT aulas_pkey PRIMARY KEY (id);


--
-- Name: calificaciones calificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calificaciones
    ADD CONSTRAINT calificaciones_pkey PRIMARY KEY (inscripcion_id, evaluacion_id);


--
-- Name: cargos cargos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT cargos_pkey PRIMARY KEY (id);


--
-- Name: carreras carreras_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carreras
    ADD CONSTRAINT carreras_codigo_key UNIQUE (codigo);


--
-- Name: carreras carreras_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.carreras
    ADD CONSTRAINT carreras_pkey PRIMARY KEY (id);


--
-- Name: cierres_oferta cierres_oferta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cierres_oferta
    ADD CONSTRAINT cierres_oferta_pkey PRIMARY KEY (oferta_id);


--
-- Name: defensas defensas_acta_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.defensas
    ADD CONSTRAINT defensas_acta_key UNIQUE (acta);


--
-- Name: defensas defensas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.defensas
    ADD CONSTRAINT defensas_pkey PRIMARY KEY (id);


--
-- Name: docentes docentes_correo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.docentes
    ADD CONSTRAINT docentes_correo_key UNIQUE (correo);


--
-- Name: docentes docentes_documento_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.docentes
    ADD CONSTRAINT docentes_documento_key UNIQUE (documento);


--
-- Name: docentes docentes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.docentes
    ADD CONSTRAINT docentes_pkey PRIMARY KEY (id);


--
-- Name: documentos_matricula documentos_matricula_matricula_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos_matricula
    ADD CONSTRAINT documentos_matricula_matricula_id_key UNIQUE (matricula_id, tipo_documento_id);


--
-- Name: documentos_matricula documentos_matricula_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos_matricula
    ADD CONSTRAINT documentos_matricula_pkey PRIMARY KEY (id);


--
-- Name: estudiantes estudiantes_correo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estudiantes
    ADD CONSTRAINT estudiantes_correo_key UNIQUE (correo);


--
-- Name: estudiantes estudiantes_documento_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estudiantes
    ADD CONSTRAINT estudiantes_documento_key UNIQUE (documento);


--
-- Name: estudiantes estudiantes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estudiantes
    ADD CONSTRAINT estudiantes_pkey PRIMARY KEY (id);


--
-- Name: estudiantes estudiantes_registro_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estudiantes
    ADD CONSTRAINT estudiantes_registro_key UNIQUE (registro);


--
-- Name: evaluaciones evaluaciones_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluaciones
    ADD CONSTRAINT evaluaciones_id_key UNIQUE (id, oferta_id);


--
-- Name: evaluaciones evaluaciones_oferta_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluaciones
    ADD CONSTRAINT evaluaciones_oferta_id_key UNIQUE (oferta_id, nombre);


--
-- Name: evaluaciones evaluaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluaciones
    ADD CONSTRAINT evaluaciones_pkey PRIMARY KEY (id);


--
-- Name: excepciones_asistencia excepciones_asistencia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.excepciones_asistencia
    ADD CONSTRAINT excepciones_asistencia_pkey PRIMARY KEY (inscripcion_id);


--
-- Name: grupo_integrantes grupo_integrantes_matricula_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_integrantes
    ADD CONSTRAINT grupo_integrantes_matricula_id_key UNIQUE (matricula_id);


--
-- Name: grupo_integrantes grupo_integrantes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_integrantes
    ADD CONSTRAINT grupo_integrantes_pkey PRIMARY KEY (id);


--
-- Name: grupo_materias grupo_materias_oferta_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_materias
    ADD CONSTRAINT grupo_materias_oferta_id_key UNIQUE (oferta_id);


--
-- Name: grupo_materias grupo_materias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_materias
    ADD CONSTRAINT grupo_materias_pkey PRIMARY KEY (id);


--
-- Name: grupos grupos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupos
    ADD CONSTRAINT grupos_pkey PRIMARY KEY (id);


--
-- Name: grupos grupos_uq_grupo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupos
    ADD CONSTRAINT grupos_uq_grupo_key UNIQUE (periodo_id, carrera_id, curso, paralelo, turno);


--
-- Name: horarios horarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horarios
    ADD CONSTRAINT horarios_pkey PRIMARY KEY (id);


--
-- Name: inscripciones inscripciones_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT inscripciones_id_key UNIQUE (id, oferta_id);


--
-- Name: inscripciones inscripciones_matricula_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT inscripciones_matricula_id_key UNIQUE (matricula_id, oferta_id);


--
-- Name: inscripciones inscripciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT inscripciones_pkey PRIMARY KEY (id);


--
-- Name: materias materias_carrera_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materias
    ADD CONSTRAINT materias_carrera_id_key UNIQUE (carrera_id, codigo);


--
-- Name: materias materias_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materias
    ADD CONSTRAINT materias_id_key UNIQUE (id, carrera_id);


--
-- Name: materias materias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materias
    ADD CONSTRAINT materias_pkey PRIMARY KEY (id);


--
-- Name: matriculas matriculas_estudiante_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_estudiante_id_key UNIQUE (estudiante_id, carrera_id, periodo_id);


--
-- Name: matriculas matriculas_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_id_key UNIQUE (id, carrera_id, periodo_id);


--
-- Name: matriculas matriculas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_pkey PRIMARY KEY (id);


--
-- Name: modalidades_graduacion modalidades_graduacion_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modalidades_graduacion
    ADD CONSTRAINT modalidades_graduacion_nombre_key UNIQUE (nombre);


--
-- Name: modalidades_graduacion modalidades_graduacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modalidades_graduacion
    ADD CONSTRAINT modalidades_graduacion_pkey PRIMARY KEY (id);


--
-- Name: notas_demo_historicas notas_demo_historicas_inscripcion_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notas_demo_historicas
    ADD CONSTRAINT notas_demo_historicas_inscripcion_id_key UNIQUE (inscripcion_id, evaluacion);


--
-- Name: notas_demo_historicas notas_demo_historicas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notas_demo_historicas
    ADD CONSTRAINT notas_demo_historicas_pkey PRIMARY KEY (id);


--
-- Name: ofertas ofertas_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_id_key UNIQUE (id, carrera_id, periodo_id);


--
-- Name: ofertas ofertas_materia_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_materia_id_key UNIQUE (materia_id, periodo_id, paralelo);


--
-- Name: ofertas ofertas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_recibo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_recibo_key UNIQUE (recibo);


--
-- Name: pasantias pasantias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pasantias
    ADD CONSTRAINT pasantias_pkey PRIMARY KEY (id);


--
-- Name: periodos periodos_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodos
    ADD CONSTRAINT periodos_nombre_key UNIQUE (nombre);


--
-- Name: periodos periodos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodos
    ADD CONSTRAINT periodos_pkey PRIMARY KEY (id);


--
-- Name: plan_materias plan_materias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_materias
    ADD CONSTRAINT plan_materias_pkey PRIMARY KEY (plan_id, materia_id);


--
-- Name: planes_estudio planes_estudio_carrera_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_estudio
    ADD CONSTRAINT planes_estudio_carrera_id_key UNIQUE (carrera_id, denominacion, cohorte);


--
-- Name: planes_estudio planes_estudio_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_estudio
    ADD CONSTRAINT planes_estudio_id_key UNIQUE (id, carrera_id);


--
-- Name: planes_estudio planes_estudio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_estudio
    ADD CONSTRAINT planes_estudio_pkey PRIMARY KEY (id);


--
-- Name: prerrequisitos prerrequisitos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prerrequisitos
    ADD CONSTRAINT prerrequisitos_pkey PRIMARY KEY (plan_id, materia_id, requerida_id);


--
-- Name: proyectos_graduacion proyectos_graduacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_graduacion
    ADD CONSTRAINT proyectos_graduacion_pkey PRIMARY KEY (id);


--
-- Name: recuperaciones recuperaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperaciones
    ADD CONSTRAINT recuperaciones_pkey PRIMARY KEY (inscripcion_id);


--
-- Name: reglas_evaluacion reglas_evaluacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reglas_evaluacion
    ADD CONSTRAINT reglas_evaluacion_pkey PRIMARY KEY (id);


--
-- Name: resultados_finales resultados_finales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resultados_finales
    ADD CONSTRAINT resultados_finales_pkey PRIMARY KEY (inscripcion_id);


--
-- Name: sesiones sesiones_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesiones
    ADD CONSTRAINT sesiones_id_key UNIQUE (id, oferta_id);


--
-- Name: sesiones sesiones_oferta_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesiones
    ADD CONSTRAINT sesiones_oferta_id_key UNIQUE (oferta_id, inicio);


--
-- Name: sesiones sesiones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesiones
    ADD CONSTRAINT sesiones_pkey PRIMARY KEY (id);


--
-- Name: tipos_documento tipos_documento_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipos_documento
    ADD CONSTRAINT tipos_documento_nombre_key UNIQUE (nombre);


--
-- Name: tipos_documento tipos_documento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipos_documento
    ADD CONSTRAINT tipos_documento_pkey PRIMARY KEY (id);


--
-- Name: tramites tramites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tramites
    ADD CONSTRAINT tramites_pkey PRIMARY KEY (id);


--
-- Name: tribunales tribunales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tribunales
    ADD CONSTRAINT tribunales_pkey PRIMARY KEY (defensa_id, docente_id);


--
-- Name: dim_materia_carrera_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX dim_materia_carrera_idx ON dw.dim_materia USING btree (carrera_id);


--
-- Name: etl_ejecuciones_inicio_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX etl_ejecuciones_inicio_idx ON dw.etl_ejecuciones USING btree (inicio);


--
-- Name: fact_matriculas_estudiante_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_matriculas_estudiante_idx ON dw.fact_matriculas USING btree (estudiante_id);


--
-- Name: fact_matriculas_fecha_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_matriculas_fecha_idx ON dw.fact_matriculas USING btree (fecha);


--
-- Name: fact_matriculas_gestion_carrera_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_matriculas_gestion_carrera_idx ON dw.fact_matriculas USING btree (gestion_id, carrera_id);


--
-- Name: fact_pagos_estudiante_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_pagos_estudiante_idx ON dw.fact_pagos USING btree (estudiante_id);


--
-- Name: fact_pagos_fecha_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_pagos_fecha_idx ON dw.fact_pagos USING btree (fecha);


--
-- Name: fact_pagos_gestion_carrera_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_pagos_gestion_carrera_idx ON dw.fact_pagos USING btree (gestion_id, carrera_id);


--
-- Name: fact_resultados_docente_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_resultados_docente_idx ON dw.fact_resultados USING btree (docente_id);


--
-- Name: fact_resultados_estudiante_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_resultados_estudiante_idx ON dw.fact_resultados USING btree (estudiante_id);


--
-- Name: fact_resultados_fecha_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_resultados_fecha_idx ON dw.fact_resultados USING btree (fecha);


--
-- Name: fact_resultados_gestion_carrera_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_resultados_gestion_carrera_idx ON dw.fact_resultados USING btree (gestion_id, carrera_id);


--
-- Name: fact_resultados_materia_idx; Type: INDEX; Schema: dw; Owner: -
--

CREATE INDEX fact_resultados_materia_idx ON dw.fact_resultados USING btree (materia_id);


--
-- Name: app_auditoria_usuario_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_auditoria_usuario_id_idx ON public.app_auditoria USING btree (usuario_id);


--
-- Name: app_usuarios_docente_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_usuarios_docente_id_idx ON public.app_usuarios USING btree (docente_id);


--
-- Name: asistencias_sesion_inscripcion_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX asistencias_sesion_inscripcion_id_idx ON public.asistencias_sesion USING btree (inscripcion_id, oferta_id);


--
-- Name: asistencias_sesion_sesion_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX asistencias_sesion_sesion_id_idx ON public.asistencias_sesion USING btree (sesion_id, oferta_id);


--
-- Name: calificaciones_evaluacion_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX calificaciones_evaluacion_id_idx ON public.calificaciones USING btree (evaluacion_id, oferta_id);


--
-- Name: calificaciones_inscripcion_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX calificaciones_inscripcion_id_idx ON public.calificaciones USING btree (inscripcion_id, oferta_id);


--
-- Name: cargos_matricula_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cargos_matricula_id_idx ON public.cargos USING btree (matricula_id);


--
-- Name: defensas_aula_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX defensas_aula_id_idx ON public.defensas USING btree (aula_id);


--
-- Name: defensas_proyecto_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX defensas_proyecto_id_idx ON public.defensas USING btree (proyecto_id);


--
-- Name: documentos_matricula_tipo_documento_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX documentos_matricula_tipo_documento_id_idx ON public.documentos_matricula USING btree (tipo_documento_id);


--
-- Name: grupo_integrantes_grupo_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX grupo_integrantes_grupo_id_idx ON public.grupo_integrantes USING btree (grupo_id);


--
-- Name: grupo_materias_grupo_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX grupo_materias_grupo_id_idx ON public.grupo_materias USING btree (grupo_id);


--
-- Name: grupos_carrera_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX grupos_carrera_id_idx ON public.grupos USING btree (carrera_id);


--
-- Name: grupos_tutor_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX grupos_tutor_id_idx ON public.grupos USING btree (tutor_id);


--
-- Name: horarios_aula_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX horarios_aula_id_idx ON public.horarios USING btree (aula_id);


--
-- Name: horarios_oferta_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX horarios_oferta_id_idx ON public.horarios USING btree (oferta_id);


--
-- Name: inscripciones_matricula_id_2_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inscripciones_matricula_id_2_idx ON public.inscripciones USING btree (matricula_id, carrera_id, periodo_id);


--
-- Name: inscripciones_oferta_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inscripciones_oferta_id_idx ON public.inscripciones USING btree (oferta_id, carrera_id, periodo_id);


--
-- Name: matriculas_carrera_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX matriculas_carrera_id_idx ON public.matriculas USING btree (carrera_id);


--
-- Name: matriculas_periodo_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX matriculas_periodo_id_idx ON public.matriculas USING btree (periodo_id);


--
-- Name: matriculas_plan_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX matriculas_plan_id_idx ON public.matriculas USING btree (plan_id, carrera_id);


--
-- Name: ofertas_docente_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ofertas_docente_id_idx ON public.ofertas USING btree (docente_id);


--
-- Name: ofertas_materia_id_2_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ofertas_materia_id_2_idx ON public.ofertas USING btree (materia_id, carrera_id);


--
-- Name: ofertas_periodo_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ofertas_periodo_id_idx ON public.ofertas USING btree (periodo_id);


--
-- Name: pagos_cargo_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pagos_cargo_id_idx ON public.pagos USING btree (cargo_id);


--
-- Name: pasantias_matricula_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pasantias_matricula_id_idx ON public.pasantias USING btree (matricula_id);


--
-- Name: pasantias_tutor_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pasantias_tutor_id_idx ON public.pasantias USING btree (tutor_id);


--
-- Name: plan_materias_materia_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plan_materias_materia_id_idx ON public.plan_materias USING btree (materia_id, carrera_id);


--
-- Name: plan_materias_plan_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plan_materias_plan_id_idx ON public.plan_materias USING btree (plan_id, carrera_id);


--
-- Name: planes_estudio_regla_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX planes_estudio_regla_id_idx ON public.planes_estudio USING btree (regla_id);


--
-- Name: prerrequisitos_plan_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prerrequisitos_plan_id_idx ON public.prerrequisitos USING btree (plan_id, requerida_id);


--
-- Name: proyectos_graduacion_matricula_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX proyectos_graduacion_matricula_id_idx ON public.proyectos_graduacion USING btree (matricula_id);


--
-- Name: proyectos_graduacion_modalidad_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX proyectos_graduacion_modalidad_id_idx ON public.proyectos_graduacion USING btree (modalidad_id);


--
-- Name: proyectos_graduacion_tutor_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX proyectos_graduacion_tutor_id_idx ON public.proyectos_graduacion USING btree (tutor_id);


--
-- Name: recuperaciones_matricula_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recuperaciones_matricula_id_idx ON public.recuperaciones USING btree (matricula_id);


--
-- Name: resultados_finales_regla_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resultados_finales_regla_id_idx ON public.resultados_finales USING btree (regla_id);


--
-- Name: tramites_matricula_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tramites_matricula_id_idx ON public.tramites USING btree (matricula_id);


--
-- Name: tribunales_docente_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tribunales_docente_id_idx ON public.tribunales USING btree (docente_id);


--
-- Name: recuperaciones no_borrar_recuperacion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER no_borrar_recuperacion BEFORE DELETE ON public.recuperaciones FOR EACH ROW EXECUTE FUNCTION public.proteger_recuperacion();


--
-- Name: recuperaciones no_editar_recuperacion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER no_editar_recuperacion BEFORE UPDATE ON public.recuperaciones FOR EACH ROW EXECUTE FUNCTION public.proteger_recuperacion();


--
-- Name: asistencias_sesion validar_asistencia_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validar_asistencia_insert BEFORE INSERT ON public.asistencias_sesion FOR EACH ROW EXECUTE FUNCTION public.validar_asistencia();


--
-- Name: asistencias_sesion validar_asistencia_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validar_asistencia_update BEFORE UPDATE ON public.asistencias_sesion FOR EACH ROW EXECUTE FUNCTION public.validar_asistencia();


--
-- Name: recuperaciones validar_recuperacion; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validar_recuperacion BEFORE INSERT ON public.recuperaciones FOR EACH ROW EXECUTE FUNCTION public.validar_recuperacion();


--
-- Name: dim_materia dim_materia_carrera_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.dim_materia
    ADD CONSTRAINT dim_materia_carrera_id_fkey FOREIGN KEY (carrera_id) REFERENCES dw.dim_carrera(carrera_id);


--
-- Name: fact_matriculas fact_matriculas_carrera_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_matriculas
    ADD CONSTRAINT fact_matriculas_carrera_id_fkey FOREIGN KEY (carrera_id) REFERENCES dw.dim_carrera(carrera_id);


--
-- Name: fact_matriculas fact_matriculas_estudiante_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_matriculas
    ADD CONSTRAINT fact_matriculas_estudiante_id_fkey FOREIGN KEY (estudiante_id) REFERENCES dw.dim_estudiante(estudiante_id);


--
-- Name: fact_matriculas fact_matriculas_fecha_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_matriculas
    ADD CONSTRAINT fact_matriculas_fecha_fkey FOREIGN KEY (fecha) REFERENCES dw.dim_tiempo(fecha);


--
-- Name: fact_matriculas fact_matriculas_gestion_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_matriculas
    ADD CONSTRAINT fact_matriculas_gestion_id_fkey FOREIGN KEY (gestion_id) REFERENCES dw.dim_gestion(gestion_id);


--
-- Name: fact_pagos fact_pagos_carrera_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_pagos
    ADD CONSTRAINT fact_pagos_carrera_id_fkey FOREIGN KEY (carrera_id) REFERENCES dw.dim_carrera(carrera_id);


--
-- Name: fact_pagos fact_pagos_estudiante_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_pagos
    ADD CONSTRAINT fact_pagos_estudiante_id_fkey FOREIGN KEY (estudiante_id) REFERENCES dw.dim_estudiante(estudiante_id);


--
-- Name: fact_pagos fact_pagos_fecha_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_pagos
    ADD CONSTRAINT fact_pagos_fecha_fkey FOREIGN KEY (fecha) REFERENCES dw.dim_tiempo(fecha);


--
-- Name: fact_pagos fact_pagos_gestion_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_pagos
    ADD CONSTRAINT fact_pagos_gestion_id_fkey FOREIGN KEY (gestion_id) REFERENCES dw.dim_gestion(gestion_id);


--
-- Name: fact_resultados fact_resultados_carrera_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_resultados
    ADD CONSTRAINT fact_resultados_carrera_id_fkey FOREIGN KEY (carrera_id) REFERENCES dw.dim_carrera(carrera_id);


--
-- Name: fact_resultados fact_resultados_docente_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_resultados
    ADD CONSTRAINT fact_resultados_docente_id_fkey FOREIGN KEY (docente_id) REFERENCES dw.dim_docente(docente_id);


--
-- Name: fact_resultados fact_resultados_estudiante_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_resultados
    ADD CONSTRAINT fact_resultados_estudiante_id_fkey FOREIGN KEY (estudiante_id) REFERENCES dw.dim_estudiante(estudiante_id);


--
-- Name: fact_resultados fact_resultados_fecha_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_resultados
    ADD CONSTRAINT fact_resultados_fecha_fkey FOREIGN KEY (fecha) REFERENCES dw.dim_tiempo(fecha);


--
-- Name: fact_resultados fact_resultados_gestion_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_resultados
    ADD CONSTRAINT fact_resultados_gestion_id_fkey FOREIGN KEY (gestion_id) REFERENCES dw.dim_gestion(gestion_id);


--
-- Name: fact_resultados fact_resultados_materia_id_fkey; Type: FK CONSTRAINT; Schema: dw; Owner: -
--

ALTER TABLE ONLY dw.fact_resultados
    ADD CONSTRAINT fact_resultados_materia_id_fkey FOREIGN KEY (materia_id) REFERENCES dw.dim_materia(materia_id);


--
-- Name: app_auditoria app_auditoria_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_auditoria
    ADD CONSTRAINT app_auditoria_ibfk_1 FOREIGN KEY (usuario_id) REFERENCES public.app_usuarios(id);


--
-- Name: app_usuarios app_usuarios_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_usuarios
    ADD CONSTRAINT app_usuarios_ibfk_1 FOREIGN KEY (docente_id) REFERENCES public.docentes(id);


--
-- Name: asistencias_demo_historicas asistencias_demo_historicas_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_demo_historicas
    ADD CONSTRAINT asistencias_demo_historicas_ibfk_1 FOREIGN KEY (inscripcion_id) REFERENCES public.inscripciones(id);


--
-- Name: asistencias_sesion asistencias_sesion_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_sesion
    ADD CONSTRAINT asistencias_sesion_ibfk_1 FOREIGN KEY (inscripcion_id, oferta_id) REFERENCES public.inscripciones(id, oferta_id);


--
-- Name: asistencias_sesion asistencias_sesion_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_sesion
    ADD CONSTRAINT asistencias_sesion_ibfk_2 FOREIGN KEY (sesion_id, oferta_id) REFERENCES public.sesiones(id, oferta_id);


--
-- Name: calificaciones calificaciones_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calificaciones
    ADD CONSTRAINT calificaciones_ibfk_1 FOREIGN KEY (inscripcion_id, oferta_id) REFERENCES public.inscripciones(id, oferta_id);


--
-- Name: calificaciones calificaciones_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calificaciones
    ADD CONSTRAINT calificaciones_ibfk_2 FOREIGN KEY (evaluacion_id, oferta_id) REFERENCES public.evaluaciones(id, oferta_id);


--
-- Name: cargos cargos_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT cargos_ibfk_1 FOREIGN KEY (matricula_id) REFERENCES public.matriculas(id);


--
-- Name: cierres_oferta cierres_oferta_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cierres_oferta
    ADD CONSTRAINT cierres_oferta_ibfk_1 FOREIGN KEY (oferta_id) REFERENCES public.ofertas(id);


--
-- Name: defensas defensas_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.defensas
    ADD CONSTRAINT defensas_ibfk_1 FOREIGN KEY (proyecto_id) REFERENCES public.proyectos_graduacion(id);


--
-- Name: defensas defensas_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.defensas
    ADD CONSTRAINT defensas_ibfk_2 FOREIGN KEY (aula_id) REFERENCES public.aulas(id);


--
-- Name: documentos_matricula documentos_matricula_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos_matricula
    ADD CONSTRAINT documentos_matricula_ibfk_1 FOREIGN KEY (matricula_id) REFERENCES public.matriculas(id);


--
-- Name: documentos_matricula documentos_matricula_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos_matricula
    ADD CONSTRAINT documentos_matricula_ibfk_2 FOREIGN KEY (tipo_documento_id) REFERENCES public.tipos_documento(id);


--
-- Name: evaluaciones evaluaciones_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluaciones
    ADD CONSTRAINT evaluaciones_ibfk_1 FOREIGN KEY (oferta_id) REFERENCES public.ofertas(id);


--
-- Name: excepciones_asistencia excepciones_asistencia_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.excepciones_asistencia
    ADD CONSTRAINT excepciones_asistencia_ibfk_1 FOREIGN KEY (inscripcion_id) REFERENCES public.inscripciones(id);


--
-- Name: grupo_integrantes grupo_integrantes_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_integrantes
    ADD CONSTRAINT grupo_integrantes_ibfk_1 FOREIGN KEY (grupo_id) REFERENCES public.grupos(id);


--
-- Name: grupo_integrantes grupo_integrantes_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_integrantes
    ADD CONSTRAINT grupo_integrantes_ibfk_2 FOREIGN KEY (matricula_id) REFERENCES public.matriculas(id);


--
-- Name: grupo_materias grupo_materias_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_materias
    ADD CONSTRAINT grupo_materias_ibfk_1 FOREIGN KEY (grupo_id) REFERENCES public.grupos(id);


--
-- Name: grupo_materias grupo_materias_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupo_materias
    ADD CONSTRAINT grupo_materias_ibfk_2 FOREIGN KEY (oferta_id) REFERENCES public.ofertas(id);


--
-- Name: grupos grupos_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupos
    ADD CONSTRAINT grupos_ibfk_1 FOREIGN KEY (periodo_id) REFERENCES public.periodos(id);


--
-- Name: grupos grupos_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupos
    ADD CONSTRAINT grupos_ibfk_2 FOREIGN KEY (carrera_id) REFERENCES public.carreras(id);


--
-- Name: grupos grupos_ibfk_3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupos
    ADD CONSTRAINT grupos_ibfk_3 FOREIGN KEY (tutor_id) REFERENCES public.docentes(id);


--
-- Name: horarios horarios_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horarios
    ADD CONSTRAINT horarios_ibfk_1 FOREIGN KEY (oferta_id) REFERENCES public.ofertas(id);


--
-- Name: horarios horarios_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horarios
    ADD CONSTRAINT horarios_ibfk_2 FOREIGN KEY (aula_id) REFERENCES public.aulas(id);


--
-- Name: inscripciones inscripciones_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT inscripciones_ibfk_1 FOREIGN KEY (matricula_id, carrera_id, periodo_id) REFERENCES public.matriculas(id, carrera_id, periodo_id);


--
-- Name: inscripciones inscripciones_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT inscripciones_ibfk_2 FOREIGN KEY (oferta_id, carrera_id, periodo_id) REFERENCES public.ofertas(id, carrera_id, periodo_id);


--
-- Name: materias materias_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materias
    ADD CONSTRAINT materias_ibfk_1 FOREIGN KEY (carrera_id) REFERENCES public.carreras(id);


--
-- Name: matriculas matriculas_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_ibfk_1 FOREIGN KEY (estudiante_id) REFERENCES public.estudiantes(id);


--
-- Name: matriculas matriculas_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_ibfk_2 FOREIGN KEY (carrera_id) REFERENCES public.carreras(id);


--
-- Name: matriculas matriculas_ibfk_3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_ibfk_3 FOREIGN KEY (periodo_id) REFERENCES public.periodos(id);


--
-- Name: matriculas matriculas_ibfk_4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_ibfk_4 FOREIGN KEY (plan_id, carrera_id) REFERENCES public.planes_estudio(id, carrera_id);


--
-- Name: notas_demo_historicas notas_demo_historicas_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notas_demo_historicas
    ADD CONSTRAINT notas_demo_historicas_ibfk_1 FOREIGN KEY (inscripcion_id) REFERENCES public.inscripciones(id);


--
-- Name: ofertas ofertas_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_ibfk_1 FOREIGN KEY (materia_id, carrera_id) REFERENCES public.materias(id, carrera_id);


--
-- Name: ofertas ofertas_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_ibfk_2 FOREIGN KEY (periodo_id) REFERENCES public.periodos(id);


--
-- Name: ofertas ofertas_ibfk_3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_ibfk_3 FOREIGN KEY (docente_id) REFERENCES public.docentes(id);


--
-- Name: pagos pagos_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_ibfk_1 FOREIGN KEY (cargo_id) REFERENCES public.cargos(id);


--
-- Name: pasantias pasantias_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pasantias
    ADD CONSTRAINT pasantias_ibfk_1 FOREIGN KEY (matricula_id) REFERENCES public.matriculas(id);


--
-- Name: pasantias pasantias_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pasantias
    ADD CONSTRAINT pasantias_ibfk_2 FOREIGN KEY (tutor_id) REFERENCES public.docentes(id);


--
-- Name: plan_materias plan_materias_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_materias
    ADD CONSTRAINT plan_materias_ibfk_1 FOREIGN KEY (plan_id, carrera_id) REFERENCES public.planes_estudio(id, carrera_id);


--
-- Name: plan_materias plan_materias_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_materias
    ADD CONSTRAINT plan_materias_ibfk_2 FOREIGN KEY (materia_id, carrera_id) REFERENCES public.materias(id, carrera_id);


--
-- Name: planes_estudio planes_estudio_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_estudio
    ADD CONSTRAINT planes_estudio_ibfk_1 FOREIGN KEY (carrera_id) REFERENCES public.carreras(id);


--
-- Name: planes_estudio planes_estudio_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_estudio
    ADD CONSTRAINT planes_estudio_ibfk_2 FOREIGN KEY (regla_id) REFERENCES public.reglas_evaluacion(id);


--
-- Name: prerrequisitos prerrequisitos_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prerrequisitos
    ADD CONSTRAINT prerrequisitos_ibfk_1 FOREIGN KEY (plan_id, materia_id) REFERENCES public.plan_materias(plan_id, materia_id);


--
-- Name: prerrequisitos prerrequisitos_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prerrequisitos
    ADD CONSTRAINT prerrequisitos_ibfk_2 FOREIGN KEY (plan_id, requerida_id) REFERENCES public.plan_materias(plan_id, materia_id);


--
-- Name: proyectos_graduacion proyectos_graduacion_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_graduacion
    ADD CONSTRAINT proyectos_graduacion_ibfk_1 FOREIGN KEY (matricula_id) REFERENCES public.matriculas(id);


--
-- Name: proyectos_graduacion proyectos_graduacion_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_graduacion
    ADD CONSTRAINT proyectos_graduacion_ibfk_2 FOREIGN KEY (modalidad_id) REFERENCES public.modalidades_graduacion(id);


--
-- Name: proyectos_graduacion proyectos_graduacion_ibfk_3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proyectos_graduacion
    ADD CONSTRAINT proyectos_graduacion_ibfk_3 FOREIGN KEY (tutor_id) REFERENCES public.docentes(id);


--
-- Name: recuperaciones recuperaciones_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperaciones
    ADD CONSTRAINT recuperaciones_ibfk_1 FOREIGN KEY (inscripcion_id) REFERENCES public.resultados_finales(inscripcion_id);


--
-- Name: recuperaciones recuperaciones_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperaciones
    ADD CONSTRAINT recuperaciones_ibfk_2 FOREIGN KEY (matricula_id) REFERENCES public.matriculas(id);


--
-- Name: resultados_finales resultados_finales_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resultados_finales
    ADD CONSTRAINT resultados_finales_ibfk_1 FOREIGN KEY (inscripcion_id) REFERENCES public.inscripciones(id);


--
-- Name: resultados_finales resultados_finales_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resultados_finales
    ADD CONSTRAINT resultados_finales_ibfk_2 FOREIGN KEY (regla_id) REFERENCES public.reglas_evaluacion(id);


--
-- Name: sesiones sesiones_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sesiones
    ADD CONSTRAINT sesiones_ibfk_1 FOREIGN KEY (oferta_id) REFERENCES public.ofertas(id);


--
-- Name: tramites tramites_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tramites
    ADD CONSTRAINT tramites_ibfk_1 FOREIGN KEY (matricula_id) REFERENCES public.matriculas(id);


--
-- Name: tribunales tribunales_ibfk_1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tribunales
    ADD CONSTRAINT tribunales_ibfk_1 FOREIGN KEY (defensa_id) REFERENCES public.defensas(id);


--
-- Name: tribunales tribunales_ibfk_2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tribunales
    ADD CONSTRAINT tribunales_ibfk_2 FOREIGN KEY (docente_id) REFERENCES public.docentes(id);


--
-- PostgreSQL database dump complete
--

\unrestrict 22gI9LU6gkgBctCdHnMX0xVWAbMlGpgm2ns5QbNcnt674LMA5dVJvXoVKpbkljP

