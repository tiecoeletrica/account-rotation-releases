#!/bin/bash
# Instalador do Account Rotation para Mac. Roda uma vez, no Terminal:
#   curl -fsSL https://raw.githubusercontent.com/tiecoeletrica/account-rotation-releases/main/install.sh | bash
# Rodar de novo conserta a instalação (app, lançador, Node) sem apagar nada.
#
# Instala em ~/Library/Application Support/AccountRotation: o Node portátil, a última versão do app e o lançador.
# Instala o Google Chrome em ~/Applications se ele faltar. Cria "Account Rotation.app" em ~/Applications (aparece no
# Launchpad e no Spotlight) e abre o app. As atualizações depois disso o próprio app faz, ao abrir.
#
# Variáveis para teste: AR_RELEASES_URL (de onde baixar), AR_BASE (pasta da instalação), AR_APLICATIVOS (onde pôr o .app)
set -euo pipefail

RELEASES="${AR_RELEASES_URL:-https://github.com/tiecoeletrica/account-rotation-releases/releases/latest/download}"
RELEASES="${RELEASES%/}"
BASE="${AR_BASE:-$HOME/Library/Application Support/AccountRotation}"
APLICATIVOS="${AR_APLICATIVOS:-$HOME/Applications}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passo() { printf '\n\033[32m> %s\033[0m\n' "$1"; }
falha() { printf '\n\033[31mA instalação parou: %s\nRode o mesmo comando de novo. Se continuar, mande esta mensagem para o TI.\033[0m\n' "$1"; exit 1; }
trap 'falha "erro na linha $LINENO"' ERR
achar_chrome() {
  for d in "/Applications" "$HOME/Applications"; do
    [ -x "$d/Google Chrome.app/Contents/MacOS/Google Chrome" ] && { echo "$d/Google Chrome.app"; return 0; }
  done
  return 1
}
json() { "$BASE/node/bin/node" -e "let s='';process.stdin.on('data',c=>s+=c).on('end',()=>{const j=JSON.parse(s);console.log(j[process.argv[1]]??'')})" "$1"; }

printf '\033[36mInstalando o Account Rotation\033[0m\n'
mkdir -p "$BASE" "$APLICATIVOS"

# 1. Node portátil (a última LTS), dentro da pasta do app
if [ -x "$BASE/node/bin/node" ]; then passo "Node já instalado ($("$BASE/node/bin/node" --version))"
else
  case "$(uname -m)" in arm64) TIPO=darwin-arm64 ;; *) TIPO=darwin-x64 ;; esac
  VERSAO_NODE="$(curl -fsSL https://nodejs.org/dist/index.json | tr '{' '\n' | grep '"lts":"' | head -1 | sed -E 's/.*"version":"([^"]+)".*/\1/')"
  [ -n "$VERSAO_NODE" ] || falha "não consegui descobrir a versão do Node"
  passo "Baixando o Node $VERSAO_NODE..."
  curl -fsSL "https://nodejs.org/dist/$VERSAO_NODE/node-$VERSAO_NODE-$TIPO.tar.gz" -o "$TMP/node.tar.gz"
  tar -xzf "$TMP/node.tar.gz" -C "$TMP"
  rm -rf "$BASE/node"
  mv "$TMP/node-$VERSAO_NODE-$TIPO" "$BASE/node"
fi

# 2. Google Chrome (em ~/Applications, sem pedir senha, quando falta)
if achar_chrome >/dev/null; then passo "Google Chrome encontrado"
else
  passo "Instalando o Google Chrome..."
  curl -fsSL https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg -o "$TMP/chrome.dmg"
  MONTADO="$(hdiutil attach -nobrowse -readonly "$TMP/chrome.dmg" | tail -1 | sed -E 's/.*(\/Volumes\/.*)$/\1/')"
  cp -R "$MONTADO/Google Chrome.app" "$APLICATIVOS/"
  hdiutil detach "$MONTADO" -quiet || true
  achar_chrome >/dev/null || printf '\033[33mO Chrome não apareceu depois da instalação. O app abre no navegador padrão até ele ser instalado.\033[0m\n'
fi

# 3. O app: a última versão das Releases
ATUAL=""
[ -f "$BASE/current.json" ] && ATUAL="$(json version < "$BASE/current.json")"
if [ -n "$ATUAL" ] && [ -f "$BASE/versions/$ATUAL/app/server.mjs" ]; then passo "App já instalado (versão $ATUAL). As atualizações ele faz sozinho, ao abrir."
else
  curl -fsSL "$RELEASES/version.json" -o "$TMP/version.json"
  V="$(json version < "$TMP/version.json")"; ZIP="$(json zip < "$TMP/version.json")"; SHA="$(json sha256 < "$TMP/version.json")"
  passo "Baixando o app (versão $V)..."
  curl -fsSL "$RELEASES/$ZIP" -o "$TMP/app.zip"
  [ -z "$SHA" ] || [ "$(shasum -a 256 "$TMP/app.zip" | cut -d' ' -f1)" = "$SHA" ] || falha "o arquivo do app veio corrompido, rode o comando de novo"
  rm -rf "$BASE/versions/$V"; mkdir -p "$BASE/versions/$V"
  tar -xf "$TMP/app.zip" -C "$BASE/versions/$V"
  printf '{ "version": "%s", "installed_at": "%s" }\n' "$V" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BASE/current.json"
  ATUAL="$V"
fi

# 4. O lançador e os ícones, da versão instalada
VERSAO="$BASE/versions/$ATUAL"
cp "$VERSAO/launcher/start.mjs" "$VERSAO/launcher/carregando.html" "$VERSAO/launcher/statusline.mjs" "$VERSAO/app/public/icon.svg" "$VERSAO/app/public/icon-512.png" "$BASE/"

# 5. Account Rotation.app: um pacote mínimo que roda o lançador com o Node portátil (montado aqui, então o macOS não bloqueia)
passo "Criando o Account Rotation.app..."
APP="$APLICATIVOS/Account Rotation.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/MacOS/account-rotation" <<EOF
#!/bin/bash
# Abre o Account Rotation (criado pelo instalador). Fica aberto enquanto o app estiver aberto.
BASE="$BASE"
exec "\$BASE/node/bin/node" "\$BASE/start.mjs"
EOF
chmod +x "$APP/Contents/MacOS/account-rotation"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Account Rotation</string>
  <key>CFBundleDisplayName</key><string>Account Rotation</string>
  <key>CFBundleIdentifier</key><string>br.com.ecoeletrica.account-rotation</string>
  <key>CFBundleExecutable</key><string>account-rotation</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
EOF
# ícone .icns a partir do PNG
ICONES="$TMP/icon.iconset"; mkdir -p "$ICONES"
for t in 16 32 128 256 512; do
  sips -z $t $t "$BASE/icon-512.png" --out "$ICONES/icon_${t}x${t}.png" >/dev/null
  sips -z $((t * 2)) $((t * 2)) "$BASE/icon-512.png" --out "$ICONES/icon_${t}x${t}@2x.png" >/dev/null
done
iconutil -c icns "$ICONES" -o "$APP/Contents/Resources/icon.icns" || true
touch "$APP"

passo "Pronto! Abrindo o Account Rotation..."
echo "  Ao abrir, o app configura a statusline do Claude Code para ler o uso das contas (a que já existir continua aparecendo)."
open "$APP"
printf '\n\033[36mDaqui para frente, abra pelo "Account Rotation" no Launchpad, no Spotlight ou em ~/Applications.\033[0m\n'
