# Writes mewt_com_port.txt with the COM port you select (for mewt_dualkey.ps1).
# Run from the same folder as mewt_dualkey.ps1 after plugging in the DualKey in USB mode.

Set-Location $PSScriptRoot

$ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
if ($ports.Count -eq 0) {
    Write-Host "No COM ports found. Plug in the DualKey (USB, not BLE) and try again."
    exit 1
}

Write-Host "Available COM ports:"
for ($i = 0; $i -lt $ports.Count; $i++) {
    Write-Host ("  [{0}] {1}" -f $i, $ports[$i])
}

$n = Read-Host "Enter the number for your DualKey"
$idx = 0
if (-not [int]::TryParse($n, [ref]$idx)) {
    Write-Host "Invalid number."
    exit 1
}
if ($idx -lt 0 -or $idx -ge $ports.Count) {
    Write-Host "Out of range."
    exit 1
}

$ports[$idx] | Out-File -FilePath ".\mewt_com_port.txt" -Encoding ascii
Write-Host "Saved $($ports[$idx]) to mewt_com_port.txt"
