# Setup Script for Test-NetStack

$HostName = "RRN44-14-09"

$domain = ".\"
$userpwd = "Test-Execution"
$username = "$HostName"
$domainUsername = "$domain\$username"
$creds = New-Object System.Management.Automation.PSCredential($domainUsername,($userpwd | ConvertTo-SecureString -asPlainText -Force))

cmd /c "mkdir C:\Test-NetStack\tools"
cmd /c "mkdir C:\Test-NetStack\tools\NDK-Perf"
cmd /c "mkdir C:\Test-NetStack\tools\CTS-Traffic"

Copy-Item C:\Test-NetStack\tools\NDK-Perf\NDKPerf.sys -Destination C:\Test-NetStack\tools\NDK-Perf -Force -ErrorAction SilentlyContinue
Copy-Item C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -Destination C:\Test-NetStack\tools\NDK-Perf -Force -ErrorAction SilentlyContinue

Copy-Item C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -Destination C:\Test-NetStack\tools\CTS-Traffic -Force -ErrorAction SilentlyContinue

cmd /c "sc create NDKPerf type=kernel binpath=C:\Test-NetStack\tools\NDK-Perf\NDKPerf.sys"

New-NetFirewallRule -DisplayName "Client-To-Server Network Test Tool" -Direction Inbound -Program "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe" -Action Allow
