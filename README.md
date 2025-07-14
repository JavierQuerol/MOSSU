# MOSSU: Mercadona Online Slack Status Updater para macOS

Este repositorio contiene tanto la aplicación de macOS como un pequeño backend que se puede desplegar en cualquier servicio de hosting compatible con funciones serverless (como Vercel, Netlify o similares). La app actualiza automáticamente tu estado de Slack según la Wi‑Fi o la localización, mientras que el backend gestiona el flujo de autenticación de Slack.

## Contenido del repositorio

- `MOSSU macos/` código Swift de la aplicación.
- `api/` funciones serverless para Vercel (OAuth de Slack).
- `public/` archivos generados para distribución (ZIP de la app y `appcast.xml`).
- `deploy.sh` script para compilar y firmar la app.

## Backend (autenticación de Slack)

1. Crea una aplicación en Slack y configura el `redirect_uri` a la ruta de tu backend, por ejemplo:
   `https://<tu-dominio>/api/slack/oauth/callback`.

2. Define las siguientes variables de entorno en tu plataforma de despliegue:
   - `SLACK_CLIENT_ID`
   - `SLACK_CLIENT_SECRET`
   - `SLACK_REDIRECT_URI` (debe coincidir con el `redirect_uri` de Slack)
   - `FRONTEND_URL` (URL base de la aplicación)

3. Despliega el backend siguiendo los pasos habituales de tu plataforma. Si usas Node.js:

```bash
npm install
npm run build
npm start
```

El endpoint `/api/slack/oauth/callback` intercambia el `code` por el token y redirige a `mossu://oauth?token=...&user=...` para que la app lo reciba.

## Aplicación de macOS

Abre `SSU.xcodeproj` en Xcode y compila el target **MOSSU macos**. La app utiliza el esquema
personalizado `mossu://oauth` para recibir el token desde el backend anterior.
El fichero `Constants.swift` contiene los valores por defecto del `client_id`, los scopes y la URL de redirección.

Para distribuir la app puedes usar `deploy.sh`, que genera el ZIP firmado y un `appcast.xml` listo para Sparkle.

## Licencia

Consulta el archivo `LICENSE` para los términos de la licencia.
