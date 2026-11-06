# Instalador do Account Rotation para Windows. Roda uma vez, num PowerShell comum (sem administrador):
#   irm https://raw.githubusercontent.com/tiecoeletrica/account-rotation-releases/main/install.ps1 | iex
# (do repositório, e não da Release: lá o GitHub entrega como texto UTF-8, e os acentos chegam certos)
# Rodar de novo conserta a instalação (atalhos, lançador, Node) sem apagar nada.
#
# Instala em %LOCALAPPDATA%\AccountRotation: o Node portátil, a última versão do app e o lançador. Instala o Google Chrome
# (só para o usuário) se ele faltar. Cria o atalho "Account Rotation" na área de trabalho e no menu Iniciar, e abre o app.
# As atualizações depois disso o próprio app faz, ao abrir.
#
# Variáveis para teste: AR_RELEASES_URL (de onde baixar), AR_BASE (pasta da instalação), AR_ATALHOS (pasta dos atalhos)
& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # a barra de progresso deixa o download muito mais lento no PowerShell 5
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Releases = if ($env:AR_RELEASES_URL) { $env:AR_RELEASES_URL.TrimEnd('/') } else { 'https://github.com/tiecoeletrica/account-rotation-releases/releases/latest/download' }
$Base = if ($env:AR_BASE) { $env:AR_BASE } else { Join-Path $env:LOCALAPPDATA 'AccountRotation' }
$Atalhos = if ($env:AR_ATALHOS) { @($env:AR_ATALHOS) } else { @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs')) }

function Passo($t) { Write-Host "`n> $t" -ForegroundColor Green }
function Baixar($url, $destino) { Invoke-WebRequest $url -OutFile $destino -UseBasicParsing }
function AcharChrome {
  @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ } |
    ForEach-Object { Join-Path $_ 'Google\Chrome\Application\chrome.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
}

try {
  Write-Host 'Instalando o Account Rotation' -ForegroundColor Cyan
  New-Item -ItemType Directory -Force $Base | Out-Null
  $tmp = Join-Path $env:TEMP ("ar-instalador-" + (Get-Random))
  New-Item -ItemType Directory -Force $tmp | Out-Null

  # 1. Node portátil (a última LTS), dentro da pasta do app
  $node = Join-Path $Base 'node\node.exe'
  if (Test-Path $node) { Passo "Node já instalado ($(& $node --version))" }
  else {
    $tipo = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
    # guardar antes de filtrar: no PowerShell 5 a lista que o irm devolve não se abre item a item no pipe
    $versoes = Invoke-RestMethod 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $lts = $versoes | Where-Object { $_.lts -and $_.files -contains "$tipo-zip" } | Select-Object -First 1
    $nome = "node-$($lts.version)-$tipo"
    Passo "Baixando o Node $($lts.version)..."
    Baixar "https://nodejs.org/dist/$($lts.version)/$nome.zip" "$tmp\node.zip"
    tar.exe -xf "$tmp\node.zip" -C $tmp
    if ($LASTEXITCODE -ne 0) { throw 'não consegui abrir o zip do Node' }
    Remove-Item (Join-Path $Base 'node') -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item "$tmp\$nome" (Join-Path $Base 'node')
  }

  # 2. Google Chrome (instalado só para o usuário quando falta)
  if (AcharChrome) { Passo 'Google Chrome encontrado' }
  else {
    Passo 'Instalando o Google Chrome...'
    Baixar 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' "$tmp\chrome_installer.exe"
    Start-Process "$tmp\chrome_installer.exe" -ArgumentList '/silent', '/install' -Wait
    for ($i = 0; $i -lt 30 -and -not (AcharChrome); $i++) { Start-Sleep -Seconds 2 }
    if (-not (AcharChrome)) { Write-Warning 'O Chrome não apareceu depois da instalação. O app abre no navegador padrão até ele ser instalado.' }
  }

  # 3. O app: a última versão das Releases
  $atual = $null
  try { $atual = (Get-Content (Join-Path $Base 'current.json') -Raw | ConvertFrom-Json).version } catch { }
  if ($atual -and (Test-Path (Join-Path $Base "versions\$atual\app\server.mjs"))) { Passo "App já instalado (versão $atual). As atualizações ele faz sozinho, ao abrir." }
  else {
    $info = Invoke-RestMethod "$Releases/version.json" -UseBasicParsing
    $v = $info.version
    Passo "Baixando o app (versão $v)..."
    Baixar "$Releases/$($info.zip)" "$tmp\app.zip"
    $sha = (Get-FileHash "$tmp\app.zip" -Algorithm SHA256).Hash.ToLower()
    if ($info.sha256 -and $sha -ne $info.sha256) { throw 'o arquivo do app veio corrompido, rode o comando de novo' }
    $destino = Join-Path $Base "versions\$v"
    Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $destino | Out-Null
    tar.exe -xf "$tmp\app.zip" -C $destino
    if ($LASTEXITCODE -ne 0) { throw 'não consegui abrir o zip do app' }
    @{ version = $v; installed_at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Base 'current.json') -Encoding ASCII
    $atual = $v
  }

  # 4. O lançador e os ícones, da versão instalada
  $versao = Join-Path $Base "versions\$atual"
  Copy-Item "$versao\launcher\start.mjs", "$versao\launcher\carregando.html" $Base -Force
  Copy-Item "$versao\app\public\icon.svg", "$versao\app\public\icon-512.png", "$versao\app\public\icon.ico" $Base -Force
  # abre o lançador sem janela de console
  @'
' Abre o Account Rotation sem janela de console (criado pelo instalador)
Set fso = CreateObject("Scripting.FileSystemObject")
pasta = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = pasta
sh.Run """" & pasta & "\node\node.exe"" """ & pasta & "\start.mjs""", 0, False
'@ | Set-Content (Join-Path $Base 'start.vbs') -Encoding ASCII

  # 5. Atalhos
  Passo 'Criando os atalhos...'
  $ws = New-Object -ComObject WScript.Shell
  foreach ($pasta in $Atalhos) {
    New-Item -ItemType Directory -Force $pasta | Out-Null
    $l = $ws.CreateShortcut((Join-Path $pasta 'Account Rotation.lnk'))
    $l.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $l.Arguments = '"' + (Join-Path $Base 'start.vbs') + '"'
    $l.WorkingDirectory = $Base
    $l.IconLocation = (Join-Path $Base 'icon.ico') + ',0'
    $l.Description = 'Rodízio das contas do Claude Code'
    $l.Save()
  }

  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Passo 'Pronto! Abrindo o Account Rotation...'
  Start-Process (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $Base 'start.vbs') + '"')
  Write-Host "`nDaqui para frente, abra pelo atalho 'Account Rotation' na área de trabalho ou no menu Iniciar." -ForegroundColor Cyan
}
catch {
  Write-Host "`nA instalação parou: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Rode o mesmo comando de novo. Se continuar, mande esta mensagem para o TI.' -ForegroundColor Red
}
}
