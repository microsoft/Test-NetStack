Set-Location C:\Test-NetStack

Remove-Module Test-NetStack -Force -ErrorAction SilentlyContinue
Remove-Module icmp          -Force -ErrorAction SilentlyContinue
Remove-Module prerequisites -Force -ErrorAction SilentlyContinue
Remove-Module internal      -Force -ErrorAction SilentlyContinue
Remove-Module udp           -Force -ErrorAction SilentlyContinue
Remove-Module tcp           -Force -ErrorAction SilentlyContinue
Remove-Module ndk           -Force -ErrorAction SilentlyContinue

psedit .\Test-NetStack.psm1
psedit .\helpers\icmp.psm1

Import-Module .\Test-NetStack.psd1 -Force
#Set-PSBreakpoint -Script .\reload.ps1 -Line 18
#Set-PSBreakpoint -Script .\Test-NetStack.psm1 -Line 226
#Set-PSBreakpoint -Script .\Test-NetStack.psm1 -Line 246
#$s = Test-NetStack -Nodes HV01, HV02 -Stage 1

$s = Test-NetStack -IPTarget 172.16.0.11, 172.16.0.12 -Stage 1