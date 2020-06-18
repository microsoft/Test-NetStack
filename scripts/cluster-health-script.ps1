while($true) {

    # $MachineList = Invoke-Command -ComputerName OrAzs-Node01 -Credential $creds -ScriptBlock { (Get-ClusterNode).Name}
    
    # $OutputFile = "Test-NetStack Output File"
    # $OutputFile | Set-Content 'C:\Test-NetStack\Test-NetStack-Cluster-Health.txt'

    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'
    $ClusterHealth = (Invoke-Command -ComputerName $MachineList[1] -Credential $Credentials -ScriptBlock { (Get-ClusterNode).State })
    $VolumeHealth = (Invoke-Command -ComputerName $MachineList[1] -Credential $Credentials -ScriptBlock { (Get-VirtualDisk).HealthStatus })
    
    Write-Host $ClusterHealth
    $ClusterHealth | Out-File 'C:\Test-NetStack\Test-NetStack-Cluster-Health.txt' -Append -Encoding utf8 

    Write-Host $VolumeHealth
    $VolumeHealth | Out-File 'C:\Test-NetStack\Test-NetStack-Cluster-Health.txt' -Append -Encoding utf8 

    Write-Host "Time: $endTime`r`n"
    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Cluster-Health.txt' -Append -Encoding utf8

    Start-Sleep -Seconds 3

}

$MachineList = "TK5-3WP15R1009.cfdev.nttest.microsoft.com", "TK5-3WP15R1010.cfdev.nttest.microsoft.com", "TK5-3WP15R1011.cfdev.nttest.microsoft.com", "TK5-3WP15R1012.cfdev.nttest.microsoft.com", "TK5-3WP15R1013.cfdev.nttest.microsoft.com", "TK5-3WP15R1014.cfdev.nttest.microsoft.com", "TK5-3WP15R1015.cfdev.nttest.microsoft.com", "TK5-3WP15R1016.cfdev.nttest.microsoft.com"
$MachineList = "TK5-3WP13R1401.cfdev.nttest.microsoft.com", "TK5-3WP13R1403.cfdev.nttest.microsoft.com", "TK5-3WP13R1405.cfdev.nttest.microsoft.com", "TK5-3WP13R1407.cfdev.nttest.microsoft.com"