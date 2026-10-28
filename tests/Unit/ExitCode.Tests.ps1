BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'ConvertFrom-ActionExitCode' {
    It 'bildet <Code> auf <Outcome> ab' -ForEach @(
        @{ Code = 0; Outcome = 'Success' }
        @{ Code = 3010; Outcome = 'SuccessReboot' }
        @{ Code = 1641; Outcome = 'SuccessReboot' }
        @{ Code = 1602; Outcome = 'Cancelled' }
        @{ Code = 1223; Outcome = 'Cancelled' }
        @{ Code = 1605; Outcome = 'NotInstalled' }
        @{ Code = 1603; Outcome = 'Failed' }
        @{ Code = -1978335189; Outcome = 'NoUpdate' }        # 0x8A15002B UPDATE_NOT_APPLICABLE
        @{ Code = -1978335212; Outcome = 'NotInstalled' }    # 0x8A150014 NO_APPLICATIONS_FOUND
        @{ Code = -1978334975; Outcome = 'Failed' }          # 0x8A150101 PACKAGE_IN_USE
        @{ Code = -1978334967; Outcome = 'SuccessReboot' }   # 0x8A150109 REBOOT_REQUIRED_TO_FINISH
        @{ Code = -1978334964; Outcome = 'Cancelled' }       # 0x8A15010C CANCELLED_BY_USER
        @{ Code = 2316632107; Outcome = 'NoUpdate' }         # dieselbe Zahl ohne Vorzeichen
    ) {
        (InModuleScope SoftwareInventory -Parameters @{ C = $Code } { ConvertFrom-ActionExitCode $C }).Outcome | Should -Be $Outcome
    }

    It 'meldet unbekannte Codes als Fehler mit Code in Hex' {
        $r = InModuleScope SoftwareInventory { ConvertFrom-ActionExitCode -1978335000 }
        $r.Outcome | Should -Be 'Failed'
        $r.Code | Should -Be '0x8A1500E8'
        $r.Message.Code | Should -Be 'ExitCodeUnknown'
        $r.Message.Args | Should -Be @('0x8A1500E8')
    }

    It 'schreibt kleine Codes dezimal' {
        InModuleScope SoftwareInventory { Format-ExitCode 3010 } | Should -Be '3010'
        InModuleScope SoftwareInventory { Format-ExitCode -1978334961 } | Should -Be '0x8A15010F'
    }
}
