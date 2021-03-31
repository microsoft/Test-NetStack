Function Invoke-ICMPPMTUD {

    #If you change order of params, you must change the order of invoke-command params to match
    [CmdletBinding(DefaultParameterSetName = 'PMTUD')]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Alias("Sender","SourceIP")]
        [string] $Source,

        [Parameter(Mandatory=$true, Position=1)]
        [Alias("Receiver", "DestinationIP", "RemoteIP", "Target")]
        [string] $Destination,

        [Parameter(Mandatory=$false, Position=2)]
        [int] $StartBytes = 32,

        [Parameter(Mandatory=$false, Position=3)]
        [int] $EndBytes = 10000,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch] $Reliability = $false,

        [Parameter(Mandatory=$false, Position=5)]
        [int] $Count = 1000,

        [Parameter(Mandatory=$false, Position=6)]
        [int] $testTime = 15,

        # Used for Write-Progress must also specify ParentID
        [Parameter(Mandatory=$false, Position=7)]
        [int] $ID,

        # Used for Write-Progress must also specify ID
        [Parameter(Mandatory=$false, Position=8)]
        [int] $ParentID
    )

    #region Start-Ping: This function needs to be nested for sending remotely via Invoke-Command (e.g. Function:\Invoke-ICMPPMTU)
    Function Start-Ping {
        param (
            [Parameter(Mandatory=$true, Position=0)]
            [Alias("Sender","SourceIP")]
            [string] $Source,

            [Parameter(Mandatory=$true, Position=1)]
            [Alias("Receiver", "DestinationIP", "RemoteIP", "Target")]
            [string] $Destination,

            [Parameter(Mandatory=$false, Position=2)]
            [int] $Size = 32,

            [Parameter(Mandatory=$false, Position=3)]
            [Switch] $RTT
        )

Add-Type @"
    using System;
    using System.Net;
    using System.Text;
    using System.Runtime.InteropServices;

    public class IcmpPing
    {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
        private struct ICMP_OPTIONS
        {
            public byte Ttl;
            public byte Tos;
            public byte Flags;
            public byte OptionsSize;
            public IntPtr OptionsData;
        }

        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
        private struct ICMP_ECHO_REPLY
        {
            public int Address;
            public int Status;
            public int RoundTripTime;
            public short DataSize;
            public short Reserved;
            public IntPtr DataPtr;
            public ICMP_OPTIONS Options;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=9900)]
            public string Data;
        }

        [DllImport("Iphlpapi.dll", SetLastError = true)]
        private static extern IntPtr IcmpCreateFile();
        [DllImport("Iphlpapi.dll", SetLastError = true)]
        private static extern bool IcmpCloseHandle(IntPtr handle);
        [DllImport("Iphlpapi.dll", SetLastError = true)]
        private static extern int IcmpSendEcho2Ex(IntPtr icmpHandle, IntPtr hEvent, IntPtr apcRoutine, IntPtr apcContext, int sourceAddress, int destinationAddress, string requestData, short requestSize, ref ICMP_OPTIONS requestOptions, ref ICMP_ECHO_REPLY replyBuffer, int replySize, int timeout);

        public bool PingStatus(IPAddress sourceIp, IPAddress destIp, int dataSize)
        {
            IntPtr icmpHandle = IcmpCreateFile();
            ICMP_OPTIONS icmpOptions = new ICMP_OPTIONS();
            icmpOptions.Ttl = 255;
            icmpOptions.Flags = 0x02;
            ICMP_ECHO_REPLY icmpReply = new ICMP_ECHO_REPLY();
            string sData = CreateSendData(dataSize);

            int replies = IcmpSendEcho2Ex(icmpHandle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, BitConverter.ToInt32(sourceIp.GetAddressBytes(), 0), BitConverter.ToInt32(destIp.GetAddressBytes(), 0), sData, (short)sData.Length, ref icmpOptions, ref icmpReply, Marshal.SizeOf(icmpReply), 30);
            IcmpCloseHandle(icmpHandle);

            if (replies > 0)
            {
                return true;
            }

            return false;
        }

        public int PingRTT(IPAddress sourceIp, IPAddress destIp, int dataSize)
        {
            IntPtr icmpHandle = IcmpCreateFile();
            ICMP_OPTIONS icmpOptions = new ICMP_OPTIONS();
            icmpOptions.Ttl = 255;
            icmpOptions.Flags = 0x02;
            ICMP_ECHO_REPLY icmpReply = new ICMP_ECHO_REPLY();
            string sData = CreateSendData(dataSize);

            int replies = IcmpSendEcho2Ex(icmpHandle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, BitConverter.ToInt32(sourceIp.GetAddressBytes(), 0), BitConverter.ToInt32(destIp.GetAddressBytes(), 0), sData, (short)sData.Length, ref icmpOptions, ref icmpReply, Marshal.SizeOf(icmpReply), 30);
            IcmpCloseHandle(icmpHandle);

            if (replies > 0)
            {
                return icmpReply.RoundTripTime;
            }

            return -1;
        }

        private string CreateSendData(int length)
        {
            var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
            var random = new Random();
            StringBuilder builder = new StringBuilder();
            for(int index = 0; index < length; index++)
            {
                builder.Append(chars[random.Next(chars.Length)]);
            }
            return builder.ToString();
        }
    }
