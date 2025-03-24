Param(
    [Parameter(Mandatory=$false)]
    [string]$licenseFilePath,
    [Parameter(Mandatory=$false)]
    [string]$dependenciesFolder = "",
    [Parameter(Mandatory=$false)]
    [string]$databaseBackupPath = ""
)

$repositoryPath = (Resolve-Path ($PSScriptRoot + "\..")).Path

# Read Build.Config
$buildConfigJsonPath = Join-Path $repositoryPath "Container\Build.Config.Json"
$buildConfig = Get-Content -Raw -LiteralPath $buildConfigJsonPath | ConvertFrom-Json -ErrorAction Stop

#################### Container Credential #########################
$credential = New-Object pscredential 'admin', (ConvertTo-SecureString -String 'P@ssword1' -AsPlainText -Force)


$imageShortName, $imageTag = $buildConfig.containerImage.Split(':')
$type, $version, $country = $imageTag.Split('-')

Check-BcContainerHelperPermissions -Fix

$artifactUrl = Get-BCArtifactUrl -type $type -version $version -country $country

if (!@(docker images --format "{{.Repository}}:{{.Tag}}").Contains($buildConfig.containerImage)) {
    

    $additionalParams = @{}
    if ($databaseBackupPath) {
        $additionalParams += @{ "databaseBackupPath" = $databaseBackupPath }
    }

    New-BcImage -artifactUrl $artifactUrl -imageName $imageShortName -skipIfImageAlreadyExists @additionalParams
} elseif ($databaseBackupPath) {
    Write-Warning "databaseBackupPath won't take effect since image already exists."
}

[bool]$containerExists = $false

try {
    $containerArtifactUrl = Get-BcContainerArtifactUrl -containerName $buildConfig.BuildContainerName -ErrorAction Stop
    if ($containerArtifactUrl -eq $artifactUrl) {
        Write-Host "Suitable container $($buildConfig.BuildContainerName) already exists" -ForegroundColor Green

        try {
            Get-BcContainerSession -containerName $buildConfig.BuildContainerName -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "Starting container $($buildConfig.BuildContainerName)" -ForegroundColor Yellow
            Start-BcContainer -containerName $buildConfig.BuildContainerName
        }

        $containerExists = $true
    }
}
catch {
    Write-Host "New container $($buildConfig.BuildContainerName) will be created" -ForegroundColor Yellow
}

if (!$containerExists) {
    

    New-BcContainer `
        -containerName $buildConfig.BuildContainerName `
        -imageName $buildConfig.containerImage `
        -accept_outdated `
        -Credential $credential `
        -accept_eula `
        -useSSL `
        -installCertificateOnHost `
        -updateHosts `
        -auth NavUserPassword `
        -memoryLimit 12GB `
        -includeAL `
        -enableTaskScheduler `
        -additionalParameters @("--volume ""$($repositoryPath):C:\Agent""") `
        -Verbose
    
    if ($buildConfig.BuildTestDependencyApps) {
        Import-TestToolkitToBcContainer -containerName $buildConfig.BuildContainerName -includeTestLibrariesOnly
    }
}

if ($appConfig.CustomCodeAnalyzers) {
    $custAnalyzerFolder = "C:/ALCustomCops";
    if (!(Test-Path $custAnalyzerFolder -PathType Container)) {
        New-Item -Path $custAnalyzerFolder -ItemType Directory | Out-Null
    }
    foreach ($analyzer in $appConfig.CustomCodeAnalyzers) {
        if ($analyzer -like 'https://*') {
            Write-Host "Downloading analyzer from $analyzer"
            $custAnalyzerPath = Join-Path $custAnalyzerFolder (Split-Path $analyzer -Leaf)
            Download-File -sourceUrl $analyzer -destinationFile $custAnalyzerPath
        } else {
            Write-Warning "App.Config.json - CustomCodeAnalyzers should contain URL-s to download analyzer."
        }
    }
}

if ([string]::IsNullOrWhiteSpace($buildConfig.BuildDependencyApps)) {
    return
}

