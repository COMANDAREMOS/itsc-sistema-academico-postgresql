import { BadRequestException, Controller, Get, Module, Query, Req, Res } from '@nestjs/common';
import type { Response } from 'express';
import PDFDocument from 'pdfkit';
import ExcelJS from 'exceljs';
import { AcademicoModule } from './academico/academico.module.js';
import { AcademicoService } from './academico/academico.service.js';

const types: Record<string, { module: string; title: string }> = {
  matriculas: { module: 'matriculas', title: 'Matrículas por gestión' },
  notas: { module: 'notas', title: 'Calificaciones' },
  asistencias: { module: 'asistencias', title: 'Asistencia por sesión' },
  saldos: { module: 'saldos', title: 'Saldos pendientes' },
  grupos: { module: 'grupos', title: 'Grupos por gestión' },
  horarios: { module: 'horarios', title: 'Horarios y aulas' },
  boletin: { module: 'boletin', title: 'Boletín de resultados' },
  estudiantes: { module: 'estudiantes', title: 'Registro de estudiantes' },
  docentes: { module: 'docentes', title: 'Registro de docentes' },
};
function display(value: any): string {
  if (value == null) return '';
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}
async function pdfReport(title: string, columns: any[], rows: any[], username: string, filter: string) {
  const doc = new PDFDocument({ size: 'A4', layout: 'landscape', margin: 32, bufferPages: true, info: { Title: title, Author: 'Instituto Tecnológico Santa Cruz' } });
  const chunks: Buffer[] = [];
  const result = new Promise<Buffer>((ok, fail) => { doc.on('data', chunk => chunks.push(chunk)); doc.on('end', () => ok(Buffer.concat(chunks))); doc.on('error', fail); });
  const width = doc.page.width - 64;
  const colWidth = width / Math.max(columns.length, 1);
  const bottom = doc.page.height - 62;
  let y = 0;
  const header = () => {
    doc.font('Helvetica-Bold').fontSize(16).fillColor('#075c37').text('INSTITUTO TECNOLÓGICO SANTA CRUZ', 32, 30);
    doc.fontSize(12).text(title, 32, 54);
    doc.font('Helvetica').fontSize(8).fillColor('#44534a').text(`${filter} · ${rows.length} registros · Emitido: ${new Date().toLocaleString('es-BO', { timeZone: 'America/La_Paz' })} · ${username}`, 32, 74, { width });
    y = 98;
    const headerHeight = Math.max(30, ...columns.map(c => doc.fontSize(7).heightOfString(c.label, { width: colWidth - 8 }) + 12));
    doc.rect(32, y, width, headerHeight).fill('#075c37');
    columns.forEach((column, i) => doc.fillColor('white').font('Helvetica-Bold').fontSize(7).text(column.label, 36 + i * colWidth, y + 7, { width: colWidth - 8 }));
    y += headerHeight;
  };
  header();
  if (!rows.length) doc.font('Helvetica').fontSize(11).fillColor('#44534a').text('No hay registros para los filtros seleccionados.', 32, y + 20);
  rows.forEach((row, index) => {
    const texts = columns.map(column => display(row[column.key]));
    doc.font('Helvetica').fontSize(7);
    const height = Math.max(23, ...texts.map(text => doc.heightOfString(text, { width: colWidth - 8 }) + 10));
    if (y + height > bottom) { doc.addPage(); header(); }
    if (index % 2 === 0) doc.rect(32, y, width, height).fill('#eef6f0');
    texts.forEach((text, i) => doc.fillColor('#163326').font('Helvetica').fontSize(7).text(text, 36 + i * colWidth, y + 5, { width: colWidth - 8 }));
    y += height;
    doc.moveTo(32, y).lineTo(32 + width, y).strokeColor('#d6e4db').lineWidth(0.3).stroke();
  });
  const range = doc.bufferedPageRange();
  for (let i = range.start; i < range.start + range.count; i++) {
    doc.switchToPage(i);
    doc.font('Helvetica').fontSize(8).fillColor('#53645b').text(`Datos ficticios de demostración · Página ${i + 1} de ${range.count}`, 32, doc.page.height - 45, { width, align: 'right', lineBreak: false });
  }
  doc.end();
  return result;
}

