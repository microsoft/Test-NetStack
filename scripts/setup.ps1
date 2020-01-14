# Setup Script for Test-RDMA

$HostName = "RRN44-14-09"
$MachineList = "RRN44-14-09","RRN44-14-11", "RRN44-14-13", "RRN44-14-15"

$domain = "cfdev"
$userpwd = "wolfpack"
$username = "wolfpack"
$domainUsername = "$domain\wolfpack"
$creds = New-Object System.Management.Automation.PSCredential($domainUsername,($userpwd | ConvertTo-SecureString -asPlainText -Force))

$HostSession = New-PSSession -ComputerName $HostName -Credential $creds

$MachineList | ForEach-Object {

    $MachineName = $_
    $DestinationSession = New-PSSession -ComputerName $MachineName -Credential $creds

    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\Test-RDMA\tools"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\Test-RDMA\tools\NDK-Perf"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\Test-RDMA\tools\CTS-Traffic"}

    Copy-Item C:\Test-RDMA\tools\NDK-Perf\NDKPerf.sys -Destination C:\Test-RDMA\tools\NDK-Perf -ToSession $DestinationSession
    Copy-Item C:\Test-RDMA\tools\NDK-Perf\NDKPerfCmd.exe -Destination C:\Test-RDMA\tools\NDK-Perf -ToSession $DestinationSession

    Copy-Item C:\Test-RDMA\tools\CTS-Traffic\ctsTraffic.exe -Destination C:\Test-RDMA\tools\CTS-Traffic -ToSession $DestinationSession

    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc delete NDKPerf type=kernel binpath=C:\Test-RDMA\tools\NDK-Perf\NDKPerf.sys"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc create NDKPerf type=kernel binpath=C:\Test-RDMA\tools\NDK-Perf\NDKPerf.sys"}

    Invoke-Command -ComputerName $MachineName -scriptBlock {New-NetFirewallRule -DisplayName "Client-To-Server Network Test Tool" -Direction Inbound -Program "C:\Test-RDMA\tools\CTS-Traffic\ctsTraffic.exe" -Action Allow}

} 