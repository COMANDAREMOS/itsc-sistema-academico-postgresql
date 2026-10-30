import { Controller, Get, Module } from '@nestjs/common';
import { DatabaseModule, PrismaService } from './common/prisma.service.js';
import { AuthModule, Public } from './auth/auth.js';
import { AcademicoModule } from './academico/academico.module.js';
import { ReportsModule } from './reports.module.js';
import { AnalyticsModule } from './analytics.module.js';

@Controller('health')
class HealthController {
  constructor(private db: PrismaService) {}
  @Public()
  @Get()
  async health() { await this.db.$queryRaw`SELECT 1`; return { status: 'ok', database: 'PostgreSQL', application: 'ITSC PostgreSQL' }; }
}
@Module({ imports: [DatabaseModule, AuthModule, AcademicoModule, ReportsModule, AnalyticsModule], controllers: [HealthController] })
export class AppModule {}
