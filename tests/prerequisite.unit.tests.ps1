Describe 'Test-NetStack Prerequisite Tests' {
    $MachineList | Foreach-Object {
        $thisMachine = $_

        Context "[SUT: $thisMachine] Remote availability" {
            $ping  = Test-Connection    -ComputerName $thisMachine -Quiet -ErrorAction SilentlyContinue
            $SMB   = Test-NetConnection -ComputerName $thisMachine -CommonTCPPort SMB   -InformationLevel Quiet -ErrorAction SilentlyContinue
            $WinRM = Test-NetConnection -ComputerName $thisMachine -CommonTCPPort WINRM -InformationLevel Quiet -ErrorAction SilentlyContinue

            It "[SUT: $thisMachine] Should reply to ICMP-v4 echo requests (ping)" {
                $ping | Should be $true
            }

            It "[SUT: $thisMachine] Should have WinRM open for remoting" {
                $WINRM | Should be $true
            }

            It "[SUT: $thisMachine] Should have SMB open to accept file copies" {
                $SMB | Should be $true
            }
        }
    }
}
