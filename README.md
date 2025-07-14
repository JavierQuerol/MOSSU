# MOSSU: Mercadona Online Slack Status Updater para macOS

Este repositorio contiene tanto la aplicación de macOS como el pequeño backend que se despliega en Vercel. La app actualiza automáticamente tu estado de Slack según la Wi‑Fi o la localización, mientras que el backend gestiona el flujo de autenticación de Slack.

## Contenido del repositorio

- `MOSSU macos/` código Swift de la aplicación.
- `api/` funciones serverless para Vercel (OAuth de Slack).
- `public/` archivos generados para distribución (ZIP de la app y `appcast.xml`).
- `deploy.sh` script para compilar y firmar la app.

## Backend en Vercel

1. Crea una aplicación en Slack y configura el `redirect_uri` a
   `https://<tu-dominio>.vercel.app/api/slack/oauth/callback`.
2. En Vercel define las variables de entorno:
   - `SLACK_CLIENT_ID`
   - `SLACK_CLIENT_SECRET`
   - `SLACK_REDIRECT_URI` (debe coincidir con el `redirect_uri` de Slack)
   - `FRONTEND_URL` (URL base de la aplicación)
3. Despliega ejecutando:

```bash
npm install
vercel login
vercel --prod
```

El endpoint `/api/slack/oauth/callback` intercambia el `code` por el token y redirige a `mossu://oauth?token=...&user=...` para que la app lo reciba.

## Aplicación de macOS

Abre `SSU.xcodeproj` en Xcode y compila el target **MOSSU macos**. La app utiliza el esquema
personalizado `mossu://oauth` para recibir el token desde el backend anterior.
El fichero `Constants.swift` contiene los valores por defecto del `client_id`, los scopes y la URL de redirección.

Para distribuir la app puedes usar `deploy.sh`, que genera el ZIP firmado y un `appcast.xml` listo para Sparkle.

## Licencia

Consulta el archivo `LICENSE` para los términos de la licencia.

