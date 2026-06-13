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
| `api/enviar-entradas.js` | Función serverless (Vercel) que envía el PDF de entradas por correo |

---

## 🚀 Pasos de instalación (15 min)

### 1) Crear la base de datos en Supabase
1. Entra a **https://supabase.com** → crea una cuenta gratuita → **New Project**.
2. Cuando esté listo, ve a **SQL Editor → New query**.
3. Copia y pega TODO el contenido de `supabase_schema.sql` y presiona **Run**.
   Esto crea las tablas (compradores, entradas, validaciones), las funciones y el bucket de comprobantes.

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

### 6) Envío de entradas por correo (opcional)
El botón **✉ Enviar por correo** del panel admin envía el PDF de entradas al correo del comprador usando tu cuenta de Gmail (`davidalexandermanriquevilchez@gmail.com`). Para activarlo:

1. Activa la **verificación en 2 pasos** en esa cuenta de Gmail: **https://myaccount.google.com/security**.
2. Genera una **contraseña de aplicación**: **https://myaccount.google.com/apppasswords** (elige "Correo" → "Otra", ej. "JORJVANA").
3. En Vercel: **Project → Settings → Environment Variables**, agrega:
   - `GMAIL_USER` = tu correo de Gmail (ej. `davidalexandermanriquevilchez@gmail.com`)
   - `GMAIL_APP_PASSWORD` = la contraseña de aplicación generada (16 caracteres, sin espacios)
4. Vuelve a desplegar (**Redeploy**) para que los cambios surtan efecto.

Si estas variables no están configuradas, el botón mostrará un error indicando que el envío de correos no está habilitado.

---

## 🧭 Cómo se usa

**Página principal** → muestra el evento, contador de entradas y botón de compra.

**Comprar** → no requiere crear cuenta ni iniciar sesión. El cliente llena sus datos, elige cantidad (el total se calcula solo), escanea el QR de Yape, sube su captura y registra la compra directamente en `public.compradores` (queda **PENDIENTE**). El comprador recibirá sus entradas por WhatsApp o correo una vez que el pago sea **APROBADO** desde el panel admin.

**Admin** (con la clave configurada en `ADMIN_PASS`) →
- Ve la lista de compradores, busca por nombre/DNI/teléfono.
- **Aprobar** un pago genera automáticamente las entradas con código y QR únicos (ej. `JORJ-2026-A8F7K2`).
- Descarga las entradas en **PDF**, o envíalas por **WhatsApp** / **correo**.
- Exporta todo a **Excel**.
- En **📊 Estadísticas** puede **aumentar o reducir el aforo total** (cantidad de entradas disponibles para la venta) sin afectar las entradas ya vendidas.

**Validar QR** → en la puerta, desde cualquier celular:
- Acceso restringido: pide un **código de validador**. El administrador (clave `ADMIN_PASS`) puede crear, activar/desactivar o eliminar estos códigos desde **Admin → 👮 Validadores de QR**, uno por cada persona que ayudará en la puerta. El administrador también puede entrar aquí con su propia clave.
- **Consultar**: muestra estado (VÁLIDA / UTILIZADA / ANULADA / NO EXISTE), nombre y código.
- **Registrar ingreso**: marca la entrada como **UTILIZADA**. Si la reescanean, avisa *"ENTRADA YA UTILIZADA"*.

---

## 🔒 Seguridad
- Los códigos QR son **aleatorios** (generados con `gen_random_bytes`), no predecibles.
- La generación verifica que no haya duplicados contra la base de datos.
- Cada entrada solo puede usarse **una vez** (la marca de ingreso se hace dentro de una función con bloqueo de fila).
- Para producción se recomienda proteger el panel admin con autenticación de Supabase (la versión actual usa una clave simple del lado del cliente).

> 💡 Para escanear con la cámara, Netlify sirve la página por **HTTPS**, requisito de los navegadores. Funciona en Android/iOS.
