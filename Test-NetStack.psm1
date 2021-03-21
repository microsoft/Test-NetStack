using module .\helpers\prerequisites.psm1
using module .\helpers\internal.psm1
using module .\helpers\icmp.psm1
using module .\helpers\udp.psm1
using module .\helpers\tcp.psm1
using module .\helpers\ndk.psm1

Function Test-NetStack {
    <#
    .SYNOPSIS
        <TODO>

    .DESCRIPTION
        <TODO>

    .PARAMETER Node
        Specifies the machines to test
        - The local machine is the source for non-congestion/stress tests
        - Congestion/stress tests require a failover cluster to ensure common credentials - No credentials are stored/entered into Test-NetStack
        - Minimum of 2 nodes required if specified
        - Optional if a member of a failover cluster; required otherwise

        If part of a failover cluster, and neither the IPTarget or Node parameters are specified, all paths will be tested
        between this node and other nodes in the failover cluster

    .PARAMETER Stage
        List of stages that specifies the tests to be run by Test-NetStack. By default, all stages will be run.
        
        Tests will always occur in order of lowest stage first and it is highly recommended
        that you run all preceeding tests as they are built upon one another.

        Currently included stages for Test-NetStack:
            Stage 1: Connectivity and PMTUD Verification (ICMP)
            Stage 2: Reliability Calculation (ICMP)
            Stage 3: TPUT Stress (TCP)
            Stage 4: 1:1 RDMA Connectivity (NDK)
            Stage 5: 1:1 RDMA Stress (NDK)
            Stage 6: N:1 RDMA Congestion (NDK)

    .EXAMPLE 4-node test Synthetic and Hardware Data Path
        Test-NetStack -MachineList 'AzStackHCI01', 'AzStackHCI02', 'AzStackHCI03', AzStackHCI04'

    .EXAMPLE Synthetic Tests Only
        Test-NetStack -MachineList 'AzStackHCI01', 'AzStackHCI02' -Stage 4

    .NOTES
        Author: Windows Core Networking team @ Microsoft
        Please file issues on GitHub @ GitHub.com/Microsoft/Test-NetStack

    .LINK
        More projects               : https://github.com/microsoft/sdn
        Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
        RDMA Configuration Guidance : https://aka.ms/ConvergedNIC
    #>

    [CmdletBinding(DefaultParameterSetName = 'FullNodeMap')]
    param (
        [Parameter(Mandatory=$false, ParameterSetName='FullNodeMap', position = 0)]
        [ValidateScript({[System.Uri]::CheckHostName($_) -eq 'DNS'})]
        [ValidateCount(2, 16)]
        [String[]] $Nodes,

        [Parameter(Mandatory=$false, ParameterSetName='IPAddress', position = 1)]
        [ValidateCount(2, 16)]
        [IPAddress[]] $IPTarget,

        [Parameter(Mandatory=$false)]
        [ValidateSet('1', '2', '3', '4', '5', '6')]
        [Int32[]] $Stage = @('1', '2', '3', '4', '5', '6')
    )

    Clear-Host

    $here = Split-Path -Parent (Get-Module -Name Test-NetStack | Select-Object -First 1).Path
    $global:Log = New-Item -Name 'Results.log' -Path "$here\Results" -ItemType File -Force
    $startTime = Get-Date -format:'yyyyMMdd-HHmmss' | Out-File $log    

    $global:fail = 'FAIL'
    $global:testsFailed = 0
    $Definitions = [Analyzer]::new()

    # Add prerequisite tester here
        #TODO: Add check, If Stage contains '2', it must contain '1' as it builds on it.

    # Each stages adds their results to this and is eventually returned by this function
    $NetStackResults = New-Object -TypeName psobject

    #region Connectivity Maps
    if ($Nodes) {
        $Mapping = Get-Connectivity -Nodes $Nodes

        $VLANSupportedNets = $Mapping | Where VLAN -ne 'Unsupported' | Group-Object Subnet, VLAN
        $TestableNets  = $VLANSupportedNets | Where Count -ne 1

        $DisqualifiedByVLANSupport    = $Mapping | Where VLAN -eq 'Unsupported' | Group-Object Subnet, VLAN
        $DisqualifiedByInterfaceCount = $VLANSupportedNets | Where Count -eq 1

        $Disqualified = New-Object -TypeName psobject
        if ($DisqualifiedByVLANSupport) {
            $Disqualified | Add-Member -MemberType NoteProperty -Name VLAN         -Value $DisqualifiedByVLANSupport
        }

        if ($DisqualifiedByInterfaceCount) {
            $Disqualified | Add-Member -MemberType NoteProperty -Name OneIntSubnet -Value $DisqualifiedByInterfaceCount
        }

        # These are the disqualified networks and adapters. Will keep this for reporting.
        if ($Disqualified) {
            $NetStackResults | Add-Member -MemberType NoteProperty -Name Disqualified -Value $Disqualified
        }       

        if ($TestableNets) {
            $NetStackResults | Add-Member -MemberType NoteProperty -Name Testable -Value $TestableNets
        }
        else {
            $NetStackResults | Add-Member -MemberType NoteProperty -Name Testable -Value 'None Available'

            Write-Verbose 'No testable networks found'
            break
        }

        Remove-Variable -Name VLANSupportedNets, Disqualified, DisqualifiedByVLANSupport, DisqualifiedByInterfaceCount -ErrorAction SilentlyContinue
    }
    else { $Mapping = $IPTarget.IPAddressToString }
    #endregion Connectivity Maps

    # Get the IPs on the local system so you can avoid invoke-command 
    $global:localIPs = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast).IPAddress

    Switch ( $Stage | Sort-Object ) {
        '1' { # Connectivity and PMTUD

            Write-Host 'Beginning Stage 1 - Connectivity and PMTUD'
            $StageResults = @()

            if ($IPTarget) {
                $Mapping | ForEach-Object {
                    $thisSource = $_
                    $targets = $Mapping -ne $thisSource

                    $thisSourceResult = @()                
                    $targets | ForEach-Object {
                        $thisTarget = $_
                        $thisComputerName = (Resolve-DnsName -Name $thisSource -DnsOnly).NameHost.Split('.')[0]

                        $Result = New-Object -TypeName psobject
                        $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisComputerName
                        $Result | Add-Member -MemberType NoteProperty -Name Source -Value $thisSource
                        $Result | Add-Member -MemberType NoteProperty -Name Destination -Value $thisTarget

                        #TODO: Find the configured MTU for the specific adapter;
                        #      Then ensure that MSS + 42 is = Configured Value; Add Property that is pass/fail for this

                        # Calls the PMTUD parameter set in Invoke-ICMPPMTUD
                        if ($thisSource -in $global:localIPs) {
                            $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource -Destination $thisTarget
                        }
                        else {
                            $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                -ArgumentList $thisSource, $thisTarget `
                                                                -ScriptBlock  ${Function:\Invoke-ICMPPMTUD}
                        }

                        $Result | Add-Member -MemberType NoteProperty -Name Connectivity -Value $thisSourceResult.Connectivity
                        $Result | Add-Member -MemberType NoteProperty -Name MTU -Value $thisSourceResult.MTU
                        $Result | Add-Member -MemberType NoteProperty -Name MSS -Value $thisSourceResult.MSS

                        $StageResults += $Result
                        Remove-Variable Result -ErrorAction SilentlyContinue
                    }
                }
            }
            elseif ($Nodes) {
                $TestableNets | ForEach-Object {
                    $thisTestableNet = $_

                    $thisTestableNet.Group | ForEach-Object {
                        $thisSource = $_
                        $thisSourceResult = @()

                        $thisTestableNet.Group | Where NodeName -ne $thisSource.NodeName | ForEach-Object {
                            $thisTarget = $_

                            $Result = New-Object -TypeName psobject
                            $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisSource.NodeName
                            $Result | Add-Member -MemberType NoteProperty -Name Source -Value $thisSource.IPAddress
                            $Result | Add-Member -MemberType NoteProperty -Name Destination -Value $thisTarget.IPaddress

                            #TODO: Find the configured MTU for the specific adapter;
                            #      Then ensure that MSS + 42 is = Configured Value; Add Property that is pass/fail for this

                            # Calls the PMTUD parameter set in Invoke-ICMPPMTUD
                            if ($thisSource.IPAddress -in $global:localIPs) {
                                $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource.IPAddress -Destination $thisTarget.IPAddress
                            }
                            else {
                                $thisSourceResult = Invoke-Command -ComputerName $thisSource.NodeName `
                                                                   -ArgumentList $thisSource.IPAddress, $thisTarget.IPAddress `
                                                                   -ScriptBlock  ${Function:\Invoke-ICMPPMTUD}
                            }

                            $Result | Add-Member -MemberType NoteProperty -Name Connectivity -Value $thisSourceResult.Connectivity
                            $Result | Add-Member -MemberType NoteProperty -Name MTU -Value $thisSourceResult.MTU
                            $Result | Add-Member -MemberType NoteProperty -Name MSS -Value $thisSourceResult.MSS

                            $StageResults += $Result
                            Remove-Variable Result -ErrorAction SilentlyContinue
                        }
                    }
                }
            }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage1 -Value $StageResults

            Write-Host 'Completed Stage 1 - Connectivity and PMTUD'
        }

        '2' { # ICMP Reliability
            Write-Host 'Beginning Stage 2 - ICMP Reliability'

            $StageResults = @()

            if ($IPTarget) {
                $Mapping | ForEach-Object {
                    $thisSource = $_
                    $targets = $Mapping -ne $thisSource

                    $thisSourceResult = @()                
                    $targets | ForEach-Object {
                        $thisTarget = $_
                        $thisComputerName = (Resolve-DnsName -Name $thisSource -DnsOnly).NameHost.Split('.')[0]
                        $thisSourceMSS = ($NetStackResults.Stage1 | Where{$_.SourceHostName -eq $thisComputerName -and $_.Destination -eq $thisTarget}).MSS

                        $Result = New-Object -TypeName psobject
                        $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisComputerName
                        $Result | Add-Member -MemberType NoteProperty -Name Source -Value $thisSource
                        $Result | Add-Member -MemberType NoteProperty -Name Destination -Value $thisTarget

                        # Calls the Reliability parameter set in icmp.psm1
                        if ($thisSource -in $global:localIPs) {
                            $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource -Destination $thisTarget -StartBytes $thisSourceMSS -Reliability
                        }
                        else {
                            $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                -ArgumentList $thisSource, $thisTarget, $thisSourceMSS, $null, $true `
                                                                -ScriptBlock ${Function:\Invoke-ICMPPMTUD}
                        }

                        $Result | Add-Member -MemberType NoteProperty -Name ICMPSent -Value $thisSourceResult.Total
                        $Result | Add-Member -MemberType NoteProperty -Name ICMPFailed -Value $thisSourceResult.Failed

                        $SuccessPercentage = ([Math]::Round((100 - (($thisSourceResult.Failed / $thisSourceResult.Total) * 100)), 2))
                        $Result | Add-Member -MemberType NoteProperty -Name ICMPReliability -Value $SuccessPercentage

                        if ($SuccessPercentage      -ge $Definitions.Reliability.ICMPReliability -and
                            $thisSourceResult.Total -ge $Definitions.Reliability.sent) {
                            $Result | Add-Member -MemberType NoteProperty -Name StageStatus -Value 'Pass'
                        }
                        else { $Result | Add-Member -MemberType NoteProperty -Name StageStatus -Value 'Fail' }

                        $StageResults += $Result
                        Remove-Variable Result -ErrorAction SilentlyContinue
                    }
                }
            }
            elseif ($Nodes) {
                $TestableNets | ForEach-Object {
                    $thisTestableNet = $_

                    $thisTestableNet.Group | ForEach-Object {
                        $thisSource = $_
                        $thisSourceResult = @()

                        $thisTestableNet.Group | Where NodeName -ne $thisSource.NodeName | ForEach-Object {
                            $thisTarget = $_
                            $thisSourceMSS = ($NetStackResults.Stage1 | Where {$_.Source -eq $thisSource.IPAddress -and $_.Destination -eq $thisTarget.IPAddress}).MSS

                            $Result = New-Object -TypeName psobject
                            $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisSource.NodeName
                            $Result | Add-Member -MemberType NoteProperty -Name Source -Value $thisSource.IPAddress
                            $Result | Add-Member -MemberType NoteProperty -Name Destination -Value $thisTarget.IPaddress

                            # Calls the Reliability parameter set in icmp.psm1
                            if ($thisSource.IPAddress -in $global:localIPs) {
                                $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource.IPAddress -Destination $thisTarget.IPAddress -StartBytes $thisSourceMSS -Reliability
                            }
                            else {
                                $thisSourceResult = Invoke-Command -ComputerName $thisSource.NodeName `
                                                                    -ArgumentList $thisSource.IPAddress, $thisTarget.IPAddress, $thisSourceMSS, $null, $true `
                                                                    -ScriptBlock ${Function:\Invoke-ICMPPMTUD}
                            }

                            $Result | Add-Member -MemberType NoteProperty -Name ICMPSent -Value $thisSourceResult.Total
                            $Result | Add-Member -MemberType NoteProperty -Name ICMPFailed -Value $thisSourceResult.Failed

                            $SuccessPercentage = ([Math]::Round((100 - (($thisSourceResult.Failed / $thisSourceResult.Total) * 100)), 2))
                            $Result | Add-Member -MemberType NoteProperty -Name ICMPReliability -Value $SuccessPercentage

                            if ($SuccessPercentage      -ge $Definitions.Reliability.ICMPReliability -and
                                $thisSourceResult.Total -ge $Definitions.Reliability.sent) {
                                $Result | Add-Member -MemberType NoteProperty -Name StageStatus -Value 'Pass'
                            }
                            else { $Result | Add-Member -MemberType NoteProperty -Name StageStatus -Value 'Fail' }

                            $StageResults += $Result
                            Remove-Variable Result -ErrorAction SilentlyContinue
                        }
                    }
                }
            }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage2 -Value $StageResults
            Write-Host 'Completed Stage 2 - ICMP Reliability'
        }

        '3' {  }

        '4' {  }
        '5' {  }
        '6' {  }
    }

    Return $NetStackResults
}
