import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req } from '@nestjs/common';
import { AcademicoService } from './academico.service.js';

@Controller()
export class AcademicoController {
 constructor(private readonly service: AcademicoService) {}
 @Get('catalogo') catalogo(@Req() req:any){return this.service.metadata(req.user);}
 @Get('opciones/:source') opciones(@Param('source') source:string,@Query() query:any,@Req() req:any){return this.service.options(source,query,req.user);}
 @Get('datos/:module') listado(@Param('module') module:string,@Query() query:any,@Req() req:any){return this.service.list(module,query,req.user);}
 @Get('datos/:module/:id') detalle(@Param('module') module:string,@Param('id') id:string,@Req() req:any){return this.service.detail(module,id,req.user);}
 @Post('datos/:module') guardar(@Param('module') module:string,@Body() body:any,@Req() req:any){return this.service.save(module,body,req.user);}
 @Patch('datos/:module/:id') editar(@Param('module') module:string,@Param('id') id:string,@Body() body:any,@Req() req:any){return this.service.save(module,body,req.user,id);}
 @Delete('datos/:module/:id') retirar(@Param('module') module:string,@Param('id') id:string,@Req() req:any){return this.service.remove(module,id,req.user);}
 @Get('dashboard') dashboard(@Query() query:any,@Req() req:any){return this.service.dashboard(query,req.user);}
 @Get('grupos/:id/candidatos') candidatos(@Param('id') id:string,@Query() query:any,@Req() req:any){return this.service.candidates(id,query,req.user);}
 @Post('grupos/:id/inscribir') inscribir(@Param('id') id:string,@Body() body:any,@Req() req:any){return this.service.bulkEnroll(id,body,req.user);}
 @Get('planillas') planillas(@Query() query:any,@Req() req:any){return this.service.roster(query,req.user);}
 @Post('planillas') guardarPlanilla(@Body() body:any,@Req() req:any){return this.service.saveRoster(body,req.user);}
}