if ($dependenciesFolder -eq "") {
    $dependenciesFolder = Join-Path $repositoryPath "dependencies"

    ############ Project specifics ############

    try {
        az --version | Out-Null
    } catch [System.Management.Automation.CommandNotFoundException] {
        Write-Host "Installing Azure CLI..." -ForegroundColor Yellow

        Invoke-WebRequest -Uri https://aka.ms/installazurecliwindowsx64 -OutFile .\AzureCLI.msi
        Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
        Remove-Item .\AzureCLI.msi

        Write-Error "Azure CLI Installed, please restart PowerShell and run this script again!"
        return
    }

    if (!(az extension show --name azure-devops)) {
        az extension add --name azure-devops
    }

    if (!(az account show)) {
        az login | Out-Null
    }

    Write-Host "Downloading packages from feeds" -ForegroundColor Yellow

    Get-ChildItem $dependenciesFolder | Where-Object { $_.Name -ne ".gitkeep" } | Remove-Item -Force -Recurse

    $project, $feed = $buildConfig.BuildDependencyFeed.Split('/')

    az artifacts universal download `
        --organization "https://dev.azure.com/AD-NAV/" `
        --project $project `
        --scope project `
        --feed $feed `
        --name $buildConfig.BuildDependencyPackage `
        --version $buildConfig.DependencyFeedVersion `
        --path $dependenciesFolder | Out-Null

    ############ End Project specifics ############
}

############ Functions ############
function Add-DependentAppsRecursive {
    Param (
        [Parameter(Mandatory=$true)]
        [ref] $toArray,
        [Parameter(Mandatory=$true)]
        [Array] $allPublishedApps,
        [Parameter(Mandatory=$true)]
        [string] $dependentOnApp
    )

    $depOnApps = @( $dependentOnApp )
    [bool]$newAppsFound = $true

    [int]$safetyLimit = 100

    while ($newAppsFound -and ($safetyLimit -gt 0)) {
        $newAppsFound = $false
        $newDepOnApps = @()

        # Check if new apps are found that depend on some app in `depOnApps`
        foreach ($publishedApp in $allPublishedApps) {
            [bool]$isDependent = $false
            foreach ($dependency in ([Array]$publishedApp.Dependencies)) {
                if ($depOnApps | Where-Object { $dependency -match "^$($_)," }) {
                    $isDependent = $true
                    break
                }
            }

            if (!$isDependent) {
                continue
            }
            if ($toArray.Value.Where({ $_.Name -eq $publishedApp.Name })) {
                continue
            }

            # new publishedApp is found
            $toArray.Value += [PSCustomObject]@{
                Name         = $publishedApp.Name
                Version      = $publishedApp.Version
                Dependencies = [Array]$publishedApp.Dependencies
                IsInstalled  = $publishedApp.IsInstalled
            }
            $newAppsFound = $true
            $newDepOnApps += $publishedApp.Name
        }

        # remember which app id-s were added in previous cycle
        $depOnApps = $newDepOnApps
        $safetyLimit--
    }

    if ($safetyLimit -eq 0) {
        Write-Error "Dependencies not found in 100 cycles!" -Category LimitsExceeded
    }
}

function Sort-AppsByDependencies {
    Param (
        [Parameter(Mandatory=$true)]
        [Array]$Apps
    )

    # clean non existing dependencies
    [Array]$newApps = @()
    foreach ($app in $Apps) {
        $newApps += [PSCustomObject]@{
            Name =         $app.Name
            Version =      $app.Version
            Dependencies = $app.Dependencies | Where-Object {
                $dependency = $_
                [bool]$include = $false
                foreach($checkApp in $Apps) {
                    if ($dependency -match "^$($checkApp.Name),") {
                        $include = $true
                        break
                    }
                }
                return $include
            }
            IsInstalled = $app.IsInstalled
        }
    }

    # process dependencies
    [Array]$sortedApps = @()
    $count = $newApps.Count
    while ($count -gt 0) {
        [bool]$found = $false
        for ($i = 0; $i -lt $count; $i++) {
            $app = $newApps.Get($i)
            if ($null -eq $app.Dependencies) {
                $found = $true
                $sortedApps += $app
                $newApps = [Array]($newApps | Where-Object { $_.Name -ne $app.Name })
                $count = $newApps.Count
                for ($j = 0; $j -lt $count; $j++) {
                    $otherApp = $newApps.Get($j)
                    $otherApp.Dependencies = $otherApp.Dependencies | Where-Object { !($_ -match "^$($app.Name),") }
                    $newApps.Set($j, $otherApp)
                }
                break
            }
        }
        if (!$found) {
            Write-Error "Dependency cycle detected!" -Category InvalidArgument
            break
        }
    }

    return $sortedApps
}
############ End Functions ############

$toInstall = @()
$buildConfig.BuildDependencyApps.Split(',') | ForEach-Object {
    $toInstall += @{
        Name = $_
    }
}
if ($buildConfig.BuildTestDependencyApps) {
    $buildConfig.BuildTestDependencyApps.Split(',') | ForEach-Object {
        $toInstall += @{
            Name = $_
            Test = $true
        }
    }
}

## Unpublish on-top apps
$allPublishedApps = Get-BcContainerAppInfo -containerName $buildConfig.BuildContainerName -tenantSpecificProperties
$onTopApps = @()
foreach ($publishedApp in $allPublishedApps) {
    if ($publishedApp.Publisher -eq 'Microsoft') {
        continue
    }

    if ($toInstall.Name | Where-Object { $publishedApp.Name -match $_ }) {
        continue
    }

    foreach ($dependency in $publishedApp.Dependencies) {
        if ($toInstall.Name | Where-Object { $dependency -match $_ }) {
            $onTopApps += $publishedApp
            Add-DependentAppsRecursive -toArray ([ref]$onTopApps) -allPublishedApps $allPublishedApps -dependentOnApp $publishedApp.Name
            break
        }
    }
}

if ($onTopApps) {
    [Array]$onTopApps = Sort-AppsByDependencies -Apps $onTopApps
    [Array]::Reverse($onTopApps)
    
    $onTopApps.ForEach({
        Write-Host "Unpublishing (on-top app): $($_.Name) [$($_.Publisher)] $($_.Version)" -ForegroundColor Yellow
        $additionalArgs = @{}
        if ($_.IsInstalled) {
            $additionalArgs.unInstall = $true
        }
        UnPublish-BcContainerApp -containerName $buildConfig.BuildContainerName `
            -name $_.Name -version $_.Version @additionalArgs -Force -Verbose
    })
}

