# Documentación Técnica — Sistema de Entradas Concierto Acústico JORJVANA

> Documento técnico para desarrolladores. Describe la arquitectura, módulos,
> base de datos, API, seguridad, instalación, despliegue y mantenimiento del
> sistema de venta, validación y gestión de entradas del Concierto Acústico
> JORJVANA.

| Campo | Valor |
|-------|-------|
| Nombre del proyecto | `concierto-jorjvana` |
| Versión | 2.0 (estructura reorganizada) |
| Tipo | Aplicación web estática (frontend) + funciones serverless + BaaS |
| Stack | HTML/CSS/JavaScript vanilla · Supabase (PostgreSQL) · Vercel · Nodemailer |
| Idioma de la interfaz | Español |
| Repositorio | `Manrique94/concierto-jorjvana` |

---

## Tabla de contenidos

1. [Resumen general del sistema](#1-resumen-general-del-sistema)
2. [Arquitectura del proyecto](#2-arquitectura-del-proyecto)
3. [Estructura de carpetas y archivos](#3-estructura-de-carpetas-y-archivos)
4. [Explicación de cada módulo](#4-explicación-de-cada-módulo)
5. [Flujo de funcionamiento](#5-flujo-de-funcionamiento)
6. [Base de datos](#6-base-de-datos)
7. [API y funciones principales](#7-api-y-funciones-principales)
8. [Seguridad implementada](#8-seguridad-implementada)
9. [Proceso de instalación](#9-proceso-de-instalación)
10. [Proceso de despliegue](#10-proceso-de-despliegue)
11. [Mantenimiento y respaldo](#11-mantenimiento-y-respaldo)
12. [Anexos](#12-anexos)

---

## 1. Resumen general del sistema

El sistema es una **plataforma web para la venta, validación y gestión de
entradas** de un evento (el Concierto Acústico JORJVANA). Permite que un
asistente compre entradas pagando por Yape, que un administrador apruebe los
pagos y genere entradas con código QR, y que personal autorizado valide el
ingreso de los asistentes escaneando dichos QR en la puerta del evento.

### Capacidades principales

- **Compra de entradas sin necesidad de cuenta:** el comprador ingresa sus
  datos, reserva por 30 minutos, paga por Yape y sube su comprobante.
- **Reserva temporal con expiración:** cada reserva bloquea cupos durante 30
  minutos; si no se sube comprobante a tiempo, el cupo se libera
  automáticamente.
- **Aprobación manual de pagos:** el administrador revisa el comprobante y
  aprueba o rechaza. Al aprobar, el sistema genera automáticamente una entrada
  con QR único por cada unidad comprada.
- **Entrega de entradas:** por correo electrónico (con QR adjunto), por
  WhatsApp (enlace prellenado) y como PDF descargable con diseño de ticket.
- **Validación en puerta:** personal autorizado escanea el QR y el sistema
  determina si la entrada es válida, ya utilizada, anulada o inexistente,
  registrando el ingreso una sola vez.
- **Panel de administración:** estadísticas en tiempo real (vendidas,
  utilizadas, anuladas, recaudación, disponibles), gestión de aforo, gestión de
  validadores, tabla de compradores y tabla de ventas, exportación a Excel.

### Actores del sistema

| Actor | Descripción | Acceso |
|-------|-------------|--------|
| **Comprador** | Público general que compra entradas. | `index.html` (sin credenciales). |
| **Administrador** | Aprueba pagos, genera entradas, gestiona aforo y validadores. | `admin.html` (clave de admin validada en servidor). |
| **Validador** | Persona en la puerta que valida ingresos. | `validador.html` (código de acceso por validador). |

### Características no funcionales

- **Costo de operación bajo:** todo el frontend es estático (hosting gratuito en
  Vercel) y la base de datos usa el plan administrado de Supabase.
- **Sin backend propio que mantener:** la lógica de negocio vive en funciones
  RPC de PostgreSQL (Supabase) y una única función serverless para el correo.
- **Pensado para uso móvil:** el flujo de compra y la validación QR están
  optimizados para el navegador del celular (cámara, captura, etc.).

---

## 2. Arquitectura del proyecto

### 2.1 Vista general

El sistema sigue una arquitectura **cliente / Backend-as-a-Service (BaaS)** con
una capa serverless mínima:

```
┌──────────────────────────────────────────────────────────────────┐
│                          NAVEGADOR (Cliente)                       │
│                                                                    │
│   index.html        admin.html          validador.html             │
│   (compra)          (administración)     (validación en puerta)     │
│        │                  │                     │                   │
│        │   js/config.js (config pública)  js/common.js (utils)      │
│        │                  │                     │                   │
│   Librerías CDN: supabase-js · qrcode · html5-qrcode · jsPDF · XLSX │
└────────┬───────────────────┬────────────────────┬──────────────────┘
         │ RPC (HTTPS)        │ fetch /api/...      │ RPC (HTTPS)
         ▼                    ▼                     ▼
┌──────────────────────┐  ┌────────────────────┐  ┌────────────────────┐
│   SUPABASE (BaaS)     │  │  VERCEL SERVERLESS  │  │   SUPABASE STORAGE  │
│                       │  │                    │  │                    │
│  PostgreSQL + RLS     │  │ api/enviar-        │  │  bucket             │
│  Funciones RPC        │  │ entradas.js        │  │  "comprobantes"     │
│  (SECURITY DEFINER)   │  │ (Nodemailer +      │  │  (imágenes de pago) │
│                       │  │  QRCode)           │  │                    │
└──────────────────────┘  └─────────┬──────────┘  └────────────────────┘
                                     │ SMTP
                                     ▼
                              ┌─────────────┐
                              │  GMAIL SMTP │
                              └─────────────┘
```

### 2.2 Decisiones arquitectónicas clave

- **Frontend estático:** tres páginas HTML independientes, sin framework ni
  proceso de build. Comparten estilos (`css/style.css`) y utilidades
  (`js/common.js`, `js/config.js`).
- **Toda la lógica de negocio en la base de datos:** las operaciones sensibles
  (crear reserva, registrar comprobante, aprobar pago, validar entrada, etc.) se
  implementan como **funciones RPC de PostgreSQL** con atributo `SECURITY
  DEFINER`. El frontend nunca hace `INSERT/UPDATE/SELECT` directo sobre las
  tablas: siempre invoca `supabase.rpc(...)`.
- **RLS cerrada (deny-by-default):** las políticas de Row Level Security de las
  tablas están en `using(false)`, por lo que el acceso directo vía REST queda
  bloqueado y el único camino válido es a través de las funciones RPC.
- **Capa serverless mínima:** la única función de servidor (`api/enviar-
  entradas.js`) existe porque el envío de correo requiere credenciales SMTP que
  no pueden vivir en el cliente. Está protegida exigiendo la clave de admin.
- **La clave de admin no vive en el cliente:** se valida contra un hash bcrypt
  almacenado en la base de datos mediante la función `verificar_admin()`.

### 2.3 Tecnologías por capa

| Capa | Tecnología |
|------|-----------|
| Presentación | HTML5, CSS3, JavaScript ES módulos/vanilla |
| Cliente de datos | `@supabase/supabase-js@2` (CDN) |
| Generación de QR | `qrcode` (cliente y servidor) |
| Escaneo de QR | `html5-qrcode@2.3.8` (CDN) |
| Exportación | `jsPDF@2.5.1` (PDF) y `xlsx@0.18.5` (Excel) — CDN |
| Backend de datos | Supabase: PostgreSQL + PostgREST + Storage |
| Funciones serverless | Vercel Functions (Node.js) |
| Envío de correo | `nodemailer@8` + Gmail SMTP |
| Hosting / despliegue | Vercel |

---

## 3. Estructura de carpetas y archivos

```
concierto-jorjvana/
├── api/
│   └── enviar-entradas.js          # Función serverless de Vercel: envía las entradas por correo
│
├── assets/
│   └── images/
│       ├── concierto.jpg           # Imagen principal / fondo del evento
│       ├── entrada-virtual.png     # Plantilla de fondo para el PDF de la entrada (9:16)
│       ├── entrada-virtual-2.png   # Variante de plantilla de entrada
│       └── qr-yape.jpeg            # Código QR de Yape para recibir los pagos
│
├── css/
│   └── style.css                   # Hoja de estilos compartida por las 3 páginas
│
├── js/
│   ├── config.js                   # Configuración pública (URL/clave Supabase, WhatsApp, precio)
│   └── common.js                   # Utilidades compartidas (init Supabase, escape, etc.)
│
├── sql/                            # Scripts SQL para Supabase (ejecutar en SQL Editor)
│   ├── supabase_schema.sql                         # Esquema base: tablas, funciones, RLS, Storage
│   ├── supabase_fix_rpc.sql                        # Funciones RPC de aforo/disponibilidad
│   ├── supabase_rpc_faltantes.sql                  # RPCs de admin/validador + firmas con admin_key
│   ├── supabase_seguridad_2c_fase_a.sql            # RPCs de consulta/admin (sin tocar RLS)
│   ├── supabase_seguridad_3_cierre_rls.sql         # Cierre de RLS: validadores/validaciones/configuracion
│   ├── supabase_seguridad_4_admin_hash.sql         # Clave admin con hash bcrypt
│   ├── supabase_seguridad_4_admin_hash_rollback.sql
│   ├── supabase_seguridad_5_registrar_ingreso_auth.sql      # Autorización real en registrar_ingreso()
│   ├── supabase_seguridad_5_registrar_ingreso_auth_rollback.sql
│   ├── supabase_seguridad_6_cierre_rls_compradores_entradas.sql  # Cierre de RLS: compradores/entradas
│   ├── supabase_seguridad_6_cierre_rls_compradores_entradas_rollback.sql
│   ├── supabase_seguridad_7_storage_comprobantes.sql            # Endurece el bucket de comprobantes
│   └── supabase_seguridad_7_storage_comprobantes_rollback.sql
│
├── index.html                      # Página pública de compra y consulta de entradas
├── admin.html                      # Panel de administración
├── validador.html                  # Página de validación de QR en la puerta
│
├── package.json                    # Dependencias de la función serverless (nodemailer, qrcode)
├── package-lock.json
├── vercel.json                     # Configuración de cabeceras (Permissions-Policy: camera)
├── .gitignore
├── README.md                       # Guía de configuración y uso
├── CAMBIOS-REORGANIZACION.md       # Bitácora de la reorganización v2.0
└── docs/
    └── DOCUMENTACION-TECNICA.md    # Este documento
```

> **Nota sobre la convención de ejecución de SQL:** los scripts de la carpeta
> `sql/` están pensados para ejecutarse **en orden de dependencia** en el SQL
> Editor de Supabase. Casi todos son idempotentes (`create or replace`,
> `if not exists`, `drop ... if exists`), por lo que pueden re-ejecutarse sin
> riesgo. El orden recomendado se detalla en la [sección 9](#9-proceso-de-instalación).

---

## 4. Explicación de cada módulo

### 4.1 Frontend — Páginas HTML

#### `index.html` — Compra y consulta de entradas (público)

Página de cara al comprador. Contiene tres "vistas" conmutables mediante
JavaScript (no hay router): **Inicio**, **Comprar entradas** y **Mis entradas**.

Responsabilidades:

- **Inicio:** muestra datos del evento y el contador de entradas disponibles
  (`contar_disponibles`).
- **Comprar (3 pasos):**
  1. *Datos del comprador:* nombre, DNI (8 dígitos), celular (9 dígitos
     empezando en 9), correo y cantidad (1–10). Calcula el total con
     `window.PRECIO`. Crea la reserva con `crear_reserva`.
  2. *Pago con Yape:* muestra el QR de Yape, el código de pago, una cuenta
     regresiva de 30 minutos y permite subir el comprobante (foto o galería). El
     archivo se sube a Supabase Storage y se registra con `registrar_comprobante`
     (incluye hash SHA-256 calculado en el navegador con `crypto.subtle`).
  3. *Confirmación:* informa que la compra quedó `PENDIENTE_APROBACION` y muestra
     el código de pago para seguimiento.
- **Mis entradas:** consulta el estado por `codigo_pago` + `dni` con
  `consultar_compra`, y renderiza según el estado (reservado, pendiente,
  aprobado con tickets+QR, rechazado, expirado/cancelado).

Funciones JS destacadas: `crearReserva()`, `subirComprobante()`,
`consultarCompra()`, `renderResultadoConsulta()`, `renderTickets()`,
`iniciarCountdown()`.

#### `admin.html` — Panel de administración (administrador)

Página protegida por la clave de admin (validada en servidor con
`verificar_admin`). Tras el login, mantiene la clave en la variable en memoria
`ADMIN_KEY` y la envía como `p_admin_key` en cada RPC administrativa.

Secciones:

- **Estadísticas** (`admin_estadisticas`): vendidas, recaudación, utilizadas,
  disponibles, anuladas.
- **Aforo:** lectura con `obtener_aforo` y actualización con
  `admin_actualizar_aforo` (no permite bajar el aforo por debajo de lo vendido).
- **Validadores de QR:** alta (`admin_crear_validador`), listado
  (`admin_listar_validadores`), activar/desactivar
  (`admin_set_validador_activo`) y eliminación (`admin_eliminar_validador`).
  Genera códigos tipo `VAL-#####` si no se indica uno.
- **Compradores:** listado (`admin_listar_compradores`), búsqueda local,
  aprobar (`aprobar_pago`), rechazar (`admin_rechazar_pago`), eliminar
  (`eliminar_compra`) y ver comprobante.
- **Tabla de ventas:** entradas individuales (`admin_listar_ventas`) con ver
  ticket, reenviar correo, anular (`admin_anular_entrada`) y exportar a Excel.
- **Entradas generadas:** descarga de PDF con diseño de ticket (jsPDF sobre la
  plantilla `entrada-virtual.png`), envío por WhatsApp (enlace `wa.me`
  prellenado) y envío por correo (POST a `/api/enviar-entradas`).

Funciones JS destacadas: `loginAdmin()`, `loadAdmin()`, `aprobar()`,
`generarPDF()`, `enviarCorreo()`, `exportExcel()`.

#### `validador.html` — Validación en puerta (validador)

Página para el personal de puerta. Se accede con un **código de acceso** de
validador (o con la clave de admin). La sesión se guarda en `sessionStorage`
(`validadorNombre`, `validadorClave`).

Responsabilidades:

- **Login** (`verificar_admin` o `verificar_validador`).
- **Escáner QR** con `html5-qrcode` usando la cámara trasera, o ingreso manual
  del código.
- **Consulta** (`consultar_entrada`): muestra el estado (VÁLIDA / UTILIZADA /
  ANULADA / NO EXISTE) sin modificar nada; registra los intentos a códigos
  inexistentes con `registrar_consulta_no_existe`.
- **Registro de ingreso** (`registrar_ingreso`): marca la entrada como
  `UTILIZADA` una sola vez. Envía la clave del validador para autorización del
  lado del servidor.
- **Overlay de acceso:** muestra a pantalla completa "ACCESO PERMITIDO" o
  "ACCESO DENEGADO" con el nombre del asistente.

Funciones JS destacadas: `loginValidador()`, `startScan()`, `consultarCodigo()`,
`registrarIngreso()`, `showAccess()`.

### 4.2 Frontend — Recursos compartidos

#### `js/config.js`

Configuración **pública** que se carga en las tres páginas. Define en `window`:

```javascript
window.SUPABASE_URL  = "https://<proyecto>.supabase.co";  // público
window.SUPABASE_KEY  = "sb_publishable_...";              // anon/publishable key (público)
window.WHATSAPP_ADMIN = "51978134651";                    // número con código de país
window.PRECIO         = 10;                                // precio por entrada (S/)
```

> La clave de administrador **no** está aquí ni en ningún archivo del cliente;
> se valida en Supabase con `verificar_admin()`.

#### `js/common.js`

Utilidades compartidas:

- `isConfigured()` / `initSupabase()`: inicializa el cliente `supabase` global
  (`sb`) si la configuración es válida; si no, muestra el aviso `#cfgWarn`.
- `msg(id, txt, tipo)`: pinta un mensaje (`ok`/`warn`/`err`) en un contenedor.
- `togglePasswordField(...)`: muestra/oculta campos de contraseña.
- `unwrapRpc(data)`: desempaqueta resultados RPC que llegan como arreglo de un
  elemento.
- `esc(s)` y `safeUrl(u)`: **escape de HTML** y **validación de URL** para
  prevenir XSS.

#### `css/style.css`

Hoja de estilos única (~510 líneas) con variables CSS (`:root`), diseño
responsive, fondo desenfocado, tarjetas, tablas, badges de estado, tickets,
overlay de validación, etc.

### 4.3 Backend serverless — `api/enviar-entradas.js`

Función serverless de Vercel (`module.exports = async function handler(req,
res)`). Envía por correo las entradas con su QR adjunto. Detalles en la
[sección 7.1](#71-api-serverless-apienviar-entradas).

### 4.4 Capa de datos — Scripts SQL

Cada archivo de `sql/` representa una fase del esquema y su endurecimiento de
seguridad. Su contenido y orden se documentan en las secciones
[6](#6-base-de-datos) y [8](#8-seguridad-implementada).

---

## 5. Flujo de funcionamiento

### 5.1 Flujo de compra (comprador)

```
Comprador (index.html)
   │  1) Ingresa datos y cantidad
   ▼
crear_reserva (RPC)
   │  → inserta comprador en estado RESERVADO, codigo_pago JORJ-XXXXX,
   │    expira_en = now()+30min. Valida disponibilidad de cupos.
   ▼
Comprador paga por Yape y sube comprobante (imagen → Storage)
   │  → calcula SHA-256 del archivo en el navegador
   ▼
registrar_comprobante (RPC)
   │  → valida que la reserva siga activa y no expirada,
   │    que el hash no esté duplicado, y pasa a PENDIENTE_APROBACION
   ▼
Estado: PENDIENTE_APROBACION  (el comprador guarda su código de pago)
```

### 5.2 Flujo de aprobación (administrador)

```
Administrador (admin.html)
   │  login → verificar_admin (compara contra hash bcrypt en BD)
   ▼
loadAdmin → limpiar_reservas_expiradas + admin_listar_compradores + admin_estadisticas
   │
   │  Revisa el comprobante de un comprador PENDIENTE_APROBACION
   ▼
aprobar_pago (RPC, requiere admin_key)
   │  → genera N entradas (N = cantidad) con código JORJ-2026-XXXXXX único,
   │    numeración global por secuencia, estado VALIDA.
   │  → comprador pasa a APROBADO
   ▼
Entrega de entradas:
   ├─ Correo  → POST /api/enviar-entradas (con QR adjunto por entrada)
   ├─ WhatsApp → enlace wa.me prellenado
   └─ PDF     → jsPDF con plantilla de ticket + QR
```

### 5.3 Flujo de validación en puerta (validador)

```
Validador (validador.html)
   │  login → verificar_validador (o verificar_admin)
   ▼
Escanea / ingresa el código de la entrada
   │
   ├─ consultar_entrada (RPC, solo lectura)  → muestra estado sin modificar
   │       └─ si no existe → registrar_consulta_no_existe (auditoría)
   │
   └─ registrar_ingreso (RPC, requiere clave de validador/admin)
           ├─ VALIDA    → marca UTILIZADA, fecha_ingreso=now() → "INGRESO_OK"
           ├─ UTILIZADA → no cambia nada → "UTILIZADA" (ingreso duplicado)
           ├─ ANULADA   → no cambia nada → "ANULADA"
           └─ NO_EXISTE → registra intento → "NO_EXISTE"
   ▼
Toda acción queda registrada en la tabla "validaciones"
```

### 5.4 Máquina de estados

**Comprador (`compradores.estado`):**

```
RESERVADO ──(sube comprobante)──> PENDIENTE_APROBACION ──(admin aprueba)──> APROBADO
    │                                      │
    │                                      └──(admin rechaza)──> RECHAZADO
    │
    └──(30 min sin comprobante)──> EXPIRADO
```

> También existen los estados `PENDIENTE`, `PENDIENTE_PAGO`, `CANCELADO`
> reconocidos por compatibilidad en distintas funciones y filtros.

**Entrada (`entradas.estado`):**

```
VALIDA ──(registrar_ingreso)──> UTILIZADA
   │
   └──(admin anula)──> ANULADA
```

---

## 6. Base de datos

La base de datos es **PostgreSQL** administrada por Supabase. Usa la extensión
`pgcrypto` (UUIDs, `gen_random_bytes`, `crypt`/`gen_salt` para bcrypt).

### 6.1 Modelo de datos (resumen)

```
configuracion (1 fila)        compradores                       entradas
┌─────────────────┐           ┌──────────────────────┐         ┌──────────────────────┐
│ id = 1          │           │ id (uuid, PK)        │ 1     N │ id (uuid, PK)        │
│ aforo           │           │ codigo_pago (uniq)   │────────<│ comprador_id (FK)    │
│ admin_pass_hash │           │ nombre, dni, celular │         │ codigo (uniq)        │
└─────────────────┘           │ correo, cantidad     │         │ numero (seq)         │
                              │ total                │         │ estado               │
entrada_numero_seq            │ comprobante_url/hash │         │ nombre_asistente     │
(secuencia global)            │ estado, metodo_pago  │         │ fecha_compra/ingreso │
                              │ expira_en            │         └──────────┬───────────┘
validadores                   │ fecha_pago/revision  │                    │ N
┌─────────────────┐           └──────────────────────┘                    │
│ id (uuid, PK)   │                                          validaciones │ 1
│ nombre          │                                          ┌────────────▼─────────┐
│ codigo / clave  │ (uniq)                                   │ id (uuid, PK)        │
│ estado / activo │                                          │ entrada_id (FK null) │
│ creado_en       │                                          │ codigo, resultado    │
└─────────────────┘                                          │ accion, fecha        │
                                                             └──────────────────────┘
```

### 6.2 Tablas

#### `compradores`

Una fila por compra (no por persona). Almacena los datos del comprador, el
estado de la compra y la referencia al comprobante.

| Columna | Tipo | Notas |
|---------|------|-------|
| `id` | uuid PK | `gen_random_uuid()` |
| `nombre` | text NOT NULL | |
| `dni` | text NOT NULL | 8 dígitos (validado en cliente) |
| `celular` | text NOT NULL | 9 dígitos (validado en cliente) |
| `correo` | text | opcional |
| `cantidad` | integer NOT NULL | `check (cantidad >= 1)` |
| `total` | numeric(10,2) NOT NULL | |
| `comprobante_url` | text | URL pública en Storage |
| `comprobante_hash` | text | SHA-256; índice único parcial (anti-duplicado) |
| `metodo_pago` | text | `Yape` / `Plin` |
| `estado` | text NOT NULL | `RESERVADO`, `PENDIENTE_APROBACION`, `APROBADO`, `RECHAZADO`, `EXPIRADO`, ... |
| `codigo_pago` | text | `JORJ-XXXXX`; índice único parcial |
| `expira_en` | timestamptz | vencimiento de la reserva |
| `fecha_pago` | timestamptz | `default now()` |
| `fecha_revision` | timestamptz | fijada al aprobar/rechazar/expirar |
| `created_at` | timestamptz | `default now()` |

Índices: `idx_compradores_codigo_pago` (único parcial),
`idx_compradores_comprobante_hash` (único parcial).

#### `entradas`

Una fila por entrada individual generada al aprobar el pago.

| Columna | Tipo | Notas |
|---------|------|-------|
| `id` | uuid PK | |
| `comprador_id` | uuid FK → `compradores(id)` | `on delete cascade` |
| `codigo` | text UNIQUE | `JORJ-2026-XXXXXX` (aleatorio, no predecible) |
| `numero` | integer NOT NULL | de la secuencia `entrada_numero_seq` |
| `estado` | text NOT NULL | `VALIDA`, `UTILIZADA`, `ANULADA` |
| `nombre_asistente` | text NOT NULL | por defecto = nombre del comprador |
| `fecha_compra` | timestamptz | `default now()` |
| `fecha_ingreso` | timestamptz | null hasta el ingreso |
| `created_at` | timestamptz | `default now()` |

Índices: `idx_entradas_codigo`, `idx_entradas_comprador`.

#### `validaciones`

Bitácora (auditoría) de cada intento de consulta/ingreso en la puerta.

| Columna | Tipo | Notas |
|---------|------|-------|
| `id` | uuid PK | |
| `entrada_id` | uuid FK → `entradas(id)` | `on delete set null` (null si no existe) |
| `codigo` | text NOT NULL | código escaneado |
| `resultado` | text NOT NULL | `VALIDA`, `UTILIZADA`, `ANULADA`, `NO_EXISTE` |
| `accion` | text | `CONSULTA` / `INGRESO` |
| `fecha` | timestamptz | `default now()` |

#### `validadores`

Personas autorizadas a validar en la puerta.

| Columna | Tipo | Notas |
|---------|------|-------|
| `id` | uuid PK | |
| `nombre` | text NOT NULL | |
| `codigo` | text NOT NULL | código de acceso (ej. `VAL-58321`) |
| `clave` | text UNIQUE NOT NULL | usada en el login del validador |
| `estado` | text NOT NULL | `ACTIVO` / `INACTIVO` |
| `activo` | boolean NOT NULL | `default true` |
| `creado_en` | timestamptz | `default now()` |

#### `configuracion`

Tabla de una sola fila (`check (id = 1)`) con el aforo del evento y el hash de
la clave de admin.

| Columna | Tipo | Notas |
|---------|------|-------|
| `id` | integer PK | siempre 1 |
| `aforo` | integer NOT NULL | total de entradas a la venta (default 500) |
| `admin_pass_hash` | text | hash bcrypt de la clave de admin (fase de seguridad 4) |

### 6.3 Secuencia

- `entrada_numero_seq`: numeración global incremental de entradas
  (`numero` 1, 2, 3, ...).

### 6.4 Vista

- `v_estadisticas`: vista de conveniencia con `vendidas`, `utilizadas`,
  `recaudacion` y `disponibles`. (El panel usa la RPC `admin_estadisticas` que
  además exige clave de admin.)

### 6.5 Storage

- Bucket **`comprobantes`** (público para lectura por URL directa). Guarda las
  imágenes de los comprobantes de pago. La fase 7 de seguridad restringe los
  tipos MIME a imágenes y limita el tamaño a 8 MB, y bloquea el listado y
  borrado público.

---

## 7. API y funciones principales

El sistema expone dos superficies "de API":

1. La **API serverless** de Vercel (`/api/enviar-entradas`).
2. Las **funciones RPC** de PostgreSQL expuestas por PostgREST en
   `/rest/v1/rpc/<funcion>` e invocadas desde el cliente con
   `supabase.rpc('<funcion>', { ...params })`.

### 7.1 API serverless: `/api/enviar-entradas`

| Atributo | Valor |
|----------|-------|
| Método | `POST` |
| Ruta | `/api/enviar-entradas` |
| Autenticación | Requiere `adminKey` válido (verificado contra `verificar_admin` en Supabase) |
| Archivo | `api/enviar-entradas.js` |

**Cuerpo de la solicitud (JSON):**

```json
{
  "adminKey": "clave-de-admin",
  "nombre": "Juan Pérez",
  "correo": "juan@ejemplo.com",
  "codigos": ["JORJ-2026-A8F7K2", "JORJ-2026-B1C2D3"],
  "codigoPago": "JORJ-12345",
  "urlConsulta": "https://.../index.html?codigo_pago=JORJ-12345#consulta",
  "evento": { "fecha": "17 de Julio 2026", "hora": "7:00 PM", "lugar": "C.C. Vida Abundante" }
}
```

**Comportamiento:**

1. Rechaza métodos distintos de `POST` (`405`).
2. Verifica `adminKey` llamando a la RPC `verificar_admin` (usando
   `SUPABASE_URL` y `SUPABASE_ANON_KEY` del entorno). Si falla → `401`.
3. Valida que vengan `correo` y `codigos` (no vacío) → si no, `400`.
4. Requiere `GMAIL_USER` y `GMAIL_APP_PASSWORD` en el entorno → si faltan, `500`.
5. Genera un PNG de QR por cada código (`qrcode.toBuffer`) y los adjunta vía CID.
6. Construye el correo HTML + texto plano (con `escHtml`/`safeUrl` para evitar
   inyección) y lo envía con Nodemailer (servicio Gmail).
7. Respuestas: `200 { ok: true }` en éxito; `4xx/5xx { error }` en fallo.

**Variables de entorno requeridas (servidor):** `GMAIL_USER`,
`GMAIL_APP_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`.

### 7.2 Funciones RPC de Supabase

> Todas son `SECURITY DEFINER` y tienen `grant execute ... to anon,
> authenticated`. Las administrativas exigen `p_admin_key` y abortan con
> excepción si la clave es inválida.

#### Públicas (flujo de compra / consulta)

| Función | Parámetros | Devuelve | Propósito |
|---------|-----------|----------|-----------|
| `crear_reserva` | `p_nombre, p_dni, p_celular, p_correo, p_cantidad, p_total, p_metodo` | jsonb (id, codigo_pago, expira_en, total, cantidad, estado) | Crea reserva RESERVADO con expiración de 30 min; valida disponibilidad. |
| `registrar_comprobante` | `p_comprador, p_url, p_hash` | jsonb | Asocia comprobante y pasa a PENDIENTE_APROBACION; valida no-expiración y hash único. |
| `consultar_compra` | `p_codigo_pago, p_dni` | jsonb (incluye `entradas` si APROBADO) | Consulta pública de "Mis entradas". |
| `contar_disponibles` | — | integer | Aforo − vendidas − reservas activas. |
| `obtener_aforo` | — | integer | Aforo configurado. |
| `consultar_entrada` | `p_codigo` | jsonb \| null | Estado de una entrada (solo lectura). |
| `registrar_consulta_no_existe` | `p_codigo` | void | Auditoría de códigos inexistentes. |
| `registrar_ingreso` | `p_codigo, p_clave` | jsonb (resultado, ...) | Marca UTILIZADA una vez; **autoriza** con clave de validador/admin. |
| `verificar_validador` | `p_clave` | jsonb (valido, nombre) | Valida código de validador activo. |
| `verificar_admin` | `p_admin_key` | boolean | Valida la clave de admin (contra hash bcrypt). |
| `limpiar_reservas_expiradas` | — | integer | Marca EXPIRADO las reservas vencidas. |

#### Administrativas (requieren `p_admin_key`)

| Función | Parámetros | Devuelve | Propósito |
|---------|-----------|----------|-----------|
| `aprobar_pago` | `p_comprador, p_admin_key` | setof entradas | Genera entradas y pasa a APROBADO. |
| `admin_rechazar_pago` | `p_admin_key, p_comprador` | void | Pasa a RECHAZADO. |
| `eliminar_compra` | `p_comprador, p_admin_key` | jsonb | Borra compra no aprobada y su comprobante en Storage. |
| `admin_listar_compradores` | `p_admin_key` | setof compradores | Listado completo. |
| `admin_estadisticas` | `p_admin_key` | jsonb | Vendidas/utilizadas/anuladas/recaudación/disponibles. |
| `admin_actualizar_aforo` | `p_admin_key, p_aforo` | void | Cambia el aforo. |
| `admin_listar_ventas` | `p_admin_key` | table | Entradas + datos del comprador. |
| `admin_obtener_entradas` | `p_admin_key, p_comprador` | setof entradas | Entradas de un comprador. |
| `admin_anular_entrada` | `p_admin_key, p_entrada` | void | Marca ANULADA. |
| `admin_listar_validadores` | `p_admin_key` | setof validadores | Listado de validadores. |
| `admin_crear_validador` | `p_admin_key, p_nombre, p_clave` | void | Alta de validador. |
| `admin_set_validador_activo` | `p_admin_key, p_id, p_activo` | void | Activa/desactiva. |
| `admin_eliminar_validador` | `p_admin_key, p_id` | void | Elimina validador. |

---

## 8. Seguridad implementada

La seguridad se construyó por **fases** (visibles en los nombres de los scripts
`sql/supabase_seguridad_*`). El principio central es:
**deny-by-default + acceso únicamente vía funciones RPC `SECURITY DEFINER`.**

### 8.1 Modelo de acceso

- El cliente solo conoce la **anon/publishable key** (pública por diseño). Con
  esa clave **no** puede leer ni escribir las tablas directamente porque las
  políticas RLS están en `using(false)`.
- El único camino para operar sobre los datos son las **funciones RPC**, que se
  ejecutan con los privilegios del propietario (`SECURITY DEFINER`) y aplican
  sus propias reglas de negocio y autorización.

### 8.2 Cierre de Row Level Security (RLS)

| Script | Tablas afectadas | Efecto |
|--------|------------------|--------|
| `supabase_seguridad_3_cierre_rls.sql` | `validadores`, `validaciones`, `configuracion` | Políticas `using(false)`; `contar_disponibles`/`obtener_aforo` pasan a `SECURITY DEFINER` para seguir leyendo `configuracion`. |
| `supabase_seguridad_6_cierre_rls_compradores_entradas.sql` | `compradores`, `entradas` | Políticas `using(false)`; el frontend ya solo usa RPCs. |

### 8.3 Autenticación de administrador con hash bcrypt

`supabase_seguridad_4_admin_hash.sql` agrega `admin_pass_hash` a `configuracion`
y reemplaza `verificar_admin()` para comparar la clave recibida contra el hash
bcrypt (`crypt(p_admin_key, v_hash)`).

- La clave en texto **no** se guarda en ningún archivo del repositorio ni en el
  cliente. Solo se introduce manualmente al ejecutar el script.
- Existe `..._rollback.sql` para revertir a la versión anterior.

### 8.4 Autorización real en la validación de ingreso

`supabase_seguridad_5_registrar_ingreso_auth.sql` cambia la firma de
`registrar_ingreso` a `(p_codigo, p_clave)` y, antes de marcar la entrada,
valida que `p_clave` corresponda a un validador activo o al admin. Esto cierra
la brecha por la cual cualquiera con la anon key podía marcar entradas como
usadas saltándose el login.

### 8.5 Endurecimiento del Storage de comprobantes

`supabase_seguridad_7_storage_comprobantes.sql`:

- Bloquea el **listado** público del bucket (`select using(false)`).
- Bloquea el **borrado** público (`delete using(false)`).
- Restringe los **tipos MIME** a imágenes (jpeg/png/webp/heic/heif) y el
  **tamaño** a 8 MB.
- Mueve el borrado del archivo al interior de `eliminar_compra()` (que ya exige
  clave de admin), de modo que ya no exista una puerta pública de borrado.

> Limitación documentada en el propio script: la **subida** (INSERT) de
> comprobantes sigue abierta sin credenciales, porque el comprador no tiene
> cuenta. Cerrarla del todo requeriría subir el archivo desde el servidor
> (cambio mayor de flujo). Asimismo, la URL pública de un comprobante concreto
> sigue siendo accesible si se conoce la URL exacta (el bucket es público a
> propósito para mostrar las imágenes en el panel).

### 8.6 Protección contra XSS e inyección

- **Cliente:** `esc()` y `safeUrl()` en `js/common.js` se usan al renderizar
  datos en `innerHTML` y al construir enlaces (mitiga XSS almacenado).
- **Servidor (correo):** `escHtml()` y `safeUrl()` en `api/enviar-entradas.js`
  escapan el contenido del HTML del correo y validan la URL de consulta.

### 8.7 Integridad de datos y reglas de negocio

- **Código de pago** (`JORJ-XXXXX`) y **código de entrada** (`JORJ-2026-XXXXXX`)
  con índices únicos; el de entrada se genera con `gen_random_bytes` (no
  predecible).
- **Anti-doble-uso del comprobante:** índice único parcial sobre
  `comprobante_hash` y verificación explícita en `registrar_comprobante`.
- **Reserva con expiración** de 30 minutos + `limpiar_reservas_expiradas`.
- **Bloqueos de fila** (`for update`) en operaciones críticas (aprobar,
  registrar ingreso, registrar comprobante) para evitar condiciones de carrera.
- **Ingreso único:** `registrar_ingreso` solo marca `UTILIZADA` si la entrada
  está `VALIDA`; los reintentos quedan registrados pero no readmiten.
- **Aforo coherente:** `admin_actualizar_aforo` y la lógica del panel impiden
  fijar un aforo inferior a las entradas ya vendidas.

### 8.8 Configuración de cabeceras

`vercel.json` agrega `Permissions-Policy: camera=(self)` para permitir el uso de
la cámara (escáner QR) únicamente desde el propio origen.

### 8.9 Gestión de secretos

| Secreto | Dónde vive | Visibilidad |
|---------|-----------|-------------|
| `SUPABASE_URL`, `SUPABASE_KEY` (anon) | `js/config.js` | Público (por diseño) |
| Clave de administrador | hash bcrypt en `configuracion.admin_pass_hash` | Privado (solo hash) |
| `GMAIL_USER`, `GMAIL_APP_PASSWORD` | variables de entorno en Vercel | Privado (servidor) |
| `SUPABASE_ANON_KEY` (para la función serverless) | variable de entorno en Vercel | Privado en servidor (aunque la anon key es pública) |

> El archivo `.gitignore` excluye `.env.local` y variantes para evitar subir
> secretos al repositorio.

---

## 9. Proceso de instalación

### 9.1 Requisitos previos

- **Node.js 16+** (para instalar dependencias de la función serverless).
- Cuenta en **Supabase** (base de datos + Storage).
- Cuenta en **Vercel** (hosting + funciones serverless).
- Cuenta de **Gmail** con **App Password** (autenticación en 2 pasos activada),
  para el envío de correos.

### 9.2 Clonar e instalar dependencias

```bash
git clone https://github.com/Manrique94/concierto-jorjvana.git
cd concierto-jorjvana
npm install
```

### 9.3 Crear el proyecto de Supabase y ejecutar los scripts SQL

En **Supabase → SQL Editor → New Query**, ejecuta los scripts **en este orden**
(de base a endurecimiento):

1. `sql/supabase_schema.sql` — esquema base: tablas, secuencia, funciones
   iniciales, RLS permisiva, bucket de Storage y vista.
2. `sql/supabase_fix_rpc.sql` — `contar_disponibles` y
   `limpiar_reservas_expiradas` (y tabla `configuracion` si faltara).
3. `sql/supabase_rpc_faltantes.sql` — RPCs de admin/validador y firmas con
   `p_admin_key` (`aprobar_pago`, `eliminar_compra`, etc.).
4. `sql/supabase_seguridad_2c_fase_a.sql` — RPCs de consulta y administración
   (`consultar_compra`, `admin_estadisticas`, `admin_listar_ventas`, etc.).
5. `sql/supabase_seguridad_3_cierre_rls.sql` — cierre de RLS en
   `validadores`/`validaciones`/`configuracion`.
6. `sql/supabase_seguridad_4_admin_hash.sql` — clave de admin con hash bcrypt
   (**reemplaza `CAMBIA_ESTA_CLAVE_AQUI` por tu clave real** al pegar el script;
   no la guardes en ningún archivo).
7. `sql/supabase_seguridad_5_registrar_ingreso_auth.sql` — autorización real en
   `registrar_ingreso`.
8. `sql/supabase_seguridad_6_cierre_rls_compradores_entradas.sql` — cierre de
   RLS en `compradores`/`entradas`.
9. `sql/supabase_seguridad_7_storage_comprobantes.sql` — endurecimiento del
   bucket de comprobantes.

> Los scripts son idempotentes; ante dudas se pueden re-ejecutar. Para revertir
> alguna fase de seguridad, usa el `..._rollback.sql` correspondiente.

### 9.4 Configurar credenciales públicas del cliente

Edita `js/config.js`:

```javascript
window.SUPABASE_URL   = "https://<tu-proyecto>.supabase.co";
window.SUPABASE_KEY   = "<tu-anon/publishable-key>";
window.WHATSAPP_ADMIN = "51XXXXXXXXX";  // número con código de país
window.PRECIO         = 10;              // precio por entrada (S/)
```

### 9.5 Configurar el QR de Yape

Reemplaza `assets/images/qr-yape.jpeg` por el QR de tu cuenta Yape (es la imagen
que se muestra al comprador en el paso de pago).

### 9.6 Variables de entorno del servidor (Vercel)

En **Vercel → Settings → Environment Variables**:

```
GMAIL_USER=tu-correo@gmail.com
GMAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx   # App Password de 16 caracteres
SUPABASE_URL=https://<tu-proyecto>.supabase.co
SUPABASE_ANON_KEY=<tu-anon-key>
```

### 9.7 Prueba local

Al ser un sitio estático, puedes servirlo con cualquier servidor estático (por
ejemplo `npx serve .`) y abrir `index.html`, `admin.html` y `validador.html`.

> Nota: la función serverless `/api/enviar-entradas` no se ejecuta con un
> servidor estático simple; para probarla localmente usa `vercel dev`.

---

## 10. Proceso de despliegue

El despliegue es **continuo** mediante Vercel conectado al repositorio de GitHub.

### 10.1 Pasos

1. **Subir el código a GitHub:**

   ```bash
   git add .
   git commit -m "feat: configuración del evento"
   git push origin main
   ```

2. **Conectar el repositorio en Vercel:** Vercel → *Add New Project* →
   importar `concierto-jorjvana`.

3. **Configurar las variables de entorno** (sección 9.6) en el proyecto de
   Vercel (entornos *Production* / *Preview* según corresponda).

4. **Deploy automático:** cada `push` a `main` dispara un despliegue de
   producción. Las ramas y PRs generan *Preview Deployments*.

### 10.2 Configuración de Vercel

- **Tipo de proyecto:** estático + funciones serverless en `api/`.
- **`vercel.json`:** define la cabecera `Permissions-Policy: camera=(self)`.
- **Funciones:** los archivos de `api/` se publican automáticamente como
  endpoints (`/api/enviar-entradas`). Las dependencias se toman de
  `package.json` (`nodemailer`, `qrcode`).
- **Dominio:** Vercel asigna `https://<proyecto>.vercel.app`. Se puede añadir un
  dominio personalizado en *Settings → Domains*.

### 10.3 Checklist post-despliegue

- [ ] Las imágenes cargan (`/assets/images/...`).
- [ ] El contador de disponibles aparece en Inicio (Supabase conectado).
- [ ] Flujo de compra completo: reserva → comprobante → PENDIENTE_APROBACION.
- [ ] Login de admin funciona (hash configurado).
- [ ] Aprobar genera entradas y el correo llega (Gmail configurado).
- [ ] El validador inicia sesión y registra ingresos.

---

## 11. Mantenimiento y respaldo

### 11.1 Operación recurrente

- **Reservas expiradas:** `limpiar_reservas_expiradas()` se invoca
  automáticamente al cargar el panel admin y dentro de `crear_reserva`. Para
  forzar limpieza, puede ejecutarse manualmente o agendarse con
  `pg_cron`/Supabase Scheduled Functions.
- **Aforo:** ajustable desde el panel admin (no puede ser menor a lo vendido).
- **Validadores:** crear/activar/desactivar/eliminar según el personal de cada
  fecha.

### 11.2 Respaldo (backup)

- **Base de datos:** Supabase realiza backups automáticos según el plan. Para un
  respaldo manual:

  ```bash
  # Volcado completo (requiere connection string del proyecto Supabase)
  pg_dump "postgresql://postgres:<password>@db.<proyecto>.supabase.co:5432/postgres" \
    --no-owner --format=custom --file=backup_jorjvana.dump
  ```

  También puedes exportar tablas a CSV desde **Supabase → Table Editor → Export**.
- **Datos operativos rápidos:** el panel admin permite **exportar a Excel** la
  tabla de compradores y la tabla de ventas, útil como respaldo funcional del
  evento.
- **Storage (comprobantes):** descargar el contenido del bucket `comprobantes`
  desde el panel de Supabase Storage o vía API si se requiere archivar las
  evidencias de pago.
- **Código:** el repositorio Git es la fuente de verdad del frontend, la función
  serverless y los scripts SQL. Mantener etiquetas/releases por evento.

### 11.3 Restauración

```bash
# Restaurar un volcado custom
pg_restore --no-owner --dbname="postgresql://postgres:<password>@db.<proyecto>.supabase.co:5432/postgres" \
  backup_jorjvana.dump
```

> Tras restaurar, verifica que las funciones RPC y las políticas RLS quedaron
> en el estado endurecido (re-ejecuta los scripts `sql/supabase_seguridad_*` si
> hiciera falta).

### 11.4 Rotación de credenciales

- **Clave de admin:** re-ejecuta el PASO 2 de
  `supabase_seguridad_4_admin_hash.sql` con la nueva clave.
- **App Password de Gmail:** genera una nueva en la cuenta de Google y
  actualiza `GMAIL_APP_PASSWORD` en Vercel.
- **Anon key de Supabase:** si se rota, actualiza `js/config.js` y la variable
  `SUPABASE_ANON_KEY` en Vercel.

### 11.5 Solución de problemas frecuentes

| Síntoma | Causa probable | Acción |
|---------|----------------|--------|
| Aviso amarillo "Configura tus credenciales" | `js/config.js` sin valores reales | Completar `SUPABASE_URL`/`SUPABASE_KEY` y recargar. |
| "Could not find the function ... in the schema cache" | Falta un `grant execute` o el script RPC no se ejecutó | Re-ejecutar el script SQL correspondiente. |
| No llegan los correos | Faltan `GMAIL_USER`/`GMAIL_APP_PASSWORD` o App Password inválido | Revisar variables en Vercel y logs (`vercel logs`). |
| Login de admin falla siempre | `admin_pass_hash` no configurado | Ejecutar la fase 4 con la clave real. |
| Validador no puede registrar ingreso | Validador inactivo o sesión vencida | Activar el validador / volver a iniciar sesión. |
| El QR de Yape no aparece | Falta `assets/images/qr-yape.jpeg` | Subir la imagen con el nombre exacto. |

---

## 12. Anexos

### 12.1 Matriz módulo ↔ RPC

| Módulo (UI) | RPC / endpoint que usa |
|-------------|------------------------|
| `index.html` (compra) | `crear_reserva`, `registrar_comprobante`, `contar_disponibles`, `consultar_compra` |
| `admin.html` (panel) | `verificar_admin`, `obtener_aforo`, `admin_actualizar_aforo`, `admin_estadisticas`, `admin_listar_compradores`, `aprobar_pago`, `admin_rechazar_pago`, `eliminar_compra`, `limpiar_reservas_expiradas`, `admin_listar_ventas`, `admin_obtener_entradas`, `admin_anular_entrada`, validadores `admin_*`, `POST /api/enviar-entradas` |
| `validador.html` (puerta) | `verificar_admin`, `verificar_validador`, `consultar_entrada`, `registrar_ingreso`, `registrar_consulta_no_existe` |

### 12.2 Convenciones de códigos

| Código | Formato | Generado por |
|--------|---------|--------------|
| Código de pago | `JORJ-#####` (5 dígitos) | `crear_reserva` |
| Código de entrada | `JORJ-2026-XXXXXX` (6 hex en mayúsculas) | `aprobar_pago` |
| Código de validador | `VAL-#####` (5 dígitos) | panel admin (`generarCodigoValidador`) o manual |

### 12.3 Dependencias

**Servidor (`package.json`):**

- `nodemailer@^8.0.11` — envío de correos SMTP.
- `qrcode@^1.5.4` — generación de QR en el servidor (adjuntos del correo).

**Cliente (vía CDN):**

- `@supabase/supabase-js@2`, `qrcode@1.5.3`, `html5-qrcode@2.3.8`,
  `jspdf@2.5.1`, `xlsx@0.18.5`.

### 12.4 Glosario

- **RPC (Remote Procedure Call):** función de PostgreSQL expuesta por PostgREST
  e invocada desde el cliente con `supabase.rpc(...)`.
- **`SECURITY DEFINER`:** la función se ejecuta con los privilegios de su
  propietario, no del rol que la llama; permite operar sobre tablas con RLS
  cerrada.
- **RLS (Row Level Security):** mecanismo de PostgreSQL para autorizar el acceso
  fila por fila; aquí está cerrado por defecto.
- **Aforo:** capacidad total de entradas a la venta del evento.
- **BaaS (Backend-as-a-Service):** Supabase actúa como backend gestionado
  (base de datos, API REST, Storage).

---

*Documento generado para el repositorio `Manrique94/concierto-jorjvana`.*
