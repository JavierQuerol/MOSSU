#!/bin/bash

set -euo pipefail

# On error, show a helpful message
trap 'echo "❌ Error en deploy.sh (línea $LINENO). Revisa los logs arriba." >&2' ERR

APP_NAME="MOSSU"
SCHEME="MOSSU"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
PUBLIC_PATH="public"
PLIST_PATH="MOSSU macos/Info.plist"
ZIP_PATH="${PUBLIC_PATH}/${APP_NAME}.zip"
SIGN_IDENTITY="Developer ID Application: Javier Querol Morata (4385X6LBF4)"
DEPLOYMENT_SERVER="Vercel"

# Notarization credentials (choose one method):
# - Keychain profile created with: xcrun notarytool store-credentials
export NOTARYTOOL_PROFILE="AC MOSSU"
# - App Store Connect API key (preferred):
#   export AC_API_KEY_ID=...; export AC_API_ISSUER_ID=...; export AC_API_KEY_PATH=.../AuthKey_XXXXXX.p8
# - Apple ID fallback (requires app-specific password):
#   export APPLE_ID=...; export APP_SPECIFIC_PASSWORD=...; export APPLE_TEAM_ID=...

# Optional: Sparkle EdDSA private key for signing appcast updates
#   export SPARKLE_PRIVATE_KEY_PATH="$HOME/.sparkle/EdDSA.priv"

# Incrementar el número de build de forma consistente con AGVTool
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST_PATH" 2>/dev/null || echo 0)
if [[ -z "$CURRENT_BUILD" ]]; then CURRENT_BUILD=0; fi
NEW_BUILD=$((CURRENT_BUILD + 1))
xcrun agvtool new-version -all "$NEW_BUILD" > /dev/null

# Incrementar la versión de marketing
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST_PATH")
MAJOR=$(echo $CURRENT_VERSION | cut -d. -f1)
MINOR=$(echo $CURRENT_VERSION | cut -d. -f2)
NEW_MINOR=$((MINOR + 1))
NEW_VERSION="${MAJOR}.${NEW_MINOR}"

# Actualizar tanto el Info.plist como la configuración de Xcode
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $NEW_VERSION" "$PLIST_PATH"

# Actualizar MARKETING_VERSION directamente en el archivo project.pbxproj
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/g" "MOSSU.xcodeproj/project.pbxproj"

echo "Actualizado al build: $NEW_BUILD y versión: $NEW_VERSION"

echo "🛠 Archivando la app..."
xcodebuild -quiet -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -sdk macosx \
  clean archive

echo "📦 Exportando la app desde el archive..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app" "$EXPORT_PATH"

echo "🔏 Firmando la app con hardened runtime..."
codesign --force --deep --options runtime --timestamp \
  --entitlements "MOSSU macos/MOSSU.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "🔎 Verificando la firma..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SUBMISSION_ZIP="build/${APP_NAME}-notary-submission.zip"

echo "📦 Preparando ZIP temporal para envío a notarización..."
rm -f "$SUBMISSION_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"

echo "🧾 Enviando a notarizar (ZIP temporal)..."
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "$SUBMISSION_ZIP" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait --output-format normal
elif [[ -n "${AC_API_KEY_ID:-}" && -n "${AC_API_ISSUER_ID:-}" && -n "${AC_API_KEY_PATH:-}" ]]; then
  xcrun notarytool submit "$SUBMISSION_ZIP" \
    --key "$AC_API_KEY_PATH" \
    --key-id "$AC_API_KEY_ID" \
    --issuer "$AC_API_ISSUER_ID" \
    --wait --output-format normal
elif [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  xcrun notarytool submit "$SUBMISSION_ZIP" \
    --apple-id "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait --output-format normal
else
  echo "⚠️  No hay credenciales para notarización. Define NOTARYTOOL_PROFILE o AC_API_* o APPLE_ID/APP_SPECIFIC_PASSWORD/APPLE_TEAM_ID." >&2
  exit 1
fi

echo "📎 Aplicando staple a la app..."
xcrun stapler staple -v "$APP_PATH"

echo "🧪 Validando Gatekeeper (spctl)..."
spctl --assess --type execute --verbose=2 "$APP_PATH" || true

echo "🚮 Borrando el fichero appcast.xml"
# Mantén el histórico si lo necesitas; por defecto Sparkle reescribe entradas.
# rm -f "$PUBLIC_PATH/appcast.xml"

echo "📁 Comprimendo la app para Sparkle (ZIP final)..."
mkdir -p "$PUBLIC_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "📎 Aplicando staple al ZIP final..."
xcrun stapler staple -v "$ZIP_PATH" || true

echo "🧪 Validando staple (app y zip)..."
xcrun stapler validate "$APP_PATH" || true
xcrun stapler validate "$ZIP_PATH" || true

echo "🔐 Firmando (Sparkle) y generando el appcast..."
if command -v generate_appcast >/dev/null 2>&1; then
  if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
    APPCAST=$(generate_appcast --ed25519-private-key "$SPARKLE_PRIVATE_KEY_PATH" "$PUBLIC_PATH")
  else
    APPCAST=$(generate_appcast "$PUBLIC_PATH")
  fi
else
  echo "⚠️  'generate_appcast' no está en PATH. Instala las utilidades de Sparkle 2 y vuelve a ejecutar." >&2
  exit 1
fi

echo "✅ Appcast actualizado: $APPCAST"
echo "🚀 Todo listo. Archivo zip y appcast generados en 'public/'"
echo "⬆ Actualizando el repo con la app y el appcast"
git add .
git commit -m "new version of $APP_NAME"
git push

echo "Servidor $DEPLOYMENT_SERVER actualizado "