@Controller('reportes')
class ReportsController {
  constructor(private academics: AcademicoService) {}
  @Get()
  async report(@Query() query: any, @Req() req: any, @Res() res: Response) {
    const type = types[String(query.tipo || 'matriculas')];
    const format = String(query.formato || 'pdf');
    if (!type || !['pdf', 'xlsx'].includes(format)) throw new BadRequestException('Selecciona un tipo de reporte y formato válidos.');
    for (const key of ['periodo_id', 'carrera_id', 'grupo_id']) {
      if (query[key] !== undefined && query[key] !== '' && (!/^\d+$/.test(String(query[key])) || !Number.isSafeInteger(Number(query[key])) || Number(query[key]) < 1 || Number(query[key]) > 2147483647)) throw new BadRequestException('Los filtros deben contener identificadores válidos.');
    }
    let page = 1;
    let columns: any[] = [];
    const rows: any[] = [];
    do {
      const listing = await this.academics.list(type.module, { ...query, page, pageSize: 100 }, req.user);
      columns = listing.columns;
      rows.push(...listing.rows);
      if (rows.length >= listing.total || !listing.rows.length) break;
      page++;
      if (page > 1000) throw new BadRequestException('Selecciona una gestión o carrera para reducir el tamaño del reporte.');
    } while (true);
    let filter = 'Todas las gestiones';
    if (query.periodo_id) {
      const period = await this.academics.prisma.periodos.findUnique({ where: { id: Number(query.periodo_id) } });
      if (period) filter = period.nombre;
    }
    const filename = `ITSC_${String(query.tipo || 'matriculas')}_${new Date().toISOString().slice(0, 10)}.${format}`;
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Cache-Control', 'no-store');
    if (format === 'pdf') {
      const bytes = await pdfReport(type.title, columns, rows, req.user.nombre, filter);
      res.type('application/pdf').send(bytes);
    } else {
      const workbook = new ExcelJS.Workbook();
      workbook.creator = 'Instituto Tecnológico Santa Cruz'; workbook.created = new Date();
      const sheet = workbook.addWorksheet('Reporte', { views: [{ state: 'frozen', ySplit: 4 }] });
      sheet.columns = columns.map(column => ({ key: column.key, width: Math.max(14, Math.min(36, column.label.length + 6)) }));
      sheet.mergeCells(1, 1, 1, Math.max(columns.length, 1));
      sheet.getCell(1, 1).value = 'INSTITUTO TECNOLÓGICO SANTA CRUZ'; sheet.getCell(1, 1).font = { bold: true, size: 16, color: { argb: 'FF075C37' } };
      sheet.mergeCells(2, 1, 2, Math.max(columns.length, 1)); sheet.getCell(2, 1).value = `${type.title} · ${filter} · ${rows.length} registros`;
      sheet.getRow(4).values = columns.map(column => column.label);
      sheet.getRow(4).font = { bold: true, color: { argb: 'FFFFFFFF' } };
      sheet.getRow(4).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF075C37' } };
      rows.forEach(row => sheet.addRow(columns.map(column => display(row[column.key]))));
      sheet.autoFilter = { from: { row: 4, column: 1 }, to: { row: 4 + rows.length, column: Math.max(columns.length, 1) } };
      sheet.eachRow((row, number) => { if (number > 4) { row.alignment = { vertical: 'top', wrapText: true }; if (number % 2) row.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFEEF6F0' } }; } });
      const bytes = await workbook.xlsx.writeBuffer();
      res.type('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet').send(Buffer.from(bytes));
    }
  }
}
@Module({ imports: [AcademicoModule], controllers: [ReportsController] })
export class ReportsModule {}
