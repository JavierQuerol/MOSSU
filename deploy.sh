#!/bin/bash

set -e

APP_NAME="MOSSU"
SCHEME="MOSSU"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
PUBLIC_PATH="public"
PLIST_PATH="MOSSU macos/Info.plist"
ZIP_PATH="${PUBLIC_PATH}/${APP_NAME}.zip"
SIGN_IDENTITY="Apple Development: Javier Querol Morata (VWXPT76R65)"
DEPLOYMENT_SERVER="Vercel"

xcrun agvtool bump -all > /dev/null
NEW_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST_PATH")
echo "Actualizado en el proyecto y en el target al build: $NEW_BUILD"

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

echo "🚮 Borrando el fichero appcast.xml"
#rm -f "$PUBLIC_PATH/appcast.xml"

echo "🔐 Firmando y generando el appcast con Sparkle..."
APPCAST=$(generate_appcast "$PUBLIC_PATH")

echo "✅ Appcast actualizado: $APPCAST"
echo "🚀 Todo listo. Archivo zip y appcast generados en 'public/'"
echo "⬆ Actualizando el repo con la app y el appcast"
git add .
git commit -m "new version of $APP_NAME"
git push

echo "Servidor $DEPLOYMENT_SERVER actualizado "




