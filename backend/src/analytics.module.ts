import { Controller, ForbiddenException, Get, Module, Post, Req } from '@nestjs/common';
import { PrismaService } from './common/prisma.service.js';

@Controller('analitica')
class AnalyticsController {
  private updating: Promise<any> | null = null;
  constructor(private db: PrismaService) {}
  private requireAdmin(req: any) { if (req.user.rol !== 'ADMIN') throw new ForbiddenException('El análisis institucional requiere acceso de administración.'); }
  @Get()
  async data(@Req() req: any) {
    this.requireAdmin(req);
    const [matriculas, recaudacion, rendimiento, ejecuciones, totals]: any = await Promise.all([
      this.db.$queryRaw`SELECT gestion,carrera,total FROM dw.v_matriculas_por_gestion_carrera ORDER BY gestion DESC,carrera`,
      this.db.$queryRaw`SELECT mes,sum(total)::numeric(14,2) AS total FROM dw.v_recaudacion_mensual GROUP BY mes ORDER BY mes`,
      this.db.$queryRaw`SELECT gestion,carrera,inscripciones,aprobados,promedio FROM dw.v_rendimiento_por_carrera ORDER BY gestion DESC,carrera`,
      this.db.dw_etl_ejecuciones.findMany({ orderBy: { id: 'desc' }, take: 10, select: { id:true,inicio:true,fin:true,estado:true,dimensiones:true,matriculas:true,resultados:true,pagos:true } }),
      this.db.$queryRaw`SELECT (SELECT count(*)::int FROM dw.fact_matriculas) AS matriculas,(SELECT count(*)::int FROM dw.fact_resultados) AS resultados,(SELECT count(*)::int FROM dw.fact_pagos) AS pagos,(SELECT coalesce(sum(monto),0)::numeric(14,2) FROM dw.fact_pagos) AS recaudacion`
    ]);
    const t = totals[0];
    return { kpis: [
      { label: 'Matrículas analizadas', value: t.matriculas, hint: 'Registros académicos del almacén' },
      { label: 'Resultados finales', value: t.resultados, hint: 'Inscripciones con cierre académico' },
      { label: 'Pagos registrados', value: t.pagos, hint: 'Abonos incorporados al análisis' },
      { label: 'Recaudación (Bs)', value: Number(t.recaudacion), hint: 'Importes de los pagos registrados' }
    ], matriculas, recaudacion, rendimiento, ejecuciones };
  }
  @Post('actualizar')
  async refresh(@Req() req: any) {
    this.requireAdmin(req);
    if (!this.updating) {
      this.updating = (async () => {
        const { runEtl } = await import(new URL('../../db/etl.mjs', import.meta.url).href);
        const resumen = await runEtl(this.db);
        await this.db.app_auditoria.create({ data: { usuario_id: req.user.id, accion: 'ACTUALIZAR_ANALISIS', entidad: 'analitica', registro_id: String(resumen.id) } });
        return { message: 'Análisis institucional actualizado correctamente.', resumen };
      })().finally(() => { this.updating = null; });
    }
    return this.updating;
  }
}
@Module({ controllers: [AnalyticsController] })
export class AnalyticsModule {}
