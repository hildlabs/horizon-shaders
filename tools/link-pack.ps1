# Links the Daybreak pack into Horizon's shaderpacks folder as a directory junction, so the game
# hot-reloads every file you save here. Run it once:  powershell -File tools\link-pack.ps1
param(
    # The instance folder: where options.txt is.
    [string]$Instance = "$env:APPDATA\horizon"
)

$pack = Join-Path $PSScriptRoot "..\pack\daybreak" | Resolve-Path
$packs = Join-Path $Instance "shaderpacks"
$link = Join-Path $packs "daybreak"

if (-not (Test-Path (Join-Path $Instance "options.txt"))) {
    throw "No options.txt in ${Instance}: pass -Instance <your instance folder>."
}
New-Item -ItemType Directory -Force $packs | Out-Null
if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -eq "Junction" -and $item.Target -contains $pack.Path) {
        Write-Host "Already linked: $link -> $pack"
        exit 0
    }
    throw "$link exists and is not a link to this pack: move it away first."
}
New-Item -ItemType Junction -Path $link -Target $pack | Out-Null
Write-Host "Linked $link -> $pack"
Write-Host "In the game: Options > Horizon Settings > Shader Packs > Daybreak (Horizon)."
