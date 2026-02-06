[string]$paramPackageConfig = $( if ($Args[0]) {$Args[0]} else {"CONFIG_NONE"} )

$currentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $currentDir
Set-Location $rootDir

# Build Config
$buildConfig = $paramPackageConfig
$buildConfigStr = $(if ($buildConfig -like "shipping") {""} else {"_${buildConfig}"})

# Build Version
$versionFilePath = Join-Path -Path $rootDir -ChildPath "Config\DefaultGame.ini"
$version = "VERSION_NONE"
$match = Select-String -Path $versionFilePath -Pattern "ProjectVersion=(.+)"
if ($match.Matches.Count -eq 1)
{
    $version = $match.Matches[0].Groups[1].Value
}
$versionStr = "_${version}"

# Git branch and commit
$branch = git rev-parse --abbrev-ref HEAD
$branchStr = $(if (($branch -like "dev") -or ($branch -like "regions")) {""} else {"-${branch}"})
$commit = git rev-parse --short HEAD
$commitStr = "-$($commit.Substring(0, 6))"

# SITL and DIS
$hasSitlCopter = $(if($Env:AllowAirSimSITL) {$Env:AllowAirSimSITL -eq 1} else {$False})
$hasSitlPlane  = $(if($Env:AllowJSBSimSITL) {$Env:AllowJSBSimSITL -eq 1} else {$False})
$hasDis        = $(if($Env:AllowDIS)        {$Env:AllowDIS        -eq 1} else {$False})
$sitlStr = ""
if ($hasSitlPlane -and $hasSitlCopter)
{
    $sitlStr = "-sitl"
}
elseif ($hasSitlPlane)
{
    $sitlStr = "-sitlP"
}
elseif ($hasSitlCopter)
{
    $sitlStr = "-sitlC"
}
$disStr = $(if ($hasDis) {"-dis"} else {""})

# Full build Name
$buildName = "Obriy${buildConfigStr}${versionStr}${branchStr}${commitStr}${sitlStr}${disStr}"
Write-Host "Packaging with BuildName $buildName"

# Paths
$buildsFolder = Join-Path -Path $rootDir -ChildPath "_Builds"
$buildFolder = Join-Path -Path $buildsFolder -ChildPath $buildName
$buildFolderPdb = "${buildFolder}_pdb"
$stagedBuildPath = Join-Path -Path $rootDir -ChildPath "Saved\StagedBuilds\Windows"
$installScriptPath = Join-Path -Path $rootDir -ChildPath "Misc\Install Script"
$installScriptPreparePath = Join-Path -Path $rootDir -ChildPath "Misc\PrepareInstallScript.bat"


# Prepare output folders
if (-NOT (Test-Path $buildsFolder))
{
    $null = New-Item -ItemType Directory -Path $buildsFolder
}
if (Test-Path $buildFolder)
{
    Write-Host "Removing previous folder $buildFolder"
    Remove-Item $buildFolder -Recurse
}
$null = New-Item -ItemType Directory -Path $buildFolder

if (Test-Path $buildFolderPdb)
{
    Write-Host "Removing previous folder $buildFolderPdb"
    Remove-Item $buildFolderPdb -Recurse
}
$null = New-Item -ItemType Directory -Path $buildFolderPdb

# Copy things into output folders
Write-Host "Copying $stagedBuildPath\* -> $buildFolder"
Copy-Item -Path "$stagedBuildPath\*" -Destination $buildFolder -Recurse
if  (-NOT ($?)) {Exit 1}

Write-Host "Preparing Install Script"
& $installScriptPreparePath
Write-Host "Copying $installScriptPath\* -> $buildFolder"
Copy-Item -Path "$installScriptPath\*" -Destination $buildFolder -Recurse -Exclude @(".gitignore",".vscode")
if (-NOT ($?)) {Exit 1}

Write-Host "Moving pdbs and manifests to $buildFolderPdb"
Get-ChildItem -Path "$buildFolder\*" -Include *.pdb -Recurse | Move-Item -Destination $buildFolderPdb
Get-ChildItem -Path "$buildFolder\*" -Include Manifest*.txt | Move-Item -Destination $buildFolderPdb
if (-NOT ($?)) {Exit 1}

Write-Host "Writing $buildFolder\version.txt"
"Version: $version" | Out-File -FilePath "$buildFolder\version.txt" -Append
"Commit: ${branch}:${commit}" | Out-File -FilePath "$buildFolder\version.txt" -Append
"Configuration: ${buildConfig}" | Out-File -FilePath "$buildFolder\version.txt" -Append
$featuresStr = "$(if($hasSitlCopter) {"sitl-copter "} else {})$(if($hasSitlPlane) {"sitl-plane "} else {})$(if($hasDis) {"dis"} else {})"
"Features: $(if([string]::IsNullOrWhiteSpace($featuresStr)) {"none"} else {$featuresStr})" | Out-File -FilePath "$buildFolder\version.txt" -Append
Add-Type -Assembly "System.IO.Compression.Filesystem"


# Archive output folders
Write-Host "Archiving $buildFolder -> $buildFolder.zip"
if (Test-Path "$buildFolder.zip")
{
    Write-Host "Removing previous archive $buildFolder.zip"
    Remove-Item "$buildFolder.zip"
}
[IO.Compression.ZipFile]::CreateFromDirectory( $buildFolder, "$buildFolder.zip", 'Fastest', $false )
#Compress-Archive -Path $buildFolder -DestinationPath "$buildFolder.zip"
if (-NOT ($?)) {Exit 1}

Write-Host "Archiving $buildFolderPdb -> $buildFolderPdb.zip"
if (Test-Path "$buildFolderPdb.zip")
{
    Write-Host "Removing previous archive $buildFolderPdb.zip"
    Remove-Item "$buildFolderPdb.zip"
}
[IO.Compression.ZipFile]::CreateFromDirectory( $buildFolderPdb, "$buildFolderPdb.zip", 'Fastest', $false )
#Compress-Archive -Path $buildFolderPdb -DestinationPath "$buildFolderPdb.zip"
if (-NOT ($?)) {Exit 1}

Exit 0