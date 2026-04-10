$param=$args[0]

# RecordingStream level at/above this value => LED "talking" (both pixels red). Tune if needed.
$DUALKEY_TALK_THRESHOLD = 8

# Always run from script folder so relative paths are stable.
Set-Location $PSScriptRoot

$module_name = "AudioDeviceCmdlets"
$module_dir = Join-Path (Split-Path $PROFILE) "Modules\$module_name"
$module_dll = Join-Path $module_dir "$module_name.dll"
$local_module_dll = Join-Path $PSScriptRoot "$module_name.dll"
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

# checks if AudioDeviceCmdlets already exists in system
if (!(Test-Path $module_dll)) {
	if (!(Test-Path $local_module_dll)) {
		Write-Error "AudioDeviceCmdlets.dll not found. Copy it next to mewt_dualkey.ps1, then rerun."
		exit 1
	}

	# if not, installs AudioDeviceCmdlets locally
	New-Item $module_dir -Type directory -Force | Out-Null
	Copy-Item $local_module_dll $module_dll -Force
	Set-Location $module_dir
	Get-ChildItem | Unblock-File
	Import-Module $module_dll
}
else {
	Import-Module $module_dll
}
Set-Location $PSScriptRoot

function Start-MewtAudioStream {
	return Start-Process -FilePath powershell.exe -WorkingDirectory $PSScriptRoot -NoNewWindow "Import-Module $module_dll; Write-AudioDevice -RecordingStream | Out-File .\out.txt" -PassThru
}

