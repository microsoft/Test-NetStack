# Setup Script for Test-NetStack

$HostName = "RRN44-14-09"
$MachineList = "RRN44-14-09","RRN44-14-11", "RRN44-14-13", "RRN44-14-15"

$domain = "cfdev"
$userpwd = "wolfpack"
$username = "wolfpack"
$domainUsername = "$domain\$username"
$creds = New-Object System.Management.Automation.PSCredential($domainUsername,($userpwd | ConvertTo-SecureString -asPlainText -Force))

$HostSession = New-PSSession -ComputerName $HostName -Credential $creds

$MachineList | ForEach-Object {

    $MachineName = $_
    $DestinationSession = New-PSSession -ComputerName $MachineName -Credential $creds

    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\Test-NetStack\tools"} -ErrorAction SilentlyContinue
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\Test-NetStack\tools\NDK-Perf"} -ErrorAction SilentlyContinue
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\Test-NetStack\tools\CTS-Traffic"} -ErrorAction SilentlyContinue

    Copy-Item C:\Test-NetStack\tools\NDK-Perf\NDKPerf.sys -Destination C:\Test-NetStack\tools\NDK-Perf -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue
    Copy-Item C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -Destination C:\Test-NetStack\tools\NDK-Perf -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue

    Copy-Item C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -Destination C:\Test-NetStack\tools\CTS-Traffic -Force -ToSession $DestinationSession

    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc delete NDKPerf type=kernel binpath=C:\Test-NetStack\tools\NDK-Perf\NDKPerf.sys"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc create NDKPerf type=kernel binpath=C:\Test-NetStack\tools\NDK-Perf\NDKPerf.sys"}

    Invoke-Command -ComputerName $MachineName -scriptBlock {New-NetFirewallRule -DisplayName "Client-To-Server Network Test Tool" -Direction Inbound -Program "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe" -Action Allow}

} 