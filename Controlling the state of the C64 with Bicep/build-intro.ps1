<#
.SYNOPSIS
    Builds intro.prg - a Fairlight-style 80's crack intro for the C64:
      - Big BICEP block logo with animated raster-bar color wash
      - "PRESENTS:" + title/name lines on pulsing color bars
      - Classic scrolling text at the bottom
      - SID arpeggio soundtrack
    Written in 6502 machine code, assembled by this tiny two-pass
    PowerShell assembler (no external tools needed).

.OUTPUT
    prg\intro.prg (BASIC stub: 10 SYS2061, code at $080D)
#>

$ErrorActionPreference = 'Stop'

# ---------- tiny assembler ----------
$script:code   = [System.Collections.Generic.List[byte]]::new()
$script:labels = @{}
$script:fixups = @()
$org = 0x0801

function PC { $org + $script:code.Count }
function Label([string]$name) { $script:labels[$name] = PC }
function Emit([byte[]]$bytes) { foreach ($b in $bytes) { $script:code.Add($b) } }
function Ref([string]$name) { $script:fixups += @{ pos = $script:code.Count; label = $name; rel = $false }; Emit 0x00, 0x00 }
function RelRef([string]$name) { $script:fixups += @{ pos = $script:code.Count; label = $name; rel = $true }; Emit 0x00 }
function RefLo([string]$name) { $script:fixups += @{ pos = $script:code.Count; label = $name; rel = $false; loOnly = $true }; Emit 0x00 }
function RefHi([string]$name) { $script:fixups += @{ pos = $script:code.Count; label = $name; rel = $false; hiOnly = $true }; Emit 0x00 }

# opcodes (some prefixed to dodge PowerShell aliases)
function SEI             { Emit 0x78 }
function OpCLC           { Emit 0x18 }
function INX             { Emit 0xE8 }
function TAY             { Emit 0xA8 }
function TXA             { Emit 0x8A }
function LSRa            { Emit 0x4A }
function LDAi([byte]$v)  { Emit 0xA9, $v }
function LDXi([byte]$v)  { Emit 0xA2, $v }
function LDYi([byte]$v)  { Emit 0xA0, $v }
function ANDi([byte]$v)  { Emit 0x29, $v }
function CMPi([byte]$v)  { Emit 0xC9, $v }
function CPXi([byte]$v)  { Emit 0xE0, $v }
function LDAzp([byte]$z) { Emit 0xA5, $z }
function STAzp([byte]$z) { Emit 0x85, $z }
function INCzp([byte]$z) { Emit 0xE6, $z }
function ADCzp([byte]$z) { Emit 0x65, $z }
function LDAindY([byte]$z) { Emit 0xB1, $z }
function LDAa([int]$a)   { Emit 0xAD, ($a -band 0xFF), ($a -shr 8) }
function STAa([int]$a)   { Emit 0x8D, ($a -band 0xFF), ($a -shr 8) }
function LDAax([int]$a)  { Emit 0xBD, ($a -band 0xFF), ($a -shr 8) }
function STAax([int]$a)  { Emit 0x9D, ($a -band 0xFF), ($a -shr 8) }
function LDAaxL([string]$l) { Emit 0xBD; Ref $l }
function LDAayL([string]$l) { Emit 0xB9; Ref $l }
function BNE([string]$l) { Emit 0xD0; RelRef $l }
function JMP([string]$l) { Emit 0x4C; Ref $l }
function LDAiLo([string]$l) { Emit 0xA9; RefLo $l }
function LDAiHi([string]$l) { Emit 0xA9; RefHi $l }

# ---------- constants ----------
$SCREEN  = 0x0400
$COLOR   = 0xD800
$BORDER  = 0xD020
$BACKGR  = 0xD021
$RASTER  = 0xD012
$SID_F1HI = 0xD401
$SID_CTL1 = 0xD404
$SID_AD1  = 0xD405
$SID_SR1  = 0xD406
$SID_VOL  = 0xD418

$ZP_CNT   = 0xFB   # frame counter
$ZP_PTRLO = 0xFC   # scroller pointer lo
$ZP_PTRHI = 0xFD   # scroller pointer hi

$SCROLL_ROW = 22
$SCROLL_POS = $SCREEN + $SCROLL_ROW * 40
$SCROLL_COL = $COLOR  + $SCROLL_ROW * 40

