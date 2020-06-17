for ($i = 0; $i -lt 2; $i++) {

    $ServerName = "TK5-3WP07R0221"
    $ClientName = "TK5-3WP07R0223"
    $ServerIP = "192.168.68.125"
    $ClientIP = "192.168.68.126"
    $ClientLinkSpeed = 25000000000
    $ServerCommand = "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -StreamLength:30 -ConsoleVerbosity:1 -ServerExitLimit:500 -BufferDepth:3"
    $ClientCommand = "c:\test-netstack\tools\cts-traffic\ctsTraffic.exe -target:$ServerIP -bind:$ClientIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -BufferDepth:3 -StreamLength:30 -iterations:1 -ConsoleVerbosity:1 -verify:connection -connections:500"
    Write-Host $ServerCommand
    Write-Host $ClientCommand
    # start powershell -command {cmd \c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -StreamLength:30 -ConsoleVerbosity:1 -ServerExitLimit:500 -BufferDepth:3"}
    # cmd \c C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -StreamLength:30 -ConsoleVerbosity:1 -ServerExitLimit:500 -BufferDepth:3
    invoke-expression "start powershell {cmd /c C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -StreamLength:30 -ConsoleVerbosity:1 -ServerExitLimit:500 -BufferDepth:3}"
}


for ($i = 0; $i -lt 2; $i++) {

    $ServerName = "TK5-3WP07R0221"
    $ClientName = "TK5-3WP07R0223"
    $ServerIP = "192.168.68.125"
    $ClientIP = "192.168.68.126"
    $ClientLinkSpeed = 25000000000
    $ServerCommand = "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -StreamLength:30 -ConsoleVerbosity:1 -ServerExitLimit:500 -BufferDepth:3"
    $ClientCommand = "c:\test-netstack\tools\cts-traffic\ctsTraffic.exe -target:$ServerIP -bind:$ClientIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -BufferDepth:3 -StreamLength:30 -iterations:1 -ConsoleVerbosity:1 -verify:connection -connections:500"
    Write-Host $ServerCommand
    Write-Host $ClientCommand
    # start powershell -command {cmd \c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -StreamLength:30 -ConsoleVerbosity:1 -ServerExitLimit:500 -BufferDepth:3"}
    # cmd \c C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -StreamLength:30 -ConsoleVerbosity:1 -ServerExitLimit:500 -BufferDepth:3
    invoke-expression "start powershell {cmd /c c:\test-netstack\tools\cts-traffic\ctsTraffic.exe -target:$ServerIP -bind:$ClientIP -port:900$i -protocol:udp -bitspersecond:10000000 -FrameRate:100 -BufferDepth:3 -StreamLength:30 -iterations:1 -ConsoleVerbosity:1 -verify:connection -connections:500}"
}