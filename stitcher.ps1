<#
.SYNOPSIS
    Downloads and stitches fragmented MP4 audio from a CDN.

.DESCRIPTION
    Fetches 'init.mp4' + all 'segment_n.m4s' files for a given song ID,
    renames them with zero-padded indices so Windows sorts them correctly,
    then concatenates everything into a single playable .mp4 audio file.

.PARAMETER Id
    The song hash/ID (e.g. 74876574-4bcb-486f-a20d-8a4c556607a7)

.PARAMETER Output
    Output filename without extension. Defaults to the song ID if omitted.

.PARAMETER Bitrate
    Bitrate folder to use. Defaults to 192k.

.PARAMETER BaseUrl
    CDN base URL. Defaults to https://cdn.musicgpt.com/conversions/standard

.PARAMETER KeepSegments
    If set, the temporary segment files are not deleted after stitching.

.EXAMPLE executed within directory of the powershell file or if microslop says you aren't allowed to run RemoteSigned scripts
    .\<powershell-file-name>.ps1 -Id 74876574-4bcb-486f-a20d-8a4c556607a7
    .\<powershell-file-name>.ps1 -Id 74876574-4bcb-486f-a20d-8a4c556607a7 -Output my_song
    .\<powershell-file-name>.ps1 -Id 74876574-4bcb-486f-a20d-8a4c556607a7 -Bitrate 64k -KeepSegments
    powershell -ExecutionPolicy Bypass -File .\<powershell-file-name>.ps1 74876574-4bcb-486f-a20d-8a4c556607a7 "output file name"
#>
param(
    [Parameter(Position=0)]
    [string]$Id = "",

    [Parameter(Position=1)]
    [string]$Output = "",

    [string]$Bitrate = "192k",
    [string]$Cdn = "",
    [string]$Url = "",
    [switch]$KeepSegments
)

# resolve base url
# priority: -Url (full base) > -Id (with optional -Cdn and -Bitrate)
if ($Url -ne "") {
    # full base url provided directly, strip any trailing slash
    $Base = $Url.TrimEnd("/")
    # derive an output name from the last meaningful path segment if not specified
    if ($Output -eq "") {
        $Output = ($Base -split "/")[-1]
        # if last segment looks like a bitrate (e.g. 192k), go one level up
        if ($Output -match '^\d+k$') {
            $Output = ($Base -split "/")[-2]
        }
    }
} elseif ($Id -ne "") {
    # build cdn hostname: cdn / cdn1 / cdn2 etc.
    $cdnHost = if ($Cdn -eq "") { "cdn" } else { "cdn$Cdn" }
    $Base = "https://$cdnHost.musicgpt.com/conversions/standard/$Id/$Bitrate"
    if ($Output -eq "") { $Output = $Id }
} else {
    Write-Host "ERROR: Provide either -Id <hash> or -Url <base-url>." -ForegroundColor Red
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\Stitch-Music.ps1 -Id 16bf2b7f-73b7-4c02-a6f5-07923bffb2af"
    Write-Host "  .\Stitch-Music.ps1 -Id 16bf2b7f-73b7-4c02-a6f5-07923bffb2af -Cdn 2"
    Write-Host "  .\Stitch-Music.ps1 -Url https://cdn3.musicgpt.com/conversions/standard/16bf2b7f-73b7-4c02-a6f5-07923bffb2af/192k"
    exit 1
}

$OutputFile = "$Output.mp4"

Write-Host "Base URL : $Base" -ForegroundColor DarkGray
Write-Host "Output   : $OutputFile" -ForegroundColor DarkGray
Write-Host ""

function TryDownload($Url, $Dest) {
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        if (Test-Path $Dest) { Remove-Item $Dest -Force }
        return $false
    }
}

# download init
Write-Host "`nDownloading init.mp4..." -ForegroundColor Cyan
if (-not (TryDownload "$Base/init.mp4" "init.mp4")) {
    Write-Host "ERROR: Could not download init.mp4. Check your ID and bitrate, also make sure the (base) URL matches '$BaseUrl', and is not e.g. 'cdn1' or another CDN." -ForegroundColor Red
    exit 1
}
Write-Host "  OK  init.mp4"

# download segments
Write-Host "Downloading segments..." -ForegroundColor Cyan
$i = 0
$segments = @()
while ($true) {
    $name = "segment_$i.m4s"
    if (TryDownload "$Base/$name" $name) {
        Write-Host "  OK  $name"
        $segments += $name
        $i++
    } else {
        Write-Host "  --  segment_$i not found, stopping." -ForegroundColor Yellow
        break
    }
}

if ($segments.Count -eq 0) {
    Write-Host "ERROR: No segments downloaded." -ForegroundColor Red
    exit 1
}
Write-Host "$($segments.Count) segment(s) downloaded." -ForegroundColor Green

# convert for lexicographical fs
$padWidth = ($segments.Count - 1).ToString().Length
$renamed = @()
if ($padWidth -gt 1) {
    Write-Host "Renaming for correct sort order..." -ForegroundColor Cyan
    for ($j = 0; $j -lt $segments.Count; $j++) {
        $padded = "segment_" + $j.ToString().PadLeft($padWidth, '0') + ".m4s"
        if ($segments[$j] -ne $padded) {
            Rename-Item -Path $segments[$j] -NewName $padded -Force
            Write-Host "  $($segments[$j]) -> $padded"
        }
        $renamed += $padded
    }
} else {
    $renamed = $segments
}

# stitch
Write-Host "Stitching into '$OutputFile'..." -ForegroundColor Cyan
$allFiles = @("init.mp4") + $renamed
$copyArg = ($allFiles | ForEach-Object { "`"$_`"" }) -join " + "
cmd /c "copy /B $copyArg `"$OutputFile`"" | Out-Null

if (Test-Path $OutputFile) {
    $kb = [math]::Round((Get-Item $OutputFile).Length / 1KB, 1)
    Write-Host "Done! $OutputFile ($kb KB)" -ForegroundColor Green
} else {
    Write-Host "ERROR: Stitching failed.`nMake sure that:`n  * The output file name is valid`n  * There are no duplicate segments in the directory`n  * All necessary files exist (init.mp4, segment_x.m4s)" -ForegroundColor Red
    exit 1
}

# cleanup
if (-not $KeepSegments) {
    Write-Host "Cleaning up..." -ForegroundColor Cyan
    Remove-Item "init.mp4" -Force
    $renamed | ForEach-Object { Remove-Item $_ -Force }
}

Write-Host "All done! Output: $OutputFile" -ForegroundColor Green
