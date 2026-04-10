$param=$args[0]

Set-Location $PSScriptRoot

$port_file = Join-Path $PSScriptRoot "mewt_com_port.txt"
if (!(Test-Path $port_file)) {
    Write-Error "mewt_com_port.txt not found in $PSScriptRoot. Run setup_dualkey_port.ps1 first."
    exit 1
}

$mewt_port = (Get-Content -Path $port_file | Select-Object -Last 1).Trim()
if ([string]::IsNullOrWhiteSpace($mewt_port)) {
    Write-Error "mewt_com_port.txt is empty. Run setup_dualkey_port.ps1 and save the DualKey COM port."
    exit 1
}

if (-not $IsWindows) {
    Write-Error "This script is for Windows only."
    exit 1
}

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeKey {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}

public enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }
[Flags] public enum CLSCTX : uint { INPROC_SERVER = 0x1, INPROC_HANDLER = 0x2, LOCAL_SERVER = 0x4, REMOTE_SERVER = 0x10, ALL = INPROC_SERVER | INPROC_HANDLER | LOCAL_SERVER | REMOTE_SERVER }

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
public class MMDeviceEnumeratorComObject {}

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
public interface IMMDeviceEnumerator {
  int NotImpl1();
  int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
}

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("D666063F-1587-4E43-81F1-B948E807363F")]
public interface IMMDevice {
  int Activate(ref Guid iid, CLSCTX dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
public interface IAudioEndpointVolume {
  int RegisterControlChangeNotify(IntPtr pNotify);
  int UnregisterControlChangeNotify(IntPtr pNotify);
  int GetChannelCount(out uint pnChannelCount);
  int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
  int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
  int GetMasterVolumeLevel(out float pfLevelDB);
  int GetMasterVolumeLevelScalar(out float pfLevel);
  int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid pguidEventContext);
  int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid pguidEventContext);
  int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
  int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
  int GetMute(out bool pbMute);
  int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
  int VolumeStepUp(ref Guid pguidEventContext);
  int VolumeStepDown(ref Guid pguidEventContext);
  int QueryHardwareSupport(out uint pdwHardwareSupportMask);
  int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}
"@

function Invoke-WinAltK {
    $KEYEVENTF_KEYUP = 0x0002
    $VK_LWIN = 0x5B
    $VK_MENU = 0x12
    $VK_K = 0x4B

    [NativeKey]::keybd_event($VK_LWIN, 0, 0, [UIntPtr]::Zero)
    [NativeKey]::keybd_event($VK_MENU, 0, 0, [UIntPtr]::Zero)
    [NativeKey]::keybd_event($VK_K, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 10
    [NativeKey]::keybd_event($VK_K, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [NativeKey]::keybd_event($VK_MENU, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [NativeKey]::keybd_event($VK_LWIN, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
}

function Get-DefaultCaptureEndpointVolume {
    $enumerator = [IMMDeviceEnumerator][Activator]::CreateInstance([type]::GetTypeFromCLSID([Guid]"BCDE0395-E52F-467C-8E3D-C4579291692E"))
    $device = $null
    $null = $enumerator.GetDefaultAudioEndpoint([EDataFlow]::eCapture, [ERole]::eCommunications, [ref]$device)
    $iid = [Guid]"5CDF2C82-841E-4546-9722-0CF74078229A"
    $epObj = $null
    $null = $device.Activate([ref]$iid, [CLSCTX]::ALL, [IntPtr]::Zero, [ref]$epObj)
    return [IAudioEndpointVolume]$epObj
}

function Get-SystemMicMuted {
    try {
        $ep = Get-DefaultCaptureEndpointVolume
        $muted = $false
        $null = $ep.GetMute([ref]$muted)
        return $muted
    } catch {
        return $false
    }
}

$port = New-Object System.IO.Ports.SerialPort $mewt_port,9600,None,8,one
$port.DTREnable = $true
$port.RTSEnable = $true
$port.ReadTimeout = 50
$port.Open()

$port.WriteLine("101")
Write-Host "MEWT ready"

$previous_button_value = -1

while ($port.IsOpen) {
    $isMuted = Get-SystemMicMuted
    if ($isMuted) {
        $dualkey_led = 0   # muted -> right green
    } else {
        $dualkey_led = 1   # unmuted -> left red
    }

    try { $port.WriteLine([string]$dualkey_led) } catch {}

    $value_from_arduino = $null
    try {
        $serial_line = $port.ReadLine().Trim()
        if ($serial_line -match '^[01]$') {
            $value_from_arduino = [int]$serial_line
        }
    } catch {}

    if (($null -ne $value_from_arduino) -and ($previous_button_value -ne $value_from_arduino)) {
        $previous_button_value = $value_from_arduino

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        if ($param -eq "Zoom") {
            $wshell = New-Object -ComObject wscript.shell
            if ($wshell.AppActivate('Zoom Meeting')) { $wshell.SendKeys('%a') }
            if ($wshell.AppActivate('Meeting Controls')) { $wshell.SendKeys('%a') }
        }
        if ($param -eq "Meet") {
            $wshell = New-Object -ComObject wscript.shell
            $wshell.AppActivate('Google Chrome') | Out-Null
            $wshell.SendKeys('^d')
        }
        if ($param -eq "Discord") {
            $wshell = New-Object -ComObject wscript.shell
            $wshell.AppActivate('Discord') | Out-Null
            $wshell.SendKeys('^+d')
        }

        try { Invoke-WinAltK } catch {}
        Start-Sleep -Milliseconds 40

        if (Get-SystemMicMuted) {
            Write-Host "toggle complete: MUTED in $($stopwatch.ElapsedMilliseconds) ms"
        } else {
            Write-Host "toggle complete: UNMUTED in $($stopwatch.ElapsedMilliseconds) ms"
        }
    }
}

Write-Host "MEWT exiting"