$previousApps = @()

## Unpublish Previous versions
[Array]::Reverse($toInstall)
foreach ($app in $toInstall.Name) {
    (Get-BcContainerAppInfo -containerName $buildConfig.BuildContainerName).Where({
        ($_.Name -match $app) -and ($_.Publisher -ne 'Microsoft')
    }).ForEach({
        $previousApp = [PSCustomObject]@{
            Name = $_.Name
            Version = [System.Version]$_.Version
        }
        $previousApps += $previousApp

        Write-Host "Unpublishing: $($_.Name) [$($_.Publisher)] $($_.Version)" -ForegroundColor Yellow
        UnPublish-BcContainerApp -containerName $buildConfig.BuildContainerName `
            -name $_.Name -version $_.Version -unInstall -force -Verbose
    })
}
[Array]::Reverse($toInstall)

## Publish Dependency apps
foreach($app in $toInstall) {
    $matchingPackage = Get-ChildItem $dependenciesFolder -Recurse -Filter "*$($app.Name)*.app"
    if ($matchingPackage.Count -ne 1) {
        $matchingPackage = $matchingPackage | Where-Object {
            (((-not $app.Test) -and ($_.DirectoryName -match "\\Apps?(\\|$)")) -or ($app.Test -and ($_.DirectoryName -match "\\AppTest(\\|$)")))
        }
    }

    if ($matchingPackage.Count -eq 0) {
        Write-Error "There are no matching app files for app '$($app.Name)' in folder '$dependenciesFolder'" -Category ObjectNotFound
        break
    }
    if ($matchingPackage.Count -gt 1) {
        Write-Error "There is more than one package for app '$($app.Name)' in folder '$dependenciesFolder'" -Category InvalidResult
        break
    }

    $appInfo = Get-BcContainerAppInfo -containerName $buildConfig.BuildContainerName -appFilePath $matchingPackage.FullName

    $additionalArgs = @{}

    try {
        ## Check if upgrade to new version is needed
        $previousApps.Where({ $_.Name -eq $appInfo.Name }).ForEach({
            $cmp = $_.Version.CompareTo($appInfo.Version)
            if ($cmp -eq 1) {
                Write-Error "App: $($appInfo.Name), Version: $($appInfo.Version) cannot be installed because newer version was already installed" -Category InvalidOperation
                return
            } elseif ($cmp -eq -1) {
                $additionalArgs.upgrade = $true
            }
        })
        
        Publish-BcContainerApp `
            -containerName $buildConfig.BuildContainerName `
            -appFile $matchingPackage.FullName `
            -skipVerification `
            -credential $credential `
            -sync -syncMode ForceSync -install @additionalArgs `
            -ignoreIfAppExists `
            -Verbose -ErrorAction Stop
    }
    catch {
        throw $_
        return
    }
}