[CmdletBinding()]
param (
    [string[]] $Actions,

    [string] $Configuration,

    [string[]] $Features = @()
)

# Set paths. Set current dir to the root dir of the project
$currentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Split-Path -Parent $currentDir
$outPackagedDir = Join-Path -Path $rootDir -ChildPath "Saved\StagedBuilds\Windows"
$global:savedLocation = Get-Location
Set-Location $rootDir

if ($Env:UE_ROOT)
{
    $engineDir = $Env:UE_ROOT
    Write-Host "Using Engine path set in Env:UE_ROOT: $engineDir" -ForegroundColor Yellow
}
else
{
    $engineDir = Split-Path -Parent $rootDir
    $engineDir = Join-Path -Path $engineDir -ChildPath "UnrealEngine"
    Write-Host "Using default Engine path: $engineDir. To override set Env:UE_ROOT" -ForegroundColor Yellow
}

# Configuration - supported actions and their parameters
$aCleanBinaries        = "CleanBinaries"
$aCleanSaved           = "CleanSaved"
$aGenerateProject      = "GenerateProject"
$aBuildEditor          = "BuildEditor"
$aBuildPackage         = "BuildPackage"
$aRunEditor            = "RunEditor"
$aPackArchive          = "PackArchive"

$ActionDescriptions = [ordered]@{
    $aCleanBinaries        = "Clean Binaries and Intermediate folder both for project and plugins";
    $aCleanSaved           = "Clean Saved folder - remove untracked files, including Cooked and Staged Builds";
    $aGenerateProject      = "Generate Visual Studio project files";
    $aBuildEditor          = "Build Editor";
    $aBuildPackage         = "Build package - build and cook";
    $aRunEditor            = "Run Editor";
    $aPackArchive          = "Pack existing build into a zip archive together with install script and other needed files";
}

$ActionProperties = [ordered]@{
    $aCleanBinaries        = [PSCustomObject]@{ConfigurationRequired = $False; FeaturesSupported = $False};
    $aCleanSaved           = [PSCustomObject]@{ConfigurationRequired = $False; FeaturesSupported = $False};
    $aGenerateProject      = [PSCustomObject]@{ConfigurationRequired = $False; FeaturesSupported = $False};
    $aBuildEditor          = [PSCustomObject]@{ConfigurationRequired = $True;  FeaturesSupported = $True};
    $aBuildPackage         = [PSCustomObject]@{ConfigurationRequired = $True;  FeaturesSupported = $True};
    $aRunEditor            = [PSCustomObject]@{ConfigurationRequired = $False; FeaturesSupported = $False};
    $aPackArchive          = [PSCustomObject]@{ConfigurationRequired = $True;  FeaturesSupported = $True};
}

$SupportedActions = @($aCleanBinaries, $aCleanSaved, $aGenerateProject, $aBuildEditor, $aBuildPackage, $aRunEditor, $aPackArchive)

$cTest = "Test"
$cShipping = "Shipping"
$cDevelopment = "Development"
$cDebugGame = "DebugGame"


$SupportedConfigurations = @{
    $aBuildEditor  = @($cDevelopment, $cDebugGame);
    $aBuildPackage = @($cTest, $cShipping, $cDevelopment);
    $aPackArchive  = @($cTest, $cShipping, $cDevelopment);
}

$fDIS = "DIS"
$fSITLCopter = "SITLCopter"
$fSITLPlane = "SITLPlane"

$SupportedFeatures = @{
    $aBuildEditor = @();
    $aBuildPackage = @($fDIS, $fSITLCopter, $fSITLPlane);
    $aPackArchive = @($fDIS, $fSITLCopter, $fSITLPlane);
}

$FeaturesToEnv = @{
    $fDIS          = "AllowDIS";
    $fSITLCopter   = "AllowAirSimSITL";
    $fSITLPlane    = "AllowJSBSimSITL";
}

function ExitWithCode($exitcode) {
    Set-Location $global:savedLocation
    $host.SetShouldExit($exitcode)
    exit $exitcode
}

function Write-Help()
{
    Write-Host ""
    Write-Host "Usage: BuildObriy.ps1 -Actions <act1,act2...> -Configuration <configuration> -Features <feat1,feat2...>"
    Write-Host ""
    Write-Host "Actions can be passed in any order, but they will be executed in a fixed order. First clean, then build etc."
    Write-Host ""
    Write-Host "Parameter -Features is optional"
    Write-Host ""
    Write-Host "Supported actions (will be executed in this order):"
    $ActionDescriptions | Format-Table -Property Key, Value -AutoSize -HideTableHeaders | Out-String | foreach-Object { $_.Trim() }
    Write-Host ""
    Write-Host "Supported configurations:"
    $SupportedConfigurations | Format-Table -Property Key, Value -AutoSize -HideTableHeaders | Out-String | foreach-Object { $_.Trim() }
    Write-Host ""
    Write-Host "Supported features:"
    $SupportedFeatures | Format-Table -Property Key, Value -AutoSize -HideTableHeaders | Out-String | foreach-Object { $_.Trim() }

}

# Parameter Validation

$actionsOk = $True
if ($Actions.Length -eq 0)
{
    Write-Host "No Actions" -ForegroundColor Red
    Write-Help
    ExitWithCode(1)
}
foreach ($action in $Actions )
{
    if (-NOT ($SupportedActions.Contains($action)))
    {
        Write-Host "Unsupported action $action" -ForegroundColor Red
        $actionsOk = $False
    }
}
if (-NOT $actionsOk)
{
    Write-Help
    ExitWithCode(1)
}


