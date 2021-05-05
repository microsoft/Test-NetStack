function Invoke-NDKPing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $Server,

        [Parameter(Mandatory=$true, Position=1)]
        [PSObject] $Client
    )

    Write-Host ":: $([System.DateTime]::Now) :: $($Client.NodeName) [$($Client.IPaddress)] -> $($Server.NodeName) [$($Server.IPAddress)] [NDK Ping]"

    $NDKPingResults = New-Object -TypeName psobject

    $ServerOutput = Start-Job `
    -ScriptBlock {
        param([string]$ServerName,[string]$ServerIP,[string]$ServerIF)
        Invoke-Command -ComputerName $ServerName `
        -ScriptBlock {
            param([string]$ServerIP,[string]$ServerIF)
            cmd /c "NdkPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 5 2>&1"
        } `
        -ArgumentList $ServerIP,$ServerIF
    } `
    -ArgumentList $Server.NodeName,$Server.IPAddress,$Server.InterfaceIndex

    Start-Sleep -Seconds 1

    $ClientOutput = Invoke-Command -ComputerName $Client.NodeName `
    -ScriptBlock { 
        param([string]$ServerIP,[string]$ClientIP,[string]$ClientIF)
        cmd /c "NdkPerfCmd.exe -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping 2>&1" 
    } `
    -ArgumentList $Server.IPAddress,$Client.IPAddress,$Client.InterfaceIndex

    Start-Sleep -Seconds 5
            
    $ServerOutput = Receive-Job $ServerOutput
                                
    Write-Verbose "NDK Ping Server Output: "
    $ServerOutput | ForEach-Object {
        $ServerSuccess = $_ -match 'completes'
        if ($_) { Write-Verbose $_ }
    }

    $NDKPingResults | Add-Member -MemberType NoteProperty -Name ServerSuccess -Value $ServerSuccess
    Return $NDKPingResults
}
    