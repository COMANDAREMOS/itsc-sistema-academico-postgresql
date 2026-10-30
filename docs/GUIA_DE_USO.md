# Guía de uso del sistema académico PostgreSQL

## 1. Abrir el sistema

1. Comprobar que el servicio Windows `postgresql-x64-18` esté iniciado.
2. Abrir la carpeta de este proyecto nuevo.
3. Hacer doble clic en `INICIAR.cmd`.
4. Abrir http://localhost:3000 en el navegador.
5. Mantener abierta la ventana del servidor. Para detenerlo, usar `Ctrl+C`.

La página utiliza Next.js en el puerto 3000, NestJS en 4001 y PostgreSQL en 5432.
Para este proyecto no es necesario iniciar Apache o MySQL de XAMPP.

Si aparece “puerto ocupado”, puede que el sistema ya esté iniciado. Abrir la
dirección antes de iniciar otra copia; no cerrar procesos de otros proyectos.

## 2. Instalar en otra computadora

Se necesita Node.js 24, PostgreSQL 18, npm y los archivos del proyecto.
Desde una terminal en la raíz:

```bat
npm ci
npm run setup
npm run build
npm start
```

En la PC preparada, el instalador utiliza la configuración privada local de
PostgreSQL. En otra PC se puede proporcionar una conexión administrativa
mediante `PGADMIN_DATABASE_URL`. Ejemplo en PowerShell sin escribir la
contraseña directamente en el historial:

```powershell
$pgAcceso = Get-Credential -UserName postgres -Message 'Administrador local de PostgreSQL'
$pgClaveUrl = [Uri]::EscapeDataString($pgAcceso.GetNetworkCredential().Password)
$env:PGADMIN_DATABASE_URL = "postgresql://postgres:${pgClaveUrl}@127.0.0.1:5432/postgres"
try { npm.cmd run setup } finally { Remove-Item Env:\PGADMIN_DATABASE_URL }
```

El procedimiento crea la base nueva `itsc_postgres`, aplica las migraciones y
carga la demostración. Si encuentra una base del mismo nombre que pertenece
a otro usuario, se detiene. No se debe borrar una base existente para resolver
un mensaje sin revisar primero su propietario y su contenido.

`.env` contiene la conexión de la aplicación y su secreto de sesión. El
archivo `.env.example` muestra los nombres de las variables sin contraseñas
reales. No publicar `.env` ni la carpeta privada de accesos.

## 3. Entrar y cerrar sesión

Las contraseñas iniciales están en:

```text
Documentos/Codex/Credenciales_Privadas/PostgreSQL_18/ITSC_PostgreSQL_accesos.json
```

- `admin`: administración del sistema.
- `docente.demo`: docente asociado a la persona docente 1 de la demostración.
- `caja.demo`: cargos, pagos y saldos.

`postgres` es el usuario administrador de la base; no es un usuario de la
página. La cuenta de la base utilizada por la aplicación es `itsc_pg_app`.

Cada persona debe utilizar su acceso. El botón de cerrar sesión elimina la
sesión del navegador. “Mi contraseña” permite cambiar la clave con un mínimo
de 12 caracteres y requiere volver a entrar. Si se cambia la contraseña,
utilizar la nueva; el archivo de accesos iniciales no se actualiza automáticamente.

El botón de modo oscuro cambia el fondo y conserva la elección en ese
navegador. El modo claro y el oscuro comparten el logotipo y los colores
institucionales.

## 4. Entender el panel

Elegir una gestión para ver sus matrículas, grupos, ofertas y saldos. El
catálogo contiene 1000 estudiantes ficticios, pero inicialmente solo 50 tienen
matrícula: 30 en Sistemas Informáticos y 20 en Contaduría General durante 2026.

Los grupos 2027 están vacíos para demostrar cómo organizar una nueva gestión.
El panel de un docente muestra únicamente sus ofertas y grupos asociados.

## 5. Preparar una gestión y sus grupos

1. Registrar el período con nombre, fecha inicial y final.
2. Revisar la carrera, sus materias y el plan de estudio.
3. Crear el grupo con gestión, carrera, nivel, paralelo, turno, cupo y tutor.
4. Crear las ofertas de materias con la misma carrera, gestión, paralelo y turno.
5. Vincular las ofertas al grupo.
6. Crear las matrículas de estudiantes usando el plan de esa carrera y gestión.

Un grupo que ya tiene asignaciones conserva su identidad. Para otra gestión,
carrera, nivel, paralelo o turno, crear otro grupo. No reducir el cupo por
debajo de sus integrantes. Un grupo cerrado no admite nuevas asignaciones.

## 6. Inscribir estudiantes

En “Inscripción por grupo”, elegir gestión, carrera y grupo. La lista muestra
matrículas activas compatibles y el estado de su asignación. Seleccionar las
matrículas y ejecutar la inscripción.

La operación asigna integrantes e inscribe las materias vinculadas al grupo.
Se controla la capacidad del grupo y de cada oferta, el plan, los
prerrequisitos y la correspondencia de carrera y gestión. Si una matrícula
del lote es inválida, se revierte toda la operación. Repetir un lote ya
procesado no duplica inscripciones.

La inscripción individual aplica las mismas reglas. Si la oferta pertenece
a un grupo, la matrícula debe estar asignada previamente a ese grupo.

## 7. Horarios y aulas

Registrar aula, oferta, día, hora inicial y final. La hora final debe ser
posterior a la inicial y el aula debe admitir el cupo de la oferta.

