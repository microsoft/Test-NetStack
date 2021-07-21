Function Test-NetStackPrerequisites {
    param (
        [String[]] $Nodes,

        [IPAddress[]] $IPTarget,

        [Int32[]] $Stage
    )

    #TODO: Test that CTSTraffic rule is in firewall

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

#region WinRM and OS
    $TargetInfo | Add-Member -MemberType NoteProperty -Name 'WinRM' -Value '' -Force
    $TargetInfo | Add-Member -MemberType NoteProperty -Name 'OSVersion' -Value '' -Force

    $Targets | ForEach-Object {
        $thisTarget = $_

        if ($thisTarget -ne $Env:ComputerName) {
            $WinRMResult = Test-NetConnection -CommonTCPPort WINRM -ComputerName $thisTarget -InformationLevel Quiet
            ($TargetInfo | Where-Object Name -eq $thisTarget).WinRM = $WinRMResult

            if (($TargetInfo | Where-Object Name -eq $thisTarget).WinRM -eq $true) {
                $NodeOS = Invoke-Command -ComputerName $thisTarget -ScriptBlock {
                    #$ProgressPreference = 'SilentlyContinue'
                    return $([System.Environment]::OSVersion.Version.Build -ge 20279)
                }
            }
        }
        else { # Machine is local; no need to test WinRM
            $ProgressPreference = 'SilentlyContinue'

            ($TargetInfo | Where-Object Name -eq $thisTarget).WinRM = $true

            $NodeOS = [System.Environment]::OSVersion.Version.Build -ge 20279
        }

        ($TargetInfo | Where-Object Name -eq $thisTarget).OSVersion = $NodeOS
    }

    $PrereqStatus += $false -notin $TargetInfo.WinRM
    $PrereqStatus += $false -notin $TargetInfo.OSVersion
#endregion WinRM and OS

    Switch ( $Stage | Sort-Object ) {
        1 { }

        2 {
            $TargetInfo | Add-Member -MemberType NoteProperty -Name 'Module' -Value '' -Force
            $TargetInfo | Add-Member -MemberType NoteProperty -Name 'Version' -Value '' -Force

            $Targets | ForEach-Object {
                $thisTarget = $_

                if ($thisTarget -ne $Env:ComputerName) {
                    $Module = Get-Module Test-NetStack -CimSession $thisTarget -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1

                    if ($Module) {
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $true
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Version = $Module.Version
                    }
                    else { ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $false }
                }
                else { # Machine is local; no need to test
                    $Module = Get-Module Test-NetStack -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1

                    if ($Module) {
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $true
                        ($TargetInfo | Where-Object Name -eq $thisTarget).Version = $Module.Version
                    }
                    else { ($TargetInfo | Where-Object Name -eq $thisTarget).Module = $false }
                }
            }

            $PrereqStatus += $false -notin $TargetInfo.Module
            $PrereqStatus += ($TargetInfo.Version | Select-Object -Unique).Count -eq 1
        }

        3 { }
        4 { }
        5 { }
        6 { }
    }

    return $TargetInfo, $PrereqStatus
}
