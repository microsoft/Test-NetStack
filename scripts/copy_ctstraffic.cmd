REM Commands for Connecting to Machines -- Add Machine Names, Examples Below, Replace net use x: \\[Machine Name]\c$ [password] [domain\username]

net use X: /delete
net use Y: /delete
net use Z: /delete
net use W: /delete

net use x: \\[Machine Name]\c$ [password] /user:[domain\username]
net use y: \\[Machine Name]\c$ [password] /user:[domain\username]
net use z: \\[Machine Name]\c$ [password] /user:[domain\username]
net use w: \\[Machine Name]\c$ [password] /user:[domain\username]

REM Copying Over CTS-Traffic .exe -- Assumes Directory C:\cmd and C:\cmd\tools on each machine

copy .\tools\CTS-Traffic\ctsTraffic.exe x:\cmd\tools\CTS-Traffic
copy .\tools\CTS-Traffic\ctsTraffic.pdb x:\cmd\tools\CTS-Traffic

copy .\tools\CTS-Traffic\ctsTraffic.exe y:\cmd\tools\CTS-Traffic
copy .\tools\CTS-Traffic\ctsTraffic.pdb y:\cmd\tools\CTS-Traffic

copy .\tools\CTS-Traffic\ctsTraffic.exe z:\cmd\tools\CTS-Traffic
copy .\tools\CTS-Traffic\ctsTraffic.pdb z:\cmd\tools\CTS-Traffic

copy .\tools\CTS-Traffic\ctsTraffic.exe w:\cmd\tools\CTS-Traffic
copy .\tools\CTS-Traffic\ctsTraffic.pdb w:\cmd\tools\CTS-Traffic