Function Test-NetStackPrerequisites {
    param (
        [String[]] $Nodes,

        [IPAddress[]] $IPTarget,

        [Int32[]] $Stage,

        [Switch] $EnableFirewallRules
    )

#region Targets
    if ($IPTarget) { $Targets = $IPTarget }
    else { $Targets = $Nodes }

    $TargetInfo = @()
    $Targets | ForEach-Object {
        $thisTarget = $_

        $thisPrereqResult = @{}
        $thisPrereqResult = [PSCustomObject] @{
            Name = $thisTarget
        }

        $TargetInfo += $thisPrereqResult
    }

    $PrereqStatus = @()
#endregion Targets

#region WinRM and OS
    $TargetInfo | Add-Member -MemberType NoteProperty -Name 'WinRM' -Value '' -Force
    $TargetInfo | Add-Member -MemberType NoteProperty -Name 'OSVersion' -Value '' -Force

    $Targets | ForEach-Object {
        $thisTarget = $_

        if ($EnableFirewallRules) {
            if ($thisTarget -ne $Env:ComputerName) {
                $null = Enable-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)' -CimSession $thisTarget -ErrorAction SilentlyContinue
            }
            else {
                $null = Enable-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)' -ErrorAction SilentlyContinue
            }
        }

        if ($thisTarget -ne $Env:ComputerName) {
            # If $NodeOS -ne $null then we can assume WinRM is successful
            $NodeOS = Invoke-Command -ComputerName $thisTarget -ErrorAction SilentlyContinue -ScriptBlock {
                return $([System.Environment]::OSVersion.Version.Build -ge 20279)
            }

            if ($NodeOS) { ($TargetInfo | Where-Object Name -eq $thisTarget).WinRM = $true }
        }
        else { # Machine is local; no need to test WinRM
            $NodeOS = [System.Environment]::OSVersion.Version.Build -ge 20279
            ($TargetInfo | Where-Object Name -eq $thisTarget).WinRM = $true
        }

        ($TargetInfo | Where-Object Name -eq $thisTarget).OSVersion = $NodeOS
    }

    $PrereqStatus += $false -notin $TargetInfo.WinRM
    $PrereqStatus += $false -notin $TargetInfo.OSVersion
