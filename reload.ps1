Set-Location C:\Test-NetStack

Remove-Module Test-NetStack -Force -ErrorAction SilentlyContinue
Remove-Module icmp          -Force -ErrorAction SilentlyContinue
Remove-Module prerequisites -Force -ErrorAction SilentlyContinue
Remove-Module internal      -Force -ErrorAction SilentlyContinue
Remove-Module icmp          -Force -ErrorAction SilentlyContinue
Remove-Module udp           -Force -ErrorAction SilentlyContinue
Remove-Module tcp           -Force -ErrorAction SilentlyContinue
Remove-Module ndk           -Force -ErrorAction SilentlyContinue

psedit .\Test-NetStack.psm1
#psedit .\helpers\icmp.psm1

Import-Module .\Test-NetStack.psd1 -Force
$s = Test-NetStack -Nodes HV01, HV02

#$s = Test-NetStack -IPTarget 172.16.0.11, 172.16.0.12