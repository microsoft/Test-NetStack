class NodeNetworkData {
    [String]$Name
    [String]$VLAN
    [String]$Subnet
    [boolean]$IsRDMACapable
    [boolean]$IsRocki 
}


function Assert-RDMA {
    <#
    .SYNOPSIS
        Test-RDMA is a module that validates RDMA Connectivity. 
    .DESCRIPTION
    Note: Test-RDMA is now an alias for Assert-RDMA.
    Test-RDMA allows you to:
        - Validate RDMA Connectivity on one to N number of systems or clusters
        Additional benefits include:
        - 
        This tool does not modify your system. As such, you can re-validate the configuration as many times as desired.
        Possible options include NDKm1 or NDKm2.  This option cannot be used with the $ConfigFilePath parameter
    .PARAMETER ReportPath
        The string path of where to place the reports.  This should point to a folder; not a specific file.
    .EXAMPLE
        Test-RDMA
    .NOTES
        Author: Windows Core Networking team @ Microsoft
        Please file issues on GitHub @ GitHub.com/Microsoft/Test-RDMA
    .LINK
        More projects               : https://github.com/microsoft/sdn
        Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
        RDMA Configuration Guidance : https://aka.ms/ConvergedNIC
    #>

    [CmdletBinding(DefaultParameterSetName = 'Create Config')]

    param (
        [Parameter(Mandatory=$false)]
        [string] $ReportPath
    )


    Clear-Host

    # TODO: Once converted to module, just add pester to required modules

    # $here = Split-Path -Parent (Get-Module -Name Test-RDMA -ListAvailable).Path
    $startTime = Get-Date -format:'yyyyMMdd-HHmmss'
    # New-Item -Name 'Results' -Path $here -ItemType Directory -Force

    #Import-Module "$here\helpers\helpers.psd1" -Force
    #$driversFilePath =  Join-Path -Path $here -ChildPath "helpers\drivers\drivers.psd1"
    #$configData += Import-PowerShellDataFile -Path $driversFilePath

    ####################################
    # Begin Test
    ####################################

    $machineName = $env:computername

    try {
        
        $machineCluster = Get-Cluster -Name $machineName
        
    } catch {
        
        Write-Host "VERBOSE: An error has occurred. Machine $($machineName) is not running the cluster service. Exiting Test-RDMA."
        Exit

    }
    $machineCluster = Get-Cluster -Name $machineName

    $nodeDataList = @()

    ####################################
    # Test Machines for RDMA Capability
    ####################################

    Get-ClusterNode | ForEach-Object {
                
        $newNode = [NodeNetworkData]::new()
        
        $newNode.Name = $_.Name

        $newNode.InterfaceList = Get-NetAdapter | select "Name", "InterfaceDescription", "ifIndex"
        $newNode.RdmaInterfaceList = Get-NetAdapterRdma | select "Name", "InterfaceDescription", "ifIndex"

        if ($newNode.RdmaInterfaceList -ne 0) {

            $newNode.IsRDMACapable = $true

        } else {

            Write-Host "VERBOSE: Machine $($newNode.Name) is not RDMA capable."

        }
        
        Write-Host "VERBOSE: Machine" $_.Name
        Write-Host "VERBOSE: RDMA Adapters" ($rdmaAdapterList | select "Name")
    }



}   
Export-ModuleMember -Function Assert-RDMA

Function _SendPing( $CompName, $Timeout, $Success, $SleepValue ){

    $TargetHost = $CompName

    if($CompName -like "*-NC-*"){
       $TargetHost = _ResolveDnsName($CompName)
    }
       
    $PingStopWatch =  [system.diagnostics.stopwatch]::StartNew()
    $ElapsedTotalSecs = [int]$("{0:N0}" -f $PingStopWatch.Elapsed.TotalSeconds)
    
    while( $ElapsedTotalSecs -lt $Timeout ){
       
       $PingTimeout = 250
       $Ping = New-Object System.Net.NetworkInformation.Ping
       $Response = $Ping.Send($TargetHost, $PingTimeout)

       if( $Success -eq $false ){
          if ($Response.Status -ne "Success"){
             _WttLogMessageWrapper "$CompName/$TargetHost went offline after $ElapsedTotalSecs secs as expected."
             break
          }
          _WttLogMessageWrapper "$CompName/$TargetHost still online after $ElapsedTotalSecs secs. Waiting..."
          Start-Sleep -Seconds $SleepValue
          $ElapsedTotalSecs = [int]$("{0:N0}" -f $PingStopWatch.Elapsed.TotalSeconds)
       }

       if($Success -eq $true) {
          if ($Response.Status -eq "Success"){
             _WttLogMessageWrapper "$CompName/$TargetHost is online after $ElapsedTotalSecs secs as expected."
             break
          }
          _WttLogMessageWrapper "$CompName/$TargetHost still offline after $ElapsedTotalSecs secs. Waiting..."
          Start-Sleep -Seconds  $SleepValue
          $ElapsedTotalSecs = [int]$("{0:N0}" -f $PingStopWatch.Elapsed.TotalSeconds)
         }
    }

    $ElapsedTotalMins = [double]$("{0:N1}" -f $PingStopWatch.Elapsed.TotalMinutes)
     
    if($Success -eq $false){
       
       if ( $Response.Status -eq "Success" ){
          _LogFailAndStop -Message "$CompName/$TargetHostfailed to get offline after $ElapsedTotalMins mins"
       }
    }

    if($Success -eq $true){
         
       if ( $Response.Status -ne "Success" ){
          _LogFailAndStop -Message "$CompName/$TargetHost failed to get online after $ElapsedTotalMins mins"
       }
    }
}

# New-Alias -Name 'Validate-DCB' -Value 'Assert-RDMA' -Force