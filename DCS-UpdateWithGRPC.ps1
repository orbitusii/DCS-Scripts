param(
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [Parameter(Position = 0)]
    [string] $InstallPath,
    [switch] $NoUpdate
)

Write-Output "Welcome to Sendit's DCS Updater script with GRPC support!"
Write-Output "This script will update DCS, then update its MissionScripting.lua file to add the dofile call required to make dcs-grpc function."
Write-Output "Please contact Sendit on Github (https://github.com/orbitusii) or Discord (@orbitusii) for questions, comments, or concerns."

# Checks to see if the user passed an InstallPath string. If it's empty, read from the console. If it's STILL empty, then default to C:\Program Files
if ($InstallPath -eq "") {
    $inputpath = Read-Host -Prompt "DCS Install directory (defaults to 'C:\Program Files\Eagle Dynamics\DCS World OpenBeta\')";
    if ($inputpath -eq "") {
        $InstallPath = "C:\Program Files\Eagle Dynamics\DCS World OpenBeta\";
    }
    else {
        $InstallPath = $inputpath;
    }
}

# Start the updater! The script will wait for it to complete before proceeding.
$updaterPath = Join-Path -Path $InstallPath -ChildPath "bin\DCS_updater.exe";

if ($NoUpdate.IsPresent) {
    Write-Output "NoUpdate flag present, skipping DCS updater."
}
else {
    Write-Output "Starting Updater...";
    Start-Process $updaterPath -ArgumentList @("update");
    Write-Output "Waiting for Updater to exit...";
    Get-Process | Where-Object ProcessName -Like "DCS*Updater*" | Wait-Process;
    Write-Output "Done!`n`nUpdating MissionScripting.lua with GRPC functions...";
}

# Locate the MissionScripting.lua file, then read its contents into a variable that we can manipulate.
$scriptPath = Join-Path -Path $InstallPath -ChildPath "Scripts\MissionScripting.lua";

$content = Get-Content -Path $scriptPath;
$insertionPoint = -1;
$addGRPCLine = $true;
$changed = $false;
$regex = "(?<comment>--)?dofile\((?<script>.+)\)";

# Skim through the contents looking for lines that have a 'dofile(...)' call
for ($i = 0; $i -lt $content.Count; $i++) {
    $line = $content[$i];
    $dofile = [regex]::Match($line, $regex);

    # If we found a dofile call, analyze it!
    if ($dofile.Success) {
        $script = $dofile.Groups['script'].Value;
        $isComment = $dofile.Groups['comment'].Success;
        Write-Debug "Found a dofile call: $line`nIs it a comment? $isComment";

        # This is a default call to 'Scripts/ScriptingSystem.lua,' we'll insert the GRPC line after this
        if ($script -like "'Scripts*'") {
            Write-Output "Found a default dofile call at $i. Inserting GRPC calls after this.";
            $insertionPoint = $i;
        }
        # This is the call to GRPC that we were planning to add. Since we found it, we won't add another line that does the same thing.
        elseif ($script -like "lfs.*gRPC*") {
            Write-Output "Found a GRPC dofile call at $i, don't need to add it again!";

            if ($isComment) {
                Write-Output "Line was commented out, undoing that"
                $content[$i] = $content[$i].Replace("--", "");
                $changed = $true;
            }
            $addGRPCLine = $false;
        }
    }
}

# We didn't find an existing grpc dofile() call, so add it! Simple array concatenation.
if ($addGRPCLine) {
    Write-Output "`nNo GRPC line found! Adding..."
    $content = $content[0..$insertionPoint] + @("dofile(lfs.writedir()..[[Scripts\DCS-gRPC\grpc-mission.lua]])") + $content[($insertionPoint + 1)..($content.Count)];
    $changed = $true;
}

# Add some whitespace for clarity.
Write-Output "";

if ($changed) {
    Write-Output "Double check that this is correct:";
    foreach ($line in $content) {
        Write-Output $line;
    }

    # Verify that the user wants to proceed with the changes
    if ($PSCmdlet.ShouldProcess("$scriptPath", "Write the modified script to file?")) {
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False;
        [System.IO.File]::WriteAllLines($scriptPath, $content, $Utf8NoBomEncoding);
    }
}
else {
    Write-Output "No changes were made to MissionScripting.lua."
}
Write-Output "Done!";