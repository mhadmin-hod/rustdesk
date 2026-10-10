#!/usr/bin/env bash
# Passt den RustDesk-Quellcode fuer den RD-Quicksupport-Client an.
# Aufruf aus dem Repo-Root:  bash .github/quicksupport/apply.sh <windows|linux>
set -euo pipefail

PLATFORM="${1:?Plattform angeben: windows oder linux}"
QS_DIR=".github/quicksupport"
# shellcheck source=config.env
source "$QS_DIR/config.env"

CONFIG_RS="libs/hbb_common/src/config.rs"

fail() { echo "::error::$*"; exit 1; }

# Ersetzt per Perl-Regex und bricht ab, wenn das Muster nicht gefunden wurde.
patch_file() {
  local file="$1" pattern="$2" replacement="$3"
  [ -f "$file" ] || fail "Datei fehlt: $file"
  PAT="$pattern" REP="$replacement" perl -0777 -i -pe '
    BEGIN { $n = 0 }
    $n += s/$ENV{PAT}/$ENV{REP}/g;
    END { exit($n ? 0 : 3) }
  ' "$file" || fail "Muster nicht gefunden in $file: $pattern"
}

echo "== Server und Key"
patch_file "$CONFIG_RS" \
  'pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[[^\]]*\];' \
  "pub const RENDEZVOUS_SERVERS: &[&str] = &[\"$QS_SERVER\"];"
patch_file "$CONFIG_RS" \
  'pub const RS_PUB_KEY: &str = "[^"]*";' \
  "pub const RS_PUB_KEY: &str = \"$QS_KEY\";"

echo "== Update-Pruefung gegen offizielle Releases abschalten"
# Sonst wuerde ein offizielles Update den Client ohne eingebauten Server ersetzen.
patch_file "src/common.rs" \
  'pub fn check_software_update\(\) \{\n    if is_custom_client\(\) \{' \
  $'pub fn check_software_update() {\n    if true || is_custom_client() {'

echo "== Icons"
for f in icon.png icon.ico tray-icon.ico 32x32.png 64x64.png 128x128.png 128x128@2x.png; do
  cp "$QS_DIR/icons/$f" "res/$f"
done
cp "$QS_DIR/icons/icon.svg" res/scalable.svg
cp "$QS_DIR/icons/icon.svg" flutter/assets/icon.svg

if [ "$PLATFORM" = "windows" ]; then
  echo "== App-Name: $QS_APP_NAME"
  patch_file "$CONFIG_RS" \
    'pub static ref APP_NAME: RwLock<String> = RwLock::new\("RustDesk"\.to_owned\(\)\);' \
    "pub static ref APP_NAME: RwLock<String> = RwLock::new(\"$QS_APP_NAME\".to_owned());"

  for toml in Cargo.toml libs/portable/Cargo.toml; do
    patch_file "$toml" 'ProductName = "RustDesk"' "ProductName = \"$QS_APP_NAME\""
    patch_file "$toml" 'FileDescription = "RustDesk Remote Desktop"' "FileDescription = \"$QS_APP_NAME\""
    patch_file "$toml" 'OriginalFilename = "rustdesk\.exe"' "OriginalFilename = \"$QS_APP_NAME.exe\""
  done
  patch_file libs/portable/src/main.rs \
    'const APP_PREFIX: &str = "rustdesk";' \
    "const APP_PREFIX: &str = \"$QS_APP_NAME\";"

  RC=flutter/windows/runner/Runner.rc
  patch_file "$RC" '"RustDesk Remote Desktop"' "\"$QS_APP_NAME\""
  patch_file "$RC" 'VALUE "InternalName", "rustdesk"' "VALUE \"InternalName\", \"$QS_APP_NAME\""
  patch_file "$RC" '"rustdesk\.exe"' "\"$QS_APP_NAME.exe\""
  patch_file "$RC" 'VALUE "ProductName", "RustDesk"' "VALUE \"ProductName\", \"$QS_APP_NAME\""

  cp "$QS_DIR/icons/icon.ico" flutter/windows/runner/resources/app_icon.ico
fi

echo "== Kontrolle"
grep -nE 'APP_NAME: RwLock|RENDEZVOUS_SERVERS:|RS_PUB_KEY:' "$CONFIG_RS"
echo "Fertig ($PLATFORM)."