function ToCodes([string]$s) {
    $s.ToUpperInvariant().ToCharArray() | ForEach-Object {
        $c = [int][char]$_
        if ($c -eq 64) { 0 }
        elseif ($c -ge 65 -and $c -le 90) { $c - 64 }
        elseif ($c -ge 32 -and $c -le 63) { $c }
        else { 32 }
    }
}
function RowCodes([string]$s) { [byte[]](ToCodes ($s.PadRight(40).Substring(0, 40))) }

# Big 5-row block font for BICEP, '#' becomes a solid block (code 160)
$logo = @(
    ' #####   ####    ####   #####  #####  '
    ' ##  ##   ##    ##  ##  ##     ##  ## '
    ' #####    ##    ##      #####  #####  '
    ' ##  ##   ##    ##  ##  ##     ##     '
    ' #####   ####    ####   #####  ##     '
)
function LogoRow([string]$s) {
    [byte[]]($s.PadRight(40).Substring(0, 40).ToCharArray() | ForEach-Object {
        if ($_ -eq '#') { 160 } else { 32 }
    })
}

# ---------- program ----------
# BASIC stub: 10 SYS2061
Emit 0x0B, 0x08, 0x0A, 0x00, 0x9E, 0x32, 0x30, 0x36, 0x31, 0x00, 0x00, 0x00

Label 'start'
SEI
LDAi 0; STAa $BORDER; STAa $BACKGR; STAzp $ZP_CNT

# init scroller pointer
LDAiLo 'scrolltext'; STAzp $ZP_PTRLO
LDAiHi 'scrolltext'; STAzp $ZP_PTRHI

# clear screen
LDAi 32
LDXi 0
Label 'clr'
STAax ($SCREEN); STAax ($SCREEN + 0x100); STAax ($SCREEN + 0x200); STAax ($SCREEN + 0x300)
INX
BNE 'clr'

# white color RAM everywhere (animated rows get recolored each frame)
LDAi 1
LDXi 0
Label 'clrcol'
STAax ($COLOR); STAax ($COLOR + 0x100); STAax ($COLOR + 0x200); STAax ($COLOR + 0x300)
INX
BNE 'clrcol'

# draw logo + text rows
LDXi 0
Label 'draw'
LDAaxL 'logo0'; STAax ($SCREEN + 1 * 40)
LDAaxL 'logo1'; STAax ($SCREEN + 2 * 40)
LDAaxL 'logo2'; STAax ($SCREEN + 3 * 40)
LDAaxL 'logo3'; STAax ($SCREEN + 4 * 40)
LDAaxL 'logo4'; STAax ($SCREEN + 5 * 40)
LDAaxL 'tagline';  STAax ($SCREEN + 8 * 40)
LDAaxL 'presents'; STAax ($SCREEN + 11 * 40)
LDAaxL 'title';    STAax ($SCREEN + 14 * 40)
LDAaxL 'author';   STAax ($SCREEN + 16 * 40)
INX
CPXi 40
BNE 'draw'

# SID: voice 1 sawtooth
LDAi 0x0F; STAa $SID_VOL
LDAi 0x00; STAa $SID_AD1
LDAi 0xF0; STAa $SID_SR1
LDAi 0x21; STAa $SID_CTL1

# ---------- main loop ----------
Label 'main'
Label 'wait'
LDAa $RASTER
CMPi 0xFF
BNE 'wait'

INCzp $ZP_CNT

# --- raster-bar color wash over the 5 logo rows ---
LDXi 0
Label 'wash'
TXA
OpCLC
ADCzp $ZP_CNT
ANDi 0x0F
TAY
LDAayL 'bar_tab'
STAax ($COLOR + 1 * 40)
STAax ($COLOR + 2 * 40)
STAax ($COLOR + 3 * 40)
STAax ($COLOR + 4 * 40)
STAax ($COLOR + 5 * 40)
INX
CPXi 40
BNE 'wash'

# --- pulsing color on title + author rows ---
LDAzp $ZP_CNT
LSRa
ANDi 0x0F
TAY
LDAayL 'bar_tab'
LDXi 0
Label 'bars'
STAax ($COLOR + 14 * 40)
STAax ($COLOR + 16 * 40)
INX
CPXi 40
BNE 'bars'

