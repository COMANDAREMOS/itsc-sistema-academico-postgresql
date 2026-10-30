import 'reflect-metadata';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from 'dotenv';
config({ path: resolve(fileURLToPath(new URL('.', import.meta.url)), '../../.env'), quiet: true });
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';
import { AppExceptionFilter } from './common/errors.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bodyParser: true });
  app.setGlobalPrefix('api');
  app.useGlobalFilters(new AppExceptionFilter());
  app.getHttpAdapter().getInstance().set('json replacer', (_key: string, value: any) => typeof value === 'bigint' ? value.toString() : value);
  app.use((_req: any, res: any, next: any) => { res.setHeader('Cache-Control', 'no-store'); res.setHeader('X-Content-Type-Options', 'nosniff'); next(); });
  app.enableShutdownHooks();
  const port = Number(process.env.API_PORT || 4001);
  await app.listen(port, '127.0.0.1');
  console.log(`API académica disponible en http://127.0.0.1:${port}/api`);
}
bootstrap().catch(error => { console.error('No se pudo iniciar el servidor:', error.message); process.exitCode = 1; });