"@

        $pingStatus = [ICMPPing]::new()

        if ($RTT) {
            return ($pingStatus.PingRTT($Source, $Destination, $Size))
        }
        else {
            return ($pingStatus.PingStatus($Source, $Destination, $Size))
        }

        
    }

#endregion
    if (-Not($Reliability)) {
        [int] $lastKnownGood = -1

        if ((Start-Ping -Destination $Destination -Source $Source -Size $StartBytes)) {
            # update LKG
            $lastKnownGood = $StartBytes

            # last failed ping size
            $lastFailed = $EndBytes

            # next ping will be somewhere between start and end
            [int]$nextPing = [math]::Round(($EndBytes - $StartBytes) / 2, 0)

            # controls whether we found the MTU or not
            $MtuFound = $false

            :FindMTU while (-NOT $MtuFound) {
                do {
                    Write-Verbose "nextPing: $nextPing, LKG: $lastKnownGood, LF: $lastFailed"
                    $PingTest = Start-Ping -Destination $Destination -Source $Source -Size $nextPing

                    if ($PingTest) { $failedCounter = 0 }
                    else { $failedCounter = $failedCounter + 1 }

                } until ($PingTest -or $failedCounter -gt 3)


                # make payload smaller
                if (-NOT $PingTest) {
                    # save the failed ping size
                    $lastFailed = $nextPing

                    # find the nextPing
                    $nextPing = [math]::Round(($nextPing + $lastKnownGood) / 2, 0)

                    if ($nextPing -ge $lastKnownGood) {
                        $nextPing = [math]::Round(($lastFailed + $nextPing) / 2, 0)
                    }

                    Write-Verbose "NextPing: $nextPing"
                }
                else { # ping worked, but we're not done; make payload larger
                    $LKG = $nextPing

                    $nextPing = [math]::Round(($lastFailed + $lastKnownGood) / 2, 0)

                    if ($nextPing -le $lastKnownGood)
                    {
                        $nextPing = [math]::Round(($lastFailed + $nextPing) / 2, 0)
                    }

                    $lastKnownGood = $LKG
                    Write-Verbose "NextPing: $nextPing"
                }

                Write-Verbose "LastFailed: $lastFailed `n`n"

                # we should reach a point where nextping should be LKG + 1... then we're done
                if ($nextPing -eq $lastKnownGood) {
                    $MtuFound = $true
                    Write-Verbose "All done!"
                }
            }
        }

        if ($lastKnownGood -ne -1) {
            <#
                MTU = Payload + headers
                MSS = Payload

                ICMP headers are:

                Ethernet = 14 Bytes
                IP       = 20 Bytes
                ICMP     = 8 Bytes

                Total    = 42 Bytes
            #>

            $obj = New-Object -TypeName psobject
            $obj | Add-Member -MemberType NoteProperty -Name Connectivity -Value $true
            $obj | Add-Member -MemberType NoteProperty -Name MSS -Value $lastKnownGood
            $obj | Add-Member -MemberType NoteProperty -Name MTU -Value $($lastKnownGood + 42)

            return $obj
        }
        else { # ping failed for some reason
            Write-Verbose "There were no successful pings. Please make sure ping (ICMP Echo) is permitted to $Destination."

            $obj = New-Object -TypeName psobject
            $obj | Add-Member -MemberType NoteProperty -Name Connectivity -Value $false
            $obj | Add-Member -MemberType NoteProperty -Name MSS -Value '0'
            $obj | Add-Member -MemberType NoteProperty -Name MTU -Value '0'

            return $obj
        }
    }
    else { # If we already know the MTU, we can send a bunch at that size to see how reliable the link is
        $ICMPResponse = @()

        $testCompleted = 0
        $startTime = [System.DateTime]::Now

        do {
            $now = [System.DateTime]::Now
            $percentComplete = (($now - $startTime).TotalSeconds / $testTime) * 100

            $progressParams = @{
                Activity = 'Sending ICMP'
                Status   = 'Reliability Test'
                PercentComplete = $percentComplete
                SecondsRemaining = ($testTime - ($now - $startTime).TotalSeconds)
            }

            if ($ID -and $ParentID) {
                $progressParams.Add('Id', $ID)
                $progressParams.Add('ParentId', $ParentID)
            }

            Write-Progress @progressParams

            #Specify the RTT Switch. We'll use this for more stuff later.
            $ICMPResponse += Start-Ping -Source $Source -Destination $Destination -Size $StartBytes -RTT
        } until([System.DateTime]::Now -ge $startTime.AddSeconds($testTime))
        
        Return $ICMPResponse
    }
}
