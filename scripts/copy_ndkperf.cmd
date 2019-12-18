REM Commands for Connecting to Machines -- Add Machine Names, Examples Below, Replace net use x: \\[Machine Name]\c$ [password] [domain\username]

net use X: /delete
net use Y: /delete
net use Z: /delete
net use W: /delete

net use x: \\[Machine Name]\c$ [password] /user:[domain\username]
net use y: \\[Machine Name]\c$ [password] /user:[domain\username]
net use z: \\[Machine Name]\c$ [password] /user:[domain\username]
net use w: \\[Machine Name]\c$ [password] /user:[domain\username]

REM Copying Over NDK Perf .exe and .sys -- Assumes Directory C:\perf and C:\perf\driver on each machine

copy .\tools\NDK-Perf\NDKPerf.sys X:\perf
copy .\tools\NDK-Perf\NDKPerfCmd.exe X:\perf
copy .\tools\NDK-Perf\NDKPerfCmd.pdb X:\perf
copy .\tools\NDK-Perf\NDKPerf\NDKPerf.sys X:\perf\driver
copy .\tools\NDK-Perf\NDKPerf.pdb X:\perf\driver

copy .\tools\NDK-Perf\NDKPerf\NDKPerf.sys Y:\perf
copy .\tools\NDK-Perf\NDKPerfCmd.exe Y:\perf
copy .\tools\NDK-Perf\NDKPerfCmd.pdb Y:\perf
copy .\tools\NDK-Perf\NDKPerf\NDKPerf.sys Y:\perf\driver
copy .\tools\NDK-Perf\NDKPerf.pdb Y:\perf\driver

copy .\tools\NDK-Perf\NDKPerf.sys Z:\perf
copy .\tools\NDK-Perf\NDKPerfCmd.exe Z:\perf
copy .\tools\NDK-Perf\Symbols.pri\retail\exe\NDKPerfCmd.pdb Z:\perf
copy .\tools\NDK-Perf\NDKPerf.sys Z:\perf\driver
copy .\tools\NDK-Perf\Symbols.pri\retail\sys\NDKPerf.pdb Z:\perf\driver

copy .\tools\NDK-Perf\NDKPerf.sys W:\perf
copy .\tools\NDK-Perf\NDKPerfCmd.exe W:\perf
copy .\tools\NDK-Perf\Symbols.pri\retail\exe\NDKPerfCmd.pdb W:\perf
copy .\tools\NDK-Perf\NDKPerf.sys W:\perf\driver
copy .\tools\NDK-Perf\Symbols.pri\retail\sys\NDKPerf.pdb W:\perf\driver




