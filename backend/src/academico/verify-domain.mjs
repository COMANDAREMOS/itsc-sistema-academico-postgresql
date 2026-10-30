import 'reflect-metadata';
import { config } from 'dotenv';
import { PrismaService } from '../common/prisma.service.ts';
import { AcademicoService } from './academico.service.ts';

config({ quiet:true });
const db=new PrismaService();
const service=new AcademicoService(db);
let checked=0;
const users=await db.app_usuarios.findMany({where:{activo:1},select:{id:true,usuario:true,nombre:true,rol:true,docente_id:true}});
const admin=users.find(u=>u.rol==='ADMIN');
if(!admin)throw Error('Falta el acceso de administración para la verificación.');
try {
 for(const user of users){
  for(const mod of service.metadata(user).modules){
   const result=await service.list(mod.key,{pageSize:3},user);
   if(!Array.isArray(result.rows)||!Array.isArray(result.columns))throw Error('Contrato de listado inválido: '+mod.key);
   if(user.rol==='DOCENTE'&&result.rows.some(row=>row.docente_id!==undefined&&row.docente_id!==user.docente_id))throw Error('Filtro de docente inválido: '+mod.key);
   if(mod.editable&&result.rows.length)await service.detail(mod.key,String(result.rows[0].id),user);
   checked++;
  }
  await service.dashboard({},user);checked++;
 }
 for(const source of ['estudiantes','docentes','carreras','periodos','planes','reglas','materias','grupos','ofertas','matriculas','inscripciones','evaluaciones','sesiones','aulas','cargos','tipos_documento','modalidades','proyectos','defensas']){
  const result=await service.options(source,{},admin);if(!Array.isArray(result))throw Error('Contrato de opciones inválido: '+source);checked++;
 }
 await service.list('estudiantes',{q:"%_! ' OR 1=1",page:1},admin);checked++;
 for(const group of await db.grupos.findMany()) {await service.candidates(String(group.id),{},admin);checked++;}
 console.log(JSON.stringify({verified:checked,status:'passed',changes:'none',description:'Listados de todos los roles, opciones, detalles, paneles y candidatos.'}));
} finally {await db.$disconnect();}