# --- scroller: every 4th frame, shift row left and fetch next char ---
LDAzp $ZP_CNT
ANDi 0x03
BNE 'noscroll'
LDXi 0
Label 'shift'
LDAax ($SCROLL_POS + 1)
STAax ($SCROLL_POS)
INX
CPXi 39
BNE 'shift'
LDYi 0
LDAindY $ZP_PTRLO
CMPi 0xFF
BNE 'notend'
LDAiLo 'scrolltext'; STAzp $ZP_PTRLO
LDAiHi 'scrolltext'; STAzp $ZP_PTRHI
LDAindY $ZP_PTRLO
Label 'notend'
STAa ($SCROLL_POS + 39)
INCzp $ZP_PTRLO
BNE 'noscroll'
INCzp $ZP_PTRHI
Label 'noscroll'

# --- scroller color cycling ---
LDAzp $ZP_CNT
LSRa
LSRa
ANDi 0x0F
TAY
LDAayL 'scroll_col_tab'
LDXi 0
Label 'scol'
STAax ($SCROLL_COL)
INX
CPXi 40
BNE 'scol'

# --- SID arpeggio ---
LDAzp $ZP_CNT
LSRa
LSRa
ANDi 0x07
TAY
LDAayL 'note_tab'
STAa $SID_F1HI

JMP 'main'

# ---------- data ----------
Label 'logo0'; Emit (LogoRow $logo[0])
Label 'logo1'; Emit (LogoRow $logo[1])
Label 'logo2'; Emit (LogoRow $logo[2])
Label 'logo3'; Emit (LogoRow $logo[3])
Label 'logo4'; Emit (LogoRow $logo[4])
Label 'tagline';  Emit (RowCodes '  ...THE HOME OF THE REAL DEPLOYERS...')
Label 'presents'; Emit (RowCodes '               PRESENTS:')
Label 'title';    Emit (RowCodes "       'DESIRED STATE ON THE C64'")
Label 'author';   Emit (RowCodes '         CODED BY FREEK BERSON')
Label 'bar_tab'   # raster bar gradient (dark -> bright -> dark)
Emit 0x06, 0x04, 0x0E, 0x05, 0x03, 0x0D, 0x01, 0x0D, 0x03, 0x05, 0x0E, 0x04, 0x06, 0x0B, 0x0C, 0x0B
Label 'scroll_col_tab'
Emit 0x01, 0x0D, 0x03, 0x0E, 0x06, 0x0E, 0x03, 0x0D, 0x01, 0x07, 0x0A, 0x08, 0x02, 0x08, 0x0A, 0x07
Label 'note_tab'
Emit 0x11, 0x15, 0x19, 0x22, 0x19, 0x15, 0x11, 0x0D
Label 'scrolltext'
Emit ([byte[]](ToCodes ('   BICEP PRESENTS: DESIRED STATE ON A REAL COMMODORE 64 ... ' +
    'DEPLOYED STRAIGHT FROM THE CLOUD ERA TO 1982 HARDWARE ... ' +
    'INFRASTRUCTURE AS CODE RULES! ... ' +
    'GREETINGS TO THE AZURE CREW AND ALL RETRO CODERS WORLDWIDE ... ' +
    'CODED BY FREEK BERSON ... PRESS RESET TO EXIT ...     ')))
Emit 0xFF   # scroller wrap marker

# ---------- fixups ----------
foreach ($f in $script:fixups) {
    if (-not $script:labels.ContainsKey($f.label)) { throw "Unknown label: $($f.label)" }
    $target = $script:labels[$f.label]
    if ($f.rel) {
        $from = $org + $f.pos + 1
        $delta = $target - $from
        if ($delta -lt -128 -or $delta -gt 127) { throw "Branch out of range to $($f.label) (delta $delta)" }
        $script:code[$f.pos] = [byte](($delta + 256) % 256)
    }
    elseif ($f.loOnly) { $script:code[$f.pos] = [byte]($target -band 0xFF) }
    elseif ($f.hiOnly) { $script:code[$f.pos] = [byte]($target -shr 8) }
    else {
        $script:code[$f.pos]     = [byte]($target -band 0xFF)
        $script:code[$f.pos + 1] = [byte]($target -shr 8)
    }
}

# ---------- write PRG ----------
$outDir = Join-Path $PSScriptRoot 'prg'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$prg = [byte[]]( ($org -band 0xFF), ($org -shr 8) ) + $script:code.ToArray()
$outFile = Join-Path $outDir 'intro.prg'
[IO.File]::WriteAllBytes($outFile, $prg)
Write-Host "Built $outFile ($($prg.Length) bytes)" -ForegroundColor Green
