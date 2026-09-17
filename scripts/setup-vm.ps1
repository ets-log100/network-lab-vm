param(
    [Parameter(Position = 0)]
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"

$Repo = "ets-log100/network-lab-vm"
$VmName = "LOG100 Network Labs"
$SshPort = 2222
$WorkDir = Join-Path $env:TEMP "log100-network-lab-vm"

function Fail([string]$Message) {
    Write-Error "ERREUR : $Message"
    exit 1
}

if ($Version -eq "latest") {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
    $ReleaseLabel = "la dernière release stable"
} else {
    if ($Version -notmatch '^[vV]?\d+\.\d+\.\d+$') {
        Fail "version invalide : $Version. Utilisez un tag comme v0.1.1."
    }
    $ReleaseTag = "v" + ($Version -replace '^[vV]', '')
    $BaseUrl = "https://github.com/$Repo/releases/download/$ReleaseTag"
    $ReleaseLabel = $ReleaseTag
}

$VBoxManage = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
if (-not $VBoxManage) {
    $Candidate = Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe"
    if (Test-Path $Candidate) {
        $VBoxManagePath = $Candidate
    } else {
        Fail "VirtualBox n'est pas installé ou VBoxManage.exe est introuvable."
    }
} else {
    $VBoxManagePath = $VBoxManage.Source
}

$Architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($Architecture) {
    "X64"   { $Arch = "amd64" }
    "Arm64" { $Arch = "arm64" }
    default { Fail "architecture non supportée : $Architecture" }
}

$VersionText = (& $VBoxManagePath --version)
if ($VersionText -notmatch '^(\d+)\.(\d+)') {
    Fail "impossible de déterminer la version de VirtualBox."
}
$Major = [int]$Matches[1]
$Minor = [int]$Matches[2]
if ($Major -lt 7 -or ($Major -eq 7 -and $Minor -lt 2)) {
    Fail "VirtualBox 7.2 ou plus récent est requis. Version détectée : $VersionText"
}

$vmExists = $false
try {
    # Temporarily ignore non-zero exit codes/native errors for this command
    $ErrorActionPreference = "SilentlyContinue"
    $null = & $VBoxManagePath showvminfo $VmName 2>&1
    if ($LASTEXITCODE -eq 0) {
        $vmExists = $true
    }
} finally {
    # Restore your preferred error action
    $ErrorActionPreference = "Stop"
}

if ($vmExists) {
    Fail "une VM nommée '$VmName' existe déjà. Supprimez-la ou renommez-la avant de continuer."
}

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$Asset = "log100-network-lab-vm-$Arch.ova.gz"
$Archive = Join-Path $WorkDir $Asset
$ChecksumFile = "$Archive.sha256"
$Ova = Join-Path $WorkDir "log100-network-lab-vm-$Arch.ova"

Write-Host "INFO : téléchargement de l'appliance $Arch depuis $ReleaseLabel"
try {
    Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $Archive
} catch {
    Fail "impossible de télécharger $Asset depuis $ReleaseLabel. Vérifiez que cette release contient une appliance pour l'architecture $Arch."
}
try {
    Invoke-WebRequest -Uri "$BaseUrl/$Asset.sha256" -OutFile $ChecksumFile
} catch {
    Fail "impossible de télécharger le SHA-256 de $Asset depuis $ReleaseLabel."
}

$Expected = ((Get-Content $ChecksumFile -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
$Actual = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
if ($Expected -ne $Actual) {
    Fail "le SHA-256 de l'appliance est invalide."
}

Write-Host "INFO : décompression"
$InputStream = [System.IO.File]::OpenRead($Archive)
try {
    $GzipStream = New-Object System.IO.Compression.GzipStream($InputStream, [System.IO.Compression.CompressionMode]::Decompress)
    try {
        $OutputStream = [System.IO.File]::Create($Ova)
        try {
            $GzipStream.CopyTo($OutputStream)
        } finally {
            $OutputStream.Dispose()
        }
    } finally {
        $GzipStream.Dispose()
    }
} finally {
    $InputStream.Dispose()
}

Write-Host "INFO : importation dans VirtualBox"
try {
    # Temporarily ignore native command errors so the progress bar doesn't crash the script
    $OldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    
    $null = & $VBoxManagePath import $Ova --vsys 0 --vmname $VmName 2>&1
} finally {
    $ErrorActionPreference = $OldErrorAction
}

if ($LASTEXITCODE -ne 0) { 
    Fail "l'importation de la VM a échoué." 
}

& $VBoxManagePath modifyvm $VmName --nat-pf1 delete ssh *> $null
& $VBoxManagePath modifyvm $VmName --nat-pf1 "ssh,tcp,127.0.0.1,$SshPort,,22"
if ($LASTEXITCODE -ne 0) { Fail "la configuration de la redirection SSH a échoué." }

$SshKeygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
if ($SshKeygen) {
    try {
        $OldErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $null = & $SshKeygen.Source -R "[localhost]:$SshPort" 2>&1
    } finally {
        $ErrorActionPreference = $OldErrorAction
    }
}

Write-Host "INFO : démarrage de la VM"
& $VBoxManagePath startvm $VmName --type headless
if ($LASTEXITCODE -ne 0) { Fail "le démarrage de la VM a échoué." }

Write-Host ""
Write-Host "OK : la VM LOG100 est démarrée."
Write-Host ""
Write-Host "Release : $ReleaseLabel"
Write-Host "Connexion :"
Write-Host "  ssh -p $SshPort log100@localhost"
Write-Host ""
Write-Host "Mot de passe initial : log100"
Write-Host "La première disponibilité de SSH peut prendre quelques dizaines de secondes."
