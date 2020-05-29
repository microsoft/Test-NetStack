# Setup Script for Test-NetStack
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True, Position=1, HelpMessage="Machine List in which to run set up for Test-NetStack")]
  [string[]] $MachineList
)

$domain = "cfdev"
$userpwd = "wolfpack"
$username = "wolfpack"
$domainUsername = "$domain\$username"
$creds = New-Object System.Management.Automation.PSCredential($domainUsername,($userpwd | ConvertTo-SecureString -asPlainText -Force))

$HostSession = New-PSSession -ComputerName $MachineList[0] -Credential $creds

$MachineList | ForEach-Object {

    $MachineName = $_
    $DestinationSession = New-PSSession -ComputerName $MachineName -Credential $creds

    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\E2EWorkload\Test-NetStack\tools"} -ErrorAction SilentlyContinue
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\E2EWorkload\Test-NetStack\tools\NDK-Perf"} -ErrorAction SilentlyContinue
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\E2EWorkload\Test-NetStack\tools\NDK-Ping"} -ErrorAction SilentlyContinue
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "mkdir C:\E2EWorkload\Test-NetStack\tools\CTS-Traffic"} -ErrorAction SilentlyContinue

    Copy-Item C:\E2EWorkload\Test-NetStack\tools\NDK-Perf\NDKPerf.sys -Destination C:\E2EWorkload\Test-NetStack\tools\NDK-Perf -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue
    Copy-Item C:\E2EWorkload\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -Destination C:\E2EWorkload\Test-NetStack\tools\NDK-Perf -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue
    Copy-Item C:\E2EWorkload\Test-NetStack\tools\NDK-Ping\NDKPing.sys -Destination C:\E2EWorkload\Test-NetStack\tools\NDK-Ping -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue
    Copy-Item C:\E2EWorkload\Test-NetStack\tools\NDK-Ping\NDKPing.exe -Destination C:\E2EWorkload\Test-NetStack\tools\NDK-Ping -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue

    Copy-Item C:\E2EWorkload\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -Destination C:\E2EWorkload\Test-NetStack\tools\CTS-Traffic -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue

    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "bcdedit -set TESTSIGNING OFF"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "bcdedit -set TESTSIGNING ON"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc delete NDKPerf type=kernel binpath=C:\E2EWorkload\Test-NetStack\tools\NDK-Perf\NDKPerf.sys"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc create NDKPerf type=kernel binpath=C:\E2EWorkload\Test-NetStack\tools\NDK-Perf\NDKPerf.sys"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc delete NDKPing type=kernel binpath=C:\E2EWorkload\Test-NetStack\tools\NDK-Ping\NDKPing.sys"}
    Invoke-Command -ComputerName $MachineName -Credential $creds -ScriptBlock {cmd /c "sc create NDKPing type=kernel binpath=C:\E2EWorkload\Test-NetStack\tools\NDK-Ping\NDKPing.sys"}

    Invoke-Command -ComputerName $MachineName -scriptBlock {New-NetFirewallRule -DisplayName "Client-To-Server Network Test Tool" -Direction Inbound -Program "C:\E2EWorkload\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe" -Action Allow}

    Invoke-Command -ComputerName $MachineName -scriptBlock {Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force}
    Invoke-Command -ComputerName $MachineName -scriptBlock {Install-Module Pester -RequiredVersion 4.9.0 -SkipPublisherCheck -Force}
    Invoke-Command -ComputerName $MachineName -scriptBlock {Import-Module C:\E2EWorkload\Test-NetStack\Test-NetStack.psd1}

} 