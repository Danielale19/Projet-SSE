$racine  = Split-Path $PSScriptRoot -Parent
$fichier = Join-Path $racine "config\computers.txt"
$export  = Join-Path $racine "reports\PatchesInventory.csv"
$lignes  = Get-Content $fichier | Where-Object { $_.Trim() -ne "" }

$patches = foreach ($ligne in $lignes) {
    $nom, $ip = $ligne -split ";"

    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        Write-Warning "$nom ($ip) : pas de reponse au ping, poste ignore"
        continue
    }
    try {
        $cred = Get-Credential -UserName "$nom\win_$($nom.ToLower())" -Message "Compte local de $nom"
        $kbs = Invoke-Command -ComputerName $ip -Credential $cred -ErrorAction Stop -ScriptBlock {
            Get-HotFix | Select-Object HotFixID, Description, InstalledOn, InstalledBy
        }
        foreach ($k in $kbs) {
            [PSCustomObject]@{
                Poste            = $nom
                AdresseIP        = $ip
                KB               = $k.HotFixID
                Description      = $k.Description
                DateInstallation = $k.InstalledOn
                InstallePar      = $k.InstalledBy
            }
        }
    }
    catch {
        Write-Warning "$nom ($ip) : echec WinRM, poste ignore ($($_.Exception.Message -replace '\s+', ' '))"
    }
}

if (-not $patches) {
    Write-Warning "Aucun correctif collecte, rien a exporter"
    return
}

$tries = $patches | Sort-Object @{Expression = 'Poste'; Descending = $false}, @{Expression = 'DateInstallation'; Descending = $true}

$tries | Select-Object Poste, AdresseIP, KB, Description,
    @{Name = 'DateInstallation'; Expression = { if ($_.DateInstallation) { $_.DateInstallation.ToString('dd/MM/yyyy') } else { 'N/A' } }},
    @{Name = 'InstallePar'; Expression = { if ($_.InstallePar) { $_.InstallePar } else { 'N/A' } }} |
    Export-Csv -Path $export -NoTypeInformation -Delimiter ";" -Encoding UTF8

$stats = $tries | Group-Object Poste | ForEach-Object {
    $dernier = $_.Group | Where-Object DateInstallation |
        Sort-Object @{Expression = 'DateInstallation'; Descending = $true}, @{Expression = 'KB'; Descending = $true} |
        Select-Object -First 1
    [PSCustomObject]@{
        Poste           = $_.Name
        NbCorrectifs    = $_.Count
        DatePlusRecente = if ($dernier) { $dernier.DateInstallation.ToString('dd/MM/yyyy') } else { 'N/A' }
        DernierKB       = if ($dernier) { $dernier.KB } else { 'N/A' }
    }
}

$stats | Format-Table -AutoSize
Write-Host "Inventaire des correctifs exporte : $export"