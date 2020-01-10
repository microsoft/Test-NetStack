function Assert-RDMA {
    <#
    .SYNOPSIS
        <TODO>
    .DESCRIPTION
        <TODO>
    .EXAMPLE
        <TODO>
    .EXAMPLE
        <TODO>
    .NOTES
        Author: Windows Core Networking team @ Microsoft
        Please file issues on GitHub @ GitHub.com/Microsoft/Test-RDMA
    .LINK
        More projects               : https://github.com/microsoft/sdn
        Validate-DCB                : https://github.com/microsoft/Validate-DCB
        Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
        RDMA Configuration Guidance : https://aka.ms/ConvergedNIC
    #>

    Clear-Host

    # TODO: Once converted to module, just add pester to required modules

    If (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Output 'Pester is an inbox PowerShell Module included in Windows 10, Windows Server 2016, and later'
        Throw 'Catastrophic Failure :: PowerShell Module Pester was not found'
    }

    $here = Split-Path -Parent (Get-Module -Name Test-RDMA | Select-Object -First 1).Path
    $startTime = Get-Date -format:'yyyyMMdd-HHmmss'
    New-Item -Name 'Results' -Path $here -ItemType Directory -Force


    $testFile = Join-Path -Path $here -ChildPath "\global.unit.tests.ps1"
    $launch_deploy = Invoke-Pester -Script $testFile -Show Summary, Failed
    # $launch_deploy = Invoke-Pester -Script $testFile -PassThru
    # $launch_deploy | Select-Object -Property TagFilter, Time, TotalCount, PassedCount, FailedCount, SkippedCount, PendingCount | Format-Table -AutoSize

}

New-Alias -Name 'Test-RDMA' -Value 'Assert-RDMA' -Force