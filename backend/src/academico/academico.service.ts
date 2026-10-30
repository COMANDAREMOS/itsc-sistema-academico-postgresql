import { Injectable, BadRequestException, ForbiddenException, NotFoundException, ConflictException, HttpException } from '@nestjs/common';
import { PrismaService } from '../common/prisma.service.js';
import { hashPassword } from '../auth/password.js';
import { MODULOS, MODULE_MAP, type Modulo, type Usuario } from './catalogo.js';
import { LISTADOS, LABELS } from './listados.js';

const positive = (value: any, label = 'identificador'): number => {
 const number = Number(value);
 if (!['string','number'].includes(typeof value) || value==='' || !Number.isSafeInteger(number) || number < 1 || number > 2147483647) throw new BadRequestException(`El ${label} debe ser un entero positivo.`);
 return number;
};
const num = (value: any, min: number, max: number, label: string): number => {
 if (value === '' || !['string','number'].includes(typeof value) || !Number.isFinite(Number(value)) || Number(value)<min || Number(value)>max) throw new BadRequestException(`${label}: usa un valor entre ${min} y ${max}.`);
 return Number(value);
};
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/La_Paz' });
const date = (value: any, datetime = false) => {
 const text = String(value ?? '');
 const pattern = datetime ? /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/ : /^\d{4}-\d{2}-\d{2}$/;
 if (!pattern.test(text)) throw new BadRequestException('La fecha no tiene un formato válido.');
 const d = new Date(text + (datetime ? 'Z' : 'T00:00:00Z'));
 if (!Number.isFinite(d.valueOf()) || d.toISOString().slice(0,10)!==text.slice(0,10)) throw new BadRequestException('La fecha no existe.');
 return d;
};
const minutes = (value: Date | string): number => { const d = new Date(value); return d.getUTCHours()*60+d.getUTCMinutes(); };
const round = (value: number, places = 5) => Number(value.toFixed(places));

