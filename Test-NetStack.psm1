using module .\helpers\prerequisites.psm1
using module .\helpers\internal.psm1
using module .\helpers\icmp.psm1
using module .\helpers\tcp.psm1
using module .\helpers\ndk.psm1

Function Test-NetStack {
    <#
    .SYNOPSIS
        Test-NetStack performs ICMP, TCP, and RDMA traffic testing of networks. Test-NetStack can help you identify misconfigured networks, hotspots, asymmetry across cluster nodes, and more.

    .DESCRIPTION
        Test-NetStack performs ICMP, TCP, and RDMA traffic testing of networks. Test-NetStack can help you identify misconfigured networks, hotspots, asymmetry across cluster nodes, and more.
        Specifically, Test-NetStack:
        - Performs connectivity mapping across a cluster, specific nodes, or IP targets
        - Stage1: ICMP Connectivity, Reliability, and PMTUD
        - Stage2: TCP Stress 1:1
        - Stage3: RDMA Connectivity
        - Stage4: RDMA Stress 1:1
        - Stage5: RDMA Stress N:1
        - Stage6: RDMA Stress N:N

    .PARAMETER Nodes
        - Specifies the machines by DNS Name to test.
        - PowerShell remoting without credentials is required; no credentials are stored or entered into Test-NetStack.
        - Minimum 2 nodes, maximum of 16 nodes.

        If part of a failover cluster, and neither the IPTarget or Node parameters are specified, get-clusternode will be run to attempt to gather nodenames.

    .PARAMETER Stage
        List of stages that specifies the tests to be run by Test-NetStack. By default, all stages will be run.

        Tests will always occur in order of lowest stage first. It is highly recommended that you always run the preceeding tests.

        Currently included stages for Test-NetStack:
        - Stage1: ICMP Connectivity, Reliability, and PMTUD
        - Stage2: TCP Stress 1:1
        - Stage3: RDMA Connectivity
        - Stage4: RDMA Stress 1:1
        - Stage5: RDMA Stress N:1
        - Stage6: RDMA Stress N:N

    .PARAMETER EnableFirewallRules
    * This command is best-effort and may fail for a variety of reasons *

    Works with:
    - The Windows Firewall
    - The built-in firewall rules for ICMP, WinRM, and iWARP
    - CTSTraffic rules (by application path) needed for Stage 2

    Note: if you upgrade the module version, firewall rules should be revoked, then re-enabled.

    .PARAMETER RevokeFirewallRules
    * This command is best-effort and may fail for a variety of reasons *

    Works with:
    - The Windows Firewall
    - The built-in firewall rules for ICMP and iWARP
    - CTSTraffic rules defined by the EnableFirewallRules parameter
    - Will not disable WinRM

    .PARAMETER OnlyPrerequisites
    Use if you want to review the connectivity map detection. This is useful if you're troubleshooting why some networks are or are not included in testing.

    .PARAMETER OnlyConnectivityMap
    Use if you want to review the connectivity map detection. This is useful if you're troubleshooting why some networks are or are not included in testing.

    .PARAMETER LogPath
    Defines the path for the logfile. By default, this will be in the path of the module under the results folder

    .PARAMETER DontCheckATC
    By default, Test-NetStack tests networks created by Network ATC intents which requires an account that can access the cluster.
    - This flag tells Test-NetStack to identify and test any possible network that resolves by the connectivity mapper
    - This flag is implicitely enabled when IP Targets are specified (rather than Node names) as ATC requires a cluster with DNS resolution

    .PARAMETER ContinueOnFailure
    By default, Test-NetStack will stop processing later stages if a failure is incurred during an earlier stage. This switch will continue testing later stages.

    The following lists the dependent stages:
    - Stage 1 -> Stage 2
    - Stage 3 -> Stage 4 -> Stage 5 -> Stage 6

    .EXAMPLE
    Run all tests in the local node's failover cluster. Review results from Stage2 and Stage6
        $Results = Test-NetStack

        $Results.Stage2
        $Results.Stage6

    .EXAMPLE
    4-domain joined nodes; all tests run
        $Results = Test-NetStack -Nodes 'AzStackHCI01', 'AzStackHCI02', 'AzStackHCI03', AzStackHCI04'

    .EXAMPLE
    2-node tests; ICMP and TCP tests only. Review results from Stage1 and Stage2
        $Results = Test-NetStack -MachineList 'AzStackHCI01', 'AzStackHCI02' -Stage 1, 2

        $Results.Stage1
        $Results.Stage2

    .NOTES
        Author: Windows Core Networking team @ Microsoft
        Please file issues on GitHub @ GitHub.com/Microsoft/Test-NetStack

    .LINK
        Networking Blog   : https://aka.ms/MSFTNetworkBlog
        HCI Host Guidance : https://docs.microsoft.com/en-us/azure-stack/hci/deploy/network-atc
    #>

    [CmdletBinding(DefaultParameterSetName = 'FullNodeMap')]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'FullNodeMap'       , position = 0)]
        [Parameter(Mandatory = $false, ParameterSetName = 'OnlyPrereqNodes'   , position = 0)]
        [Parameter(Mandatory = $false, ParameterSetName = 'OnlyConMapNodes'   , position = 0)]
        [Parameter(Mandatory = $false, ParameterSetName = 'RevokeFWRulesNodes', position = 0)]
        [ValidateScript({[System.Uri]::CheckHostName($_) -eq 'DNS'})]
        [ValidateCount(2, 16)]
        [String[]] $Nodes,

        [Parameter(Mandatory = $true, ParameterSetName = 'IPAddress'            , position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'OnlyPrereqIPTarget'   , position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'OnlyConMapIPTarget'   , position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'RevokeFWRulesIPTarget', position = 0)]
        [ValidateCount(2, 16)]
        [IPAddress[]] $IPTarget,

        [Parameter(Mandatory = $false, ParameterSetName = 'FullNodeMap'          , position = 1)]
        [Parameter(Mandatory = $false, ParameterSetName = 'IPAddress'            , position = 1)]
        [Parameter(Mandatory = $false, ParameterSetName = 'OnlyPrereqNodes'      , position = 1)]
        [Parameter(Mandatory = $false, ParameterSetName = 'OnlyPrereqIPTarget'   , position = 1)]
        [Parameter(Mandatory = $false, ParameterSetName = 'RevokeFWRulesNodes'   , position = 1)]
        [Parameter(Mandatory = $false, ParameterSetName = 'RevokeFWRulesIPTarget', position = 1)]
        [ValidateSet('1', '2', '3', '4', '5', '6')]
        [Int32[]] $Stage = @('1', '2', '3', '4', '5', '6'),

        [Parameter(Mandatory = $false, ParameterSetName = 'FullNodeMap', position = 2)]
        [Parameter(Mandatory = $false, ParameterSetName = 'IPAddress'  , position = 2)]
        [Switch] $EnableFirewallRules = $false,

        [Parameter(Mandatory = $true, ParameterSetName = 'RevokeFWRulesNodes'   , position = 2)]
        [Parameter(Mandatory = $true, ParameterSetName = 'RevokeFWRulesIPTarget', position = 2)]
        [Switch] $RevokeFirewallRules = $false,

        [Parameter(Mandatory = $true, ParameterSetName = 'OnlyPrereqNodes'   , position = 2)]
        [Parameter(Mandatory = $true, ParameterSetName = 'OnlyPrereqIPTarget', position = 2)]
        [Switch] $OnlyPrerequisites = $false,

        [Parameter(Mandatory = $true, ParameterSetName = 'OnlyConMapNodes'   , position = 2)]
        [Parameter(Mandatory = $true, ParameterSetName = 'OnlyConMapIPTarget', position = 2)]
        [Switch] $OnlyConnectivityMap = $false,

        [Parameter(Mandatory = $false, ParameterSetName = 'FullNodeMap'       , position = 3)]
        [Parameter(Mandatory = $false, ParameterSetName = 'OnlyConMapNodes'   , position = 3)]
        [Parameter(Mandatory = $false, ParameterSetName = 'OnlyConMapIPTarget', position = 3)]
        [Parameter(Mandatory = $false, ParameterSetName = 'IPAddress'         , position = 3)]
        [switch] $DontCheckATC = $false,

        [Parameter(Mandatory = $false, ParameterSetName = 'FullNodeMap', position = 4)]
        [Parameter(Mandatory = $false, ParameterSetName = 'IPAddress'  , position = 4)]
        [switch] $ContinueOnFailure = $false,

        [Parameter(Mandatory = $false)]
        [String] $LogPath = "$(Join-Path -Path $((Get-Module -Name Test-Netstack -ListAvailable | Select-Object -First 1).ModuleBase) -ChildPath "Results\NetStackResults-$(Get-Date -f yyyy-MM-dd-HHmmss).txt")"
    )

    $Global:ProgressPreference = 'SilentlyContinue'

    $LogFileParentPath = Split-Path -Path $LogPath -Parent -ErrorAction SilentlyContinue

    if (-not (Test-Path $LogFileParentPath -ErrorAction SilentlyContinue)) {
        $null = New-Item -Path $LogFileParentPath -ItemType Directory -Force -ErrorAction SilentlyContinue
    }

    $LogFile = New-Item -Path $LogPath -ItemType File -Force -ErrorAction SilentlyContinue

    "Starting Test-NetStack - $([System.DateTime]::Now)`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

    # Each stages adds their results to this and is eventually returned by this function
    $NetStackResults = New-Object -TypeName psobject

    # Since FullNodeMap is the default, we can check if the customer entered Nodes or IPTarget. If neither, check for cluster membership, and use that for the nodes.
    if ( $PsCmdlet.ParameterSetName -eq 'FullNodeMap' -or $PsCmdlet.ParameterSetName -eq 'OnlyPrereqNodes' -or $PsCmdlet.ParameterSetName -eq 'OnlyConMapNodes' -or $PsCmdlet.ParameterSetName -eq 'RevokeFWRulesNodes' ) {
        if (-not($PSBoundParameters.ContainsKey('Nodes'))) {
            try { $Nodes = (Get-ClusterNode -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Name }
            catch {
                Write-Host 'To run this cmdlet without parameters, join a cluster then try again. Otherwise, specify the Nodes or IPTarget parameters' -ForegroundColor Red
                "To run this cmdlet without parameters, join a cluster then try again. Otherwise, specify the Nodes or IPTarget parameters." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                break
            }
        }

        If ($EnableFirewallRules) { $TargetInfo, $PrereqStatus = Test-NetStackPrerequisites -Nodes $Nodes -Stage $Stage -EnableFirewallRules }
        else { $TargetInfo, $PrereqStatus = Test-NetStackPrerequisites -Nodes $Nodes -Stage $Stage }
    }
    else { # Function returns both the target information and the results of the prerequisite testing
        If ($EnableFirewallRules) { $TargetInfo, $PrereqStatus = Test-NetStackPrerequisites -IPTarget $IPTarget -Stage $Stage -EnableFirewallRules }
        else { $TargetInfo, $PrereqStatus = Test-NetStackPrerequisites -IPTarget $IPTarget -Stage $Stage }
    }

    if ( $RevokeFirewallRules ) {
        if ($IPTarget) { $Targets = $IPTarget }
        else { $Targets = $Nodes }

        Revoke-FirewallRules -Stage $Stage -Targets $Targets

        Return
    }

    $NetStackResults | Add-Member -MemberType NoteProperty -Name Prerequisites -Value $TargetInfo
    Remove-Variable TargetInfo -ErrorAction SilentlyContinue

    "Prerequisite Test Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    $NetStackResults.Prerequisites | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

    if ($OnlyPrerequisites) {
        return $NetStackResults
    }
    elseif ($false -in $PrereqStatus) {
        "Prerequsite tests have failed. Review the NetStack results below for more details." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        $NetStackResults.Prerequisites | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        throw "Prerequsite tests have failed. Review the NetStack results for more details."
    }

    #region Connectivity Maps
    if ($Nodes) { $EthernetMapping, $RDMAMapping = Get-ConnectivityMapping -Nodes $Nodes       -Logfile $LogFile -DontCheckATC:$DontCheckATC }
    else        { $EthernetMapping, $RDMAMapping = Get-ConnectivityMapping -IPTarget $IPTarget -Logfile $LogFile -DontCheckATC:$DontCheckATC }


    if (-not($EthernetMapping)) { # Not sure if we want to fail if RDMAMapping is missing as well...
        "Connectivity mapping has failed. This may be because Network ATC is not in use. To resolve this either define Network ATC intents, or specify the DontCheckATC switch." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        throw "Connectivity mapping has failed. This may be because Network ATC is not in use. To resolve this either define Network ATC intents, or specify the DontCheckATC switch."
    }

    $TestableEthernetNetworks = Get-TestableNetworksFromMapping -Mapping $EthernetMapping
    $TestableRDMANetworks     = Get-TestableNetworksFromMapping -Mapping $RDMAMapping

    $DisqualifiedEthernetNetworks = Get-DisqualifiedNetworksFromMapping -Mapping $EthernetMapping
    $DisqualifiedRDMANetworks     = Get-DisqualifiedNetworksFromMapping -Mapping $RDMAMapping

    # If at least one note property doesn't exist, then no disqualified networks (Ethernet) were identified
    if (($DisqualifiedEthernetNetworks | Get-Member -MemberType NoteProperty).Count) {
        "Disqualified Ethernet Networks" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

        $DisqualifiedEthernetNetworks.PSObject.Properties | ForEach-Object {
            $DisqualificationCategory = $_
            "`r`nDisqualification Category: $($DisqualificationCategory.Name)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $DisqualificationCategory.Value | ForEach-Object {
                $_.Name | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                $_.Group | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            }
        }

        "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        $NetStackResults | Add-Member -MemberType NoteProperty -Name DisqualifiedEthernetNetworks -Value $DisqualifiedEthernetNetworks
    }
    else { Remove-Variable -Name DisqualifiedEthernetNetworks -ErrorAction SilentlyContinue }

    # If at least one note property doesn't exist, then no disqualified networks (RDMA) were identified
    if (($DisqualifiedRDMANetworks | Get-Member -MemberType NoteProperty).Count) {
        "Disqualified RDMA Networks" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

        $DisqualifiedRDMANetworks.PSObject.Properties | ForEach-Object {
            $DisqualificationCategory = $_
            "`r`nDisqualification Category: $($DisqualificationCategory.Name)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $DisqualificationCategory.Value | ForEach-Object {
                $_.Name | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                $_.Group | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            }
        }

        "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        $NetStackResults | Add-Member -MemberType NoteProperty -Name DisqualifiedRDMANetworks -Value $DisqualifiedRDMANetworks
    }
    else { Remove-Variable -Name DisqualifiedRDMANetworks -ErrorAction SilentlyContinue }

    $NetStackResults | Add-Member -MemberType NoteProperty -Name TestableEthernetNetworks -Value $TestableEthernetNetworks
    $NetStackResults | Add-Member -MemberType NoteProperty -Name TestableRDMANetworks     -Value $TestableRDMANetworks

    if ($TestableEthernetNetworks -eq 'None Available' -and (-not($OnlyConnectivityMap))) { # Not sure if we want to fail if there are no RDMA networks.
        Write-Error 'No testable ethernet networks found. Aborting Test-NetStack.'
        "No testable ethernet networks found. Aborting Test-NetStack." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        return $NetStackResults
    }

    "Testable Ethernet Networks`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    $TestableEthernetNetworks | ForEach-Object {
        $_.Values | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        $_.Group | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    }
    "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

    "Testable RDMA Networks`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    $TestableRDMANetworks | ForEach-Object {
        $_.Values | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        $_.Group | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    }
    "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

    if ($OnlyConnectivityMap) { return $NetStackResults }
    #endregion Connectivity Maps

    $EthernetRunspaceGroups = Get-RunspaceGroups -TestableNetworks $TestableEthernetNetworks
    $RDMARunspaceGroups     = Get-RunspaceGroups -TestableNetworks $TestableRDMANetworks

    # Defines the stage requirements - internal.psm1
    $Definitions = [Analyzer]::new()

    $ResultsSummary = New-Object -TypeName psobject
    $StageFailures = 0

    $MaxRunspaces = [int]$env:NUMBER_OF_PROCESSORS * 2

    Switch ( $Stage | Sort-Object ) {
        '1' { # ICMP Connectivity, Reliability, and PMTUD
            $thisStage = $_
            Write-Host "Beginning Stage: $thisStage - Connectivity and PMTUD - $([System.DateTime]::Now)"
            "Stage 1`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Console Output" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Beginning Stage: $thisStage - Connectivity and PMTUD - $([System.DateTime]::Now)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxRunspaces, $ISS, $host)
            $RunspacePool.Open()

            $AllJobs = @()
            $StageResults = @()

            $TestableEthernetNetworks | ForEach-Object {
                $thisTestableNet = $_

                $thisTestableNet.Group | ForEach-Object {
                    $thisSource = $_
                    $thisSourceResult = @()

                    $thisTestableNet.Group | Where-Object NodeName -ne $thisSource.NodeName | ForEach-Object {
                        $thisTarget = $_

                        $PowerShell = [powershell]::Create()
                        $PowerShell.RunspacePool = $RunspacePool

                        [void] $PowerShell.AddScript({
                            param ( $thisComputerName, $thisSource, $thisTarget, $Definitions, $LogFile )

                            if ($thisSource.NodeName -eq $Env:COMPUTERNAME) {
                                $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource.IPAddress -Destination $thisTarget.IPAddress -MTU
                            }
                            else {
                                $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                    -ArgumentList $thisSource.IPAddress, $thisTarget.IPAddress, 32, 10000, $false, $true `
                                                                    -ScriptBlock  ${Function:\Invoke-ICMPPMTUD}
                            }

                            $Result = New-Object -TypeName psobject
                            $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisComputerName
                            $Result | Add-Member -MemberType NoteProperty -Name Source         -Value $thisSource.IPAddress
                            $Result | Add-Member -MemberType NoteProperty -Name Destination    -Value $thisTarget.IPAddress
                            $Result | Add-Member -MemberType NoteProperty -Name Connectivity   -Value $thisSourceResult.Connectivity
                            $Result | Add-Member -MemberType NoteProperty -Name MTU -Value $thisSourceResult.MTU
                            $Result | Add-Member -MemberType NoteProperty -Name MSS -Value $thisSourceResult.MSS

                            if ($thisSource.NodeName -eq $Env:COMPUTERNAME) {
                                $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource.IPAddress -Destination $thisTarget.IPAddress -StartBytes $thisSourceResult.MSS -Reliability
                            }
                            else { # Arguments must be sent in order. True param indicates the switch for -Reliability.
                                $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                    -ArgumentList $thisSource.IPAddress, $thisTarget.IPAddress, $thisSourceResult.MSS, $null, $true `
                                                                    -ScriptBlock ${Function:\Invoke-ICMPPMTUD}
                            }

                            $TotalSent   = $thisSourceResult.Count
                            $TotalFailed = ($thisSourceResult -eq '-1').Count
                            $SuccessPercentage = ([Math]::Round((100 - (($TotalFailed / $TotalSent) * 100)), 2))

                            $Result | Add-Member -MemberType NoteProperty -Name TotalSent   -Value $TotalSent
                            $Result | Add-Member -MemberType NoteProperty -Name TotalFailed -Value $TotalFailed
                            $Result | Add-Member -MemberType NoteProperty -Name Reliability -Value $SuccessPercentage

                            # -1 (no response) will be ignored for LAT and JIT
                            $Latency = Get-Latency -RoundTripTime ($thisSourceResult -ne -1)
                            $Jitter  = Get-Jitter  -RoundTripTime ($thisSourceResult -ne -1)

                            $Result | Add-Member -MemberType NoteProperty -Name Latency -Value $Latency
                            $Result | Add-Member -MemberType NoteProperty -Name Jitter -Value $Jitter

                            if ($TotalSent -and $SuccessPercentage -and $Latency -and $Jitter -and
                                $Definitions.Reliability.ICMPSent  -and $Definitions.Reliability.ICMPReliability  -and
                                $Definitions.Reliability.ICMPLatency -and $Definitions.Reliability.ICMPJitter) {

                                    if ($TotalSent         -ge $Definitions.Reliability.ICMPSent        -and
                                        $SuccessPercentage -ge $Definitions.Reliability.ICMPReliability -and
                                        $Latency           -le $Definitions.Reliability.ICMPLatency     -and
                                        $Jitter            -le $Definitions.Reliability.ICMPJitter ) {

                                        $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Pass'
                                    }
                                    else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' }
                            }
                            else {
                                $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail'
                                "ERROR: Data failed to be collected for path ($($thisComputerName)) $($thisSource.IPAddress) -> $($thisTarget.IPAddress)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                            }

                            return $Result
                        })

                        $param = @{
                            thisComputerName = $thisSource.NodeName
                            thisSource  = $thisSource
                            thisTarget  = $thisTarget
                            Definitions = $Definitions
                            LogFile     = $LogFile
                        }

                        [void] $PowerShell.AddParameters($param)

                        Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] ($($thisSource.NodeName)) $($thisSource.IPAddress) -> $($thisTarget.IPAddress)"
                        ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] ($($thisSource.NodeName)) $($thisSource.IPAddress) -> $($thisTarget.IPAddress)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $asyncJobObj = @{ JobHandle = $PowerShell; AsyncHandle = $PowerShell.BeginInvoke() }

                        $AllJobs += $asyncJobObj
                        Remove-Variable Result -ErrorAction SilentlyContinue
                    }
                }
            }

            While ($AllJobs -ne $null) {
                $AllJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                    $thisJob = $_
                    $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                    $thisSourceHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).SourceHostName
                    $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Source
                    $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Destination

                    $AllJobs = $AllJobs -ne $thisJob

                    Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] ($thisSourceHostName) $($thisSource) -> $($thisTarget)"
                    ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] ($thisSourceHostName) $($thisSource) -> $($thisTarget)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage1 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage1 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage1 -Value $StageResults

            Write-Host "Completed Stage: $thisStage - Connectivity and PMTUD - $([System.DateTime]::Now)"
            "Completed Stage: $thisStage - Connectivity and PMTUD - $([System.DateTime]::Now)`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Stage 1 Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $StageResults | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        }

        '2' { # TCP Stress 1:1
            if ( $ContinueOnFailure -eq $false ) {
                if ('fail' -in $NetStackResults.Stage1.PathStatus) {

                    $Stage -gt 1 | ForEach-Object {
                        $AbortedStage = $_
                        $NetStackResults | Add-Member -MemberType NoteProperty -Name "Stage$AbortedStage" -Value 'Aborted'; $StageFailures++
                    }

                    Write-Warning 'Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter.'
                    "Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    return $NetStackResults
                }
            }

            $thisStage = $_
            Write-Host "Beginning Stage: $thisStage - TCP - $([System.DateTime]::Now)"
            "Stage 2`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Console Output" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Beginning Stage: $thisStage - TCP - $([System.DateTime]::Now)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxRunspaces, $ISS, $host)
            $RunspacePool.Open()

            $StageResults = @()
            foreach ($group in $EthernetRunspaceGroups) {
                $GroupedJobs = @()
                foreach ($pair in $group) {
                    $PowerShell = [powershell]::Create()
                    $PowerShell.RunspacePool = $RunspacePool

                    [void] $PowerShell.AddScript({
                        param ( $thisComputerName, $thisSource, $thisTarget, $Definitions, $LogFile )

                        $Result = New-Object -TypeName psobject
                        $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisTarget.NodeName
                        $Result | Add-Member -MemberType NoteProperty -Name Sender -Value $thisSource.IPaddress
                        $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisTarget.IPAddress

                        $thisTargetResult = Invoke-TCP -Receiver $thisTarget -Sender $thisSource

                        $Result | Add-Member -MemberType NoteProperty -Name RxLinkSpeedGbps -Value $thisTargetResult.ReceiverLinkSpeedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisTargetResult.ReceivedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxPctgOfLinkSpeed -Value $thisTargetResult.ReceivedPctgOfLinkSpeed
                        $Result | Add-Member -MemberType NoteProperty -Name MinExpectedPctgOfLinkSpeed -Value $Definitions.TCPPerf.TPUT

                        if ($thisTargetResult.ReceivedPctgOfLinkSpeed -and $Definitions.TCPPerf.TPUT) {
                            if ($thisTargetResult.ReceivedPctgOfLinkSpeed -ge $Definitions.TCPPerf.TPUT) { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Pass' }
                            else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' }
                        }
                        else {
                            $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail'
                            "ERROR: Data failed to be collected for path  $($thisSource.IPAddress) -> ($($thisTarget.NodeName)) $($thisTarget.IPAddress)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        }

                        $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisTargetResult.RawData

                        Return $Result
                    })

                    $param = @{
                        thisComputerName = $pair.Source.NodeName
                        thisSource  = $pair.Source
                        thisTarget  = $pair.Target
                        Definitions = $Definitions
                        LogFile     = $LogFile
                    }

                    [void] $PowerShell.AddParameters($param)

                    Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] $($pair.Source.IPAddress) -> ($($pair.Target.NodeName)) $($pair.Target.IPAddress)"
                    ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] $($pair.Source.IPAddress) -> ($($pair.Target.NodeName)) $($pair.Target.IPAddress)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    $asyncJobObj = @{ JobHandle   = $PowerShell
                                        AsyncHandle = $PowerShell.BeginInvoke() }

                    $GroupedJobs += $asyncJobObj
                }

                While ($GroupedJobs -ne $null) {
                    $GroupedJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                        $thisJob = $_
                        $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                        $thisReceiverHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).ReceiverHostName
                        $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Sender
                        $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Receiver

                        $GroupedJobs = $GroupedJobs -ne $thisJob

                        Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)"
                        ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage2 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage2 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage2 -Value $StageResults
            Write-Host "Completed Stage: $thisStage - TCP - $([System.DateTime]::Now)"
            "Completed Stage: $thisStage - TCP - $([System.DateTime]::Now)`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Stage 2 Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $StageResults | Select-Object -Property * -ExcludeProperty RawData | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        }

        '3' { # RDMA Connectivity
            $thisStage = $_

            "Stage 3`r`n"    | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Console Output" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Beginning Stage: $thisStage - RDMA Ping - $([System.DateTime]::Now)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            Write-Host "Beginning Stage: $thisStage - RDMA Ping - $([System.DateTime]::Now)"

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxRunspaces, $ISS, $host)
            $RunspacePool.Open()

            $AllJobs = @()
            $StageResults = @()
            $TestableRDMANetworks | ForEach-Object {
                $thisTestableNet = $_

                $thisTestableNet.Group | Where-Object -FilterScript { $_.RDMAEnabled } | ForEach-Object {
                    $thisSource = $_
                    $thisSourceResult = @()

                    $thisTestableNet.Group | Where-Object NodeName -ne $thisSource.NodeName | Where-Object -FilterScript { $_.RDMAEnabled } | ForEach-Object {
                        $thisTarget = $_

                        $PowerShell = [powershell]::Create()
                        $PowerShell.RunspacePool = $RunspacePool

                        [void] $PowerShell.AddScript({
                            param ( $thisSource, $thisTarget, $Definitions, $IsIPTarget )

                            $Result = New-Object -TypeName psobject
                            $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisTarget.NodeName
                            $Result | Add-Member -MemberType NoteProperty -Name Sender -Value $thisSource.IPaddress
                            $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisTarget.IPAddress

                            $thisSourceResult = Invoke-NDKPing -Server $thisTarget -Client $thisSource

                            if ($thisSourceResult.ServerSuccess) {
                                $Result | Add-Member -MemberType NoteProperty -Name Connectivity -Value $true

                                if ($IsIPTarget) {
                                    $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Warning'
                                    $Result | Add-Member -MemberType NoteProperty -Name Reason     -Value 'RDMA Intent Undefined'
                                }
                                else {
                                    $Result | Add-Member -MemberType NoteProperty -Name PathStatus   -Value 'Pass'
                                }
                            }
                            else {
                                $Result | Add-Member -MemberType NoteProperty -Name Connectivity -Value $false
                                $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail'
                            }

                            Return $Result
                        })

                        if ($IPTarget) { [Boolean] $IsIPTarget = $true }

                        $param = @{
                            thisSource  = $thisSource
                            thisTarget  = $thisTarget
                            Definitions = $Definitions
                            IsIPTarget  = $IsIPTarget
                        }

                        [void] $PowerShell.AddParameters($param)

                        Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] $($thisSource.IPAddress) -> $($thisTarget.IPAddress)"
                        ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] $($thisSource.IPAddress) -> $($thisTarget.IPAddress)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $asyncJobObj = @{ JobHandle   = $PowerShell
                                          AsyncHandle = $PowerShell.BeginInvoke() }

                        $AllJobs += $asyncJobObj
                    }
                }
            }

            While ($AllJobs -ne $null) {
                $AllJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                    $thisJob = $_
                    $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                    $thisReceiverHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).ReceiverHostName
                    $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Sender
                    $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Receiver

                    $AllJobs = $AllJobs -ne $thisJob

                    Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)"
                    ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage3 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage3 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage3 -Value $StageResults

            Write-Host "Completed Stage: $thisStage - RDMA Ping - $([System.DateTime]::Now)"
            "Completed Stage: $thisStage - RDMA Ping - $([System.DateTime]::Now)`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Stage 3 Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $StageResults | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        }

        '4' { # RDMA Stress 1:1
            if ( $ContinueOnFailure -eq $false ) {
                if ('fail' -in $NetStackResults.Stage3.PathStatus) {

                    $Stage -ge 4 | ForEach-Object {
                        $AbortedStage = $_
                        $NetStackResults | Add-Member -MemberType NoteProperty -Name "Stage$AbortedStage" -Value 'Aborted'; $StageFailures++
                    }

                    Write-Warning 'Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter.'
                    "Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    return $NetStackResults
                }
            }

            $thisStage = $_
            Write-Host "Beginning Stage: $thisStage - RDMA Perf 1:1 - $([System.DateTime]::Now)"
            "Stage 4`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Console Output" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Beginning Stage: $thisStage - RDMA Perf 1:1 - $([System.DateTime]::Now)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxRunspaces, $ISS, $host)
            $RunspacePool.Open()

            $StageResults = @()
            foreach ($group in $RDMARunspaceGroups) {
                $GroupedJobs = @()
                foreach ($pair in $group) {

                    $PowerShell = [powershell]::Create()
                    $PowerShell.RunspacePool = $RunspacePool

                    [void] $PowerShell.AddScript({
                        param ( $thisSource, $thisTarget, $Definitions, $IsIPTarget )

                        $Result = New-Object -TypeName psobject
                        $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisTarget.NodeName
                        $Result | Add-Member -MemberType NoteProperty -Name Sender -Value $thisSource.IPaddress
                        $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisTarget.IPAddress

                        $thisSourceResult = Invoke-NDKPerf1to1 -Server $thisTarget -Client $thisSource -ExpectedTPUT $Definitions.NDKPerf.TPUT

                        $Result | Add-Member -MemberType NoteProperty -Name RxLinkSpeedGbps -Value $thisSourceResult.ReceiverLinkSpeedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisSourceResult.ReceivedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxPctgOfLinkSpeed -Value $thisSourceResult.ReceivedPctgOfLinkSpeed
                        $Result | Add-Member -MemberType NoteProperty -Name MinExpectedPctgOfLinkSpeed -Value $Definitions.NDKPerf.TPUT

                        if ($thisSourceResult.ReceivedPctgOfLinkSpeed -and $Definitions.NDKPerf.TPUT) {
                            if ($thisSourceResult.ReceivedPctgOfLinkSpeed -ge $Definitions.NDKPerf.TPUT) {
                                if ($IsIPTarget) {
                                    $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Warning'
                                    $Result | Add-Member -MemberType NoteProperty -Name Reason     -Value 'RDMA Intent Undefined'
                                }
                                else {
                                    $Result | Add-Member -MemberType NoteProperty -Name PathStatus   -Value 'Pass'
                                }
                            }
                            else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' }
                        }
                        else {
                            $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail'
                            "ERROR: Data failed to be collected for path  $($thisSource.IPAddress) -> ($($thisTarget.NodeName)) $($thisTarget.IPAddress)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        }

                        $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisSourceResult.RawData
                        Return $Result
                    })

                    if ($IPTarget) { [Boolean] $IsIPTarget = $true }

                    $param = @{
                        thisSource  = $pair.Source
                        thisTarget  = $pair.Target
                        Definitions = $Definitions
                        IsIPTarget  = $IsIPTarget
                    }

                    [void] $PowerShell.AddParameters($param)

                    Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] $($pair.Source.IPAddress) -> ($($pair.Target.NodeName)) $($pair.Target.IPAddress)"
                    ":: Stage $thisStage : $([System.DateTime]::Now) :: [Started] $($pair.Source.IPAddress) -> ($($pair.Target.NodeName)) $($pair.Target.IPAddress)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

                    $asyncJobObj = @{ JobHandle   = $PowerShell; AsyncHandle = $PowerShell.BeginInvoke() }
                    $GroupedJobs += $asyncJobObj
                }

                While ($GroupedJobs -ne $null) {
                    $GroupedJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                        $thisJob = $_
                        $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                        $thisReceiverHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).ReceiverHostName
                        $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Sender
                        $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Receiver

                        $GroupedJobs = $GroupedJobs -ne $thisJob

                        Write-Host ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)"
                        ":: Stage $thisStage : $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage4 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage4 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage4 -Value $StageResults

            Write-Host "Completed Stage: $thisStage - RDMA Perf 1:1 - $([System.DateTime]::Now)"
            "Completed Stage: $thisStage - RDMA Perf 1:1 - $([System.DateTime]::Now)`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Stage 4 Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $StageResults | Select-Object -Property * -ExcludeProperty RawData | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        }

        '5' { # RDMA Stress N:1
            if ( $ContinueOnFailure -eq $false ) {
                if ('fail' -in $NetStackResults.Stage3.PathStatus -or 'fail' -in $NetStackResults.Stage4.PathStatus) {

                    $Stage -ge 5 | ForEach-Object {
                        $AbortedStage = $_
                        $NetStackResults | Add-Member -MemberType NoteProperty -Name "Stage$AbortedStage" -Value 'Aborted'; $StageFailures++
                    }

                    Write-Warning 'Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter.'
                    "Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    return $NetStackResults
                }
            }

            $thisStage = $_
            Write-Host "Beginning Stage: $thisStage - RDMA Perf N:1 - $([System.DateTime]::Now)"
            "Stage 5`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Console Output" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Beginning Stage: $thisStage - RDMA Perf N:1 - $([System.DateTime]::Now)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

            $StageResults = @()
            $TestableRDMANetworks | ForEach-Object {
                $thisTestableNet = $_

                $thisTestableNet.Group | Where-Object -FilterScript { $_.RDMAEnabled } | ForEach-Object {
                    $thisTarget = $_
                    $ClientNetwork = @($thisTestableNet.Group | Where-Object NodeName -ne $thisTarget.NodeName | Where-Object -FilterScript { $_.RDMAEnabled })

                    Write-Host ":: $([System.DateTime]::Now) :: [Started] N -> Interface $($thisTarget.InterfaceIndex) ($($thisTarget.IPAddress))"
                    ":: $([System.DateTime]::Now) :: [Started] N -> Interface $($thisTarget.InterfaceIndex) ($($thisTarget.IPAddress))" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

                    $thisTargetResult = Invoke-NDKPerfNto1 -Server $thisTarget -ClientNetwork $ClientNetwork -ExpectedTPUT $Definitions.NDKPerf.TPUT

                    $Result = New-Object -TypeName psobject
                    $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisTarget.NodeName
                    $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisTarget.IPAddress

                    $Result | Add-Member -MemberType NoteProperty -Name RxLinkSpeedGbps -Value $thisTargetResult.ReceiverLinkSpeedGbps
                    $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisTargetResult.RxGbps

                    if ($thisTargetResult.ServerSuccess) { $Result | Add-Member -MemberType NoteProperty -Name ReceiverStatus -Value 'Pass' }
                    else { $Result | Add-Member -MemberType NoteProperty -Name ReceiverStatus -Value 'Fail' }

                    $Result | Add-Member -MemberType NoteProperty -Name ClientNetworkTested -Value $thisTargetResult.ClientNetworkTested
                    $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisTargetResult.RawData

                    $StageResults += $Result
                    Remove-Variable Result -ErrorAction SilentlyContinue

                    Write-Host ":: $([System.DateTime]::Now) :: [Completed] N -> Interface $($thisTarget.InterfaceIndex) ($($thisTarget.IPAddress))"
                    ":: $([System.DateTime]::Now) :: [Completed] N -> Interface $($thisTarget.InterfaceIndex) ($($thisTarget.IPAddress))" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                }
            }

            if ('Fail' -in $StageResults.ReceiverStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage5 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage5 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage5 -Value $StageResults

            Write-Host "Completed Stage: $thisStage - RDMA Perf N:1 - $([System.DateTime]::Now)"
            "Completed Stage: $thisStage - RDMA Perf N:1 - $([System.DateTime]::Now)`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Stage 5 Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $StageResults | Select-Object -Property * -ExcludeProperty RawData | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        }

        '6' { # RDMA Stress N:N
            if ( $ContinueOnFailure -eq $false ) {
                if ('fail' -in $NetStackResults.Stage3.PathStatus -or 'fail' -in $NetStackResults.Stage4.PathStatus -or 'fail' -in $NetStackResults.Stage5.PathStatus) {

                    $Stage -ge 6 | ForEach-Object {
                        $AbortedStage = $_
                        $ResultsSummary | Add-Member -MemberType NoteProperty -Name "Stage$AbortedStage" -Value 'Aborted'; $StageFailures++
                    }

                    Write-Warning 'Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter.'
                    "Aborted due to failures in earlier stage(s). To continue despite failures, use the ContinueOnFailure parameter." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    return $NetStackResults
                }
            }

            $thisStage = $_
            Write-Host "Beginning Stage: $thisStage - RDMA Perf N:N - $([System.DateTime]::Now)"
            "Stage 6`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Console Output" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Beginning Stage: $thisStage - RDMA Perf N:N - $([System.DateTime]::Now)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

            $StageResults = @()
            $TestableRDMANetworks | ForEach-Object {
                $thisTestableNet = $_

                $ServerList = $thisTestableNet.Group | Where-Object -FilterScript { $_.RDMAEnabled }

                $thisSubnet = ($ServerList | Select-Object -First 1).subnet
                $thisVLAN = ($ServerList | Select-Object -First 1).VLAN

                Write-Host ":: $([System.DateTime]::Now) :: [Started] N -> N on subnet $($thisSubnet) and VLAN $($thisVLAN)"
                ":: $([System.DateTime]::Now) :: [Started] N -> N on subnet $($thisSubnet) and VLAN $($thisVLAN)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

                $thisSourceResult = Invoke-NDKPerfNtoN -ServerList $ServerList -ExpectedTPUT $Definitions.NDKPerf.TPUT

                $Result = New-Object -TypeName psobject
                $thisSubnet = $thisTestableNet.Name.Split(',')[0]
                $thisVLAN = $thisTestableNet.Name.Split(',')[1].Trim()
                $Result | Add-Member -MemberType NoteProperty -Name Subnet -Value $thisSubnet
                $Result | Add-Member -MemberType NoteProperty -Name VLAN -Value $thisVLAN

                $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisSourceResult.RxGbps

                if ($thisSourceResult.ServerSuccess) { $Result | Add-Member -MemberType NoteProperty -Name NetworkStatus -Value 'Pass' }
                else { $Result | Add-Member -MemberType NoteProperty -Name NetworkStatus -Value 'Fail' }

                $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisSourceResult.RawData

                Write-Host ":: $([System.DateTime]::Now) :: [Completed] N -> N on subnet $($thisSubnet) and VLAN $($thisVLAN)"
                ":: $([System.DateTime]::Now) :: [Completed] N -> N on subnet $($thisSubnet) and VLAN $($thisVLAN)" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

                $StageResults += $Result
                Remove-Variable Result -ErrorAction SilentlyContinue
            }

            if ('Fail' -in $StageResults.NetworkStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage6 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage6 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage6 -Value $StageResults

            Write-Host "Completed Stage: $thisStage - RDMA Perf N:N - $([System.DateTime]::Now)"
            "Completed Stage: $thisStage - RDMA Perf N:N - $([System.DateTime]::Now)`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "Stage 6 Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            $StageResults | Select-Object -Property * -ExcludeProperty RawData | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
            "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        }
    }

    if ($StageFailures -gt 0) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name NetStack -Value 'Fail' }
    else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name NetStack -Value 'Pass' }

    "Net Stack Results" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    $ResultsSummary | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

    $NetStackResults | Add-Member -MemberType NoteProperty -Name ResultsSummary -Value $ResultsSummary

    $Failures = Get-Failures -NetStackResults $NetStackResults
    if (@($Failures.PSObject.Properties).Count -gt 0) {
        $NetStackResults | Add-Member -MemberType NoteProperty -Name Failures -Value $Failures
    }
    Write-RecommendationsToLogFile -NetStackResults $NetStackResults -LogFile $LogFile
    Write-Verbose "Log file stored at: $LogPath"

    Return $NetStackResults
}
