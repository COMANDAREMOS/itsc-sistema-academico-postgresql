import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const sources = ['../../../db/schema-metadata.json','../../../../prisma/schema-metadata.json','../../../prisma/schema-metadata.json','../../../../db/schema-metadata.json'].map(relative=>path.resolve(here,relative));
const source = sources.find(candidate=>fs.existsSync(candidate));
if(!source) throw new Error('No se encontró db/schema-metadata.json ni prisma/schema-metadata.json.');
const output = path.resolve(here, '../diagrama-clases.html');
const raw = JSON.parse(fs.readFileSync(source, 'utf8').replace(/^\uFEFF/, ''));
const names = {
  app_auditoria:'RegistroActividad',app_intentos:'IntentoAcceso',app_usuarios:'Usuario',asistencias_demo_historicas:'AsistenciaHistorica',asistencias_sesion:'Asistencia',aulas:'Aula',calificaciones:'Calificacion',cargos:'Cargo',carreras:'Carrera',cierres_oferta:'CierreAcademico',defensas:'Defensa',docentes:'Docente',documentos_matricula:'DocumentoMatricula',estudiantes:'Estudiante',evaluaciones:'Evaluacion',excepciones_asistencia:'Justificacion',grupo_integrantes:'IntegranteGrupo',grupo_materias:'MateriaGrupo',grupos:'Grupo',horarios:'Horario',inscripciones:'Inscripcion',materias:'Materia',matriculas:'Matricula',modalidades_graduacion:'ModalidadGraduacion',notas_demo_historicas:'NotaHistorica',ofertas:'OfertaMateria',pagos:'Pago',pasantias:'Pasantia',periodos:'Gestion',plan_materias:'MateriaPlan',planes_estudio:'PlanEstudio',prerrequisitos:'Prerrequisito',proyectos_graduacion:'ProyectoGraduacion',recuperaciones:'Recuperacion',reglas_evaluacion:'ReglaEvaluacion',resultados_finales:'ResultadoFinal',sesiones:'SesionClase',tipos_documento:'TipoDocumento',tramites:'Tramite',tribunales:'Tribunal',
};
const groups = {
  'Comunidad y accesos':['estudiantes','docentes','app_usuarios','app_auditoria','app_intentos'],
  'Catálogo académico':['carreras','materias','planes_estudio','plan_materias','prerrequisitos','reglas_evaluacion'],
  'Gestión e inscripción':['periodos','grupos','grupo_integrantes','grupo_materias','matriculas','ofertas','inscripciones'],
  'Clases y evaluación':['aulas','horarios','sesiones','evaluaciones','calificaciones','asistencias_sesion','excepciones_asistencia','cierres_oferta','resultados_finales','recuperaciones'],
  'Caja y servicios':['cargos','pagos','tipos_documento','documentos_matricula','tramites','pasantias'],
  'Graduación e histórico':['modalidades_graduacion','proyectos_graduacion','defensas','tribunales','asistencias_demo_historicas','notas_demo_historicas'],
};
const sameSet = (a,b) => a.length === b.length && a.every(x => b.includes(x));
const entities = Object.values(raw).map(table => ({
  table: table.name,
  name: names[table.name] || table.name,
  section: Object.entries(groups).find(([,tables])=>tables.includes(table.name))?.[0] || 'Otros',
  pk: table.pk,
  fields: table.fields.map(field => ({name:field.name,type:field.prisma_type,nullable:field.nullable,pk:table.pk.includes(field.name),fk:table.fks.some(fk=>fk.local.includes(field.name))})),
  fks: table.fks.map(fk=>({local:fk.local,target:fk.target,remote:fk.remote,parentCardinality:fk.local.some(name=>table.fields.find(f=>f.name===name)?.nullable)?'0..1':'1',childCardinality:sameSet(table.pk,fk.local)||table.uniques.some(unique=>sameSet(unique.columns||unique,fk.local))?'0..1':'0..*'})),
}));
if(entities.length!==40) throw new Error(`Se esperaban 40 clases; hay ${entities.length}.`);
const ids = new Set(entities.map(entity=>entity.table));
entities.forEach(entity=>entity.fks.forEach(fk=>{if(!ids.has(fk.target))throw new Error(`Relación sin destino: ${entity.table} -> ${fk.target}`);}));
const encoded = JSON.stringify({entities,sections:Object.keys(groups)}).replace(/</g,'\\u003c');
const template = fs.readFileSync(path.join(here,'plantilla.html'),'utf8');
if(!template.includes('__SCHEMA_JSON__'))throw new Error('Falta el marcador de metadatos.');
const document = template.replace('__SCHEMA_JSON__',encoded);
for(const match of document.matchAll(/<script>([\s\S]*?)<\/script>/g)) new Function(match[1]);
fs.writeFileSync(output,document,'utf8');
console.log(JSON.stringify({output,clases:entities.length,relacionesFK:entities.reduce((sum,entity)=>sum+entity.fks.length,0),autonomo:true}));
