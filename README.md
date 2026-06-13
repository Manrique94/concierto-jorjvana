# 🎫 Sistema de Entradas — Concierto Acústico JORJVANA

Plataforma web para **vender, administrar y validar** entradas digitales con QR únicos.
Aforo: hasta **500 asistentes** · Compras múltiples por persona · Validación en tiempo real desde el celular.

---

## 📁 Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | La aplicación completa (frontend) |
| `supabase_schema.sql` | Script para crear la base de datos |
| `concierto.jpg` | Imagen del evento (ya incluida) |
| `vercel.json` | Configuración de hosting (Vercel) |
| `yape.jpg` | QR de pago de Yape |

---

## 🚀 Pasos de instalación (15 min)

### 1) Crear la base de datos en Supabase
1. Entra a **https://supabase.com** → crea una cuenta gratuita → **New Project**.
2. Cuando esté listo, ve a **SQL Editor → New query**.
3. Copia y pega TODO el contenido de `supabase_schema.sql` y presiona **Run**.
   Esto crea las tablas (compradores, entradas, validaciones), las funciones y el bucket de comprobantes.
4. (Recomendado) En **Authentication → Providers → Email**, desactiva **"Confirm email"** para que al crear una cuenta el usuario quede con sesión iniciada de inmediato (sin tener que confirmar por correo).

### 2) Obtener tus credenciales
En Supabase: **Project Settings → API**. Copia:
- **Project URL** (algo como `https://abcd.supabase.co`)
- **anon public key**

### 3) Configurar la app
Abre `index.html` y edita el bloque de configuración (cerca del final):

```js
window.SUPABASE_URL = "https://TU-PROYECTO.supabase.co";
window.SUPABASE_KEY = "TU-ANON-KEY";
window.ADMIN_PASS   = "jorjvana2026";        // cambia esta clave
window.WHATSAPP_ADMIN = "51987654321";
```

### 4) Tu QR de pago
Coloca la imagen **`yape.jpg`** junto al `index.html` (ya incluida).
Se muestra automáticamente en la sección de pago. Ajusta también el número que aparece en el HTML (busca "987 654 321").

### 5) Publicar en Vercel
**Opción A — Vercel CLI (rápido, sin GitHub):**
1. Instala la CLI: `npm install -g vercel`
2. Desde la carpeta del proyecto, ejecuta: `vercel`
3. Sigue las preguntas (acepta los valores por defecto: sin framework, directorio actual).
4. Para publicar a producción: `vercel --prod`
5. ¡Listo! Tendrás una URL pública tipo `https://jorjvana.vercel.app`.

**Opción B — Desde GitHub:**
1. Sube esta carpeta a un repositorio en GitHub.
2. Entra a **https://vercel.com** → **Add New → Project** → importa el repositorio.
3. Déjalo como proyecto estático (sin build command, *Output Directory* = `.`) y haz click en **Deploy**.

---

## 🧭 Cómo se usa

**Página principal** → muestra el evento, contador de entradas y botón de compra.

**Mi Cuenta** → el cliente crea una cuenta (correo + contraseña) o inicia sesión. Es el paso obligatorio antes de poder comprar: así sus compras quedan guardadas en su cuenta y puede volver más tarde a ver el estado de sus pagos y, cuando estén **APROBADOS**, sus entradas con código QR (con opción de descargar el PDF).

**Comprar** → solo disponible con sesión iniciada. El cliente llena sus datos, elige cantidad (el total se calcula solo), escanea el QR de Yape, sube su captura y registra la compra (queda **PENDIENTE**, asociada a su cuenta).

**Admin** (con la clave configurada en `ADMIN_PASS`) →
- Ve la lista de compradores, busca por nombre/DNI/teléfono.
- **Aprobar** un pago genera automáticamente las entradas con código y QR únicos (ej. `JORJ-2026-A8F7K2`).
- Descarga las entradas en **PDF**, o envíalas por **WhatsApp** / **correo**.
- Exporta todo a **Excel**.

**Validar QR** → en la puerta, desde cualquier celular:
- **Consultar**: muestra estado (VÁLIDA / UTILIZADA / ANULADA / NO EXISTE), nombre y código.
- **Registrar ingreso**: marca la entrada como **UTILIZADA**. Si la reescanean, avisa *"ENTRADA YA UTILIZADA"*.

---

## 🔒 Seguridad
- Los códigos QR son **aleatorios** (generados con `gen_random_bytes`), no predecibles.
- La generación verifica que no haya duplicados contra la base de datos.
- Cada entrada solo puede usarse **una vez** (la marca de ingreso se hace dentro de una función con bloqueo de fila).
- Para producción se recomienda proteger el panel admin con autenticación de Supabase (la versión actual usa una clave simple del lado del cliente).

> 💡 Para escanear con la cámara, Netlify sirve la página por **HTTPS**, requisito de los navegadores. Funciona en Android/iOS.