El sistema rechaza cruces del mismo docente, aula o grupo, también cuando
dos gestiones tienen fechas superpuestas. Dos intervalos contiguos, como
08:00-10:00 y 10:00-12:00, pueden utilizar el mismo recurso.

Si una gestión ya tiene horarios, retirar o reorganizar esas asignaciones
antes de modificar sus fechas.

## 8. Evaluación y asistencia

Las evaluaciones se dividen en práctica y teoría. Los pesos deben sumar 100%
dentro de cada componente antes del cierre.

Las calificaciones admiten valores de 1 a 100. La asistencia se registra en
minutos de una sesión realizada:0 significa ausencia y el máximo es la
duración de la sesión. Las planillas permiten guardar varios estudiantes en
una sola operación; los espacios dejados en blanco conservan lo registrado.

El docente solo puede operar las ofertas que tiene asignadas. Administración
puede supervisarlas y registrar justificaciones autorizadas con referencia
documental y resolución.

## 9. Cerrar y calcular resultados

Antes de cerrar una oferta:

1. Completar el 100% de práctica y teoría.
2. Registrar las calificaciones de todos sus estudiantes.
3. Registrar todas las sesiones realizadas y su asistencia.
4. Resolver sesiones todavía programadas.
5. Indicar una carga horaria igual a la suma de minutos de las sesiones realizadas.

El cierre calcula resultados y bloquea nuevas modificaciones académicas de
esa oferta. Las reglas del práctico utilizan 70% de práctica, 30% de teoría,
aprobación desde 61 y asistencia mínima de 80%, con la excepción documental
prevista en el sistema. Se presentan como referencia académica conservada,
sin afirmar que se haya verificado normativa vigente para una institución real.

Una recuperación requiere un resultado reprobado habilitado desde 40 puntos
y respeta el límite del régimen. Si se aprueba, registra 61 como nota final.
El registro es definitivo y no admite edición o borrado ordinario.

## 10. Caja, documentos y seguimiento

Administración define cargos y vencimientos. Caja registra abonos con un
recibo único y método de pago. No se aceptan importes de pago mayores al saldo.
Un cargo liquidado deja de aparecer como pendiente. Los importes iniciales
son ficticios y no representan tarifas oficiales.

Documentación permite marcar cada requisito como pendiente, recibido u
observado. La misma matrícula y tipo de documento se actualizan sin
duplicarse. La aplicación no almacena copias de documentos personales.

Los módulos de trámites, pasantías y graduación conservan sus estados y
relaciones con la matrícula y los docentes correspondientes.

## 11. Reportes y analítica

En “Reportes”, elegir tipo, filtros y formato PDF o XLSX. Los permisos son
los mismos que para consultar los datos de origen. Un docente no exporta
información de caja y caja no exporta calificaciones.

El módulo de analítica utiliza el esquema estrella `dw`. Solo administración
puede consultarlo y actualizarlo. Después de registrar matrículas, pagos,
cierres o recuperaciones, ejecutar “Actualizar” o:

```bat
npm run etl
```

El almacén muestra la información de la última ejecución correcta. La
repetición no suma filas duplicadas. Los conteos de ejecución y su estado
permiten comprobar el proceso. Al inicio es normal tener 0 resultados
académicos en el almacén: las ofertas de demostración todavía están abiertas.

## 12. Respaldo de la base nueva

Desde la raíz del proyecto:

```bat
npm run backup
```

Se genera un archivo de formato personalizado de PostgreSQL en `backups/`.
El respaldo contiene los esquemas operativo y analítico. Conservarlo de
forma privada; puede contener datos y hashes de usuarios y no debe subirse
a un repositorio público.

Para comprobar una restauración, crear **otra base vacía**. Este ejemplo
no reemplaza `itsc_postgres` ni utiliza el servidor MariaDB anterior:

```powershell
$pgBin = 'C:\Program Files\PostgreSQL\18\bin'
& "$pgBin\createdb.exe" -h 127.0.0.1 -p 5432 -U postgres -O itsc_pg_app -T template0 -E UTF8 itsc_postgres_restauracion
& "$pgBin\pg_restore.exe" -h 127.0.0.1 -p 5432 -U itsc_pg_app -d itsc_postgres_restauracion --no-owner --exit-on-error 'backups\ARCHIVO_ELEGIDO.dump'
```

Elegir el nombre real del archivo de respaldo en el último comando. Las
herramientas solicitarán la contraseña del usuario indicado. Si la base
de restauración ya existe, detenerse y elegir otro nombre vacío; no usar
opciones de limpieza o reemplazo sobre datos que se necesiten conservar.

Abrir la copia en pgAdmin y verificar tablas, conteos y consultas antes de
cambiar cualquier conexión de la aplicación. El `.env` del sistema principal
puede mantenerse intacto durante esta comprobación.

## 13. Qué mostrar al docente

- La página funcionando con los roles y procesos del instituto.
- pgAdmin con la base `itsc_postgres`, esquema `public` y esquema `dw`.
- Las relaciones del ORM y las migraciones SQL de la carpeta `db`.
- Los diagramas de [arquitectura, OLTP y estrella](ARQUITECTURA.md).
- La ejecución ETL, los reportes y el registro de pruebas.
- El repositorio del grupo y sus evidencias reales cuando se publique.

La guía recibida también evalúa contribuciones de cada integrante, PRs
revisados, Issues, tablero y etiquetas por hito. Esas evidencias corresponden
al trabajo real del equipo y no se generan ni se simulan automáticamente.
