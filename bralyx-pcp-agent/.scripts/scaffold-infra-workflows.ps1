# Scaffolds the Bralyx infra workflows from the Welmy reference project by
# cloning the 1:1 (non-domain) workflows and applying safe token replacements.
# Domain workflows (Bridge, Agent, Relatorio) and the front are authored separately.
$ErrorActionPreference = 'Stop'

$srcDir = 'c:\Users\Administrador\Downloads\Bralynx\welmy-pcp-agent\workspaces'
$dstDir = 'c:\Users\Administrador\Downloads\Bralynx\bralyx-pcp-agent\workspaces'
New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

# file map: Welmy source -> Bralyx target (only the 1:1 infra workflows)
$map = @{
  'Welmy-AdminUser.json'          = 'Bralyx-AdminUser.json'
  'Welmy-Chat-GET-Sessions.json'  = 'Bralyx-Chat-GET-Sessions.json'
  'Welmy-Chat-GET-History.json'   = 'Bralyx-Chat-GET-History.json'
  'Welmy-Chat-DELETE-Session.json'= 'Bralyx-Chat-DELETE-Session.json'
  'Welmy-RAG.json'                = 'Bralyx-RAG.json'
  'Welmy-RAG-Admin.json'          = 'Bralyx-RAG-Admin.json'
}

function Convert-Tokens([string]$s) {
  # order matters: uppercase/placeholder forms before generic lowercase
  $s = $s -creplace 'REPLACE_ME_WELMY_DB', 'REPLACE_ME_BRALYX_DB'
  $s = $s -creplace 'WELMY', 'BRALYX'
  $s = $s -creplace 'Welmy', 'Bralyx'
  $s = $s -creplace 'welmy', 'bralyx'
  $s = $s -creplace 'wl_', 'bx_'            # infra tables/functions map 1:1 (wl_documents->bx_documents, etc.)
  $s = $s -creplace '139W-HfLxR7y3XzFHv8VULfy8tnTZ2FcO', '18enOlOFXT_r4TH5w7cC16fYhfls7PItB'
  return $s
}

foreach ($k in $map.Keys) {
  $src = Join-Path $srcDir $k
  $dst = Join-Path $dstDir $map[$k]
  if (-not (Test-Path $src)) { Write-Warning "missing $src"; continue }
  $txt = [System.IO.File]::ReadAllText($src)
  $txt = Convert-Tokens $txt
  [System.IO.File]::WriteAllText($dst, $txt)
  Write-Host ("scaffolded {0} -> {1}" -f $k, $map[$k])
}
Write-Host 'done.'
