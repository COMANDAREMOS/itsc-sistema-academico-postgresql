import { Body, CanActivate, Controller, ExecutionContext, ForbiddenException, Get, HttpException, Injectable, Module, Post, Req, Res, SetMetadata, UnauthorizedException, BadRequestException } from '@nestjs/common';
import { APP_GUARD, Reflector } from '@nestjs/core';
import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import type { Request, Response } from 'express';
import { PrismaService } from '../common/prisma.service.js';
import { hashPassword, verifyPassword } from './password.js';

export const Public = () => SetMetadata('public', true);
export const cookieName = 'itsc_pg_sesion';
const dummyHash = hashPassword(randomBytes(32).toString('hex'));
const safeUser = (u: any) => ({ id: u.id, usuario: u.usuario, nombre: u.nombre, rol: u.rol, docente_id: u.docente_id });
const passwordVersion = (hash: string) => createHash('sha256').update(hash).digest('hex').slice(0, 24);
function secret() {
  if (!process.env.SESSION_SECRET || process.env.SESSION_SECRET.length < 32) throw new Error('SESSION_SECRET debe tener al menos 32 caracteres.');
  return new TextEncoder().encode(process.env.SESSION_SECRET);
}
function sessionCookie(req: Request) {
  const cookies = String(req.headers.cookie || '').split(';');
  const value = cookies.find(x => x.trim().startsWith(cookieName + '='));
  return value ? decodeURIComponent(value.trim().slice(cookieName.length + 1)) : '';
}