@Injectable()
export class AcademicoService {
 constructor(public readonly prisma: PrismaService) {}
 private module(key: string, user: Usuario, write=false): Modulo {
  const m=MODULE_MAP[key];
  if(!m) throw new NotFoundException('La pantalla solicitada no existe.');
  if(!m.roles.includes(user.rol) || (write && (!m.writeRoles.includes(user.rol) || m.readonly))) throw new ForbiddenException('Tu rol no permite realizar esta operación.');
  return m;
 }
 metadata(user: Usuario) {
  return {modules:MODULOS.filter(m=>m.roles.includes(user.rol)).map(m=>({...m,table:undefined,writeRoles:undefined,readonly:m.readonly || !m.writeRoles.includes(user.rol),editable:!!m.editable&&m.writeRoles.includes(user.rol),deletable:!!m.deletable&&m.writeRoles.includes(user.rol)}))};
 }
 private async raw(db:any,sql:string,args:any[]=[]):Promise<any[]> { return db.$queryRawUnsafe(sql,...args); }
 private async audit(db:any,user:Usuario,accion:string,entidad:string,id:any) {
  await db.app_auditoria.create({data:{usuario_id:user.id,accion,entidad,registro_id:id==null?null:String(id).slice(0,50)}});
 }
 private async serialize(db:any) { await this.raw(db,'SELECT pg_advisory_xact_lock(74824601)::text'); }
 private async transaction<T>(fn:(tx:any)=>Promise<T>):Promise<T> {
  try { return await this.prisma.$transaction(async tx=>{await this.serialize(tx);return fn(tx);},{maxWait:15000,timeout:45000}) as T; }
  catch(error:any) {
   if(error instanceof HttpException) throw error;
   if(error.code==='P2002') throw new ConflictException('Ya existe un registro con esos datos. Revisa documento, registro, recibo o asignación.');
   if(error.code==='P2003') throw new ConflictException('El registro está relacionado con otros datos o una selección ya no existe.');
   if(error.code==='P2025') throw new NotFoundException('El registro ya no existe. Actualiza la pantalla.');
   if(error.code==='P2000') throw new BadRequestException('Uno de los campos supera la longitud permitida.');
   if(error.code==='P2010' || error.code==='P2004') {
    const text=String(error.meta?.message??error.message??'');
    const message=text.match(/(?:ERROR:\s*|P0001:\s*)([^\n]+)/)?.[1];
    if(message) throw new BadRequestException(message.replace(/\s*CONTEXT:.*/,''));
    throw new BadRequestException('Los datos no cumplen una regla de la base de datos. Revisa las selecciones y valores.');
   }
   throw error;
  }
 }
 async list(key:string,query:any,user:Usuario) {
  this.module(key,user);
  const definition=LISTADOS[key];
  if(!definition) return {rows:[],total:0,page:1,pageSize:20,columns:[]};
  const pageSize=Math.min(100,positive(query.pageSize??20,'tamaño de página'));
  let page=positive(query.page??1,'número de página');
  const args:any[]=[];const predicates:string[]=[];
  const add=(column:string,value:any)=>{args.push(value);predicates.push(`listado."${column}"=$${args.length}`);};
  if(user.rol==='DOCENTE'&&definition.docente) add(definition.docente,user.docente_id);
  for(const [param,column] of [['periodo_id',definition.periodo],['carrera_id',definition.carrera],['grupo_id',definition.grupo]] as [string,string|undefined][]) if(query[param]&&column) add(column,positive(query[param]));
  if(query.oferta_id && ['evaluaciones','notas','sesiones','asistencias','cierres','inscripciones','horarios','grupo_materias'].includes(key)) add('oferta_id',positive(query.oferta_id));
  if(query.q){args.push('%'+String(query.q).slice(0,200).replace(/[!%_]/g,'!$&')+'%');predicates.push(`row_to_json(listado)::text ILIKE $${args.length} ESCAPE '!'`);}
  const from=`FROM (${definition.sql}) listado${predicates.length?' WHERE '+predicates.join(' AND '):''}`;
  const count=await this.raw(this.prisma,`SELECT count(*)::int AS total ${from}`,args);
  const total=count[0].total;page=Math.min(page,Math.max(1,Math.ceil(total/pageSize)));
  const rows=await this.raw(this.prisma,`SELECT * ${from} ORDER BY listado.id DESC NULLS LAST LIMIT $${args.length+1} OFFSET $${args.length+2}`,[...args,pageSize,(page-1)*pageSize]);
  return {rows,total,page,pageSize,columns:definition.columns.map(key=>({key,label:LABELS[key]??(key[0].toUpperCase()+key.slice(1).replaceAll('_',' '))}))};
 }
 async detail(key:string,idText:string,user:Usuario) {
  const m=this.module(key,user);if(!m.table) throw new NotFoundException('Esta pantalla no tiene registros editables.');
  let where:any;
  if(['notas','asistencias','plan_materias','prerrequisitos','tribunales'].includes(key)){
   const ids=idText.split('-').map(id=>positive(id));
   if(key==='notas'&&ids.length===2)where={inscripcion_id_evaluacion_id:{inscripcion_id:ids[0],evaluacion_id:ids[1]}};
   else if(key==='asistencias'&&ids.length===2)where={inscripcion_id_sesion_id:{inscripcion_id:ids[0],sesion_id:ids[1]}};
   else if(key==='plan_materias'&&ids.length===2)where={plan_id_materia_id:{plan_id:ids[0],materia_id:ids[1]}};
   else if(key==='prerrequisitos'&&ids.length===3)where={plan_id_materia_id_requerida_id:{plan_id:ids[0],materia_id:ids[1],requerida_id:ids[2]}};
   else if(key==='tribunales'&&ids.length===2)where={defensa_id_docente_id:{defensa_id:ids[0],docente_id:ids[1]}};
   else throw new BadRequestException('Usa el identificador compuesto completo del registro.');
  }else where={[m.pk&&m.pk!=='composite'?m.pk:'id']:positive(idText)};
  const data=await (this.prisma as any)[m.table].findUnique({where});
  if(!data) throw new NotFoundException('Registro inexistente.');
  if(user.rol==='DOCENTE'){const offerId=data.oferta_id??(key==='ofertas'?data.id:null);if(!offerId)throw new ForbiddenException('No tienes acceso a este registro.');await this.offer(this.prisma,offerId,user,false,false);}
  if(key==='usuarios')delete data.password_hash;
  for(const field of m.fields) if(data[field.name] instanceof Date) data[field.name]=field.type==='time'?data[field.name].toISOString().slice(11,16):field.type==='date'?data[field.name].toISOString().slice(0,10):data[field.name].toISOString().slice(0,16);
  return data;
 }
 private values(m:Modulo,body:any) {
  if(!body||typeof body!=='object'||Array.isArray(body))throw new BadRequestException('Los datos del formulario no son válidos.');
  const result:any={};
  for(const field of m.fields){
   const value=body[field.name];
   if(value===undefined||value===null||value===''){if(field.required)throw new BadRequestException(`Completa el campo «${field.label}».`);result[field.name]=null;continue;}
   if(typeof value==='object'||typeof value==='boolean')throw new BadRequestException(`Valor inválido en «${field.label}».`);
   if(field.source || field.name.endsWith('_id'))result[field.name]=positive(value,field.label);
   else if(field.type==='number') {const n=num(value,0,2147483647,field.label);if(!Number.isInteger(n))throw new BadRequestException(`${field.label} debe ser un número entero.`);result[field.name]=n;}
   else if(field.type==='decimal')result[field.name]=num(value,0,99999999,field.label);
   else if(field.type==='date'||field.type==='datetime-local')result[field.name]=date(value,field.type==='datetime-local');
   else if(field.type==='time'){if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(String(value)))throw new BadRequestException('Usa horas en formato HH:MM.');result[field.name]=new Date('1970-01-01T'+value+':00Z');}
   else {result[field.name]=String(value).trim();if(!result[field.name]&&field.required)throw new BadRequestException(`Completa «${field.label}».`);if(result[field.name].length>5000)throw new BadRequestException(`${field.label} es demasiado largo.`);}
   if(field.options){const option=field.options.find(o=>String(o.value)===String(value));if(!option)throw new BadRequestException(`Selecciona una opción válida en «${field.label}».`);if(typeof option.value==='number')result[field.name]=option.value;}
   if(field.name==='activa')result.activa=Number(value);
   if(field.type==='email'&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value)))throw new BadRequestException('El correo electrónico no es válido.');
  }
  return result;
 }
 private async offer(db:any,id:number,user:Usuario,editable=true,lock=true) {
  if(lock) await this.raw(db,'SELECT id FROM ofertas WHERE id=$1 FOR UPDATE',[id]);
  const offer=await db.ofertas.findUnique({where:{id}});
  if(!offer)throw new NotFoundException('La oferta no existe.');
  if(user.rol==='DOCENTE'&&offer.docente_id!==user.docente_id)throw new ForbiddenException('No tienes acceso a esta oferta de materia.');
  if(editable&&await db.cierres_oferta.findUnique({where:{oferta_id:id}}))throw new ConflictException('La oferta está cerrada. No admite cambios académicos.');
  return offer;
 }
 private async enrollment(db:any,id:number,user:Usuario,editable=true) {
  const ins=await db.inscripciones.findUnique({where:{id}});if(!ins)throw new NotFoundException('La inscripción no existe.');
  await this.offer(db,ins.oferta_id,user,editable);
  if(ins.estado==='RETIRADA')throw new ConflictException('La inscripción fue retirada.');return ins;
 }
 private async group(db:any,id:number) {
  await this.raw(db,'SELECT id FROM grupos WHERE id=$1 FOR UPDATE',[id]);
  const group=await db.grupos.findUnique({where:{id}});if(!group)throw new NotFoundException('El grupo no existe.');
  if(group.estado!=='ACTIVO')throw new ConflictException('El grupo está cerrado.');return group;
 }
 private parallel(value:string){const normalized=value.toUpperCase().trim();if(!/^[A-Z0-9-]{1,10}$/.test(normalized))throw new BadRequestException('El paralelo admite hasta 10 letras, números o guiones.');return normalized;}
 async save(key:string,body:any,user:Usuario,idText?:string) {
  const m=this.module(key,user,true);
  const id=idText?positive(idText):undefined;
  if(id&&key==='usuarios')return this.toggleUser(id,body,user);
  if(id&&!m.editable)throw new ForbiddenException('Esta pantalla no permite editar registros.');
  const data=this.values(m,body);
  return this.transaction(async db=>{
   if(id){const existing=await db[m.table!].findUnique({where:{id}});if(!existing)throw new NotFoundException('Registro inexistente.');}
   let result:any;
   switch(key){
    case 'estudiantes':if(data.fecha_nacimiento.toISOString().slice(0,10)>today())throw new BadRequestException('La fecha de nacimiento no puede ser futura.');break;
    case 'periodos':
     if(data.fecha_fin<data.fecha_inicio)throw new BadRequestException('La fecha final debe ser posterior o igual a la inicial.');
     if(id){const previous=await db.periodos.findUnique({where:{id}});if(+previous.fecha_inicio!==+data.fecha_inicio||+previous.fecha_fin!==+data.fecha_fin){const count=await this.raw(db,'SELECT count(*)::int AS n FROM horarios h JOIN ofertas o ON o.id=h.oferta_id WHERE o.periodo_id=$1',[id]);if(count[0].n)throw new ConflictException('La gestión tiene horarios. Retíralos antes de cambiar sus fechas.');}}
     break;
    case 'carreras':num(data.duracion_anios,1,10,'Duración');if(id){const previous=await db.carreras.findUnique({where:{id}});if(previous.regimen!==data.regimen&&await db.matriculas.count({where:{carrera_id:id}}))throw new ConflictException('La carrera tiene matrículas. Conserva su régimen para mantener las reglas académicas aplicadas.');}break;
    case 'materias':num(data.nivel_curso,1,6,'Curso');if(id){const previous=await db.materias.findUnique({where:{id}});if(previous.nivel_curso!==data.nivel_curso){const linked=await this.raw(db,'SELECT gm.id FROM grupo_materias gm JOIN ofertas o ON o.id=gm.oferta_id WHERE o.materia_id=$1 LIMIT 1',[id]);if(linked.length)throw new ConflictException('La materia está vinculada a grupos. Conserva su curso o desvincula primero las ofertas.');}}break;
    case 'aulas':num(data.capacidad,1,1000,'Capacidad');if(id){const conflicts=await this.raw(db,'SELECT h.id FROM horarios h JOIN ofertas o ON o.id=h.oferta_id WHERE h.aula_id=$1 AND o.cupo>$2 LIMIT 1',[id,data.capacidad]);if(conflicts.length)throw new ConflictException('Hay ofertas programadas con cupo mayor a la capacidad propuesta.');}break;
    case 'planes':await this.exists(db,'carreras',data.carrera_id);await this.exists(db,'reglas_evaluacion',data.regla_id);if(id&&await db.matriculas.count({where:{plan_id:id}})){const previous=await db.planes_estudio.findUnique({where:{id}});if(previous.carrera_id!==data.carrera_id||previous.regla_id!==data.regla_id)throw new ConflictException('El plan ya tiene matrículas. Conserva la carrera y regla de evaluación.');}break;
    case 'plan_materias': {const plan=await this.exists(db,'planes_estudio',data.plan_id);const subject=await this.exists(db,'materias',data.materia_id);if(plan.carrera_id!==subject.carrera_id)throw new BadRequestException('La materia y el plan deben pertenecer a la misma carrera.');data.carrera_id=plan.carrera_id;break;}
    case 'prerrequisitos':await this.prerequisite(db,data);break;
    case 'grupos':await this.validateGroup(db,data,id);break;
    case 'integrantes':result=await this.addMember(db,data.grupo_id,data.matricula_id);break;
    case 'grupo_materias':result=await this.linkSubject(db,data.grupo_id,data.oferta_id,user);break;
    case 'ofertas':{const subject=await this.exists(db,'materias',data.materia_id);data.carrera_id=subject.carrera_id;data.paralelo=this.parallel(data.paralelo);num(data.cupo,1,1000,'Cupo');break;}
    case 'matriculas':{const plan=await this.exists(db,'planes_estudio',data.plan_id);data.carrera_id=plan.carrera_id;break;}
    case 'inscripciones':result=await this.inscribe(db,data.matricula_id,data.oferta_id,data.fecha,user);break;
    case 'evaluaciones':{await this.offer(db,data.oferta_id,user);num(data.peso,0.001,100,'Peso');const others=await db.evaluaciones.aggregate({where:{oferta_id:data.oferta_id,componente:data.componente},_sum:{peso:true}});if(Number(others._sum.peso??0)+data.peso>100.00001)throw new BadRequestException('Los pesos del componente superarían el 100 %.');break;}
    case 'notas':result=await this.grade(db,data.inscripcion_id,data.evaluacion_id,data.nota,user);break;
    case 'sesiones':await this.offer(db,data.oferta_id,user);if(data.fin<=data.inicio||(data.fin-data.inicio)/60000>65535)throw new BadRequestException('La duración de la sesión debe ser positiva y válida.');data.estado='REALIZADA';break;
    case 'asistencias':result=await this.attendance(db,data.inscripcion_id,data.sesion_id,data.minutos_presentes,user);break;
    case 'excepciones':await this.enrollment(db,data.inscripcion_id,user);data.aprobada_por=user.nombre;break;
    case 'cierres':result=await this.closeOffer(db,data.oferta_id,data.minutos_carga,user);break;
    case 'recuperaciones':result=await this.recovery(db,data,user);break;
    case 'cargos':this.money(data.monto);break;
    case 'pagos':await this.validatePayment(db,data);break;
    case 'documentos':result=await this.documents(db,data);break;
    case 'pasantias':if(data.fecha_fin&&data.fecha_fin<data.fecha_inicio)throw new BadRequestException('La fecha final de la pasantía no puede ser anterior al inicio.');break;
    case 'defensas':if(data.nota!==null)num(data.nota,0,100,'Nota');break;
    case 'usuarios':
     if(String(data.password).length<12||String(data.password).length>200)throw new BadRequestException('La contraseña debe tener entre 12 y 200 caracteres.');
     if(!/^[a-zA-Z0-9_.-]{3,60}$/.test(data.usuario))throw new BadRequestException('El usuario admite entre 3 y 60 letras, números, puntos o guiones.');
     if(data.rol==='DOCENTE'){if(!data.docente_id)throw new BadRequestException('Asocia el docente a este acceso.');await this.exists(db,'docentes',data.docente_id);}else data.docente_id=null;
     data.password_hash=hashPassword(data.password);delete data.password;break;
    case 'horarios':await this.validateSchedule(db,data,user,id);break;
   }
   if(!result)result=id?await db[m.table!].update({where:{id},data}):await db[m.table!].create({data});
   const recordId=result.id??result.inscripcion_id??result.oferta_id??(result.plan_id?[result.plan_id,result.materia_id,result.requerida_id].filter(x=>x!==undefined).join('-'):result.defensa_id?`${result.defensa_id}-${result.docente_id}`:id);
   await this.audit(db,user,id?'EDITAR':'GUARDAR',key,recordId);
   if(key==='usuarios')delete result.password_hash;
   return {message:key==='cierres'?'Oferta cerrada y resultados calculados correctamente.':'Operación guardada correctamente.',data:result};
  });
 }
 private async exists(db:any,table:string,id:number){const row=await db[table].findUnique({where:{id}});if(!row)throw new BadRequestException('Una selección ya no existe. Actualiza los catálogos.');return row;}
 private async prerequisite(db:any,data:any){
  if(data.materia_id===data.requerida_id)throw new BadRequestException('Una materia no puede ser requisito de sí misma.');
  const members=await db.plan_materias.findMany({where:{plan_id:data.plan_id,materia_id:{in:[data.materia_id,data.requerida_id]}}});if(members.length!==2)throw new BadRequestException('Ambas materias deben pertenecer al plan.');
  const dependencies=await db.prerrequisitos.findMany({where:{plan_id:data.plan_id}});
  const stack=[data.requerida_id];const seen=new Set<number>();
  while(stack.length){const current=stack.pop()!;if(current===data.materia_id)throw new BadRequestException('El prerrequisito produciría un ciclo.');if(seen.has(current))continue;seen.add(current);for(const edge of dependencies)if(edge.materia_id===current)stack.push(edge.requerida_id);}
 }
 private async validateGroup(db:any,data:any,id?:number){
  data.paralelo=this.parallel(data.paralelo);num(data.curso,1,6,'Curso');num(data.cupo,1,1000,'Cupo');
  const career=await this.exists(db,'carreras',data.carrera_id);if(!career.activa)throw new BadRequestException('Selecciona una carrera activa.');
  if(id){const previous=await db.grupos.findUnique({where:{id}});const count=await db.grupo_integrantes.count({where:{grupo_id:id}});if(data.cupo<count)throw new BadRequestException('El cupo no puede ser menor al número de integrantes.');
   if(count||await db.grupo_materias.count({where:{grupo_id:id}}))for(const key of ['periodo_id','carrera_id','curso','paralelo','turno'])if(previous[key]!==data[key])throw new ConflictException('El grupo ya tiene asignaciones. Crea otro para cambiar su gestión, carrera, curso, paralelo o turno.');
  }
 }
 private async addMember(db:any,groupId:number,enrollmentId:number,idempotent=false){
  const group=await this.group(db,groupId);const enrollment=await this.exists(db,'matriculas',enrollmentId);
  if(enrollment.estado!=='ACTIVA'||enrollment.carrera_id!==group.carrera_id||enrollment.periodo_id!==group.periodo_id)throw new BadRequestException('La matrícula debe estar activa y coincidir con carrera y gestión del grupo.');
  const existing=await db.grupo_integrantes.findUnique({where:{matricula_id:enrollmentId}});
  if(existing){if(idempotent&&existing.grupo_id===groupId)return existing;throw new ConflictException('La matrícula ya pertenece a un grupo.');}
  if(await db.grupo_integrantes.count({where:{grupo_id:groupId}})>=group.cupo)throw new ConflictException('El grupo alcanzó su cupo máximo.');
  const elsewhere=await this.raw(db,"SELECT i.id FROM inscripciones i JOIN grupo_materias gm ON gm.oferta_id=i.oferta_id WHERE i.matricula_id=$1 AND gm.grupo_id<>$2 AND i.estado<>'RETIRADA' LIMIT 1",[enrollmentId,groupId]);
  if(elsewhere.length)throw new ConflictException('La matrícula tiene materias asignadas a otro grupo.');
  return db.grupo_integrantes.create({data:{grupo_id:groupId,matricula_id:enrollmentId}});
 }
 private async linkSubject(db:any,groupId:number,offerId:number,user:Usuario){
  const group=await this.group(db,groupId);const offer=await this.offer(db,offerId,user);const subject=await this.exists(db,'materias',offer.materia_id);
  if(offer.periodo_id!==group.periodo_id||offer.carrera_id!==group.carrera_id||subject.nivel_curso!==group.curso||offer.paralelo!==group.paralelo||offer.turno!==group.turno)throw new BadRequestException('La oferta debe coincidir con gestión, carrera, curso, paralelo y turno del grupo.');
  const outsiders=await this.raw(db,"SELECT i.id FROM inscripciones i LEFT JOIN grupo_integrantes gi ON gi.matricula_id=i.matricula_id AND gi.grupo_id=$1 WHERE i.oferta_id=$2 AND i.estado<>'RETIRADA' AND gi.id IS NULL LIMIT 1",[groupId,offerId]);
  if(outsiders.length)throw new ConflictException('La oferta tiene estudiantes que todavía no pertenecen al grupo. Asígnalos primero.');
  const conflicts=await this.raw(db,'SELECT a.id FROM horarios a JOIN horarios b ON b.dia=a.dia AND b.hora_inicio<a.hora_fin AND b.hora_fin>a.hora_inicio JOIN grupo_materias gm ON gm.oferta_id=b.oferta_id WHERE a.oferta_id=$1 AND gm.grupo_id=$2 LIMIT 1',[offerId,groupId]);
  if(conflicts.length)throw new ConflictException('Los horarios de esta oferta se cruzan con otra materia del grupo.');
  return db.grupo_materias.create({data:{grupo_id:groupId,oferta_id:offerId}});
 }
 private async inscribe(db:any,enrollmentId:number,offerId:number,when:Date,user:Usuario,idempotent=false){
  const offer=await this.offer(db,offerId,user);const enrollment=await this.exists(db,'matriculas',enrollmentId);
  if(enrollment.estado!=='ACTIVA'||enrollment.carrera_id!==offer.carrera_id||enrollment.periodo_id!==offer.periodo_id)throw new BadRequestException('La oferta debe coincidir con la carrera y la gestión de una matrícula activa.');
  const existing=await db.inscripciones.findUnique({where:{matricula_id_oferta_id:{matricula_id:enrollmentId,oferta_id:offerId}}});
  if(existing){if(idempotent&&existing.estado!=='RETIRADA')return {row:existing,created:false};throw new ConflictException('La materia ya está inscrita para esta matrícula.');}
  const groupLink=await db.grupo_materias.findUnique({where:{oferta_id:offerId}});
  if(groupLink){await this.group(db,groupLink.grupo_id);const member=await db.grupo_integrantes.findUnique({where:{matricula_id:enrollmentId}});if(!member||member.grupo_id!==groupLink.grupo_id)throw new BadRequestException('Asigna primero la matrícula al grupo de esta oferta.');}
  if(!await db.plan_materias.findUnique({where:{plan_id_materia_id:{plan_id:enrollment.plan_id,materia_id:offer.materia_id}}}))throw new BadRequestException('La materia no pertenece al plan de estudio de la matrícula.');
  if(await db.inscripciones.count({where:{oferta_id:offerId,estado:{not:'RETIRADA'}}})>=offer.cupo)throw new ConflictException('La oferta ya no tiene cupos disponibles.');
  const requirements=await db.prerrequisitos.findMany({where:{plan_id:enrollment.plan_id,materia_id:offer.materia_id}});
  for(const requirement of requirements){const passed=await this.raw(db,"SELECT i.id FROM inscripciones i JOIN matriculas mt ON mt.id=i.matricula_id JOIN ofertas o ON o.id=i.oferta_id JOIN v_boletin_final v ON v.inscripcion_id=i.id WHERE mt.estudiante_id=$1 AND o.materia_id=$2 AND v.resultado IN ('APROBADO','APROBADO_RECUPERACION') LIMIT 1",[enrollment.estudiante_id,requirement.requerida_id]);if(!passed.length)throw new BadRequestException('El estudiante tiene un prerrequisito pendiente.');}
  const row=await db.inscripciones.create({data:{matricula_id:enrollmentId,oferta_id:offerId,carrera_id:offer.carrera_id,periodo_id:offer.periodo_id,fecha:when,estado:'ACTIVA'}});
  return idempotent?{row,created:true}:row;
 }
 private async grade(db:any,inscriptionId:number,evaluationId:number,grade:number,user:Usuario){
  num(grade,1,100,'Nota');const inscription=await this.enrollment(db,inscriptionId,user);const evaluation=await this.exists(db,'evaluaciones',evaluationId);
  if(evaluation.oferta_id!==inscription.oferta_id)throw new BadRequestException('La evaluación y la inscripción deben pertenecer a la misma oferta.');
  return db.calificaciones.upsert({where:{inscripcion_id_evaluacion_id:{inscripcion_id:inscriptionId,evaluacion_id:evaluationId}},create:{inscripcion_id:inscriptionId,evaluacion_id:evaluationId,oferta_id:inscription.oferta_id,nota:grade},update:{nota:grade}});
 }
 private async attendance(db:any,inscriptionId:number,sessionId:number,present:number,user:Usuario){
  const inscription=await this.enrollment(db,inscriptionId,user);const session=await this.exists(db,'sesiones',sessionId);
  if(session.estado!=='REALIZADA'||session.oferta_id!==inscription.oferta_id)throw new BadRequestException('La sesión realizada y la inscripción deben pertenecer a la misma oferta.');
  const duration=Math.floor((session.fin-session.inicio)/60000);num(present,0,duration,'Minutos presentes');if(!Number.isInteger(present))throw new BadRequestException('Los minutos deben ser enteros.');
  return db.asistencias_sesion.upsert({where:{inscripcion_id_sesion_id:{inscripcion_id:inscriptionId,sesion_id:sessionId}},create:{inscripcion_id:inscriptionId,sesion_id:sessionId,oferta_id:inscription.oferta_id,minutos_presentes:present},update:{minutos_presentes:present}});
 }
 private async closeOffer(db:any,offerId:number,load:number,user:Usuario){
  await this.offer(db,offerId,user);num(load,1,2147483647,'Carga horaria');
  const sessions=await db.sesiones.findMany({where:{oferta_id:offerId}});
  if(sessions.some((s:any)=>s.estado==='PROGRAMADA'))throw new ConflictException('Hay sesiones programadas pendientes.');
  const performed=sessions.filter((s:any)=>s.estado==='REALIZADA');const total=performed.reduce((n:number,s:any)=>n+Math.floor((s.fin-s.inicio)/60000),0);
  if(!total||total!==load)throw new BadRequestException('La carga debe coincidir con la suma de minutos de las sesiones realizadas.');
  const evaluations=await db.evaluaciones.findMany({where:{oferta_id:offerId}});
  for(const part of ['PRACTICA','TEORIA'])if(Math.abs(evaluations.filter((e:any)=>e.componente===part).reduce((n:number,e:any)=>n+Number(e.peso),0)-100)>0.00001)throw new ConflictException('Completa el 100 % de práctica y teoría antes de cerrar.');
  const students=await db.inscripciones.findMany({where:{oferta_id:offerId,estado:{not:'RETIRADA'}}});if(!students.length)throw new ConflictException('La oferta no tiene estudiantes inscritos.');
  const results:any[]=[];
  for(const ins of students){const grades=await db.calificaciones.findMany({where:{inscripcion_id:ins.id}});const attendance=await db.asistencias_sesion.findMany({where:{inscripcion_id:ins.id}});
   if(evaluations.some((e:any)=>!grades.some((g:any)=>g.evaluacion_id===e.id)))throw new ConflictException('Hay estudiantes con calificaciones pendientes.');
   if(performed.some((s:any)=>!attendance.some((a:any)=>a.sesion_id===s.id)))throw new ConflictException('Hay estudiantes con asistencia pendiente.');
   const enrollment=await this.exists(db,'matriculas',ins.matricula_id);const plan=await this.exists(db,'planes_estudio',enrollment.plan_id);const rule=await this.exists(db,'reglas_evaluacion',plan.regla_id);
   const component=(part:string)=>evaluations.filter((e:any)=>e.componente===part).reduce((n:number,e:any)=>n+Number(grades.find((g:any)=>g.evaluacion_id===e.id).nota)*Number(e.peso)/100,0);
   const average=round(component('PRACTICA')*Number(rule.practica)+component('TEORIA')*Number(rule.teoria));
   const percentage=round(100*attendance.reduce((n:number,a:any)=>n+a.minutos_presentes,0)/load);
   const exception=!!await db.excepciones_asistencia.findUnique({where:{inscripcion_id:ins.id}});
   const status=percentage<Number(rule.asistencia)&&!exception?'REPROBADO_ASISTENCIA':average>=Number(rule.aprobacion)?'APROBADO':'REPROBADO';
   results.push({inscripcion_id:ins.id,regla_id:rule.id,promedio:average,porcentaje_asistencia:percentage,excepcion_documentada:exception?1:0,estado:status});
  }
  const closure=await db.cierres_oferta.create({data:{oferta_id:offerId,minutos_carga:load,cerrado_por:user.nombre}});
  await db.resultados_finales.createMany({data:results});
  await db.inscripciones.updateMany({where:{oferta_id:offerId,estado:'ACTIVA'},data:{estado:'CONCLUIDA'}});
  return {...closure,resultados:results.length};
 }
 private async recovery(db:any,data:any,user:Usuario){
  const ins=await this.enrollment(db,data.inscripcion_id,user,false);num(data.nota_prueba,1,100,'Nota de la prueba');
  const result=await db.resultados_finales.findUnique({where:{inscripcion_id:ins.id}});if(!result||result.estado!=='REPROBADO'||Number(result.promedio)<40)throw new BadRequestException('Solo recuperan resultados reprobados con promedio desde 40 y asistencia habilitada.');
  const enrollment=await this.exists(db,'matriculas',ins.matricula_id);const career=await this.exists(db,'carreras',enrollment.carrera_id);
  const limits=await db.reglas_evaluacion.findUnique({where:{id:result.regla_id}});
  const count=await this.raw(db,'SELECT count(*)::int AS n FROM recuperaciones r JOIN matriculas mt ON mt.id=r.matricula_id WHERE mt.estudiante_id=$1 AND mt.carrera_id=$2 AND mt.periodo_id=$3',[enrollment.estudiante_id,enrollment.carrera_id,enrollment.periodo_id]);
  const max=career.regimen==='ANUAL'?limits.max_rec_anual:limits.max_rec_semestral;if(count[0].n>=max)throw new ConflictException(`Se alcanzó el máximo de ${max} recuperaciones de la gestión.`);
  return db.recuperaciones.create({data:{...data,matricula_id:ins.matricula_id,nota_registrada:data.nota_prueba>=61?61:data.nota_prueba}});
 }
 private async validatePayment(db:any,data:any){
  this.money(data.monto);const charge=await this.exists(db,'cargos',data.cargo_id);const paid=await db.pagos.aggregate({where:{cargo_id:data.cargo_id},_sum:{monto:true}});
  if(Math.round(data.monto*100)>Math.round((Number(charge.monto)-Number(paid._sum.monto??0))*100))throw new BadRequestException('El pago no puede superar el saldo pendiente.');
 }
 private money(value:number){num(value,0.01,99999999,'Importe');if(Math.abs(value*100-Math.round(value*100))>0.00001)throw new BadRequestException('El importe admite como máximo dos decimales.');}
 private async documents(db:any,data:any){
  const reception=data.estado==='RECIBIDO'?date(today()):null;
  return db.documentos_matricula.upsert({where:{matricula_id_tipo_documento_id:{matricula_id:data.matricula_id,tipo_documento_id:data.tipo_documento_id}},create:{...data,fecha_recepcion:reception},update:{estado:data.estado,fecha_recepcion:reception,observacion:data.observacion}});
 }
 private async validateSchedule(db:any,data:any,user:Usuario,id?:number){
  if(id){const old=await this.exists(db,'horarios',id);await this.offer(db,old.oferta_id,user);}
  const offer=await this.offer(db,data.oferta_id,user);const period=await this.exists(db,'periodos',offer.periodo_id);const room=await this.exists(db,'aulas',data.aula_id);
  if(offer.cupo>room.capacidad)throw new BadRequestException('El aula tiene menos capacidad que el cupo de la oferta.');
  num(data.dia,1,7,'Día');if(minutes(data.hora_fin)<=minutes(data.hora_inicio))throw new BadRequestException('La hora final debe ser posterior a la inicial.');
  const link=await db.grupo_materias.findUnique({where:{oferta_id:offer.id}});if(link)await this.group(db,link.grupo_id);
  const conflicts=await this.raw(db,'SELECT h.id,h.aula_id,o.docente_id,gm.grupo_id,o.id AS oferta_id FROM horarios h JOIN ofertas o ON o.id=h.oferta_id JOIN periodos p ON p.id=o.periodo_id LEFT JOIN grupo_materias gm ON gm.oferta_id=o.id WHERE h.id<>$1 AND h.dia=$2 AND h.hora_inicio<$3::time AND h.hora_fin>$4::time AND p.fecha_inicio<=$5 AND p.fecha_fin>=$6 AND(h.aula_id=$7 OR o.docente_id=$8 OR o.id=$9 OR gm.grupo_id=$10) LIMIT 1',[id??0,data.dia,data.hora_fin.toISOString().slice(11,19),data.hora_inicio.toISOString().slice(11,19),period.fecha_fin,period.fecha_inicio,room.id,offer.docente_id,offer.id,link?.grupo_id??0]);
  if(conflicts.length){const c=conflicts[0];const reason=c.aula_id===room.id?'el aula':c.docente_id===offer.docente_id?'el docente':c.oferta_id===offer.id?'la materia':'el grupo';throw new ConflictException(`Cruce de horario: ${reason} ya tiene una actividad en ese intervalo.`);}
 }
 private async toggleUser(id:number,body:any,user:Usuario){
  if(id===user.id)throw new ConflictException('No puedes desactivar tu propio acceso.');
  if(body.activo!==0&&body.activo!==1)throw new BadRequestException('Indica activo 0 o 1.');
  return this.transaction(async db=>{const result=await db.app_usuarios.update({where:{id},data:{activo:body.activo},select:{id:true,usuario:true,nombre:true,rol:true,docente_id:true,activo:true}});await this.audit(db,user,'CAMBIO_ACCESO','usuarios',id);return {message:'Acceso actualizado.',data:result};});
 }
 async remove(key:string,idText:string,user:Usuario){
  const m=this.module(key,user,true);if(!m.deletable||!m.table)throw new ForbiddenException('Esta pantalla no permite eliminar registros.');
  return this.transaction(async db=>{
   let where:any;let row:any;
   if(m.pk==='composite'){const ids=idText.split('-').map(id=>positive(id));if(key==='plan_materias'&&ids.length===2)where={plan_id_materia_id:{plan_id:ids[0],materia_id:ids[1]}};else if(key==='prerrequisitos'&&ids.length===3)where={plan_id_materia_id_requerida_id:{plan_id:ids[0],materia_id:ids[1],requerida_id:ids[2]}};else if(key==='tribunales'&&ids.length===2)where={defensa_id_docente_id:{defensa_id:ids[0],docente_id:ids[1]}};else throw new BadRequestException('Identificador inválido.');}
   else where={id:positive(idText)};
   row=await db[m.table!].findUnique({where});if(!row)throw new NotFoundException('El registro no existe.');
   if(key==='horarios'){await this.offer(db,row.oferta_id,user);const linked=await db.grupo_materias.findUnique({where:{oferta_id:row.oferta_id}});if(linked)await this.group(db,linked.grupo_id);}
   if(key==='integrantes'||key==='grupo_materias'){
    await this.group(db,row.grupo_id);
    const sql=key==='grupo_materias'?"SELECT id FROM inscripciones WHERE oferta_id=$1 AND estado<>'RETIRADA' LIMIT 1":"SELECT i.id FROM inscripciones i JOIN grupo_materias gm ON gm.oferta_id=i.oferta_id WHERE i.matricula_id=$1 AND gm.grupo_id=$2 AND i.estado<>'RETIRADA' LIMIT 1";
    const links=await this.raw(db,sql,key==='grupo_materias'?[row.oferta_id]:[row.matricula_id,row.grupo_id]);if(links.length)throw new ConflictException('Hay inscripciones asociadas. Retíralas antes de desvincular la asignación.');
   }
   if(key==='plan_materias'){const offers=await this.raw(db,'SELECT i.id FROM inscripciones i JOIN matriculas mt ON mt.id=i.matricula_id JOIN ofertas o ON o.id=i.oferta_id WHERE mt.plan_id=$1 AND o.materia_id=$2 LIMIT 1',[row.plan_id,row.materia_id]);if(offers.length)throw new ConflictException('La materia del plan ya tiene inscripciones y debe conservarse.');}
   await db[m.table!].delete({where});await this.audit(db,user,'RETIRAR',key,idText);return {message:'Registro retirado correctamente.'};
  });
 }
 async options(source:string,query:any,user:Usuario) {
  const teacherAllowed=['periodos','carreras','grupos','ofertas','inscripciones','evaluaciones','sesiones','docentes'];
  const cashAllowed=['periodos','carreras','grupos','estudiantes','matriculas','cargos'];
  if(user.rol==='DOCENTE'&&!teacherAllowed.includes(source)||user.rol==='CAJA'&&!cashAllowed.includes(source))throw new ForbiddenException('Tu rol no permite consultar ese catálogo.');
  const queries:Record<string,{sql:string;periodo?:boolean;carrera?:boolean;oferta?:boolean;docente?:boolean}>= {
   estudiantes:{sql:"SELECT id,concat(registro,' · ',apellidos,' ',nombres) AS label FROM estudiantes"},
   docentes:{sql:"SELECT id,concat(apellidos,' ',nombres,' · ',especialidad) AS label FROM docentes"},
   carreras:{sql:'SELECT id,nombre AS label FROM carreras WHERE activa=1'},
   periodos:{sql:'SELECT id,nombre AS label,fecha_inicio,fecha_fin FROM periodos'},
   planes:{sql:"SELECT p.id,p.carrera_id,concat(c.codigo,' · ',p.denominacion,' · ',p.cohorte) AS label FROM planes_estudio p JOIN carreras c ON c.id=p.carrera_id",carrera:true},
   reglas:{sql:'SELECT id,nombre AS label FROM reglas_evaluacion'},
   materias:{sql:"SELECT m.id,m.carrera_id,m.nivel_curso AS curso,concat(c.codigo,' · ',m.codigo,' · ',m.nombre) AS label FROM materias m JOIN carreras c ON c.id=m.carrera_id",carrera:true},
   grupos:{sql:"SELECT g.id,g.periodo_id,g.carrera_id,g.curso,g.paralelo,g.turno,g.estado,concat(p.nombre,' · ',c.codigo,' · ',g.curso,'° ',g.paralelo,' · ',g.turno) AS label FROM grupos g JOIN periodos p ON p.id=g.periodo_id JOIN carreras c ON c.id=g.carrera_id",periodo:true,carrera:true},
   ofertas:{sql:"SELECT o.id,o.periodo_id,o.carrera_id,o.docente_id,o.paralelo,o.turno,m.nivel_curso AS curso,gm.grupo_id,concat('#',o.id,' · ',p.nombre,' · ',m.nombre,' · ',o.paralelo,' ',o.turno) AS label FROM ofertas o JOIN periodos p ON p.id=o.periodo_id JOIN materias m ON m.id=o.materia_id LEFT JOIN grupo_materias gm ON gm.oferta_id=o.id",periodo:true,carrera:true,docente:true},
   matriculas:{sql:"SELECT mt.id,mt.periodo_id,mt.carrera_id,mt.estudiante_id,concat('#',mt.id,' · ',e.registro,' · ',e.apellidos,' ',e.nombres,' · ',c.codigo,' · ',p.nombre) AS label FROM matriculas mt JOIN estudiantes e ON e.id=mt.estudiante_id JOIN carreras c ON c.id=mt.carrera_id JOIN periodos p ON p.id=mt.periodo_id WHERE mt.estado='ACTIVA'",periodo:true,carrera:true},
   inscripciones:{sql:"SELECT i.id,i.matricula_id,i.oferta_id,i.periodo_id,i.carrera_id,o.docente_id,concat('#',i.id,' · ',e.apellidos,' ',e.nombres,' · ',m.nombre) AS label FROM inscripciones i JOIN matriculas mt ON mt.id=i.matricula_id JOIN estudiantes e ON e.id=mt.estudiante_id JOIN ofertas o ON o.id=i.oferta_id JOIN materias m ON m.id=o.materia_id WHERE i.estado<>'RETIRADA'",periodo:true,carrera:true,oferta:true,docente:true},
   evaluaciones:{sql:"SELECT ev.id,ev.oferta_id,o.docente_id,o.periodo_id,o.carrera_id,concat('#',ev.id,' · ',ev.nombre,' · ',ev.componente,' · oferta ',o.id) AS label FROM evaluaciones ev JOIN ofertas o ON o.id=ev.oferta_id",periodo:true,carrera:true,oferta:true,docente:true},
   sesiones:{sql:"SELECT s.id,s.oferta_id,o.docente_id,o.periodo_id,o.carrera_id,concat('#',s.id,' · ',to_char(s.inicio,'DD/MM/YYYY HH24:MI'),' · ',(EXTRACT(EPOCH FROM(s.fin-s.inicio))/60)::int,' min · oferta ',o.id) AS label FROM sesiones s JOIN ofertas o ON o.id=s.oferta_id WHERE s.estado='REALIZADA'",periodo:true,carrera:true,oferta:true,docente:true},
   aulas:{sql:"SELECT id,concat(codigo,' · capacidad ',capacidad) AS label FROM aulas"},
   cargos:{sql:"SELECT c.id,c.matricula_id,mt.periodo_id,mt.carrera_id,concat('#',c.id,' · ',e.registro,' · ',c.concepto,' · saldo Bs ',v.saldo) AS label FROM cargos c JOIN v_saldos v ON v.cargo_id=c.id JOIN matriculas mt ON mt.id=c.matricula_id JOIN estudiantes e ON e.id=mt.estudiante_id WHERE v.saldo>0",periodo:true,carrera:true},
   tipos_documento:{sql:'SELECT id,nombre AS label FROM tipos_documento'},
   modalidades:{sql:'SELECT id,nombre AS label FROM modalidades_graduacion'},
   proyectos:{sql:'SELECT id,titulo AS label FROM proyectos_graduacion'},
   defensas:{sql:"SELECT d.id,concat('#',d.id,' · ',p.titulo) AS label FROM defensas d JOIN proyectos_graduacion p ON p.id=d.proyecto_id"},
  };
  const def=queries[source];if(!def)throw new NotFoundException('El catálogo solicitado no existe.');
  const args:any[]=[];const conditions:string[]=[];
  const add=(column:string,value:any)=>{args.push(value);conditions.push(`opciones.${column}=$${args.length}`);};
  if(user.rol==='DOCENTE'&&def.docente)add('docente_id',user.docente_id);
  if(user.rol==='DOCENTE'&&source==='docentes')add('id',user.docente_id);
  if(user.rol==='DOCENTE'&&source==='grupos'){args.push(user.docente_id);conditions.push(`EXISTS(SELECT 1 FROM grupo_materias gm JOIN ofertas o ON o.id=gm.oferta_id WHERE gm.grupo_id=opciones.id AND o.docente_id=$${args.length})`);}
  if(query.periodo_id&&def.periodo)add('periodo_id',positive(query.periodo_id));
  if(query.carrera_id&&def.carrera)add('carrera_id',positive(query.carrera_id));
  if(query.oferta_id&&def.oferta)add('oferta_id',positive(query.oferta_id));
  if(query.grupo_id&&source==='ofertas')add('grupo_id',positive(query.grupo_id));
  if(query.matricula_id&&['inscripciones','cargos'].includes(source))add('matricula_id',positive(query.matricula_id));
  if(query.q){args.push('%'+String(query.q).slice(0,200).replace(/[!%_]/g,'!$&')+'%');conditions.push(`opciones.label ILIKE $${args.length} ESCAPE '!'`);}
  const rows=await this.raw(this.prisma,`SELECT * FROM(${def.sql}) opciones${conditions.length?' WHERE '+conditions.join(' AND '):''} ORDER BY opciones.label LIMIT 1100`,args);
  return rows.map(row=>({...row,value:row.id}));
 }
 async dashboard(query:any,user:Usuario){
  const periodoId=query.periodo_id?positive(query.periodo_id):null;
  const args:any[]=[];const addPeriod=(alias:string)=>{if(!periodoId)return '';args.push(periodoId);return ` AND ${alias}.periodo_id=$${args.length}`;};
  const periodClause=addPeriod('mt');
  let teacherClause='';if(user.rol==='DOCENTE'){args.push(user.docente_id);teacherClause=` AND EXISTS(SELECT 1 FROM inscripciones i JOIN ofertas o ON o.id=i.oferta_id WHERE i.matricula_id=mt.id AND o.docente_id=$${args.length})`;}
  const enrolled=await this.raw(this.prisma,`SELECT count(*)::int AS total,count(DISTINCT mt.estudiante_id)::int AS personas FROM matriculas mt WHERE mt.estado='ACTIVA'${periodClause}${teacherClause}`,args);
  const filterArgs:any[]=[];let where=' WHERE 1=1';if(periodoId){filterArgs.push(periodoId);where+=` AND g.periodo_id=$${filterArgs.length}`;}
  if(user.rol==='DOCENTE'){filterArgs.push(user.docente_id);where+=` AND EXISTS(SELECT 1 FROM grupo_materias gm JOIN ofertas o ON o.id=gm.oferta_id WHERE gm.grupo_id=g.id AND o.docente_id=$${filterArgs.length})`;}
  const groups=await this.raw(this.prisma,`SELECT g.id,p.nombre AS gestion,c.nombre AS carrera,c.codigo,g.curso,g.paralelo,g.turno,g.cupo,g.estado,(SELECT count(*)::int FROM grupo_integrantes gi JOIN matriculas mt ON mt.id=gi.matricula_id WHERE gi.grupo_id=g.id AND mt.estado='ACTIVA') AS estudiantes,(SELECT count(*)::int FROM grupo_materias gm WHERE gm.grupo_id=g.id) AS materias FROM grupos g JOIN carreras c ON c.id=g.carrera_id JOIN periodos p ON p.id=g.periodo_id${where} ORDER BY p.fecha_inicio DESC,c.nombre,g.curso,g.paralelo`,filterArgs);
  const careerRows=await this.raw(this.prisma,`SELECT c.nombre AS carrera,count(*)::int AS estudiantes FROM matriculas mt JOIN carreras c ON c.id=mt.carrera_id WHERE mt.estado='ACTIVA'${periodClause}${teacherClause} GROUP BY c.nombre ORDER BY estudiantes DESC,c.nombre`,args);
  const offerArgs:any[]=[];let offerWhere=' WHERE 1=1';if(periodoId){offerArgs.push(periodoId);offerWhere+=` AND o.periodo_id=$${offerArgs.length}`;}if(user.rol==='DOCENTE'){offerArgs.push(user.docente_id);offerWhere+=` AND o.docente_id=$${offerArgs.length}`;}
  const offers=await this.raw(this.prisma,`SELECT count(*)::int AS total FROM ofertas o${offerWhere}`,offerArgs);
  let fourth:any;
  if(user.rol==='DOCENTE'){const evaluations=await this.raw(this.prisma,`SELECT count(*)::int AS total FROM evaluaciones ev JOIN ofertas o ON o.id=ev.oferta_id${offerWhere}`,offerArgs);fourth={label:'Evaluaciones',value:evaluations[0].total,hint:'De tus ofertas asignadas'};}
  else{const money=await this.raw(this.prisma,'SELECT COALESCE(sum(v.saldo),0) AS total FROM v_saldos v JOIN matriculas mt ON mt.id=v.matricula_id'+(periodoId?' WHERE mt.periodo_id=$1':''),periodoId?[periodoId]:[]);fourth={label:'Saldo pendiente (Bs)',value:Number(money[0].total),hint:'Cargos menos pagos registrados'};}
  const periodos=await (this.prisma as any).periodos.findMany({orderBy:{fecha_inicio:'desc'}});
  const catalog=await this.raw(this.prisma,'SELECT (SELECT count(*)::int FROM estudiantes) AS estudiantes,(SELECT count(*)::int FROM docentes) AS docentes,(SELECT count(*)::int FROM carreras) AS carreras');
  const activity=await this.raw(this.prisma,'SELECT a.id,u.usuario,a.accion,a.entidad,a.fecha FROM app_auditoria a JOIN app_usuarios u ON u.id=a.usuario_id'+(user.rol==='ADMIN'?'':' WHERE a.usuario_id=$1')+' ORDER BY a.id DESC LIMIT 8',user.rol==='ADMIN'?[]:[user.id]);
  return {periodos,periodo_id:periodoId,kpis:[{label:'Estudiantes matriculados',value:enrolled[0].personas,hint:`${enrolled[0].total} matrículas activas`},{label:'Grupos por gestión',value:groups.length,hint:'Organizados por carrera, nivel y turno'},{label:'Ofertas de materias',value:offers[0].total,hint:user.rol==='DOCENTE'?'Solo tus materias asignadas':'Materias abiertas y cerradas'},fourth],catalogo:catalog[0],grupos:groups,carreras:careerRows,actividad:activity};
 }
 async candidates(groupText:string,query:any,user:Usuario){
  if(user.rol!=='ADMIN')throw new ForbiddenException('Solo administración puede inscribir grupos.');
  const groupId=positive(groupText);const group=await (this.prisma as any).grupos.findUnique({where:{id:groupId}});if(!group)throw new NotFoundException('El grupo no existe.');
  const pageSize=50;let page=positive(query.page??1,'número de página');const args:any[]=[group.periodo_id,group.carrera_id,groupId];
  let where="WHERE mt.periodo_id=$1 AND mt.carrera_id=$2 AND mt.estado='ACTIVA' AND (gi.id IS NULL OR gi.grupo_id=$3)";
  if(query.q){args.push('%'+String(query.q).slice(0,200).replace(/[!%_]/g,'!$&')+'%');where+=` AND concat_ws(' ',e.registro,e.documento,e.nombres,e.apellidos) ILIKE $${args.length} ESCAPE '!'`;}
  const from=`FROM matriculas mt JOIN estudiantes e ON e.id=mt.estudiante_id LEFT JOIN grupo_integrantes gi ON gi.matricula_id=mt.id ${where}`;
  const counts=await this.raw(this.prisma,`SELECT count(*)::int AS total ${from}`,args);const total=counts[0].total;page=Math.min(page,Math.max(1,Math.ceil(total/pageSize)));
  const rows=await this.raw(this.prisma,`SELECT mt.id AS matricula_id,e.registro,concat(e.apellidos,' ',e.nombres) AS estudiante,gi.id IS NOT NULL AS asignado,(SELECT count(*)::int FROM inscripciones i JOIN grupo_materias gm ON gm.oferta_id=i.oferta_id WHERE i.matricula_id=mt.id AND gm.grupo_id=$3 AND i.estado<>'RETIRADA') AS materias_inscritas ${from} ORDER BY e.apellidos,e.nombres,mt.id LIMIT $${args.length+1} OFFSET $${args.length+2}`,[...args,pageSize,(page-1)*pageSize]);
  const subjects=await this.raw(this.prisma,'SELECT o.id,ma.nombre AS materia,o.cupo,(SELECT count(*)::int FROM inscripciones i WHERE i.oferta_id=o.id AND i.estado<>\'RETIRADA\') AS inscritos FROM grupo_materias gm JOIN ofertas o ON o.id=gm.oferta_id JOIN materias ma ON ma.id=o.materia_id WHERE gm.grupo_id=$1 ORDER BY ma.nombre',[groupId]);
  return {rows,total,page,pageSize,grupo:group,ofertas:subjects};
 }
 async bulkEnroll(groupText:string,body:any,user:Usuario){
  if(user.rol!=='ADMIN')throw new ForbiddenException('Solo administración puede inscribir grupos.');
  const groupId=positive(groupText);if(!Array.isArray(body?.matricula_ids)||!body.matricula_ids.length||body.matricula_ids.length>100)throw new BadRequestException('Selecciona entre 1 y 100 matrículas por operación.');
  const ids=body.matricula_ids.map((id:any)=>positive(id));if(new Set(ids).size!==ids.length)throw new BadRequestException('La selección contiene matrículas repetidas.');
  return this.transaction(async db=>{await this.group(db,groupId);const subjects=await db.grupo_materias.findMany({where:{grupo_id:groupId},orderBy:{oferta_id:'asc'}});if(!subjects.length)throw new ConflictException('El grupo todavía no tiene ofertas de materias vinculadas.');
   for(const subject of subjects)await this.offer(db,subject.oferta_id,user);
   let members=0,enrollments=0,existing=0;
   for(const id of ids){const previous=await db.grupo_integrantes.findUnique({where:{matricula_id:id}});await this.addMember(db,groupId,id,true);if(!previous)members++;
    for(const subject of subjects){const result=await this.inscribe(db,id,subject.oferta_id,date(today()),user,true);if(result.created)enrollments++;else existing++;}
   }
   await this.audit(db,user,'INSCRIBIR_GRUPO','grupos',groupId);
   return {message:`Proceso completado: ${members} integrantes nuevos, ${enrollments} inscripciones nuevas y ${existing} inscripciones ya existentes.`,integrantes_nuevos:members,inscripciones_nuevas:enrollments,existentes:existing};
  });
 }
 async roster(query:any,user:Usuario){
  if(!['ADMIN','DOCENTE'].includes(user.rol))throw new ForbiddenException('Tu rol no permite consultar planillas.');
  const type=query.tipo==='asistencias'?'asistencias':query.tipo==='notas'?'notas':null;if(!type)throw new BadRequestException('Selecciona planilla de notas o asistencias.');
  const offerId=positive(query.oferta_id,'identificador de oferta');const offer=await this.offer(this.prisma,offerId,user,false,false);
  const isGrade=type==='notas';const chosen=isGrade?query.evaluacion_id:query.sesion_id;const selected=chosen?positive(chosen):null;
  const choices=await this.options(isGrade?'evaluaciones':'sesiones',{oferta_id:offerId},user);
  let max=100;if(selected){const record=await this.exists(this.prisma,isGrade?'evaluaciones':'sesiones',selected);if(record.oferta_id!==offerId)throw new BadRequestException('La evaluación o sesión no pertenece a la oferta.');if(!isGrade){if(record.estado!=='REALIZADA')throw new BadRequestException('Selecciona una sesión realizada.');max=Math.floor((record.fin-record.inicio)/60000);}}
  const editable=!await (this.prisma as any).cierres_oferta.findUnique({where:{oferta_id:offerId}});
  const base={tipo:type,oferta_id:offerId,[isGrade?'evaluacion_id':'sesion_id']:selected,evaluaciones:isGrade?choices:[],sesiones:isGrade?[]:choices,min:isGrade?1:0,max,editable,columns:[{key:'registro',label:'Registro'},{key:'estudiante',label:'Estudiante'},{key:'valor',label:isGrade?'Nota (1 a 100)':'Minutos presentes'}]};
  if(!selected)return {...base,rows:[],total:0,page:1,pageSize:200};
  const table=isGrade?'calificaciones':'asistencias_sesion';const field=isGrade?'nota':'minutos_presentes';const join=isGrade?'evaluacion_id':'sesion_id';
  const counts=await this.raw(this.prisma,"SELECT count(*)::int AS total FROM inscripciones WHERE oferta_id=$1 AND estado<>'RETIRADA'",[offerId]);
  const pageSize=200;const page=Math.min(positive(query.page??1,'número de página'),Math.max(1,Math.ceil(counts[0].total/pageSize)));
  const rows=await this.raw(this.prisma,`SELECT i.id AS inscripcion_id,e.registro,concat(e.apellidos,' ',e.nombres) AS estudiante,v.${field} AS valor FROM inscripciones i JOIN matriculas mt ON mt.id=i.matricula_id JOIN estudiantes e ON e.id=mt.estudiante_id LEFT JOIN ${table} v ON v.inscripcion_id=i.id AND v.${join}=$2 WHERE i.oferta_id=$1 AND i.estado<>'RETIRADA' ORDER BY e.apellidos,e.nombres,i.id LIMIT $3 OFFSET $4`,[offerId,selected,pageSize,(page-1)*pageSize]);
  return {...base,rows,total:counts[0].total,page,pageSize};
 }
 async saveRoster(body:any,user:Usuario){
  if(!['ADMIN','DOCENTE'].includes(user.rol))throw new ForbiddenException('Tu rol no permite guardar planillas.');
  const type=body?.tipo;if(!['notas','asistencias'].includes(type))throw new BadRequestException('La planilla seleccionada no existe.');
  const offerId=positive(body.oferta_id);const selected=positive(type==='notas'?body.evaluacion_id:body.sesion_id);
  if(!Array.isArray(body.registros)||body.registros.length>200)throw new BadRequestException('La planilla admite hasta 200 filas por guardado.');
  const values=body.registros.filter((r:any)=>r&&r.valor!==null&&r.valor!==undefined&&r.valor!=='').map((r:any)=>{if(!['string','number'].includes(typeof r.valor))throw new BadRequestException('Los valores de la planilla deben ser numéricos.');return {id:positive(r.inscripcion_id),value:Number(r.valor)};});
  if(!values.length)throw new BadRequestException('Ingresa al menos un valor para guardar.');
  if(new Set(values.map((r:any)=>r.id)).size!==values.length)throw new BadRequestException('La planilla contiene filas repetidas.');
  return this.transaction(async db=>{await this.offer(db,offerId,user);const record=await this.exists(db,type==='notas'?'evaluaciones':'sesiones',selected);if(record.oferta_id!==offerId)throw new BadRequestException('La evaluación o sesión no pertenece a la oferta.');
   for(const value of values){const ins=await this.enrollment(db,value.id,user);if(ins.oferta_id!==offerId)throw new BadRequestException('Una inscripción no pertenece a esta planilla.');if(type==='notas')await this.grade(db,value.id,selected,value.value,user);else await this.attendance(db,value.id,selected,value.value,user);}
   await this.audit(db,user,'GUARDAR_PLANILLA',type,offerId);return {message:`Planilla guardada correctamente: ${values.length} registros.`,guardados:values.length};
  });
 }
}
