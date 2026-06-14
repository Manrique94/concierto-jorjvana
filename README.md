# 🎵 Concierto Acústico JORJVANA - Sistema de Venta de Entradas

Sistema completo de venta, validación y gestión de entradas para eventos. Incluye compra con QR, validación en tiempo real y panel de administración.

## 📋 Tabla de Contenidos

- [Estructura del Proyecto](#estructura-del-proyecto)
- [Requisitos Previos](#requisitos-previos)
- [Configuración Inicial](#configuración-inicial)
- [Flujos de Usuario](#flujos-de-usuario)
- [Despliegue](#despliegue)
- [Variables de Entorno](#variables-de-entorno)
- [Solución de Problemas](#solución-de-problemas)

## 📁 Estructura del Proyecto

```
CONCIERTO-JORJVANA/
├── api/
│   └── enviar-entradas.js          # Serverless function de Vercel para enviar correos
│
├── assets/
│   └── images/
│       ├── concierto.jpg           # Imagen principal del evento
│       ├── entrada-virtual.png     # Ícono de entrada
│       └── yape.jpg                # Código QR de Yape (actualizar con tu QR)
│
├── css/
│   └── style.css                   # Estilos compartidos por todas las páginas
│
├── js/
│   ├── config.js                   # Credenciales de Supabase y configuración global
│   └── common.js                   # Funciones utilitarias compartidas
│
├── sql/
│   ├── supabase_schema.sql         # Estructura base de datos
│   └── supabase_fix_rpc.sql        # Funciones RPC de Supabase
│
├── index.html                      # Página pública de compra de entradas
├── admin.html                      # Panel de administración
├── validador.html                  # Página de validación QR (puerta)
│
├── .env.local                      # Variables de entorno (credenciales Vercel)
├── .gitignore                      # Archivos a ignorar en Git
├── package.json                    # Dependencias del proyecto
├── package-lock.json               # Lock de dependencias
├── vercel.json                     # Configuración de despliegue en Vercel
└── README.md                       # Este archivo
```

## ⚙️ Requisitos Previos

- **Node.js** 16+ (para desarrollo local y API)
- **Supabase** (base de datos en la nube)
- **Vercel** (hosting del proyecto)
- **SMTP de Gmail** (para envío de correos con entradas)

## 🚀 Configuración Inicial

### 1. Clonar el Repositorio

```bash
git clone https://github.com/tu-usuario/CONCIERTO-JORJVANA.git
cd CONCIERTO-JORJVANA
```

### 2. Instalar Dependencias

```bash
npm install
```

### 3. Configurar Supabase

#### a) Crear proyecto en Supabase

1. Ir a [supabase.com](https://supabase.com)
2. Crear nuevo proyecto
3. Copiar las credenciales (Project URL y Anon Key)

#### b) Crear tablas y funciones

1. En Supabase, ir a **SQL Editor**
2. Ejecutar los scripts en este orden:
   - `sql/supabase_schema.sql` (crear tablas)
   - `sql/supabase_fix_rpc.sql` (crear funciones RPC)

### 4. Configurar Credenciales

Editar `js/config.js` con tus credenciales:

```javascript
window.SUPABASE_URL = "https://tu-proyecto.supabase.co";
window.SUPABASE_KEY = "tu_clave_publica";
window.ADMIN_PASS = "tu_clave_admin";
window.WHATSAPP_ADMIN = "51978134651"; // Tu número con código de país
window.PRECIO = 10; // Precio por entrada en soles
```

### 5. Configurar Imagen de Yape

1. Actualizar `assets/images/yape.jpg` con tu código QR de Yape personal

### 6. Configurar Variables de Entorno (Vercel)

En Vercel dashboard, agregar estas variables:

```
GMAIL_USER=tu-correo@gmail.com
GMAIL_APP_PASSWORD=tu-clave-app-gmail
```

## 👥 Flujos de Usuario

### 📱 Flujo 1: Compra de Entradas (index.html)

1. **Usuario accede a la página**
   - Ve información del evento: fecha, hora, lugar, precio
   - Ve cantidad de entradas disponibles

2. **Paso 1: Ingresa datos**
   - Nombre completo (validación requerida)
   - DNI (8 dígitos, validación numérica)
   - Celular (validación requerida)
   - Correo (validación de email)
   - Cantidad de entradas (1-10)
   - Sistema calcula total automáticamente

3. **Paso 2: Realiza pago por Yape**
   - Se genera código de pago único (JORJ-XXXXXX)
   - Se crea reserva con expiración en 30 minutos
   - Se muestra QR de Yape
   - Usuario toma captura de comprobante de pago
   - Carga archivo de comprobante
   - Sistema almacena evidencia en Supabase Storage

4. **Paso 3: Confirmación**
   - Compra registrada como "PENDIENTE_APROBACION"
   - Sistema guarda código de pago para seguimiento
   - Usuario puede consultar estado en "Mis entradas"

**Flujo de Base de Datos:**
```
Datos → crear_reserva (RPC) → comprador (RESERVADO, 30 min)
    ↓
Comprobante → registrar_comprobante (RPC) → PENDIENTE_APROBACION
    ↓
Admin aprueba → APROBADO
    ↓
Sistema genera entradas (tabla "entradas")
    ↓
Email automático con QR de cada entrada
```

### 👨‍💼 Flujo 2: Aprobación de Pagos (admin.html)

1. **Admin ingresa con contraseña**
   - Acceso restringido con clave

2. **Ve estadísticas en tiempo real**
   - Entradas vendidas
   - Entradas utilizadas
   - Entradas disponibles
   - Recaudación total

3. **Gestiona validadores QR**
   - Crea nuevos validadores de puerta
   - Asigna códigos de acceso
   - Genera código automático o manual

4. **Revisa comprobantes de pago**
   - Tabla de compradores filtrable
   - Ve estado de cada compra
   - Puede descargar imagen del comprobante
   - Aprueba o rechaza manualmente

5. **Genera entradas**
   - Al aprobar, genera entradas con QR único
   - Envía correo automático con entradas

6. **Exportación de datos**
   - Descarga Excel con todos los compradores
   - Genera PDF de entradas por comprador

### 🎫 Flujo 3: Validación en Puerta (validador.html)

1. **Validador ingresa con código de acceso**
   - Código único generado por admin
   - Diferente a la clave de admin (más seguro)

2. **Escanea o ingresa código manualmente**
   - Abre cámara del celular
   - Escanea QR de entrada
   - O ingresa código manualmente (JORJ-2026-XXXXXX)

3. **Sistema valida la entrada**
   - ✅ VÁLIDA: Primera vez, permiso de ingreso
   - ⚠️ UTILIZADA: Ya fue escaneada antes
   - 🚫 ANULADA: Entrada cancelada
   - ❌ NO EXISTE: Código inválido

4. **Registra ingreso**
   - Marca hora de ingreso
   - Actualiza estado a "UTILIZADA"
   - Previene ingresos duplicados

5. **Log de validación**
   - Registra cada intento en tabla "validaciones"

## 🌐 Despliegue en Vercel

### 1. Preparar Repositorio Git

```bash
git add .
git commit -m "chore: reorganizar estructura del proyecto"
git push origin main
```

### 2. Conectar a Vercel

1. Ir a [vercel.com](https://vercel.com)
2. Conectar repositorio de GitHub
3. Seleccionar proyecto `CONCIERTO-JORJVANA`

### 3. Configurar Variables de Entorno

En Vercel Settings → Environment Variables:

```
GMAIL_USER = tu-correo@gmail.com
GMAIL_APP_PASSWORD = tu-clave-app-gmail
```

### 4. Deploy

```bash
# Automático con cada push a main
git push origin main
```

El proyecto se despliega en: `https://concierto-jorjvana.vercel.app`

### 5. Configurar Dominio Custom (Opcional)

En Vercel Settings → Domains, agregar dominio personalizado

## 🔐 Variables de Entorno

### .env.local (Solo servidor - Vercel)

```
GMAIL_USER=tu-correo@gmail.com
GMAIL_APP_PASSWORD=tu-clave-app-gmail
VERCEL_OIDC_TOKEN=auto-generado-por-vercel
```

### config.js (Compartido en cliente - PÚBLICO)

⚠️ **IMPORTANTE:** Los valores en `config.js` son públicos (visibles en el navegador). No guardar secretos aquí.

```javascript
window.SUPABASE_URL = "https://..."          // Público (Anon Key)
window.SUPABASE_KEY = "pk_..."               // Público (Anon Key)
window.ADMIN_PASS = "tu-clave-admin"         // Considera cambiar si se filtra
window.WHATSAPP_ADMIN = "51..."              // Público (número)
window.PRECIO = 10                           // Público
```

## 📧 Configurar Gmail App Password

Para poder enviar correos automáticos desde el servidor:

1. Activar autenticación en 2 pasos en Google Account
2. Generar "App Password"
3. Copiar la contraseña generada (16 caracteres)
4. Guardar en variable `GMAIL_APP_PASSWORD` en Vercel

## 📊 Estructura de Datos (Supabase)

### Tabla: compradores
```sql
id              UUID
codigo_pago     TEXT (JORJ-XXXXXX)
nombre          TEXT
dni             TEXT (8 dígitos)
celular         TEXT
correo          EMAIL
cantidad        INTEGER
total           DECIMAL
comprobante_url TEXT (URL a Storage)
comprobante_hash TEXT (SHA-256)
estado          TEXT (RESERVADO, PENDIENTE_APROBACION, APROBADO, RECHAZADO)
metodo_pago     TEXT (Yape, Transferencia, etc)
expira_en       TIMESTAMP
created_at      TIMESTAMP
```

### Tabla: entradas
```sql
id              UUID
comprador_id    UUID FK → compradores
numero          INTEGER (orden dentro de la compra)
codigo          TEXT (JORJ-2026-XXXXXX)
nombre_asistente TEXT
estado          TEXT (VALIDA, UTILIZADA, ANULADA)
fecha_compra    TIMESTAMP
fecha_ingreso   TIMESTAMP (null hasta usar)
```

### Tabla: validadores
```sql
id              UUID
nombre          TEXT
clave           TEXT (código de acceso)
activo          BOOLEAN
creado_en       TIMESTAMP
```

### Tabla: validaciones
```sql
id              UUID
codigo          TEXT
resultado       TEXT (INGRESO_OK, UTILIZADA, ANULADA, NO_EXISTE)
validador       TEXT
accion          TEXT (CONSULTA, INGRESO)
created_at      TIMESTAMP
```

### Tabla: configuracion
```sql
id              INTEGER
aforo           INTEGER (total de entradas disponibles)
```

## 🐛 Solución de Problemas

### "Configura tus credenciales de Supabase"

**Problema:** Aparece advertencia amarilla en la página

**Solución:**
1. Verificar que `js/config.js` tenga valores reales
2. No debe contener "TU-PROYECTO" ni "TU-ANON"
3. Reload la página (Ctrl+F5)

### No llegan los correos con entradas

**Problema:** Admin aprueba compra pero usuario no recibe email

**Solución:**
1. Verificar que `GMAIL_USER` y `GMAIL_APP_PASSWORD` estén en Vercel
2. Verificar que el correo sea correcto en la base de datos
3. Revisar logs en Vercel: `vercel logs`
4. Asegurar que Gmail tiene "Aplicaciones menos seguras" habilitadas o usar App Password

### QR de Yape no se ve

**Problema:** La imagen `assets/images/yape.jpg` no carga

**Solución:**
1. Verificar que el archivo existe en la carpeta correcta
2. Probar en navegador: `https://dominio.com/assets/images/yape.jpg`
3. Revalidar que la ruta es correcta (sensible a mayúsculas)

### Entradas no se generan

**Problema:** Admin aprueba pero no se crean entradas

**Solución:**
1. Verificar que la función RPC `generar_entradas` existe en Supabase
2. Revisar logs de Supabase
3. Asegurar que `sql/supabase_fix_rpc.sql` fue ejecutado

### Validador no puede ingresar

**Problema:** Código de validador válido no funciona

**Solución:**
1. Verificar que el validador está "activo" en tabla
2. Revisión sensible a mayúsculas
3. Probar con contraseña admin directamente
4. Ver logs en navegador (F12 → Console)

## 📱 Contacto y Soporte

- **WhatsApp:** +51 978 134 651 (número de admin en config.js)
- **Correo:** administrador@ejemplo.com
- **GitHub Issues:** Para reportar bugs

## 📄 Licencia

© 2026 Concierto Acústico JORJVANA. Todos los derechos reservados.

---

**Última actualización:** 2026-06-13  
**Versión:** 2.0 (Estructura reorganizada)
