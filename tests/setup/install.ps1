git.exe clone -q https://github.com/PowerShell/DscResource.Tests

Import-Module -Name "$env:APPVEYOR_BUILD_FOLDER\DscResource.Tests\AppVeyor.psm1"
Invoke-AppveyorInstallTask

Remove-Item .\DscResource.Tests\ -Force -Confirm:$false -Recurse

Write-Output 'Checking version of CTSTraffic...'

git.exe clone -q https://github.com/microsoft/ctsTraffic c:\projects\CTSTraffic
$Releases = (Get-ChildItem c:\projects\CTSTraffic\Releases).Name | Sort-Object -Descending | Select-Object -First 1

$ExistingVersion = (Get-ItemProperty c:\projects\test-netstack\ctsTraffic.exe).versioninfo.fileversion

if ($ExistingVersion -ne $Releases) {
    Write-Output "Updating CTSTraffic from $ExistingVersion to $Releases"

    Copy-Item "C:\projects\CTSTraffic\Releases\$Releases\x64\ctstraffic.exe" 'C:\projects\Test-NetStack\tools\CTS-Traffic\ctstraffic.exe' -force

    Write-Output "Updated CTSTraffic from $ExistingVersion to $Releases"
}

Remove-Item C:\projects\CTSTraffic -Force -Confirm:$false -Recurse

Write-Output '...Ending CTSTraffic version check'

[string[]]$PowerShellModules = @("Pester", 'posh-git')

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