#endregion WinRM and OS

    Switch ( $Stage | Sort-Object ) {
        1 {
            $TargetInfo | Add-Member -MemberType NoteProperty -Name 'ICMP' -Value '' -Force

            $Targets | ForEach-Object {
                if ($EnableFirewallRules) {
                    if ($thisTarget -ne $Env:ComputerName) {
                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In' -CimSession $thisTarget -ErrorAction SilentlyContinue
                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In' -CimSession $thisTarget -ErrorAction SilentlyContinue

                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In-NoScope' -CimSession $thisTarget -ErrorAction SilentlyContinue
                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In-NoScope' -CimSession $thisTarget -ErrorAction SilentlyContinue
                    }
                    else {
                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In' -ErrorAction SilentlyContinue
                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In' -ErrorAction SilentlyContinue

                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In-NoScope' -ErrorAction SilentlyContinue
                        $null = Enable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In-NoScope' -ErrorAction SilentlyContinue
                    }
                }

                $thisTarget = $_

                if ($thisTarget -ne $Env:ComputerName) {
                    $ICMPResult = Test-NetConnection -ComputerName $thisTarget -InformationLevel Quiet
                    ($TargetInfo | Where-Object Name -eq $thisTarget).ICMP = $ICMPResult
                }
                else { # Machine is local; no need to test
                    ($TargetInfo | Where-Object Name -eq $thisTarget).ICMP = $true
                }

                $PrereqStatus += $false -notin $TargetInfo.ICMP
            }
        }

        2 {
            $TargetInfo | Add-Member -MemberType NoteProperty -Name 'Module' -Value '' -Force
            $TargetInfo | Add-Member -MemberType NoteProperty -Name 'Version' -Value '' -Force

            $Targets | ForEach-Object {
                $thisTarget = $_

                if ($thisTarget -ne $Env:ComputerName) {
                    $Module = Invoke-Command -ComputerName $thisTarget -ScriptBlock {
                        Get-Module Test-NetStack -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
                    }

                    if ($Module) {
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $true
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Version = $Module.Version
                    }
                    else { ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $false }

                    if ($EnableFirewallRules) {
                        $psSession = New-PSSession -ComputerName $thisTarget
                        $ModuleBase = (Get-Module Test-NetStack -PSSession $psSession -ListAvailable).ModuleBase
                        Remove-PSSession -Session $psSession
                        $null = New-NetFirewallRule -CimSession $thisTarget -DisplayName 'Test-NetStack - NTTTCP' -Direction Inbound -Program "$ModuleBase\tools\NTttcp\ntttcp.exe" -Action Allow -ErrorAction SilentlyContinue
                    }
                }
                else { # Machine is local; no need to test
                    $Module = Get-Module Test-NetStack -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1

                    if ($Module) {
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $true
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Version = $Module.Version
                    }
                    else { ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $false }

                    if ($EnableFirewallRules) {
                        $ModuleBase = (Get-Module Test-NetStack -ListAvailable | Select-Object -First 1).ModuleBase
                        $null = New-NetFirewallRule -DisplayName 'Test-NetStack - NTTTCP' -Direction Inbound -Program "$ModuleBase\tools\NTttcp\ntttcp.exe" -Action Allow -ErrorAction SilentlyContinue
                    }
                }
            }

            $PrereqStatus += $false -notin $TargetInfo.Module
            $PrereqStatus += ($TargetInfo.Version | Select-Object -Unique).Count -eq 1
        }

        { $_ -eq 3 -or $_ -eq 4 -or $_ -eq 5 -or $_ -eq 6 } {
            $Targets | ForEach-Object {
                $thisTarget = $_

                if ($thisTarget -ne $Env:ComputerName) {
                    if ($EnableFirewallRules) {
                        $null = Enable-NetFirewallRule 'FPSSMBD-iWARP-In-TCP' -CimSession $thisTarget -ErrorAction SilentlyContinue
                    }
                }
                else { # Machine is local; no need to test
                    if ($EnableFirewallRules) {
                        $null = Enable-NetFirewallRule 'FPSSMBD-iWARP-In-TCP' -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        4 { }
        5 { }
        6 { }
    }

    return $TargetInfo, $PrereqStatus
}

Function Revoke-FirewallRules {
    param (
        $Targets,
        [Int32[]] $Stage
    )

    Write-Warning 'WinRM rules with DisplayName "Windows Remote Management (HTTP-In)" will not be disabled'

    Switch ( $Stage | Sort-Object ) {
        1 {
            $Targets | ForEach-Object {
                $thisTarget = $_

                if ($thisTarget -ne $Env:ComputerName) {
                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In' -CimSession $thisTarget -ErrorAction SilentlyContinue
                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In' -CimSession $thisTarget -ErrorAction SilentlyContinue

                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In-NoScope' -CimSession $thisTarget -ErrorAction SilentlyContinue
                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In-NoScope' -CimSession $thisTarget -ErrorAction SilentlyContinue
                }
                else {
                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In' -ErrorAction SilentlyContinue
                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In' -ErrorAction SilentlyContinue

                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In-NoScope' -ErrorAction SilentlyContinue
                    $null = Disable-NetFirewallRule -Name 'FPS-ICMP6-ERQ-In-NoScope' -ErrorAction SilentlyContinue
                }
            }
        }

        2 {
            $Targets | ForEach-Object {
                $thisTarget = $_

                if ($thisTarget -ne $Env:ComputerName) {
                    $null = Remove-NetFirewallRule -DisplayName 'Test-NetStack - NTTTCP' -CimSession $thisTarget -ErrorAction SilentlyContinue
                }
                else {
                    $null = Remove-NetFirewallRule -DisplayName 'Test-NetStack - NTTTCP' -ErrorAction SilentlyContinue
                }
            }
        }

        { $_ -eq 3 -or $_ -eq 4 -or $_ -eq 5 -or $_ -eq 6 } {
            $Targets | ForEach-Object {
                $thisTarget = $_

                if ($thisTarget -ne $Env:ComputerName) {
                    $null = Disable-NetFirewallRule -Name 'FPSSMBD-iWARP-In-TCP' -CimSession $thisTarget -ErrorAction SilentlyContinue
                }
                else {
                    $null = Disable-NetFirewallRule -Name 'FPSSMBD-iWARP-In-TCP' -ErrorAction SilentlyContinue
                }
            }
        }

        3 { }
        4 { }
        5 { }
        6 { }
    }
}