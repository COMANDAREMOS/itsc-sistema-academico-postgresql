# Base de datos independiente del Instituto Tecnológico Santa Cruz

La base PostgreSQL conserva las 40 tablas y los nombres de columnas del modelo
académico del práctico en el esquema `public`. El esquema estrella `dw` agrega
10 tablas: seis dimensiones, tres hechos y el registro de ejecuciones ETL.
En total hay 50 tablas y seis vistas. No utiliza ni modifica MariaDB.

## Archivos que se necesitan para instalarla

`ITSC_PostgreSQL_Demo.sql` es una exportación completa de estructura y datos
ficticios. Excluye las cuentas de acceso, los intentos de sesión y la auditoría.
La instalación recomendada sigue utilizando Prisma con `npm run setup`.
Como alternativa, el SQL se puede importar con `psql -f` en una base nueva y
vacía; después `setup` prepara los accesos privados. No se debe importar sobre
una base que ya tiene tablas y datos. El archivo se regenera con `npm run export:demo`.

- `schema.prisma`: modelos de Prisma ORM, claves, índices y relaciones.
- `migrations/202610300001_initial/migration.sql`: estructura PostgreSQL completa,
  incluidas restricciones `CHECK`, tres vistas y cinco disparadores.
- `migrations/202610300002_warehouse/migration.sql`: dimensiones, hechos,
  claves, índices y tres vistas analíticas del esquema estrella.
- `catalogo-demo.json`: 1000 estudiantes y 80 docentes ficticios, 12 carreras y
  el catálogo de 267 materias conservado del práctico.
- `seed.mjs`: crea una demostración coherente utilizando Prisma ORM.
- `etl.mjs`: extrae del modelo operativo y actualiza el almacén analítico.

El `seed` añade planes para las 12 carreras. Las cuatro carreras adicionales y
sus 24 materias se identifican expresamente como demostración. Las dos gestiones
son 2026 y 2027, sin superposición de fechas. Hay cuatro grupos de ejemplo,
50 matrículas, 150 inscripciones, 12 ofertas, 24 evaluaciones, 300 notas y
150 registros de asistencia. También se incluyen ejemplos de caja,
documentación, trámites y pasantías con importes y empresas ficticios.

Las ofertas están abiertas para poder practicar el cierre académico. No se
precargan resultados ni recuperaciones definitivas. Los usuarios de acceso los
prepara el instalador de la aplicación por separado.

## Ejecución

Con las dependencias del proyecto instaladas y `DATABASE_URL` apuntando a una
base PostgreSQL nueva:

```powershell
npx prisma validate
npx prisma generate
npx prisma migrate deploy
node db/seed.mjs
node db/etl.mjs
```

El `seed` trabaja en una transacción. Si ya se instaló esta demostración, no
modifica ningún registro. Si encuentra datos anteriores sin su marcador de
demostración, se detiene y no reemplaza la información existente.

## Decisiones de compatibilidad

- Los identificadores y campos enteros usan `Int`, incluidos los indicadores
  `activo`, `activa` y `excepcion_documentada`, cuyos valores permitidos son 0/1.
- Los estados usan `String` y restricciones PostgreSQL `CHECK`.
- Las fechas usan `DateTime @db.Date`; los horarios usan `DateTime @db.Time(0)`.
- Las relaciones compuestas conservan la pertenencia de materias, ofertas,
  matrículas y calificaciones a una misma carrera y gestión.
- La asistencia no puede superar los minutos de una sesión realizada.
- Las recuperaciones comprueban elegibilidad y límites por régimen, y son
  definitivas: no se permite modificarlas ni borrarlas.

`invariants.sql` es el origen legible de las vistas y funciones incorporadas en
la migración inicial. El archivo de migración ya está completo y no necesita
ejecutar `invariants.sql` por separado.

## Almacén analítico

Las dimensiones son gestión, carrera, estudiante, docente, materia y tiempo.
Los hechos conservan una fila por matrícula, inscripción con resultado cerrado
y pago, respectivamente. La carga utiliza `upsert` y no duplica esas filas.
Al inicio hay 50 hechos de matrícula, cero resultados y 20 pagos; cero resultados
es correcto porque las ofertas del ejemplo todavía no se cerraron.

`runEtl(prisma)` se puede importar desde NestJS. La consola también permite
`npm run etl`. La ejecución modifica únicamente `dw`, conserva una instantánea
consistente del origen y registra conteos y estado. Si falla, se revierte la
actualización analítica.

Los diagramas completos están en `docs/ARQUITECTURA.md`. Las migraciones
ya aplicadas se conservan: cualquier cambio posterior de estructura debe
prepararse como una nueva migración.

La utilidad `scripts/db-import-reference.py` fue usada exclusivamente para
la conversión inicial de una referencia local. No forma parte de la instalación,
el arranque, la carga de datos ni el ETL del sistema y no debe ejecutarse
sobre las migraciones ya establecidas.
