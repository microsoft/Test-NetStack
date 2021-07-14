$DataFile   = Import-PowerShellDataFile .\$($env:repoName).psd1 -ErrorAction SilentlyContinue
$TestModule = Test-ModuleManifest       .\$($env:repoName).psd1 -ErrorAction SilentlyContinue

Describe "$($env:APPVEYOR_BUILD_FOLDER)-Manifest" {
    Context Validation {
        It "[Manifest] - $($env:repoName).psd1 exists" { Test-Path "$($env:repoName).psd1" | Should Be True }

        It "[Test-Path] - $($env:repoName).psm1 exists" { Test-Path "$($env:repoName).psm1" | Should Be True }

        It "[Manifest Property] - $($env:repoName).psm1 exists" { $DataFile.RootModule | Should Be "$($env:repoName).psm1" }

        It "[Import-PowerShellDataFile] - $($env:repoName).psd1 is a valid PowerShell Data File" {
            $DataFile | Should Not BeNullOrEmpty
        }

        It "[Test-ModuleManifest] - $($env:repoName).psd1 should pass the basic test" {
            $TestModule | Should Not BeNullOrEmpty
        }

        'icmp.psm1', 'internal.psm1', 'ndk.psm1', 'tcp.psm1' | ForEach-Object {
            $thisModule = $_
            
            Write-Host "------------$PWD------------"

            Write-Host "------------$(dir C:\projects\Test-NetStack\helpers)----"
            
            Write-Host "------------ $($thisModule) ----"
            
            Write-Host "------------ $(Test-Path .\helpers\$thisModule) ----"

            It "[Test-Path] - $($env:repoName)\helpers\$thisModule exists" { Test-Path ".\helpers\$thisModule" | Should Be True }

            Import-Module .\$($env:repoName)\helpers\$thisModule -Force
            $Module = Get-Module $thisModule

            It "[Import-Module] - $($env:repoName)\helpers\$thisModule is a valid PowerShell Module" {
                $Module | Should Not BeNullOrEmpty
            }

            Switch ($Module.Name) {
                'icmp' {
                    'Invoke-ICMPPMTUD' | ForEach-Object {
                        It "Should have an available command: $_" {
                            $module.ExportedCommands.ContainsKey($_) | Should be $true
                        }
                    }
                }

                'internal' {
                    'Get-ConnectivityMapping', 'Get-TestableNetworksFromMapping', 'Get-DisqualifiedNetworksFromMapping', 'Get-RunspaceGroups',
                    'Get-Jitter', 'Get-Latency', 'Get-Failures', 'Write-LogFile', 'Convert-CIDRToMask', 'Convert-MaskToCIDR', 'Convert-IPv4ToInt',
                    'Convert-IntToIPv4' | ForEach-Object {
                        It "Should have an available command: $_" {
                            $module.ExportedCommands.ContainsKey($_) | Should be $true
                        }
                    }

                    $Analyzer = [Analyzer]::New()

                    It "Should have a class named $thisClass" {
                        $Analyzer |  Should Not BeNullOrEmpty
                    }

                    'MTU', 'Reliability', 'TCPPerf', 'NDKPerf' | ForEach-Object {
                        $thisClass = $_

                        It "Analyzer should define the class named $thisClass" {
                            $Analyzer.$thisClass | Should Not BeNullOrEmpty
                        }

                        Switch ($thisClass) {
                            'Reliability' {
                                It "Should require ICMPReliability to be -ge 90" {
                                    $Analyzer.$thisClass.ICMPReliability | Should BeGreaterOrEqual 90
                                }

                                It "Should require ICMPPacketLoss to be -ge 95" {
                                    $Analyzer.$thisClass.ICMPReliability | Should BeGreaterOrEqual 95
                                }
                            }

                            'TCPPerf' {
                                It "Should require TCP TPUT to be -ge 90" {
                                    $Analyzer.$thisClass.TPUT | Should BeGreaterOrEqual 90
                                }
                            }

                            'NDKPerf' {
                                It "Should require NDK TPUT to be -ge 90" {
                                    $Analyzer.$thisClass.TPUT | Should BeGreaterOrEqual 90
                                }
                            }
                        }
                    }
                }

                'ndk' {
                    'Invoke-NDKPing', 'Invoke-NDKPerf1to1', 'Invoke-NDKPerfNto1', 'Invoke-NDKPerfNtoN' | ForEach-Object {
                        It "Should have an available command: $_" {
                            $module.ExportedCommands.ContainsKey($_) | Should be $true
                        }
                    }
                }

                'tcp' {
                    'Invoke-TCP' | ForEach-Object {
                        It "Should have an available command: $_" {
                            $module.ExportedCommands.ContainsKey($_) | Should be $true
                        }
                    }
                }
            }
        }

        <#
        'Test-NICAdvancedProperties', 'Test-SwitchCapability' | ForEach-Object {
            It "Should have an available command: $_" {
                $module.ExportedCommands.ContainsKey($_) | Should be $true
            }
        }

        It "Should have an available alias: Test-NICProperties" {
            $module.ExportedAliases.ContainsKey('Test-NICProperties') | Should be $true
        }

        It "Should have an reference command: Test-NICAdvancedProperties" {
            $module.ExportedAliases.'Test-NICProperties'.ReferencedCommand.Name | Should be 'Test-NICAdvancedProperties'
        }

        It "Should have an required module of: DataCenterBridging" {
            $module.RequiredModules | Should be 'DataCenterBridging'
        }
        #>

        $requiredModule = Find-Module DataCenterBridging -ErrorAction SilentlyContinue
        It "Should list required modules (DataCenterBridging) on the PowerShell Gallery" {
            if ($requiredModule) { $true | Should be $true }
            else { $false | Should be $true }

        }
    }
}
