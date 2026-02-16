# === CONFIGURATION ===
$projectPath = "C:\Users\Lev Computer\OneDrive\Documents\DIS-HMI\Leighton\WTP 10 Leighton"
$repoURL = "https://github.com/GRINVIRO-GLOBAL/PLC-WTP-LEIGHTON.git"

Set-Location $projectPath

# Initialize git if not exists
if (-not (Test-Path ".git")) {
    git init
    git branch -M main
    git remote add origin $repoURL
}

# Remove all tracked files (reset structure)
git rm -r --cached . 2>$null
git commit -m "Reset tracking before structured re-upload" 2>$null

# Commit each file individually
Get-ChildItem -Recurse -File | Sort-Object Name | ForEach-Object {

    $file = $_.FullName
    $relativePath = Resolve-Path -Relative $file
    $ext = $_.Extension.ToLower()

    if ($ext -eq ".st") {
        $msg = "Update PLC structured text program"
    }
    elseif ($ext -eq ".ccwsln") {
        $msg = "Update CCW solution project"
    }
    elseif ($ext -eq ".csv") {
        $msg = "Update register mapping data"
    }
    elseif ($ext -eq ".json") {
        $msg = "Update configuration file"
    }
    else {
        $msg = "Add project file"
    }

    git add -- "$relativePath"
    git commit -m "$msg ($($_.Name)) | after FAT & for shipment"
}

Write-Host "All files committed individually."
