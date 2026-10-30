import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from '@nestjs/common';

@Catch()
export class AppExceptionFilter implements ExceptionFilter {
  catch(error: any, host: ArgumentsHost) {
    let status = 500, message = 'No se pudo completar la operación. Intenta nuevamente.';
    if (error instanceof HttpException) {
      status = error.getStatus();
      const response: any = error.getResponse();
      message = typeof response === 'string' ? response : Array.isArray(response.message) ? response.message.join(' ') : response.message || message;
    } else if (error.code === 'P2002' || error.code === '23505') { status = 409; message = 'Ya existe un registro con esos datos. Revisa documento, registro, grupo o recibo.'; }
    else if (error.code === 'P2003' || error.code === '23503') { status = 409; message = 'El registro está relacionado con otros datos. Revisa las selecciones antes de continuar.'; }
    else if (error.code === 'P2025') { status = 404; message = 'El registro ya no existe.'; }
    else if (error.code === 'P2034' || error.code === '40001' || error.code === '40P01') { status = 409; message = 'Otra operación modificó estos datos. Actualiza la pantalla y vuelve a intentarlo.'; }
    else if (['P2000','P2006','P2007','P2011','23514','22001','22007'].includes(error.code)) { status = 422; message = 'Los datos no cumplen las restricciones. Revisa los campos del formulario.'; }
    else console.error('Error de aplicación:', error.name, error.code || '', error.message?.slice(0, 500));
    host.switchToHttp().getResponse().status(status).json({ statusCode: status, message });
  }
}
