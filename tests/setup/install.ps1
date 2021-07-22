git.exe clone -q https://github.com/PowerShell/DscResource.Tests

Import-Module -Name "$env:APPVEYOR_BUILD_FOLDER\DscResource.Tests\AppVeyor.psm1"
Invoke-AppveyorInstallTask

Remove-Item .\DscResource.Tests\ -Force -Confirm:$false -Recurse

[string[]]$PowerShellModules = @("Pester")

$ModuleManifest = Test-ModuleManifest .\$($env:RepoName).psd1 -ErrorAction SilentlyContinue
$repoRequiredModules = $ModuleManifest.RequiredModules.Name
$repoRequiredModules += $ModuleManifest.PrivateData.PSData.ExternalModuleDependencies

If ($repoRequiredModules) { $PowerShellModules += $repoRequiredModules }

# Feature Installation
$serverFeatureList = @('Hyper-V')

If ($PowerShellModules -contains 'FailoverClusters') {
    $serverFeatureList += 'RSAT-Clustering-Mgmt', 'RSAT-Clustering-PowerShell'
}

$BuildSystem = Get-CimInstance -ClassName 'Win32_OperatingSystem'

ForEach ($Module in $PowerShellModules) {
    If ($Module -eq 'FailoverClusters') {
        Switch -Wildcard ($BuildSystem.Caption) {
            '*Windows 10*' {
                Write-Output 'Build System is Windows 10'
                Write-Output "Not Implemented"

                # Get FailoverCluster Capability Name and Install on W10 Builds
                $capabilityName = (Get-WindowsCapability -Online | Where-Object Name -like *RSAT*FailoverCluster.Management*).Name
                Add-WindowsCapability -Name $capabilityName -Online
            }

            Default {
                Write-Output "Build System is $($BuildSystem.Caption)"
                Install-WindowsFeature -Name $serverFeatureList -IncludeManagementTools | Out-Null
            }
        }
    }
    ElseIf ($Module -eq 'Pester') {
        Write-Output "Installing Pester version 4.9.0"
        Install-Module $Module -Scope AllUsers -Force -Repository PSGallery -AllowClobber -SkipPublisherCheck -RequiredVersion 4.9.0
        Import-Module $Module -RequiredVersion 4.9.0
    }
    else {
        Install-Module $Module -Scope AllUsers -Force -Repository PSGallery -AllowClobber
        Import-Module $Module
    }
}
