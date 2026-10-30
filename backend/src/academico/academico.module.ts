import { Module } from '@nestjs/common';
import { AcademicoService } from './academico.service.js';
import { AcademicoController } from './academico.controller.js';

@Module({providers:[AcademicoService],controllers:[AcademicoController],exports:[AcademicoService]})
export class AcademicoModule {}
