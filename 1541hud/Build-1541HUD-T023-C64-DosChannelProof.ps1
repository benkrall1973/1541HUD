[CmdletBinding()]
param(
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "build-address-test"
}

# Builds a tokenised C64 BASIC V2 PRG, rather than using KERNAL calls.
# Program:
# 10 OPEN15,8,15
# 20 PRINT#15,"M-R"+CHR$(0)+CHR$(6)+CHR$(1)
# 25 FORI=1TO100:NEXTI
# 30 GET#15,A$:PRINT LEN(A$)
# 40 CLOSE15
#
# It performs one read of drive RAM $0600.  It changes nothing in the drive.

function Add-BasicLine {
    param(
        [System.Collections.Generic.List[byte]]$Body,
        [int]$Address,
        [int]$LineNumber,
        [byte[]]$Content
    )

    $nextAddress = $Address + 5 + $Content.Length
    $Body.Add([byte]($nextAddress -band 0xFF))
    $Body.Add([byte](($nextAddress -shr 8) -band 0xFF))
    $Body.Add([byte]($LineNumber -band 0xFF))
    $Body.Add([byte](($LineNumber -shr 8) -band 0xFF))
    $Body.AddRange($Content)
    $Body.Add(0)
    return $nextAddress
}

$FOR    = 0x81
$NEXT   = 0x82
$TO     = 0xA4
$OPEN   = 0x9F
$CLOSE  = 0xA0
$GET    = 0xA1
$PRINT  = 0x99
$PRINTN = 0x98
$LEN    = 0xC3
$CHR    = 0xC7
$PLUS   = 0xAA
$EQUALS = 0xB2

$lines = @(
    [pscustomobject]@{ N = 10; B = [byte[]]($OPEN,49,53,44,56,44,49,53) },
    [pscustomobject]@{ N = 20; B = [byte[]]($PRINTN,49,53,44,34,77,45,82,34,$PLUS,$CHR,40,48,41,$PLUS,$CHR,40,54,41,$PLUS,$CHR,40,49,41) },
    [pscustomobject]@{ N = 25; B = [byte[]]($FOR,73,$EQUALS,49,$TO,49,48,48,58,$NEXT,73) },
    [pscustomobject]@{ N = 30; B = [byte[]]($GET,35,49,53,44,65,36,58,$PRINT,32,$LEN,40,65,36,41) },
    [pscustomobject]@{ N = 40; B = [byte[]]($CLOSE,49,53) }
)

$body = [System.Collections.Generic.List[byte]]::new()
$address = 0x0801
foreach ($line in $lines) {
    $address = Add-BasicLine -Body $body -Address $address -LineNumber $line.N -Content $line.B
}
$body.Add(0)
$body.Add(0)

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outFile = Join-Path $OutputDirectory "1541HUD_UB3_T0.0.23_DOS_Channel_Read_Proof.prg"
[System.IO.File]::WriteAllBytes($outFile, [byte[]](@(0x01, 0x08) + $body.ToArray()))

Get-FileHash -Algorithm SHA256 $outFile
Get-Item $outFile | Select-Object Name, Length, LastWriteTime
Write-Host ""
Write-Host "T0.0.23 C64 BASIC DOS-channel read proof built."
Write-Host "Run at the C64. It prints the number of bytes returned by a read of 1541 RAM $0600."
