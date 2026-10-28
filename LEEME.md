# Raíz Rutas

Es una guía territorial para el teléfono: el visitante recorre una ruta parada por parada y, al llegar a cada una, compra productos o reserva y paga experiencias que propone cada familia anfitriona.

- **App:** Raíz Rutas · paquete `cl.raizdelterritorio.rutas` · versión 0.2.0
- **Tecnología:** Capacitor 8 (Android) + Supabase (servidor, base de datos y cuentas)
- **Pagos:** en modo prueba. No se cobra dinero real.

## Cómo se genera el APK

Cada cambio que se sube a la rama `main` dispara el flujo **Generar APK** (pestaña *Actions*). Unos minutos después, el archivo `raiz-rutas.apk` queda en **Releases → "Raíz Rutas · última versión"**.

El APK se firma con una llave de prueba fija (`android/app/debug.keystore`), así que cada versión nueva se instala encima de la anterior. Esa llave **no** sirve para Google Play. Para publicar hay que generar una llave propia y guardarla como secreto.

## Configuración del servidor (una sola vez)

1. En Supabase, abre **SQL Editor → New query**, pega el contenido de `supabase/01_esquema.sql` y pulsa **Run**.
2. En otra consulta, pega `supabase/02_ruta_ejemplo.sql` y pulsa **Run**. Esto carga la ruta de ejemplo del Lago Budi.
3. Para el piloto, en **Authentication → Sign In / Providers → Email**, desactiva **Confirm email**. El correo gratuito de Supabase envía muy pocos mensajes por hora, y sin un dominio propio el enlace de confirmación no lleva de vuelta a la app.
4. Crea tu cuenta desde la app y luego conviértete en administrador de la red con esta consulta (cambia el correo):

   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'tu-correo@ejemplo.cl');
   ```

Los dos archivos SQL se pueden volver a ejecutar sin borrar reservas.

## Roles

| Rol | Qué hace |
|---|---|
| Visitante | Recorre la ruta, gana sellos, compra en el lugar, reserva y paga experiencias, cancela según la política de cada familia. |
| Anfitrión | Se registra desde "Soy anfitrión" y espera a que la red lo active. Luego ve sus reservas, valida códigos, abre o cierra su parada y propone experiencias con su propio precio. |
| Red (administrador) | Desde "Mi viaje → Panel de la red": activa anfitriones en su parada y aprueba o rechaza las experiencias nuevas. |

## Seguridad

- La app usa solo la clave **publicable** de Supabase.
- Las tablas tienen RLS activo y sin acceso directo. Todo pasa por funciones que revisan quién llama: un visitante ve solo sus reservas, y un anfitrión solo las de su parada.
- La capacidad de cada horario se controla en el servidor, así que dos personas no pueden tomar el mismo último cupo.
- Cada persona puede **eliminar su cuenta** desde la app (Google Play lo exige). Las reservas pagadas quedan sin datos personales.

## Archivos

- `www/index.html`: la app completa (pantallas, estilos y lógica).
- `supabase/`: esquema del servidor y datos de ejemplo.
- `android/`: proyecto nativo (permisos de ubicación, ícono, pantalla de inicio).
- `.github/workflows/apk.yml`: compilación automática.