@Injectable()
export class AuthenticationGuard implements CanActivate {
  constructor(private reflector: Reflector, private db: PrismaService) {}
  async canActivate(ctx: ExecutionContext) {
    const req = ctx.switchToHttp().getRequest();
    if (!['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
      if (req.headers['x-requested-with'] !== 'ITSC') throw new ForbiddenException('La solicitud no tiene una verificación válida. Actualiza la página.');
      const origins = new Set(['http://localhost:3000', 'http://127.0.0.1:3000', process.env.WEB_ORIGIN].filter(Boolean));
      if (req.headers.origin && !origins.has(req.headers.origin)) throw new ForbiddenException('Origen de la solicitud no autorizado.');
    }
    if (this.reflector.getAllAndOverride<boolean>('public', [ctx.getHandler(), ctx.getClass()])) return true;
    try {
      const token = sessionCookie(req);
      if (!token) throw new Error('Sin sesión');
      const { payload } = await jwtVerify(token, secret(), { algorithms: ['HS256'], issuer: 'itsc-academico', audience: 'itsc-web' });
      const id = Number(payload.sub);
      if (!Number.isSafeInteger(id) || id < 1) throw new Error('Sesión inválida');
      const usuario = await this.db.app_usuarios.findUnique({ where: { id } });
      if (!usuario?.activo || payload.pwv !== passwordVersion(usuario.password_hash)) throw new Error('Sesión revocada');
      req.user = safeUser(usuario);
      return true;
    } catch { throw new UnauthorizedException('Tu sesión terminó. Inicia sesión nuevamente.'); }
  }
}

@Controller('auth')
export class AuthController {
  constructor(private db: PrismaService) {}
  @Public()
  @Post('login')
  async login(@Body() body: any, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    if (typeof body?.usuario !== 'string' || typeof body?.password !== 'string') throw new UnauthorizedException('Usuario o contraseña incorrectos.');
    const usuario = body.usuario.trim();
    const password = body.password;
    if (!usuario || usuario.length > 60 || !password || password.length > 200) throw new UnauthorizedException('Usuario o contraseña incorrectos.');
    const clave = createHash('sha256').update(usuario.toLocaleLowerCase('es') + ':' + req.ip).digest('hex');
    const attempt: any = await this.db.$transaction(async tx => {
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${clave}, 0))::text`;
      const intento = await tx.app_intentos.findUnique({ where: { clave } });
      const recent = intento && Date.now() - intento.ultimo.getTime() < 15 * 60 * 1000;
      if (recent && intento.fallos >= 5) return { blocked: true };
      const found = await tx.app_usuarios.findUnique({ where: { usuario } });
      const valid = verifyPassword(password, found?.password_hash || dummyHash);
      if (!found?.activo || !valid) {
        await tx.app_intentos.upsert({ where: { clave }, create: { clave, fallos: 1, ultimo: new Date() }, update: { fallos: recent ? { increment: 1 } : 1, ultimo: new Date() } });
        return { rejected: true };
      }
      await tx.app_intentos.deleteMany({ where: { clave } });
      return { found };
    }, { maxWait: 15000, timeout: 20000 });
    if (attempt.blocked) throw new HttpException('Se alcanzó el límite de intentos. Espera 15 minutos.', 429);
    if (attempt.rejected) throw new UnauthorizedException('Usuario o contraseña incorrectos.');
    const found = attempt.found;
    const token = await new SignJWT({ pwv: passwordVersion(found.password_hash) }).setProtectedHeader({ alg: 'HS256' }).setSubject(String(found.id)).setIssuer('itsc-academico').setAudience('itsc-web').setIssuedAt().setExpirationTime('1h').sign(secret());
    res.cookie(cookieName, token, { httpOnly: true, sameSite: 'strict', secure: process.env.COOKIE_SECURE === 'true', maxAge: 3600000, path: '/' });
    res.setHeader('Cache-Control', 'no-store');
    await this.db.app_auditoria.create({ data: { usuario_id: found.id, accion: 'INICIO_SESION', entidad: 'usuarios', registro_id: String(found.id) } });
    return { user: safeUser(found) };
  }
  @Get('me')
  me(@Req() req: any, @Res({ passthrough: true }) res: Response) { res.setHeader('Cache-Control', 'no-store'); return { user: req.user }; }
  @Post('logout')
  async logout(@Req() req: any, @Res({ passthrough: true }) res: Response) {
    res.clearCookie(cookieName, { path: '/' });
    await this.db.app_auditoria.create({ data: { usuario_id: req.user.id, accion: 'CIERRE_SESION', entidad: 'usuarios', registro_id: String(req.user.id) } });
    return { message: 'Sesión cerrada.' };
  }
  @Post('password')
  async password(@Body() body: any, @Req() req: any, @Res({ passthrough: true }) res: Response) {
    if (typeof body?.actual !== 'string' || typeof body?.nueva !== 'string' || typeof body?.confirmacion !== 'string') throw new BadRequestException('Completa correctamente los campos de contraseña.');
    const actual = body.actual, nueva = body.nueva;
    if (actual.length > 200) throw new BadRequestException('La contraseña actual no es válida.');
    if (nueva.length < 12 || nueva.length > 200) throw new BadRequestException('La nueva contraseña debe tener entre 12 y 200 caracteres.');
    if (nueva !== body.confirmacion) throw new BadRequestException('La confirmación no coincide.');
    const user = await this.db.app_usuarios.findUnique({ where: { id: req.user.id } });
    if (!user || !verifyPassword(actual, user.password_hash)) throw new BadRequestException('La contraseña actual es incorrecta.');
    await this.db.$transaction(async tx => {
      await tx.app_usuarios.update({ where: { id: user.id }, data: { password_hash: hashPassword(nueva) } });
      await tx.app_auditoria.create({ data: { usuario_id: user.id, accion: 'CAMBIO_CONTRASENA', entidad: 'usuarios', registro_id: String(user.id) } });
    });
    res.clearCookie(cookieName, { path: '/' });
    return { message: 'Contraseña actualizada. Inicia sesión con tu nueva contraseña.', relogin: true };
  }
}

@Module({ controllers: [AuthController], providers: [{ provide: APP_GUARD, useClass: AuthenticationGuard }] })
export class AuthModule {}
