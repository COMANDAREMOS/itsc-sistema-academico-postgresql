# Verificación de la entrega — 30 de octubre de 2026

La aplicación fue compilada y comprobada con PostgreSQL 18.6, NestJS 12.3.2,
Next.js 16.4.3 y Prisma 7.10.1 en Windows.

| Comprobación automatizada | Correctas | Fallos |
| --- | ---: | ---: |
| Procesos funcionales y permisos | 276 | 0 |
| Seguridad del acceso y concurrencia | 31 | 0 |
| Almacén analítico y ETL | 12 | 0 |
| Total | 319 | 0 |

Los detalles están en `docs/pruebas/`. Las pruebas que escriben registros
utilizaron exclusivamente `itsc_postgres_pruebas`, en el puerto 4002.
La aplicación entregada usa `itsc_postgres` y el puerto 4001.

También se verificaron:

- Compilaciones de producción del backend y frontend y validación del esquema ORM.
- Registro de 1.000 estudiantes, 80 docentes, 12 carreras y 4 grupos, con 50 matrículas iniciales.
- Exportación real de 1.000 estudiantes: Excel de 1.004 filas, incluidos encabezados;
  PDF de 67 páginas, todas con encabezado, contenido y pie, sin páginas vacías.
- Texto y acentos del PDF legibles mediante un lector independiente.
- Cero vulnerabilidades reportadas por `npm audit --omit=dev` en esta revisión.
- Respaldo PostgreSQL en formato personalizado legible por `pg_restore`:
  50 tablas de la aplicación, la tabla de migraciones y 6 vistas.
- Interfaz en escritorio y pantalla de 390 px, menú móvil, modo oscuro,
  formularios, filtros, diagrama de clases y actualización analítica desde la página.
- Comparación SHA256 de 81 archivos del proyecto anterior: ningún cambio.
- Inicio y detención del nuevo servidor mediante los scripts incluidos.

Las comprobaciones describen el estado probado de esta entrega. Los nuevos
cambios de código o configuración deben verificarse nuevamente.