if ($IsWindows) {
	Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeKey {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
}

function Invoke-WinAltK {
	# Win+Alt+K (Windows system microphone toggle hotkey).
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

# starts writing volume stream to temporary file.
$process = Start-MewtAudioStream
#$port.close()
$port = new-Object System.IO.Ports.SerialPort $mewt_port,9600,None,8,one
$port.DTREnable = $True
$port.RTSEnable = $True
$port.ReadTimeout = 50
$port.open()

$port.Write([int]101)
write-host "MEWT ready"

# sets up initial state for later comparison
$previous_button_value = -1
$unmewtable_device = -1

# takes a snapshot of the reocrding devices in the system for later comparison
$audio_device_list = Get-AudioDevice -list
$recording_devices_old = $audio_device_list | ? {$_.Type -eq "Recording"}
$out_timer =  [system.diagnostics.stopwatch]::StartNew()
$out_timer.start()
$loop = 1

while ($port.IsOpen)
{
	$mewt_stream_txt_file = Join-Path $PSScriptRoot "mewt_stream.txt"

	# reads last volume value written
	$last_mewt_stream_value = Get-Content -path ".\out.txt" -tail 1

	# skips non-integer values, and explicit types the output as int
	if (($last_mewt_stream_value -ne $null) -and ($last_mewt_stream_value.gettype().name -eq "String")) {
		$last_mewt_stream_value = [int]$last_mewt_stream_value

		# writes value to mewt_stream.txt
		Set-Content -Path $mewt_stream_txt_file -Value $last_mewt_stream_value -Encoding ASCII -ErrorAction SilentlyContinue
	}

	# gets mewt state, if mewted preps 0 to be sent to arduino
	try  {$current_mewt_state = Get-AudioDevice -RecordingMute -erroraction SilentlyContinue}
	Catch [System.exception] {"faulty audio device"}
	#$_.exception.gettype().fullname}

	if ($process.HasExited) {$process = Start-MewtAudioStream}
	
	if ($current_mewt_state) {
		$send_value_to_arduino = "0"
	} else {
		$send_value_to_arduino = "1"
	}

	# reads last button pushed by arduino
	try {$value_from_arduino = $port.ReadLine()}
	Catch [System.exception] {}
#write-host $value_from_arduino
	# holds mewt state in variable.  we are inverting the mewt state because we are sending 0 to arduino to indicate mute=true
	$opposite_mewt_state = $send_value_to_arduino
	
	
	# DualKey: 0 = muted (right green), 1 = unmuted quiet (left red), 2 = unmuted talking (both red)
	if ([int]$send_value_to_arduino -eq 0) {
		$dualkey_led = [int]0
	} else {
		$dualkey_vol = Get-Content -path ".\mewt_stream.txt" -head 1 -ErrorAction SilentlyContinue
		if ($null -eq $dualkey_vol -or $dualkey_vol -eq "") { $dualkey_vol = 1 }
		if ([int]$dualkey_vol -eq 0) { $dualkey_vol = 1 }
		if ([int]$dualkey_vol -ge [int]$DUALKEY_TALK_THRESHOLD) {
			$dualkey_led = [int]2
		} else {
			$dualkey_led = [int]1
		}
	}
	try {$port.writeline([int]$dualkey_led)}
	Catch [System.exception] {"No audio data"}

	# if a value is read from arduino, that means there's a button push
	#if (($value_from_arduino.length -gt 0) -and ($previous_button_value -ne [int]$value_from_arduino.Substring($value_from_arduino.length-1))){
	if (($value_from_arduino.length -gt 0) -and ($previous_button_value -ne [int]$value_from_arduino)){
		$value_from_arduino = [int]$value_from_arduino
		$previous_button_value = $value_from_arduino
		
		# if value read is the same as $opposite_mewt_state, that means that a change in state was requested
		if ($value_from_arduino -eq $opposite_mewt_state) {

$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
$stopwatch

if ($param -eq "Zoom") {
$wshell = New-Object -ComObject wscript.shell;
if ($wshell.AppActivate('Zoom Meeting')) {
	$wshell.SendKeys('%a')
	}
if ($wshell.AppActivate('Meeting Controls')) {
	$wshell.SendKeys('%a')
	}
}

if ($param -eq "Meet") {
$wshell = New-Object -ComObject wscript.shell;
$wshell.AppActivate('Google Chrome')
$wshell.SendKeys('^d')
}

if ($param -eq "Discord") {
$wshell = New-Object -ComObject wscript.shell;
$wshell.AppActivate('Discord')
$wshell.SendKeys('^+d')
}

#$stopwatch
			# keep console history for debugging (no clear)

			# prints out requested mewt state
			if ($value_from_arduino -eq 0) {
				write-host "===========UNMEWTING===========" 
#$serial |Write-ArduinoSerial [int]0		
#write-host "0"		
			} else {
			write-host "============MEWTING============" 
#$stopwatch
#$serial |Write-ArduinoSerial [int]1
#write-host "1"		
#$stopwatch
			}

			# Fast path: trigger Windows global mic shortcut, then read state back via AudioDeviceCmdlets.
			try  {Invoke-WinAltK}
			Catch [System.exception] {"failed to send Win+Alt+K"}

			if ($process.HasExited) {$process = Start-MewtAudioStream}
			Start-Sleep -Milliseconds 60
			try  {$actual_mute_state = Get-AudioDevice -RecordingMute -erroraction SilentlyContinue}
			Catch [System.exception] {"faulty audio device"}
			if ($actual_mute_state) {
				write-host "toggle complete: MUTED in " $stopwatch.Elapsed.Seconds"."$stopwatch.Elapsed.Milliseconds "s"
			} else {
				write-host "toggle complete: UNMUTED in " $stopwatch.Elapsed.Seconds"."$stopwatch.Elapsed.Milliseconds "s"
			}

		} 	# if ($value_from_arduino -eq $mewt_state) {
			# if value read is the same as mewt_state, that means that a change in state was requested
			
		
		
	}  	#if ($value_from_arduino.length -gt 0) {
		#if a value is read from arduino, that means there's a button push	
#if ($out_timer.Elapsed.hours -gt 10) {$process.Kill(); $loop = 0;import-module .\audiodevicecmdlets;$mewt_process = start-Process -FilePath powershell.exe  '.\mewt.ps1'}
}
$process.kill()
write-host "MEWT exiting"