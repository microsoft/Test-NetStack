function Assert-RDMA {
    <#
    .SYNOPSIS
        <TODO>
    .DESCRIPTION
        <TODO>
    .PARAMETER MachineList [Optional]
        Specifies the machines to test. If not specified, will select all cluster nodes in the cluster where
        localhost is a member
        
        Minimum of 2 nodes required if specified

        Current Maximum is 16 considering the maximum number of Azure Stack HCI systems. This could be 
        increased in the future following time and testing.

        Note: For congestion tests, more nodes are beneficial however each additional node adds considerable testing time.

    .PARAMETER StageNumber [Optional]
        Specifies the tests to be run by Test-NetStack. By default, all stages will be tested.

        If you specify a stage, all previous stages will be run. For example, Stage 3 will run Stage 1, 2, and 3

        THE FOLLOWING STAGES ARE AVAILABLE FOR Test-NetStack:
            Stage 1: Testing Connectivity
            Stage 2: Testing MTU Configuration
            Stage 3: Testing TCP Throughput
            Stage 4: Testing RDMA Connectivity
            Stage 5: Testing RDMA Congestion (1:1)
            Stage 6: Testing RDMA Congestion (N:1)

    .EXAMPLE 4-node test Synthetic and Hardware Data Path
        Test-RDMA -MachineList 'AzStackHCI01', 'AzStackHCI02', 'AzStackHCI03', AzStackHCI04'

    .EXAMPLE Synthetic Tests Only
        Test-RDMA -MachineList 'AzStackHCI01', 'AzStackHCI02' -Stage 3

    .NOTES
        Author: Windows Core Networking team @ Microsoft
        Please file issues on GitHub @ GitHub.com/Microsoft/Test-NetStack
    .LINK
        More projects               : https://github.com/microsoft/sdn
        Validate-DCB                : https://github.com/microsoft/Validate-DCB
        Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
        RDMA Configuration Guidance : https://aka.ms/ConvergedNIC
    #>

    param (
        [Parameter(Mandatory=$false)]
        [ValidateCount(2, 16)]
        [String[]] $MachineList,  

        [Parameter(Mandatory=$false)]
        [ValidateSet('1', '2', '3', '4', '5', '6')]
        [Int32] $StageNumber = '6'
    )

    Clear-Host

    $here = Split-Path -Parent (Get-Module -Name Test-RDMA | Select-Object -First 1).Path
    $startTime = Get-Date -format:'yyyyMMdd-HHmmss'
    New-Item -Name 'Results' -Path $here -ItemType Directory -Force

    $testFile    = Join-Path -Path $here -ChildPath "tests\prerequisite.unit.tests.ps1"
    $prereqTests = Invoke-Pester -Script $testFile -Show All -PassThru

    If ($prereqTests.FailedCount -ne 0) {
        throw 'One or more prerequisite tests failed. Please review the test output, resolve the issues, then restart the tests'
    }

    #TODO: We may want to consider showing all output (success and failures) for positive on-screen feedback
    $testFile = Join-Path -Path $here -ChildPath "tests\test-netstack.unit.tests.ps1"
    $testNetStack = Invoke-Pester -Script $testFile -Show Summary, Failed

    If ($testNetStack.FailedCount -ne 0) {
        throw 'One or more tests failed. The system may not be ready to support production workloads. Please review the output, resolve the issues, then restart the tests'
    }

}

New-Alias -Name 'Test-RDMA' -Value 'Assert-RDMA' -Force