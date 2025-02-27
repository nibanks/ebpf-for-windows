﻿# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param ([Parameter(Mandatory=$True)] [string] $WorkingDirectory,
       [Parameter(Mandatory=$True)] [string] $LogFileName)

Push-Location $WorkingDirectory

Import-Module .\common.psm1 -Force -ArgumentList ($LogFileName) -WarningAction SilentlyContinue
Import-Module .\install_ebpf.psm1 -Force -ArgumentList ($WorkingDirectory, $LogFileName) -WarningAction SilentlyContinue

#
# Execute tests on VM.
#

function Invoke-NetshEbpfCommand
{
    param([Parameter(Mandatory=$True)][string] $Arguments)

    $ArgumentsList = @("ebpf") + $Arguments.Split(" ")

    $AddProgram = $false
    if ($ArgumentsList[1] -eq "add"){
        $AddProgram = $true
    }

    $LASTEXITCODE = 0
    $Output = &netsh.exe $ArgumentsList 2>&1

    # Check for errors.
    if ($LASTEXITCODE -ne 0) {
        throw ("netsh command returned error.")
    }

    Out-String -InputObject $Output | Write-Log -ForegroundColor Green

    # For add program command, the 4th element of the output string contains
    # the program Id.

    if ($AddProgram -eq $true) {
        $ProgId = ($Output.Split(" "))[3]
        return $ProgId
    }
}

function Invoke-Test
{
    param([Parameter(Mandatory=$True)][string] $TestName,
          [Parameter(Mandatory=$True)][bool] $VerboseLogs)

    Write-Log "Executing $Testname"

    $LASTEXITCODE = 0

    # Execute Test.
    if ($VerboseLogs -eq $true) {
        $Output = &$TestName "-s"
    } else {
        $Output = &$TestName
    }

    # Check for errors.
    Out-String -InputObject $Output | Write-Log
    $ParsedOutput = $Output.Split(" ")
    if (($LASTEXITCODE -ne 0) -or ($ParsedOutput[$ParsedOutput.Length -2] -eq "failed")) { throw ("$TestName Test Failed.") }

    Write-Log "$TestName Passed" -ForegroundColor Green
}

function Invoke-CICDTests
{
    param([parameter(Mandatory=$true)][bool] $VerboseLogs)

    pushd $WorkingDirectory

    try {

         $TestList = @(
            "unit_tests.exe",
            "ebpf_client.exe",
            "api_test.exe",
            "sample_ext_app.exe")

        foreach ($Test in $TestList) {
            Invoke-Test -TestName $Test -VerboseLogs $VerboseLogs
        }

        if ($Env:BUILD_CONFIGURATION -eq "Release") {
            Invoke-Test -TestName "ebpf_performance.exe" -VerboseLogs $VerboseLogs
        }
    } catch {
        Write-Log "One or more tests failed."
        throw
    }

    popd
}

function Invoke-XDPTest
{
    param([parameter(Mandatory=$true)][string] $RemoteIPV4Address,
          [parameter(Mandatory=$true)][string] $RemoteIPV6Address,
          [parameter(Mandatory=$true)][string] $XDPTestName,
          [parameter(Mandatory=$true)][string] $WorkingDirectory)

    pushd $WorkingDirectory

    Write-Log "Executing $XDPTestName with remote address: $RemoteIPV4Address."
    $LASTEXITCODE = 0
    $Output = .\xdp_tests.exe $XDPTestName --remote-ip $RemoteIPV4Address
    Out-String -InputObject $Output | Write-Log
    $ParsedOutput = $Output.Split(" ")
    if (($LASTEXITCODE -ne 0) -or ($ParsedOutput[$ParsedOutput.Length -2] -eq "failed")) { throw ("$XDPTestName Test Failed.") }

    Write-Log "Executing $XDPTestName with remote address: $RemoteIPV6Address."
    $LASTEXITCODE = 0
    $Output = .\xdp_tests.exe $XDPTestName --remote-ip $RemoteIPV6Address
    Out-String -InputObject $Output | Write-Log
    $ParsedOutput = $Output.Split(" ")
    if (($LASTEXITCODE -ne 0) -or ($ParsedOutput[$ParsedOutput.Length -2] -eq "failed")) { throw ("$XDPTestName Test Failed.") }

    Write-Log "$XDPTestName Test Passed" -ForegroundColor Green

    popd
}

Pop-Location