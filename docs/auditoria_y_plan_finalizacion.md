# Bodegas del Atuel — Auditoría y plan de finalización

Auditoría original: 9 de noviembre de 2026, fase A. **El estado vigente al cierre
de G está en [§15](#15-estado-vigente-tras-fase-g)**. El cierre de E y su informe
de rendimiento están en §13. Las secciones 1–9 conservan el diagnóstico inicial;
los cierres 10–12 describen cada fase anterior, no bloqueos actuales. La frase
«no se modificó SQL» y los pendientes de esos cortes no describen el estado G.

**Actualización de fase B:** el inventario, matriz y hallazgos siguientes
conservan la fotografía inicial de fase A. H2, H3 y los defectos nominales y de
permisos de H6/H7 se corrigieron después; el estado vigente, pruebas y pendientes
se detallan en [§10](#10-cierre-de-fase-b). La afirmación de auditoría estática
aplica a fase A, no a las pruebas reales posteriores.

**Estado vigente B.2:** H1/H4 ya están resueltos bajo la política histórica
expresamente autorizada por el usuario; véase [§11](#11-cierre-de-fase-b2).
Las preguntas y alternativas anteriores se conservan como antecedentes de A/B,
no como bloqueos actuales ni como decisiones docentes confirmadas.

**Actualización C:** la carga masiva ya está implementada y verificada;
véase [§12](#12-cierre-de-fase-c). La matriz inicial sigue siendo la fotografía
de la auditoría A, no el estado actualizado de estos entregables.

El diagnóstico A recomendaba conservar la base lógica/física y corregir borrados,
cabeceras y totales antes de cargar. Esas correcciones y la carga ya se realizaron;
se mantienen a continuación sus fundamentos e historial de decisiones.

## 1. Fuentes y límites de la revisión

Se inspeccionaron todos los archivos de `database/`, los seis archivos de `docs/`, `README.md`, `basico.py`, el log DBML y el contenido de `database.zip`. No se encontró `AGENTS.md` en el proyecto ni en su directorio padre.

La consigna y el DER no están dentro del repositorio. Sus rutas aparecen en `trazabilidad_der_relacional.md` y se pudieron leer:

- `C:\Users\eluam\Downloads\TPI_Bodegas_del_Atuel.md`: fuente local principal del enunciado, con sus nueve etapas y sección 8.
- `C:\Users\eluam\Downloads\DER.drawio.xml`: dos páginas; 347 celdas en la primera y dos en la segunda. Se confirmaron 25 rombos, 97 elipses y la ISA total/disjunta. SHA-256: `3fa9095cdcb06f98527876fdecaf8e84f33fd7237839554bad05b6e850368f34`.

También se leyó la [copia pública del PDF del TPI](https://github.com/mmartimolina/Bodegas-del-Atuel/blob/37918fd0d64f555d731dc3c3f5f6d0cf6cf88941/docs/consigna/TPI_Bodegas_del_Atuel.pdf), de 29 páginas. Los requisitos citados abajo se contrastaron con la consigna local; el PDF externo no reemplaza decisiones aprobadas del proyecto. Su SHA-256 es `577d3ab796d957b564c872015713a0b6a728bccb6651262b1bcd3a50668a5c2e`.

Prioridad aplicada: consigna local → decisiones aprobadas → modelo/SQL → referencias externas. Se conservan las 29 tablas, Localidad–Finca 1:N, provincia mediante Localidad, Parcela compuesta, clave alternativa de Lote, ISA total/disjunta y descuento histórico. No se encontró una razón demostrada para cambiar la descomposición en 3FN.

**Evidencia:** esta auditoría es estática. Se leyeron implementaciones y pruebas; no se ejecutaron scripts contra PostgreSQL, suites, endpoints ni benchmarks. Hay binarios PostgreSQL 18 instalados, aunque `psql` no está en PATH. No se inspeccionó una base activa. El README declara una ejecución previa en 18.4 y una prueba concurrente: se registra como antecedente, sin convertirla en resultado de esta auditoría; no hay salidas conservadas que permitan reproducir esa afirmación desde el repositorio.

Estados: **completo** significa evidencia suficiente para el entregable indicado; **parcial**, implementación o documentación con validación/alcance faltante; **pendiente**, entregable ausente; **bloqueado**, conflicto concreto que exige una decisión. P0: resolver antes de cargar; P1: siguiente entregable obligatorio; P2: etapa posterior. No se asigna porcentaje global de cumplimiento ni nota.

## 2. Inventario que conviene conservar

| Componente | Evidencia inspeccionada | Evaluación |
|---|---|---|
| Modelo lógico | DBML: 29 tablas y 35 referencias; esquema relacional y trazabilidad | Conservar claves y decisiones. El DBML no contiene notas descriptivas de tabla. |
| Normalización | Matriz individual de las 29 relaciones, DF y descomposiciones de descuento/provincia | Conservar. La prueba es respecto de las DF justificadas; el total materializado es redundancia agregada explícita. |
| DDL | `02_tablas.sql`: 29 tablas, 35 FK, cuatro UNIQUE adicionales, 22 CHECK | Conteo de declaraciones, no catálogo de una base instalada. Todas las tablas declaran PK; FK con acciones explícitas. |
| Defaults/tipos | Cinco defaults explícitos en columnas; además `BY DEFAULT AS IDENTITY` en auditoría. Dos ENUM y un DOMAIN CUIT | Supera los mínimos declarativos. El dominio controla once dígitos, no dígito verificador fiscal. |
| Rutinas | `04_funciones.sql`: nueve funciones y dos procedimientos | Incluye las cuatro funciones y dos procedimientos solicitados; auxiliares justificados por recálculo, ISA y composición. |
| Triggers | `05_triggers.sql`: 22 declaraciones CREATE TRIGGER, incluidas diferidas | Hay BEFORE, AFTER y constraint triggers. No contar funciones de trigger como funciones de negocio adicionales. |
| Índices | `06_indices.sql`: 23 índices explícitos B-tree | Conservar como candidatos, sujetos a medición. No hay duplicación exacta evidente con PK/UNIQUE por prefijo izquierdo. |
| Vistas | Stock total, ventas mensuales por sala y documentos pendientes | Tres vistas ordinarias; no hace falta materializar una para cumplir. |
| Roles | Propietario, API y reportes, todos NOLOGIN | Buena separación inicial; faltan probar alcance real y propiedad de objetos. |
| Pruebas | `08` y `09`, fixtures transaccionales, excepciones esperadas, ROLLBACK | Conservar y ampliar los huecos señalados; no reemplazar por otra suite duplicada. |
| Diagramación | `.dbdiagram` es JSON de posiciones y vistas | Complementa al DBML; no es otro esquema ni un script para ejecutar. |

La lista completa de relaciones ya está en [esquema_relacional.md](esquema_relacional.md); no se duplica aquí. Los importes usan NUMERIC, estados ENUM, las FK de localidad/finca respetan la decisión y `comprobante_vino` conserva cantidad/precio sin repetir el porcentaje histórico.

## 3. Comparación de las tres referencias

Se consultaron árboles y archivos relevantes mediante GitHub API y archivos raw, sin ejecutar código ajeno ni copiarlo. Versiones inspeccionadas: Lucas `3e21aec3f9571549049e2667ee2192df9373656a`; Molina `37918fd0d64f555d731dc3c3f5f6d0cf6cf88941`; Grupo 28 `6f18017a61f6ae70af9ce5a6055562a0e62ef8b3`. La existencia de un artefacto externo no prueba su corrección.

### Lucas Bordon

El [árbol del proyecto](https://github.com/LucasBordon33/Proyecto-BDD-PSQL/tree/3e21aec3f9571549049e2667ee2192df9373656a) contiene migraciones, CSV y generador, pruebas SQL, cuatro archivos de consultas, FastAPI, frontend HTML/JS, Compose, pruebas de API y documentos de carga/rendimiento. Se leyeron manifiesto, conexión, entrada de API, repositorio/servicio de ventas, UPDATE, índices y generador. Los PDF y las pantallas se inventariaron; no se validó su contenido ni funcionamiento.

Aprovechable: SQL parametrizado, transacción para cabecera y renglones, pool, manejo central de errores, `/salud`, frontend sencillo y archivos separados por tipo de consulta. La [venta transaccional](https://github.com/LucasBordon33/Proyecto-BDD-PSQL/blob/3e21aec3f9571549049e2667ee2192df9373656a/api/services/comprobantes_service.py) sirve como referencia de atomicidad.

Evitar: su [repositorio de comprobantes](https://github.com/LucasBordon33/Proyecto-BDD-PSQL/blob/3e21aec3f9571549049e2667ee2192df9373656a/api/repositories/comprobantes_repo.py) convierte dinero a float, calcula subtotales en Python y actualiza importes de cabecera. Eso contradice nuestra responsabilidad de PostgreSQL. En [UPDATE](https://github.com/LucasBordon33/Proyecto-BDD-PSQL/blob/3e21aec3f9571549049e2667ee2192df9373656a/consultas/update.sql), U1 recalcula descuentos y termina con COMMIT; U6 modifica comprobantes históricos. También hay nombres de tablas que difieren entre consultas y API. No trasladar esas sentencias ni su separación completa routes/services/repositories por defecto.

### Martín Molina

El [árbol del proyecto](https://github.com/mmartimolina/Bodegas-del-Atuel/tree/37918fd0d64f555d731dc3c3f5f6d0cf6cf88941) contiene consigna, análisis de requisitos/modelo/diccionario, migraciones, pruebas por RN, demostraciones de concurrencia, benchmarks con salidas y Compose. No aparecen API, frontend ni `consultas/` en el árbol inspeccionado. Su carga de benchmark no equivale por sí sola al dataset coherente de etapa 3.

Aprovechable: separar requisito, inferencia y pregunta; conservar evidencia de sesiones y planes; pruebas positivas/negativas; scripts de medición. Se leyeron requisitos, procesamiento, índices, runner e informe de rendimiento. Los [índices](https://github.com/mmartimolina/Bodegas-del-Atuel/blob/37918fd0d64f555d731dc3c3f5f6d0cf6cf88941/db/migrations/013_indices.sql) incluyen parciales para pendientes. No incorporan en ese archivo una variante de expresión/BRIN/INCLUDE: tampoco esa referencia cumple automáticamente toda la variedad exigida. Sus nombres entrecomillados y su esquema no corresponden al nuestro. Las variantes de concurrencia que retiran controles deben limitarse a laboratorios descartables.

### Grupo 28

El [árbol del proyecto](https://github.com/marcos-velez-20/TPI-Base-de-Datos-Grupo-28/tree/6f18017a61f6ae70af9ce5a6055562a0e62ef8b3) contiene consigna, DER, diccionario, migraciones, generador/CSV, controles, dump, cuatro archivos de consultas, pruebas e informe de rendimiento. No aparecen API ni frontend. Se leyeron esquema, README de carga, controles, generador en sus decisiones relevantes, UPDATE e informe de índices; no se ejecutaron ni se verificó el dump.

Aprovechable: semilla y fecha de referencia explícitas, controles de carga, comparación de datos por hashes, operaciones con controles antes/después y ROLLBACK. El [informe de rendimiento](https://github.com/marcos-velez-20/TPI-Base-de-Datos-Grupo-28/blob/6f18017a61f6ae70af9ce5a6055562a0e62ef8b3/docs/informe_rendimiento.md) muestra casos sin mejora, costo de escritura y BRIN descartado. Sus propias tablas no demuestran tres consultas con menor tiempo: no copiar la conclusión de mejora de Q5, que contradice su tabla comparativa.

Evitar: el generador tiene unas 2.500 líneas y deshabilita triggers de usuario para cargar historia. Es una estrategia de terceros que exige controles equivalentes, no un requisito para nosotros. Su [U1](https://github.com/marcos-velez-20/TPI-Base-de-Datos-Grupo-28/blob/6f18017a61f6ae70af9ce5a6055562a0e62ef8b3/consultas/update.sql) actualiza renglones para reaplicar descuentos vigentes después de U6: incompatible con nuestra historia. Sus nombres (`clientes`, `detalle_comprobante`, etc.) y decisiones de claves no deben reemplazar las 29 relaciones propias.

## 4. Matriz histórica de cumplimiento — fase A

Las páginas remiten a la consigna, no a documentación de terceros. Las filas de ejecución siguen parciales aunque el mecanismo se vea correcto por lectura.

Esta matriz es la fotografía A. Para decidir el siguiente trabajo se utiliza
el estado vigente de §13, no las etiquetas pendientes/bloqueadas de esta tabla.

| Requisito del TPI | Etapa | Archivo o componente existente | Estado | Evidencia de cumplimiento | Acción necesaria | Prioridad | Referencia externa útil |
|---|---|---|---|---|---|---|---|
| DER fuente e imagen/PDF (p. 10) | 1 | XML en Downloads; trazabilidad | Parcial | XML legible, ISA y entidad débil documentadas; no fuente ni exportación en repo | Incorporar original sin alterarlo y exportación revisada | P1 | Molina: entrega fuente/exportaciones |
| Entidades, claves y 3FN | 1 | DBML, esquema, normalización | Completo, documental | 29 relaciones y prueba individual de DF; decisiones aprobadas representadas | Conservar; contrastar diccionario futuro con DDL | P1 | Ninguna necesaria |
| Diccionario por tabla y columna | 1 | Esquema y DDL | Parcial | Tipos/restricciones existen; faltan descripciones y nulabilidad en diccionario completo | Agregar `docs/diccionario_datos.md` | P1 | Diccionarios Molina/Grupo 28 |
| Instalación desde cero en contenedor | 1–2 | SQL 01–07 y README | Parcial | Orden documentado; antecedente declarado, sin Compose ni evidencia conservada | Probar base limpia y guardar versión/salidas | P0 | Compose de referencias |
| PK/FK/NOT NULL; ≥4 UNIQUE; ≥8 CHECK, uno entre columnas; ≥3 DEFAULT | 2 | SQL 01–03 | Parcial | 29 PK, 35 FK, cuatro UNIQUE, 22 CHECK; fechas de permiso entre columnas; cinco defaults de columna | Ejecutar y verificar catálogo; revisar identidad obligatoria de cliente | P0 | Consigna p. 11 |
| ≥1 ENUM y ≥1 DOMAIN | 2 | SQL 01 | Parcial | Dos ENUM y un dominio de formato CUIT | Verificar instalación/casos válidos e inválidos | P1 | Conservar implementación |
| Cuatro funciones y dos procedimientos | 2 | SQL 04 | Parcial | Rutinas requeridas presentes; procesamiento delega impacto al trigger | Ejecutar como rol real; documentar parámetros/volatilidad y propósito | P0 | Lucas: transacciones |
| ≥6 propósitos de trigger; BEFORE/AFTER/diferido | 2 | SQL 05 | Parcial | 22 triggers; suma, ISA, stock, estados, precios | Completar comentarios RN y pruebas de huecos | P0 | Molina: casos por regla |
| RN-01 precio positivo y único por vino | 2 | Vino; suite 09 | Parcial | Precio en Vino, CHECK > 0; caso de rechazo | Reejecutar; no duplicar precio vigente en salas | P1 | — |
| RN-02 localidad/encargado y RN-03 empleado/sala | 2 | Localidad, Sala, Empleado; suite 09 | Parcial | Encargado en Localidad y FK NOT NULL | Verificar casos positivos y negativos de ambas referencias | P1 | — |
| RN-04 parcela/cepa/campaña | 2 | Parcela, Lote; suite 09 | Parcial | PK compuesta, cepa obligatoria y UNIQUE parcela/campaña | Reejecutar | P1 | — |
| RN-05 composición 100 % | 2 | Funciones y constraint triggers | Parcial | Suma diferida y bloqueo de Vino al editar composición | Probar sin composición, suma menor/mayor, reemplazo y concurrencia | P0 | Molina: pruebas RN-05 |
| RN-06 descuentos e ISA | 2 | Cliente/subtipos; SQL 04–05 | Parcial | Base 10/20/30, excepción U6 35, validación total/disjunta | Casos de cliente sin subtipo, subtipo incorrecto y tasa no elegible | P0 | No copiar U1 externos |
| RN-07 permisos | 2 | Permiso; suite 09 | Parcial | FK a exportador y vencimiento > emisión | Reejecutar | P1 | — |
| RN-08 total e historia U1/U6 | 2/5 | Cabecera/detalle, recálculos, suite 09 | Parcial | Fórmula e historia correctas en camino normal; escritura directa de total no protegida para todo escritor | Resolver H3 y reforzar prueba histórica con venta no vacía | P0 | Evitar UPDATE de referencias |
| RN-09 stock de venta | 2 | Trigger venta y CHECK de stock | Parcial | Débito condicional atómico; UPDATE/DELETE restituyen cantidad anterior | Probar rechazo sin stock y carrera con dos sesiones | P0 | Molina: evidencia concurrente |
| RN-10 ingresos | 2 | Procedimiento, estados e impacto | Parcial | Transición terminado→procesado y aplicación una vez | Probar atomicidad y proteger cabecera procesada | P0 | — |
| RN-11 transferencias | 2 | Procedimiento, estados/fecha/impacto | Parcial | Fecha fijada/inmutable y débito/crédito por transición | Resolver cabecera mutable; probar falta de stock en segundo vino | P0 | — |
| RN-12 detalles fuera de confección | 2 | `tg_validar_lineas_documento` | Parcial | INSERT/UPDATE/DELETE controlados; borrado por cascada permite padre ausente | Resolver política D5 sin desactivar controles; probar cascadas válidas | P0 | Molina: matriz de rechazos |
| RN-13 auditoría | 2 | Trigger precio y tabla | Parcial | Solo cambio efectivo, anterior/nuevo y session_user | Probar con login API; generar evento real para llenar auditoría | P1 | — |
| RN-14 movimientos asociados | 2 | FK RESTRICT | Parcial | Vino/Bodega/Transportista protegidos por FK | Separar RN-14 de conservación adicional; resolver D1/D5 | P0 | Consigna p. 6 |
| RN-15 cantidades/superficies/kg/precios/graduación | 2 | CHECK en tablas | Parcial | Positividad y graduación 5–20 declaradas | Reejecutar límites; no añadir rangos físicos no pedidos sin justificación | P1 | — |
| Tres vistas | 2 | SQL 07 | Parcial | Tres SELECT definidos, stock preagregado evita multiplicación por salas | Verificar resultados, ventas sin actividad y permisos | P1 | — |
| Tres roles y privilegios mínimos | 2 | SQL 03 y grants finales | Parcial | API sin DML directo de stocks/auditoría ni UPDATE total | Probar propiedad, membresías, reportes y mínimo de tablas de API | P0 | Molina: pruebas de permisos |
| Prueba por RN y concurrencia con/sin bloqueo | 2 | Suites 08–09, relato README | Parcial | Hay casos RN, pero faltan escenarios y script/log de dos sesiones | Guardar ejecución, aislamiento y capturas; contraprueba en laboratorio | P0 | Molina: runner/sesiones |
| Todas las tablas ≥1; tres >10.000; una >100.000 | 3 | Sin dataset persistente | Pendiente | Fixtures terminan con ROLLBACK y no son carga | Dataset y reporte de conteos verificables | P1 | Grupo 28: controles |
| CSV reales, Python/psycopg/Faker, semilla, coherencia | 3 | No existe generador | Pendiente | Sin CSV ni dependencias de carga | Generador compacto con fecha de referencia y triggers activos inicialmente | P1 | Lucas: carga compacta; Grupo 28: fecha/hash |
| Comparar fila/lotes, controles y dump | 3 | Ausente | Pendiente | Sin tiempos, controles de dataset ni volcado PostgreSQL | Medir con mismos datos, validar y documentar dump/restauración | P1 | Grupo 28: métodos de carga |
| ≥5 índices: compuesto, parcial, FK y variante (p. 14–15) | 4 | SQL 06 | Parcial | 23, compuestos y FK; ninguno parcial ni expresión/BRIN/INCLUDE | Diseñar variante/parcial sobre consultas reales; evaluar reemplazos | P2 | Molina: parcial; Grupo 28: INCLUDE |
| ≥3 mejoras medidas, planes completos, descarte y escritura | 4 | Ausente | Pendiente | Ninguna medición local conservada | Baseline solo PK/UNIQUE, ANALYZE, mismos datos; registrar casos sin mejora | P2 | Informes externos como formato |
| U1–U6, I1–I6, D1–D6, S1–S12 (30 códigos) | 5 | U1 rutina y parte de U6 en test | Parcial | No existe `consultas/` | Cuatro archivos comentados, parámetros reales, controles y ROLLBACK | P1 | Grupo 28: organización |
| D5 ingreso procesado >365 días | 2/5 | Trigger borrado y suite 09 | Bloqueado | Rechazo incondicional si estado ≠ confección | Decidir excepción de eliminación documental y su relación con RN-12 | P0 | Consigna §8.3 |
| API: endpoints, pool, SQL parametrizado, errores y ≥8 pruebas/≥3 negativas | 6 | Ausente | Pendiente | Roles no constituyen API | API mínima con módulo SQL propio, transacciones y OpenAPI | P2 | Lucas: pool y transacción, sin cálculos Python |
| Cinco pantallas, gráfico y errores de DB | 7 | Ausente | Pendiente | Ningún frontend en proyecto | HTML/CSS/JS consumiendo API | P2 | Lucas: estructura front |
| Compose, secretos, HTTPS, DB cifrada/restringida, backup restaurado | 6–8 | Ausente | Pendiente | Sin Compose/.env.example/URL/evidencia de restauración | Primero entorno local; luego comparar dos proveedores y pedir autorización de recursos | P2 | Compose como referencia conceptual |
| README, informe, Git colectivo y defensa | 9 | README raíz mínimo; docs parciales | Parcial | Solo un commit inicial; SQL/docs figuran sin seguimiento en git status | Completar README y evidencia; integrar trabajo por autores reales | P1 | No fabricar autoría/historial |

## 5. Hallazgos que deben resolverse antes de la carga

**H1 — RN-14 está ampliada más allá de la consigna (P0).** El texto explícito prohíbe borrar Transportista, Bodega y Vino con movimientos asociados. No prohíbe por sí mismo borrar todo documento procesado. `tg_proteger_estado_documento` sí lo hace; la suite 09 espera ese rechazo y `validacion_tpi.md` lo atribuye a RN-14. D5 exige borrar ingresos procesados con más de 365 días. No se puede considerar cumplido D5 mostrando solamente un error esperado. RN-12 añade otro conflicto: prohíbe quitar sus renglones fuera de confección, mientras D5 supone eliminarlos junto con el documento.

Requisito: satisfacer D5 sin alterar saldos ya aplicados. Interpretación propuesta: distinguir eliminación documental de reversión operativa; una purga histórica autorizada no resta stock otra vez. Debe confirmarse con el docente cómo conciliarla con RN-12. No cambiar silenciosamente el trigger ni usar profundidad de triggers o variables manipulables. La excepción, si se aprueba, debe ser específica, transaccional y probada; no una apertura general del borrado.

**H2 — Cabeceras de movimientos procesados modificables (P0, defecto por lectura).** El trigger de estados protege fecha de transferencia y transiciones, pero no bloquea el resto de atributos. El rol API tiene UPDATE sobre Ingreso y Transferencia completos. Tras procesar una transferencia hacia sala A, `UPDATE transferencia SET id_sala = B` pasa la lógica del trigger sin trasladar el stock acreditado a A: el historial queda atribuido a otra sala. También pueden cambiarse fecha, bodega o transportista de un ingreso procesado si las FK lo permiten. Propuesta: hacer inmutables los atributos operativos de documentos cerrados; definir qué se puede corregir en confección. Añadir una regresión que intente cambiar sala tras procesar y compruebe rechazo y saldos intactos. No hace falta agregar tablas.

**H3 — Total protegido por permisos solo en el rol API (P0, defecto por lectura).** `tg_proteger_comprobante` fuerza cero en INSERT, pero en UPDATE únicamente impide cambiar cliente, sala y descuento histórico. El rol `bodegas_propietario` recibe UPDATE de tabla completo. Puede ejecutar `UPDATE comprobante SET total = -1` o cualquier total distinto del detalle; no hay CHECK de total ni recálculo en esa ruta. El SQL normal de detalles sí mantiene el agregado, y el rol API no puede escribirlo directamente. La obligación RN-08 requiere explicitar el alcance y cerrar esta ruta para escritores ordinarios, conservando U1. No intentar proteger contra un superusuario capaz de desactivar triggers. Evaluar recalcular el valor en el camino de UPDATE o restringir columnas a los roles pertinentes, con una prueba del mecanismo elegido, sin GUC de bypass ni recursión dependiente de profundidad.

**H4 — D1 puede destruir historia y crear stock disponible (P0, decisión pendiente).** La FK de comprobantes es RESTRICT y no hay trigger actual que elimine sus detalles automáticamente. El camino permitido es borrar detalles, que reintegran stock, y después cabecera. D1 pide borrar comprobantes de socios de más de cinco años: aplicarlo así devuelve al inventario actual botellas vendidas hace años. El borrado de una venta y una purga histórica tienen efectos distintos. Confirmar qué espera la cátedra antes de implementar D1; conservar el comportamiento operativo aprobado hasta documentar una decisión. No cambiar RESTRICT por CASCADE: el trigger de detalle necesita consultar la cabecera para localizar la sala.

**H5 — Comentarios y pruebas no respaldan todo lo afirmado (P1).** La tabla RN-14 de `database/README.md` todavía dice que un trigger de borrado elimina detalles; `05_triggers.sql` elimina precisamente ese trigger y la explicación anterior del mismo README dice RESTRICT. También dice «dos tablas de subtipos», pero hay tres. El caso final de U1 en suite 09 comprueba un comprobante ya vacío, por lo que no demuestra el resultado monetario de una venta no vacía después de U6. Hay casos insuficientes para ISA inválida, falta de stock al procesar una transferencia y rollback de un procesamiento multirrenglón. Agregar casos al archivo existente y guardar salidas; no reescribir pruebas válidas. Las GUC en suite 09 son ataques deliberados para demostrar que no evaden controles, no mecanismos productivos: se deben conservar como pruebas negativas.

**H6 — Atributos obligatorios y dominios incompletos (P1).** Cliente permite `nombre` y `apellido` ambos NULL, aunque el escenario exige nombre o razón social. Proponer una restricción de identidad mínima que cubra los tres subtipos sin exigir apellido a una empresa. `vino.tipo` es texto libre: revisar un CHECK de tipos del catálogo requerido; no añadir una tabla número 30 solo para ello. No imponer automáticamente los rangos de añada/presentación del ejemplo del anexo: son orientativos y deben justificarse.

**H7 — Roles, propiedad y contexto de funciones (P0/P1).** `bodegas_propietario` tiene privilegios de tablas y CREATE del esquema, pero eso no lo vuelve propietario de objetos creados por el instalador. Es importante para reaplicar scripts, ALTER/DROP y despliegue. Establecer quién instala y quién posee los objetos; distinguir provisión administrativa de roles de migraciones habituales. Probar membresías reales, permisos de reportes y SECURITY DEFINER con dueño controlado. Las funciones SQL `fn_stock_sala` y `fn_descuento_tipo` no fijan search_path; verificar invocación con contexto real de API y fijarlo donde corresponda. No duplicar roles ni añadir contraseñas al SQL. El alcance actual de SELECT/INSERT/DELETE de API sobre todas las tablas debe revisarse al conocer sus endpoints; reportes hoy lee vistas y stocks/auditoría, no todas las tablas base, lo que puede ser suficiente si se documenta.

**H8 — Índices suficientes en número, incompletos en variedad/evidencia (P2).** No hay base para retirar los 23 por no tener mediciones ni para afirmar que aceleran consultas. Un candidato parcial es transferencias pendientes por sala/fecha; uno cubriente podría atender ventas por fecha. Evaluar sustituciones de índices existentes, no agregar duplicados para completar una lista. Las FK con prefijo ya cubierto por PK/UNIQUE no necesitan otro índice idéntico.

Otras recomendaciones, no requisitos adicionales: verificar correspondencia de bodega del ingreso con vinos de sus detalles y si documentos vacíos pueden terminarse/procesarse. El código actual los permite; no se presenta como incumplimiento de una RN que no lo explicita. Tampoco se exige que una localidad tenga al menos una sala solo por una frase del escenario sin acordar el alcance.

## 6. Consultas: alcance confirmado y precauciones

La sección 8 exige 30 códigos; S11 y S12 contienen dos resultados cada uno. No hay soluciones entregadas en `consultas/`. Esta tabla es planificación, no implementación ni resultado de ejecución.

| Códigos | Alcance y criterio de implementación propio |
|---|---|
| U1 | Invocar recálculo con `comprobante.descuento_aplicado`; dejar texto literal y discrepancia de interpretación documentados. |
| U2 | Salario +20 % con antigüedad estrictamente mayor a cinco años; probar el límite exacto. |
| U3 | Precio +13 % por bodega del dataset; auditoría debe registrar cada cambio. |
| U4 | Intercambiar lunes/miércoles con un CASE en una sentencia y vocabulario consistente. |
| U5 | Precio −15 % a diez vinos menos vendidos, incluir cero ventas y desempatar por código. |
| U6 | Actualizar Cliente al 35 % para exportadores con más de tres permisos; no comprobantes anteriores. |
| I1 | Cobertura de General Alvear para transportista con menos ingresos del último trimestre; considerar cero y empates, evitar par duplicado. |
| I2 | Crear «cordero al disco» solo si hay tintos ≥14°, y asociar todos los que cumplen en la misma transacción. |
| I3 | Venta completa de tres renglones en sala ID 1; dataset debe garantizar cliente, vinos y stock; usar funciones de cálculo. |
| I4–I5 | Nueva bodega y sala con claves válidas del esquema; no suponer identidades automáticas inexistentes. |
| I6 | Ingreso en confección de 120 botellas con vino/bodega/transportista reales; no incrementar stock antes de procesar. |
| D1 | Comprobantes de socios de más de cinco años: resolver H4 antes de escribir la sentencia final. |
| D2 | Cepas sin composición ni parcela mediante NOT EXISTS para ambas relaciones. |
| D3 | Empleados con menos de dos años en sala de una localidad concreta; no borrar la sala implícitamente. |
| D4 | Socios sin compras, alta de más de cinco años; borrar supertipo respetando ISA y CASCADE de subtipo. |
| D5 | Ingresos procesados >365 días: bloqueado por H1; no resolver desactivando triggers. |
| D6 | Socios sin compras de localidad elegida; comprobar ausencia de comprobantes antes del borrado. |
| S1 | Top diez por SUM de botellas, no por cantidad de renglones. |
| S2 | Vinos vendidos en todas las salas: división relacional; definir universo de salas y comportamiento vacío. |
| S3 | Clientes distintos por tipo que compraron en sala durante última semana. |
| S4 | Top cinco salas por cantidad de un vino solicitada en transferencias de últimos quince días. |
| S5 | Salas con menor cantidad de transferencias pendientes; incluir salas con cero y empates. |
| S6 | Sin stock en sala, incluido saldo ausente, con depósito positivo. |
| S7 | Transportista de mayor actividad del último mes; actividad se mide con ingresos, donde existe la FK. |
| S8 | SUM(total) por sala en último trimestre, orden descendente. |
| S9 | Ficha con composición, bodega, maridajes y stock; preagregar asociaciones para no multiplicar cantidades. Usar vista. |
| S10 | Kg/ha por parcela y campaña; CTE y subconsulta correlacionada para promedio de finca comparable por campaña. |
| S11 | RANK por vino dentro de sala y ventas mensuales acumuladas; agregar por mes antes de ventana. |
| S12 | Doble NOT EXISTS para todos los vinos de bodega y anti-join para nunca haber comprado tinto. |

Todas las modificaciones llevarán BEGIN, controles antes/después, conteo real y ROLLBACK. Las consultas relativas usan CURRENT_DATE; «último trimestre» puede significar tres meses móviles o trimestre calendario anterior: fijar criterio docente consistente para I1/S8. Documentar empates y conjuntos vacíos donde afecten resultados. No usar una razón social como si fuera UNIQUE si el modelo no la declara así.

## 7. Plan mínimo para las etapas restantes

**Carga, fase C.** Un generador Python con psycopg, Faker y random; semilla y `--fecha-ref` explícitas, versiones de dependencias fijadas. La semilla sola no estabiliza CURRENT_DATE, identidades de auditoría ni hora/usuario de triggers: comparar datos de negocio y documentar qué metadatos varían, con base limpia en cada ejecución. CSV reales de cepas, maridajes, localidades/departamentos y tipos; no transformar cada archivo de catálogo en tabla si no existe en el modelo.

Orden propuesto: catálogos/geografía/bodegas/transportistas → salas/empleados/fincas/parcelas/lotes/análisis → vinos y composición/maridajes → clientes y subtipos/permisos → ingresos con detalles y procesamiento → transferencias con detalles y procesamiento → comprobantes y detalles. Vino crea su stock central en cero automáticamente: no duplicar esa fila. Generar al menos un cambio de precio real para poblar auditoría. Vinos/composición y Cliente/subtipo se confirman juntos para satisfacer diferidos.

Objetivo compacto: 20.000 clientes, más de 100.000 comprobantes y más de 100.000 renglones cubren tres tablas >10.000 y una >100.000; las cifras recomendadas de la consigna son 150.000 comprobantes/500.000 renglones y no deben confundirse con mínimos. Todas las otras tablas tendrán al menos una fila. Asegurar sala 1, General Alvear, tres vinos vendibles, exportadores elegibles/no elegibles, socios sin compras, fechas históricas y datos recientes para las consultas. Evitar que las pruebas no afecten filas por falta de casos.

Empezar con triggers activos, lotes acotados y aprovisionamiento antes de ventas. La fecha de transferencia forzada a CURRENT_DATE impide simular historia antigua mediante INSERT ordinario; diseñar las transferencias recientes requeridas por S4 y documentar esa limitación. Si fuera indispensable cargar historia de transferencias, resolverla como decisión de carga específica con controles finales, sin relajar silenciosamente RN-11. Medir fila/lotes con el mismo subconjunto y estado inicial. Un `COPY` por sí solo no elimina el costo de triggers ni de recalcular totales; elegirlo por medición. Controles: conteos de las 29 tablas, huérfanos, composición, ISA, totales históricos, estados, saldos y conciliación de ingresos/transferencias/ventas con política de purgas acordada. Producir dump e instrucciones de restauración.

**Consultas y rendimiento, fases D/E.** Primero disponer de consultas correctas, luego medir al menos tres candidatas (por ejemplo S3, S4, S8). En base de benchmark descartable usar los mismos datos: baseline con PK/UNIQUE sin índices de `06`; ANALYZE; planes completos EXPLAIN (ANALYZE, BUFFERS); agregar candidatos y repetir. Registrar versión, conteos, parámetros, varias corridas, caché, tiempos, buffers, tamaños y costo de escritura. El criterio de aceptación pide mejora real en tres consultas, además de medirlas: si no ocurre, revisar candidatos, no inventar mejoras ni forzar planes para simular éxito. Guardar también índice descartado y caso en que el planificador ignora un índice. S9–S12 requieren sus planes aunque no sean los tres casos optimizados.

**API, fase F.** Propuesta de menor estructura razonable: FastAPI, un driver psycopg con pool y servidor ASGI; `main.py` para rutas/errores y `db.py` para pool/SQL parametrizado. Sin ORM ni servicios/repositorios por entidad si dos módulos alcanzan. OpenAPI viene del framework; pruebas con cliente HTTP. Confirmar versiones al implementar. Las transacciones deben incluir el commit y su posible error de constraints diferidas antes de devolver éxito.

Endpoints obligatorios (consigna pp. 16–17): catálogo/detalle y POST/PUT/DELETE de vinos; GET/POST/PUT/DELETE de clientes; POST de comprobantes y GET por número; alta, renglones, terminar y procesar transferencias; alta, renglones y procesar ingresos; `/salud`; reportes top-vinos, ventas-por-sala, vinos-sin-stock, transportista-activo y trazabilidad por código. Los listados requieren filtros/paginación. La tabla omite ruta de terminar ingresos aunque describe el mismo circuito y el procedimiento exige terminado: confirmar contrato o agregar una transición mínima documentada, sin saltar estados. Mapear SQLSTATE centralmente; stock insuficiente debe devolver 409 según aceptación aunque hoy se emita como 23514, cuyo mapeo genérico sugerido es 422. Al menos ocho pruebas, tres negativas de reglas; probar inyección SQL fallida. Conexión con cuenta miembro de `bodegas_api`, no con dueño/superusuario. Importes, descuentos y stocks se consultan a PostgreSQL.

**Frontend, fase G.** HTML/CSS/JS sin framework de build inicialmente; una capa de llamadas y cinco pantallas: catálogo/detalle paginado y filtrado, alta/edición con composición, venta, transferencias y tablero. El tablero incluye gráfico de ventas trimestrales por sala. Mostrar errores de la API, total confirmado por DB y estados reales. No agregar autenticación compleja ni cálculos de negocio en JS.

**Despliegue/defensa, fase H.** Compose mínimo de DB/API/front, o DB/API sirviendo también archivos estáticos si satisface la entrega; un comando desde máquina limpia, volumen y healthcheck. `.env.example` sin secretos y `.gitignore`. Comparar dos proveedores con condiciones vigentes cuando toque desplegar, sin crear ahora servicios ni recursos pagos. HTTPS público, conexión PostgreSQL cifrada y restringida, roles reales, migraciones ordenadas, backup restaurado en base nueva con conteos y prueba de trigger en nube. La consigna acepta reducir nube a ≥10.000 filas en una tabla por límites del plan, justificándolo y manteniendo carga local completa. Demo de 10–15 minutos con venta válida/inválida, transferencia y plan; cada integrante defiende todo el modelo.

## 8. Estructura final mínima propuesta

Los nombres `db/migrations/` de la consigna son una estructura sugerida (§10.1). Mantener `database/` evita mudanzas y duplicación; confirmar solo si la cátedra automatiza rutas. `03_restricciones.sql` contiene principalmente roles, mientras constraints están en `02`; documentar esa distribución antes que copiar el DDL a otros archivos para igualar nombres.

```text
README.md
.gitignore
.env.example
docker-compose.yml
database/
  01_tipos_dominios.sql ... 09_pruebas_reglas_negocio.sql
  README.md
  seed/
    csv/
    cargar.py
    requirements.txt
    controles.sql
    README.md
  benchmark/
    medir.sql
    resultados/                 # planes y salidas reales
consultas/
  update.sql
  insert.sql
  delete.sql
  select.sql
api/
  main.py
  db.py
  requirements.txt
  Dockerfile
  tests/
front/
  index.html
  app.js
  api.js
  styles.css
docs/
  consigna/                    # fuente local del TPI
  DER.drawio.xml               # original, sin rediseñarlo
  DER.pdf                      # exportación revisada
  modelo_relacional.dbml
  modelo_relacional.dbdiagram
  esquema_relacional.md
  normalizacion.md
  trazabilidad_der_relacional.md
  validacion_tpi.md
  auditoria_y_plan_finalizacion.md
  diccionario_datos.md
  informe_final.md              # enlaza evidencia parcial, evita repetir modelo
  evidencias/                  # SQL, carga, concurrencia, API, restauración
```

Agregar archivos por fase cuando tengan contenido, sin crear esqueletos vacíos ahora. Los informes de carga, rendimiento y despliegue pueden ser secciones de `informe_final.md` con enlaces a salidas, no informes repetidos. Un README raíz explica la ejecución completa y enlaza al README de DB; no copia su detalle.

Redundancias verificadas: `database.zip` incluye exactamente los mismos bytes que los archivos actuales que empaqueta, y no contiene la consigna ni el DER. No es un `pg_dump` ni evidencia de backup/restauración de PostgreSQL. Evitar mantenerlo como segunda fuente de código; decidir su exclusión en otra fase. `dbml-error.log` está vacío y no demuestra validación. `basico.py` dibuja un girasol con turtle y no pertenece al TPI; proponer retirarlo de la entrega, sin borrarlo durante esta auditoría. `.dbdiagram` sí es útil para el diseño visual y no debe eliminarse por parecer duplicado del DBML. No se identifican funciones correctas que deban suprimirse solo por cantidad de líneas.

## 9. Próxima fase concreta y decisiones docentes

**Fase B: cerrar integridad y evidencia del SQL existente.** Orden mínimo:

1. Acordar D1/D5 frente a purga histórica, reintegro de stock y RN-12; mantener esas consultas bloqueadas hasta resolverlo. RN-14 no implica conservar todos los documentos para siempre.
2. Corregir cabeceras cerradas, escritura de totales e identidad de Cliente; revisar roles/propiedad/contexto de funciones. Conservar las 29 tablas y el DER.
3. Ampliar suites existentes: comprobante no vacío conserva tasa/total tras U6 y U1; ISA inválida; insuficiencia de stock y rollback de transferencia multirrenglón; modificación de sala procesada; borrados aprobados con saldos esperados; permisos reales.
4. Instalar 01–07 en base limpia con versión identificada y ejecutar 08/09 como administrador y casos pertinentes con rol API/reportes. Guardar comandos, salidas y conteos de catálogo. Demostrar concurrencia con dos sesiones y aislamiento documentado.
5. Corregir las contradicciones del README/trazabilidad y completar diccionario. Incorporar fuentes y exportación al repo. Solo entonces iniciar fase C.

Criterio de cierre: ninguna inconsistencia reproducida sin resolver; política D1/D5 escrita; pruebas positivas y negativas relevantes con salidas; instalación reproducible y roles comprobados. Si una definición docente tarda, se pueden corregir los defectos independientes de esa respuesta, sin cambiar por cuenta propia la política histórica.

Confirmaciones para el docente, separadas de las decisiones internas ya aprobadas:

- U1: se mantiene la interpretación histórica aprobada; confirmar compatibilidad con la frase «descuento que corresponde al tipo». No se reabre esa decisión interna ni se adopta la tasa vigente.
- D1: ¿purga documental o anulación con devolución de stock? ¿Cómo conservar saldos al eliminar una venta antigua?
- D5/RN-12: ¿se autoriza eliminación conjunta de ingreso procesado antiguo y sus detalles sin revertir su impacto? La prohibición actual es más amplia que RN-14.
- Ingresos API: precisar transición a terminado que la tabla de endpoints omite; confirmar códigos HTTP esperados para stock frente al 422 genérico de CHECK.
- Períodos: trimestre móvil/calendario y tratamiento de empates/universos vacíos cuando cambien el resultado.
- Presentación: confirmar equivalencia de `database/` con rutas sugeridas si existe corrección automatizada. La organización del equipo y fecha final se acuerdan con cátedra; no se importan excepciones de otros grupos.

No requieren confirmación para iniciar trabajo posterior autorizado: conservar modelo/3FN, no copiar código, completar diccionario, usar SQL parametrizado y reforzar pruebas de defectos. Esta ejecución finaliza con la auditoría; los cambios funcionales quedan para la fase siguiente.

## 10. Cierre de fase B

Se conservaron el DER conceptual, las 29 relaciones y la 3FN. No se cambió
ninguna FK ni regla de DELETE, ni se implementaron purgas, carga masiva,
consultas de etapa 5, API, frontend o despliegue.

| Hallazgo | Estado después de fase B | Solución y evidencia |
|---|---|---|
| H2 | Corregido | El trigger existente de estados rechaza cualquier cambio efectivo de una cabecera procesada. Pruebas de todos los campos de Ingreso/Transferencia y sala mediante API; saldos intactos. |
| H3 | Corregido para DML autorizado | El trigger existente de comprobante usa la función de total histórico y rechaza un importe distinto del detalle. Se probaron INSERT, UPDATE, DELETE y U1 con los roles API/propietario. No se promete impedir DDL deliberado del dueño. |
| H6, identidad | Corregido | CHECK exige nombre o razón social en `cliente.nombre`; no obliga a apellido de empresas. Rechaza NULL, vacío y espacios. No se agregan dominios redundantes ni tablas de catálogo. |
| H7 | Corregidos defectos verificados | Propiedad real al terminar instalación, search_path de funciones dependientes de esquema y defaults de EXECUTE. Catálogo confirma dueño de esquema, relaciones/índices/secuencias, tipos y rutinas. SET ROLE comprueba permisos reales. |
| H5 | Corregido en lo afectado | README dice tres subtipos y RN-14 refleja el texto original; se añade prueba de venta histórica no vacía, ISA, insuficiencia y atomicidad. La concurrencia multisesión sigue siendo un entregable pendiente. |
| H1/H4 | Pendientes de decisión docente | Se conserva el rechazo de borrados actual y el reintegro al eliminar detalles de venta. No se añadió excepción de purga. |
| H8 | Pendiente, etapa 4 | Ningún índice añadido/retirado sin datos y mediciones. |

No se cambió el dominio de CUIT: ya controla longitud/formato. Un catálogo de
tipos de vino y sus validaciones se revisará con los CSV de carga; no se impuso
un rango tomado del ejemplo del anexo como si fuera una nueva RN.

### Alternativas D1/D5: decisión pendiente, sin implementación

RN-14 protege Transportista/Bodega/Vino referenciados; no define retención
universal de documentos. RN-12 prohíbe modificar detalles fuera de confección.
D1 exige borrar comprobantes de socios de más de cinco años y D5 ingresos
procesados de más de 365 días. Debe acordarse si borrar el documento completo
es una excepción documental a RN-12 y qué historia debe conservarse.

| Alternativa técnica | Consecuencia en inventario e historial | Costo de diseño / aprobación |
|---|---|---|
| Conservar la política actual | Una eliminación operativa de detalles de venta devuelve botellas; documentos procesados permanecen. No satisface D5 y no sirve como purga D1 sin cambiar inventario. | Ningún cambio; solo válida como solución final si el docente redefine o exceptúa D1/D5. |
| Purga explícita y transaccional, sin tablas nuevas | D1 puede conservar los triggers: identificar y bloquear comprobantes/saldos, borrar detalles con su reintegro normal, compensar exactamente ese reintegro en la misma transacción y borrar cabeceras. El inventario final debe ser idéntico al inicial; cualquier fallo revierte todo. D5 requiere autorizar de forma acotada el DELETE de cabeceras procesadas antiguas; la cascada elimina detalles sin volver a aplicar stock. Se pierde el historial eliminado, por lo que la conciliación posterior necesita un corte documentado o respaldo. | Menor impacto en las 29 relaciones. La compensación agrega operaciones, pero evita flags de bypass. Requiere autorización docente y diseño de permisos, bloqueos y pruebas antes de implementarla; no habilitar DELETE general de procesados. |
| Archivar antes de purgar | Conserva respaldo consultable del historial y luego aplica una purga que mantiene saldos. Un backup externo no duplica tablas del modelo; debe probarse su restauración y documentar el corte. | Más operación; nuevas tablas de archivo alterarían el diseño y requerirían autorización. No es necesario introducirlas ahora. |

La alternativa de menor impacto estructural es una operación de purga explícita
con inventario final inalterado y elegibilidad comprobada. No se recomienda
detectar una purga mediante `pg_trigger_depth()`, GUC, deshabilitación de triggers
o una llamada no autorizada. Tampoco cambiar a CASCADE el comprobante sin revisar
el trigger que necesita la cabecera para identificar la sala. La excepción D5
no está autorizada por esta fase y no se aplica.

### Pruebas y entrega

La evidencia se conserva en [fase_b_postgresql.log](evidencias/fase_b_postgresql.log):
instalación administrativa desde cero `01`–`07`, reaplicación `02`–`07` con
SET ROLE propietario, suites `08` y `09`, y catálogo final. Se utiliza un clúster
local descartable independiente de las bases existentes. La versión exacta y
salidas de cada paso constan en el archivo. Las suites revierten fixtures y la
función transaccional de prueba de ACL, que no queda instalada.

Además del rol administrador que instala, las pruebas cambian efectivamente a
API, propietario y reportes. Verifican funciones con search_path ajeno, denegación
de escritura directa de stocks/auditoría/total y CREATE de API, lectura de las
tres vistas y denegación de procesamiento a reportes. Prueban ambos CALL con API,
rollback al fallar el segundo vino de una transferencia y venta sin existencias.
U6 cambia el descuento vigente y U1 mantiene 140 para una venta de 200 al 30 %;
una venta posterior al 35 % da 130. Los fixtures verifican también que la empresa
no necesita apellido.

Componentes productivos añadidos: **un CHECK y cero tablas, funciones, triggers,
vistas, índices o roles**. Componentes productivos eliminados: **cero**. Se
modificaron dos funciones SQL para fijar contexto, dos funciones de trigger y
la configuración de instalación/propiedad/permisos. Las pruebas crecen dentro
de las suites existentes; el único archivo adicional es el log de evidencia.

La base corregida permite preparar la carga con los controles activos, sin
purgas. No se declara cerrada toda la etapa 2 ni lista una carga histórica
definitiva: siguen pendientes D1/D5, demostración de concurrencia con evidencia,
diccionario completo y política de fechas históricas de transferencias. No se
ejecutó carga masiva. La próxima tarea es acordar D1/D5 y completar esos
entregables, conservando mientras tanto los controles actuales.

## 11. Cierre de fase B.2

**Decisión aprobada:** D1 y D5 eliminan documentación histórica sin modificar
existencias actuales. Se contrastaron D1, D5 y RN-08–RN-14 con la consigna local:
el enunciado exige los borrados, pero no especifica revertir inventario. RN-14
restringe maestros con movimientos; RN-12 prohíbe el DML operativo sobre detalles
cerrados. Se documenta D5 como excepción de eliminación documental completa,
sin afirmar que la cátedra haya aprobado esa interpretación.

H1/H4 quedan **implementados y probados**. D1 usa DELETE de cabecera elegible y
CASCADE sobre su FK de detalle; el trigger existente valida antigüedad y Socio.
La cascada encuentra la cabecera ausente y no reintegra stock. Borrar directamente
un detalle con cabecera presente sigue devolviendo botellas. D5 habilita únicamente
el borrado de ingresos procesados de más de 365 días; no dispara impacto de stock
y su cascada elimina detalles. Los documentos terminados, transferencias procesadas
y documentos procesados recientes conservan su protección. Los filtros D1/D5 no
seleccionan documentos ajenos, aunque las cabeceras vacías y los ingresos en
confección mantengan su eliminación ordinaria independiente.

Se modificaron `02_tablas.sql`, tres funciones de trigger y un evento del trigger
de comprobante en `05_triggers.sql`, y la suite `09`. No se añadieron funciones,
procedimientos, triggers, tablas ni roles. Las 29 relaciones, PK, 35 FK y 3FN se
conservan; solo cambia a CASCADE la acción DELETE de una FK, reflejada también en
el DBML. Los RESTRICT de Vino/Bodega/Transportista permanecen. No se usa una señal
de sesión, profundidad de trigger ni desactivación de controles para autorizar.

Para no reconstruir instalaciones previas se entrega `database/migracion_b2.sql`:
la FK y los triggers se actualizan atómicamente con bloqueo de las tablas afectadas.
`consultas/delete.sql` contiene solo D1/D5, con controles y ROLLBACK; las otras
28 consignas quedan fuera del alcance. La explicación operativa está centralizada
en [database/README.md](../database/README.md#eliminación-histórica-d1d5--política-aprobada-en-b2).

**Evidencia real:** [fase_b2_postgresql.log](evidencias/fase_b2_postgresql.log).
En PostgreSQL 18.4 pasaron `08` y `09` en una instalación nueva y en otra migrada
desde los archivos previos de fase B. La suite elimina un comprobante D1 y un
ingreso D5, verifica límites de cinco años/365 días y exclusión de otros tipos
y estados, compara ambas tablas completas de stock y prueba rollback de cabeceras
y detalles ante un fallo posterior. También comprueba que una GUC no evade controles,
que el DELETE ordinario reintegra una botella y que RN-14 sigue rechazando maestros.
El archivo de consultas se ejecutó con documentos elegibles y se verificó su ROLLBACK.

Dos sesiones READ COMMITTED intentaron D1 sobre la misma cabecera y luego D5 sobre
el mismo ingreso: A borró uno y B cero en cada caso; sala=15 y depósito=80 permanecieron
intactos después de los COMMIT. Esa prueba valida carreras de purga, no reemplaza
la demostración académica de la última botella con/sin bloqueo que sigue pendiente.
La suite mantiene casos de RN-01–RN-15, U1/U6 y permisos; RN-12 ahora incluye la
excepción documental explicada, sin abrir DML directo sobre detalles procesados.

Limitación: una purga definitiva pierde los documentos y sus resultados históricos.
La conciliación de saldos exige un corte o respaldo de historia previa; no se
puede reconstruir stock actual sumando solo documentos supervivientes. Pendientes:
diccionario completo, demostración académica concurrente de ventas, política de
fechas para carga histórica de transferencias, carga y etapas posteriores. H1/H4
ya no bloquean la carga; no se generaron datos masivos en esta ejecución.

## 12. Cierre de fase C

Etapa 3 implementada en [`database/seed/`](../database/seed/README.md), con un
generador Python, cinco CSV reales de catálogo, validador SQL y dos dependencias
directas fijadas. No se modificaron las 29 tablas, el DER, los índices ni las
definiciones de reglas; U1/U6 y D1/D5 permanecen intactos. `.gitignore` excluye
entorno virtual, credenciales y datos locales generados.

Evidencia real: [fase_c_resultados.json](evidencias/fase_c_resultados.json).
Las dos cargas con semilla 42 y referencia 2026-11-09 produjeron 357.894 filas,
las 29 tablas pobladas, cuatro tablas >10.000 y dos >100.000. Coincidieron todas
las huellas lógicas; los 26 controles, las 35 FK, PK/UNIQUE y la conciliación
histórica/actual pasaron. Se comprobó el rechazo de base no identificada/no vacía
y el rollback de una importación fallida, incluida la reactivación del trigger.

Se resolvió la limitación de fechas mediante importación administrativa histórica
de solo 18 cabeceras de transferencia en confección, suspendiendo su trigger de
fecha/estado durante ese COPY bajo bloqueo y transacción. Se reactiva antes del
procesamiento normal; las demás restricciones y triggers de stock/detalle siguen
activos. RN-11 operativa se probó después y sigue vigente. La justificación, el
alcance de la huella (metadatos reales de auditoría excluidos) y los conteos por
tabla se centralizan en el README de carga, sin redefinir la regla del negocio.

La comparación real de 2.000 renglones midió INSERT por fila y COPY con triggers
activos y rollback de ambos casos. El dump comprimido se restauró en otra base
y se validaron las mismas 29 huellas. No se versiona el dump masivo ni el clúster.

Próxima fase: consultas SQL definitivas sobre el dataset cargado, seguida de
mediciones e índices de etapa 4 según el orden D/E acordado. Siguen pendientes
el diccionario y la demostración académica de concurrencia de ventas; las pruebas
de carga no los sustituyen. No se implementaron API, frontend ni despliegue.

## 13. Estado vigente tras fases D y E

| Componente | Estado comprobado | Evidencia vigente |
|---|---|---|
| Integridad B/B.2 | H1/H2/H3/H4 y defectos nominales/permisos H6/H7 corregidos; políticas históricas conservadas | Cierres B/B.2 y validación de carga |
| Carga de etapa 3 | Completa y reproducible en 29 tablas; dump restaurado | `database/seed/README.md` y `fase_c_resultados.json` |
| Consultas U1–S12 | 30/30 implementadas, reejecutadas y verificadas con rollback | [fase_d_consultas.json](evidencias/fase_d_consultas.json) |
| Índices/rendimiento, H8 | Etapa 4 completada; tres mejoras claras y resultados sin mejora declarados | [Informe único](informe_rendimiento_indices.md) y [planes/mediciones](evidencias/fase_e_indices.json) |
| Diccionario y demo académica de concurrencia | Pendientes como entregables de documentación/integridad | No se confunden con los benchmarks ni con carreras de purga ya probadas |
| API, frontend, despliegue | Pendientes, fuera de alcance E | Próximas fases F–H |

I1 conserva el mínimo global con desempate determinista: si ya existe cobertura,
la inserción idempotente no elige un transportista de mayor actividad. Se verificó
el caso de un mínimo único ya cubierto. I3 se corrigió únicamente en la consulta:
preserva tres pedidos con VALUES y LEFT JOIN de precios, de modo que un vino
faltante sea rechazado por los controles existentes. El SQL anterior podía
insertar solo dos renglones; se reprodujo el defecto y se probaron éxito, falta
de vino, falta de stock y rollback de cabecera/inventario. No cambiaron tablas,
funciones operativas, descuentos ni triggers para lograrlo.

Los índices definitivos conservan 21 originales y sustituyen dos prefijos;
se añade el parcial requerido. Hay 24 secundarios y 33 automáticos de PK/UNIQUE.
La comparación A/B usa las mismas 357.894 filas y configuración, con medianas de
siete ejecuciones y planes completos. D4 muestra por qué un índice de FK importa
también para el costo de integridad, aunque no figure en el plan principal.
No se atribuye una mejora al parcial de S5 ignorado en una tabla de 18 filas.
El costo observado de escritura y sus rangos solapados se explican en el informe,
sin presentar una penalización exacta como universal. BRIN fue medido y descartado.

La documentación inicial sigue siendo un historial de diagnóstico. Los pendientes
antiguos de carga, D1/D5 o falta de consultas no son tareas vigentes. Para decidir
el siguiente trabajo, corresponde avanzar con la API mínima y cerrar en paralelo
diccionario/demo académica; no rehacer el modelo ni repetir la carga/consultas.

## 14. Estado vigente tras fase F

La API REST está implementada en [`api/`](../api/README.md): FastAPI, psycopg 3,
pool de 1–5 conexiones, SQL parametrizado y transacciones confirmadas antes de
responder. Incluye 26 operaciones sobre 20 rutas de vinos, clientes,
comprobantes, transferencias, ingresos, reportes y salud, más OpenAPI/Swagger.
No incorpora ORM, frontend ni autenticación ajena al TPI.

Se reutilizan los dos procedimientos de procesamiento y los triggers existentes.
La composición y la ISA se validan en PostgreSQL al COMMIT; stock, descuento
histórico, precio, total y auditoría conservan su responsabilidad en la base.
La cuenta de conexión es un LOGIN miembro del rol API, sin propietario,
superusuario ni DML directo sobre stocks/auditoría/totales.

Única extensión de base indispensable: `10_api_baja_vino.sql` incorpora una
función SECURITY DEFINER para borrar un vino sin movimientos y su saldo inicial
de depósito cero, que antes impedía cualquier baja por FK. Las dependencias,
stock positivo y auditoría siguen bloqueando el DELETE con rollback completo.
No cambia las 29 tablas, RN-01–15, D1/D5, consultas ni índices aprobados.

La [evidencia F](evidencias/fase_f_resultados.json) registra las pruebas HTTP
reales contra una base descartable y el inicio de Uvicorn con cuenta API.
También se probaron la inyección SQL como texto, los rechazos de reglas de base,
permisos y recuperación de salud tras cortar conexiones.

Compose está escrito y su configuración validada. El arranque de contenedores
queda pendiente porque el motor Docker Desktop no estaba disponible; no se
declara cumplido ese criterio de ejecución de la consigna. Las pruebas locales
de API/PostgreSQL sí se ejecutaron. La fase G puede consumir la API; siguen
pendientes frontend, despliegue, diccionario y demostración académica de
concurrencia. Los diagnósticos y próximos pasos anteriores a este apartado son
históricos.

## 15. Estado vigente tras fase G

Se implementaron las cinco pantallas de Etapa 7 con HTML/CSS/JavaScript y Fetch,
sin framework ni dependencias en el navegador: catálogo, gestión de vinos,
venta, transferencias y reportes con gráfico. La guía de ejecución y los flujos
están en [frontend/README.md](../frontend/README.md).

Única extensión funcional de la API: `GET /catalogos`, consulta de salas, cepas
y bodegas para formularios. No se cambiaron tablas, índices, reglas, funciones,
triggers ni las consultas aprobadas. Los mensajes de la base llegan a pantalla;
el frontend no calcula importes, descuentos ni existencias.

Pasaron 22 pruebas de API y 14 de navegador, con Uvicorn, proxy local, rol API
y PostgreSQL reales. Se comprobaron escritorio/móvil, paginación de vinos y
clientes, alta/edición/baja, composición 80 % rechazada al COMMIT, stock
insuficiente con rollback, procesamiento de transferencias, reportes y caída
real de la API. [Resultados y límites](evidencias/fase_g_resultados.json).

Compose incluye frontend Nginx y dependencias con healthchecks. Su configuración
es válida, pero el motor Docker Desktop no estaba disponible: el arranque de
contenedores permanece sin verificar. Etapa 7 funciona localmente; fase H
(nube), diccionario y demostración académica de concurrencia siguen pendientes.