$configurationRequired = $False
$configurationOk = $True
foreach ($action in $Actions )
{
    if ($ActionProperties[$action].ConfigurationRequired)
    {
        $configurationRequired = $True
        if ($Configuration)
        {
            if (-NOT ($SupportedConfigurations[$action].Contains($Configuration)))
            {
                Write-Host "Configuration $Configuration is not supported by action $action" -ForegroundColor Red
                $configurationOk = $False
            }
        }
    }
}

if ($configurationRequired -and (-NOT $Configuration))
{
    Write-Host "No Configuration" -ForegroundColor Red
    Write-Help
    ExitWithCode(1)
}
if (-NOT $configurationOk)
{
    Write-Help
    ExitWithCode(1)
}

$featuresOk = $True
foreach ($action in $Actions )
{
    if ($ActionProperties[$action].FeaturesSupported)
    {
        foreach ($feature in $Features)
        {
            if (-NOT ($SupportedFeatures[$action].Contains($feature)))
            {
                Write-Host "Feature $feature is not supported by action $action" -ForegroundColor Red
                $featuresOk = $False
            }
        }
    }
}
if (-NOT $featuresOk)
{
    Write-Help
    ExitWithCode(1)
}

Write-Host "Parameter validation done" -ForegroundColor Green

function WriteResultExitOnFail($Success, $ActionStr)
{
    if ($Success -eq $True)
    {
        Write-Host "Action $ActionStr success" -ForegroundColor Green
    }
    else
    {
        Write-Host "Action $ActionStr failed" -ForegroundColor Red
        ExitWithCode($process.ExitCode)
    }
}

# Actions are executed in our order, regardless of the order they're passed in
foreach ($action in $SupportedActions)
{
    if (-NOT ($Actions.Contains($action)))
    {
        continue
    }
    # Print log message
    $hasConfiguration = $ActionProperties[$action].ConfigurationRequired
    $hasFeatures      = $ActionProperties[$action].FeaturesSupported
    $message = "Executing $action"
    if ($hasConfiguration)
    {
        $message += ", configuration: $Configuration"
    }
    if ($hasFeatures)
    {
        $message += ", features: "
        $message += $(if ($Features) {$Features -join ", "} else {"None"})
    }
    Write-Host $message -ForegroundColor Green

    # Execute action
    if ($action -eq $aCleanBinaries)
    {
        & ".\Scripts\CleanObriyProject.bat" `"$rootDir`" 1 0
        WriteResultExitOnFail -Success $? -ActionStr $action
    }
    elseif ($action -eq $aCleanSaved)
    {
        & ".\Scripts\CleanObriyProject.bat" `"$rootDir`" 0 1
        WriteResultExitOnFail -Success $? -ActionStr $action
    }
    elseif ($action -eq $aGenerateProject)
    {
        & "${engineDir}\Engine\Build\BatchFiles\GenerateProjectFiles.bat" -project="`"$rootDir\Obriy.uproject`"" -game -engine
        WriteResultExitOnFail -Success $? -ActionStr $action
    }
    elseif ($action -eq $aBuildEditor)
    {
        & "${engineDir}\Engine\Build\BatchFiles\Build.bat" "ObriyEditor" "Win64" $Configuration "`"$rootDir\Obriy.uproject`"" -WaitMutex -NoHotReload
        WriteResultExitOnFail -Success $? -ActionStr $action
    }
    elseif ($action -eq $aBuildPackage)
    {
        if (Test-Path $outPackagedDir)
        {
            Write-Host "Removing previous build" -ForegroundColor Yellow
            Remove-Item $outPackagedDir -Recurse
        }
        foreach ($feature in $SupportedFeatures[$aBuildPackage])
        {
            $value = $(if ($Features.Contains($feature)) {1} else {0})
            [System.Environment]::SetEnvironmentVariable($FeaturesToEnv[$feature], $value)
        }
        & "${engineDir}\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun `
            -project="`"$rootDir\Obriy.uproject`"" `
            -noP4 `
            -utf8output `
            -build `
            -cook `
            -map="MainMenuLevel+MultirotorLevel+BriefingLevel" `
            -CookCultures="en+uk" `
            -unversionedcookedcontent `
            -encryptinifiles `
            -pak `
            -compressed `
            -manifests `
            -distribution `
            -prereqs `
            -stage `
            -package `
            -platform=Win64 `
            -clientconfig="$Configuration"
        WriteResultExitOnFail -Success $? -ActionStr $action
    }
    elseif($action -eq $aRunEditor)
    {
        Start-Process "${engineDir}\Engine\Binaries\Win64\UnrealEditor.exe" "`"$rootDir\Obriy.uproject`""
        WriteResultExitOnFail -Success $? -ActionStr $action
    }
    elseif ($action -eq $aPackArchive)
    {
        foreach ($feature in $SupportedFeatures[$aBuildPackage])
        {
            $value = $(if ($Features.Contains($feature)) {1} else {0})
            [System.Environment]::SetEnvironmentVariable($FeaturesToEnv[$feature], $value)
        }
        & "Scripts\PackObriyProject.ps1" $Configuration
        WriteResultExitOnFail -Success $? -ActionStr $action
    }
}

ExitWithCode(0)