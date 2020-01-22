# Setup Script for Test-RDMA

$HostName = "RRN44-14-09"

$domain = ".\"
$userpwd = "Test-Execution"
$username = "$HostName"
$domainUsername = "$domain\$username"
$creds = New-Object System.Management.Automation.PSCredential($domainUsername,($userpwd | ConvertTo-SecureString -asPlainText -Force))

cmd /c "mkdir C:\Test-RDMA\tools"
cmd /c "mkdir C:\Test-RDMA\tools\NDK-Perf"
cmd /c "mkdir C:\Test-RDMA\tools\CTS-Traffic"

Copy-Item C:\Test-RDMA\tools\NDK-Perf\NDKPerf.sys -Destination C:\Test-RDMA\tools\NDK-Perf -ErrorAction SilentlyContinue
Copy-Item C:\Test-RDMA\tools\NDK-Perf\NDKPerfCmd.exe -Destination C:\Test-RDMA\tools\NDK-Perf -ErrorAction SilentlyContinue

Copy-Item C:\Test-RDMA\tools\CTS-Traffic\ctsTraffic.exe -Destination C:\Test-RDMA\tools\CTS-Traffic -ErrorAction SilentlyContinue

cmd /c "sc create NDKPerf type=kernel binpath=C:\Test-RDMA\tools\NDK-Perf\NDKPerf.sys"

New-NetFirewallRule -DisplayName "Client-To-Server Network Test Tool" -Direction Inbound -Program "C:\Test-RDMA\tools\CTS-Traffic\ctsTraffic.exe" -Action Allow
