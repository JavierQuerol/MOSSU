#!/bin/bash

set -e

APP_NAME="MOSSU"
SCHEME="MOSSU"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
PUBLIC_PATH="public"
ZIP_PATH="${PUBLIC_PATH}/${APP_NAME}.zip"
SIGN_IDENTITY="Apple Development: Javier Querol Morata (VWXPT76R65)"
DEPLOYMENT_SERVER="Vercel"

echo "🛠 Archivando la app..."
xcodebuild -quiet -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -sdk macosx \
  clean archive

echo "📦 Exportando la app desde el archive..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app" "$EXPORT_PATH"

echo "🔏 Firmando la app (si procede)..."
codesign --deep --force --verify \
  --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "📁 Comprimendo la app para Sparkle..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "🔐 Generando firma con Sparkle..."
rm "$PUBLICPATH/appcast.xml"
APPCAST=$(generate_appcast "$PUBLIC_PATH")

echo "✅ Appcast actualizado: $APPCAST"
echo "🚀 Todo listo. Archivo zip y appcast generados en 'public/'"
echo "⬆ Actualizando el repo con la app y el appcast"
git add .
git commit -m "new version of $APP_NAME"
git push

echo "Servidor $DEPLOYMENT_SERVER actualizado "
