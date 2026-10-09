# Raíz del Territorio · proyecto Android

App de comercio directo entre productores rurales y consumidores (pitch Semillero Cero, Mariana Ávila).
Prototipo para el piloto: funciona sin conexión y guarda los datos en el teléfono. Los productores, productos y pedidos son de ejemplo y los pagos no se procesan.

- **Nombre de la app:** Raíz
- **ID del paquete:** `cl.ipchile.impulsa.raiz`
- **Versión:** 0.1.0
- **Tecnología:** Capacitor 8 (la app es una página web empaquetada como app Android nativa)

## Qué incluye

| Pantalla | Qué hace |
|---|---|
| Bienvenida | Elegir "Quiero comprar" o "Soy productor" |
| 01 Descubrir | Búsqueda, filtros (verificados, cerca, cooperativas), productor destacado y productos disponibles hoy |
| 02 Mapa regional | 9 productores alrededor de Puyehue, filtro por categoría, lista ordenada por distancia |
| 03 Perfil del productor | Sellos (origen verificado, intercultural), trazabilidad y catálogo |
| 04 Producto y origen | Reparto del precio a la vista: cuánto llega al productor y cuánto es comisión |
| 05 Pedido y pago | Carrito, "comercio justo a la vista", medio de pago y confirmación |
| 06 Panel del productor | Ventas y pedidos del mes, disponibilidad con un toque, avisos formativos, publicar y editar productos con foto, pedidos recibidos |

Modelo de comisión usado: 8 % por venta, repartido mitad y mitad (4 % incluido en el precio que paga el consumidor y 4 % lo asume el productor), más $3.500 de envío regional por pedido.

---

## Opción A · Generar el APK con GitHub (no hay que instalar nada)

1. Crea una cuenta en <https://github.com> si no tienes.
2. Crea un repositorio nuevo (por ejemplo `raiz-app`), puede ser privado.
3. Sube **todo el contenido de esta carpeta** (incluida la carpeta oculta `.github`).
   - La forma más simple: en el repositorio vacío, "uploading an existing file" y arrastra las carpetas.
   - Si la carpeta `.github` no se sube al arrastrar, créala a mano: *Add file → Create new file*, nombre `.github/workflows/apk.yml`, y pega el contenido del archivo `apk.yml`.
4. Ve a la pestaña **Actions**. Se ejecuta solo el flujo "Generar APK" (tarda unos 5 minutos). Si no parte, entra a "Generar APK" y pulsa **Run workflow**.
5. Cuando termine con ✓ verde, ve a **Releases → "Raíz · última versión"** y descarga `raiz.apk`. Desde el celular puedes abrir esa misma página y descargarlo directo.

Cada vez que subas un cambio a la rama `main`, se genera un APK nuevo.

## Opción B · Android Studio

1. Instala [Node.js 22](https://nodejs.org) y [Android Studio](https://developer.android.com/studio).
2. En esta carpeta: `npm install` y luego `npx cap sync android`.
3. `npx cap open android` abre el proyecto en Android Studio.
4. *Build → Build App Bundle(s) / APK(s) → Build APK(s)*. El archivo queda en `android/app/build/outputs/apk/debug/app-debug.apk`.

## Instalar el APK en un teléfono Android

1. Pasa `raiz.apk` al teléfono (descarga, WhatsApp, cable).
2. Ábrelo. Android pedirá permitir "instalar apps desconocidas" para esa aplicación (Chrome, Archivos o WhatsApp): acéptalo.
3. Instala y abre **Raíz**.

El APK es de prueba ("debug"): sirve para el piloto y para mostrar en presentaciones. Para publicarlo en Google Play hay que generar una versión firmada (release) y crear una cuenta de desarrollador en Play Console.

## Cambiar contenidos

Toda la app está en `www/index.html` (HTML, estilos y código en un solo archivo). Los datos de productores y productos están al inicio del código, en `PRODUCERS` y `BASE_PRODUCTS`. Después de editar, ejecuta `npx cap sync android` (o simplemente sube el cambio a GitHub y se genera el APK nuevo).

## Próximos pasos para un piloto real

- Base de datos y cuentas de usuario (por ejemplo Firebase o Supabase) para que productores y consumidores vean la misma información.
- Pasarela de pago (Webpay, Mercado Pago o Flow) con pago dividido al productor.
- Flujo de verificación con INDAP y cooperativas ancla.
- Mapa real con la ubicación de cada predio.
