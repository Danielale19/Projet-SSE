$racine  = Split-Path $PSScriptRoot -Parent
$fichier = Join-Path $racine "config\computers.txt"
$requis  = Join-Path $racine "config\required-patches.txt"
$export  = Join-Path $racine "reports\ComplianceReport.csv"

$lignes   = Get-Content $fichier | Where-Object { $_.Trim() -ne "" }
$kbRequis = @(Get-Content $requis | ForEach-Object { $_.Trim().ToUpper() } |
              Where-Object { $_ -ne "" -and -not $_.StartsWith("#") })

if ($kbRequis.Count -eq 0) { Write-Warning "required-patches.txt est vide"; return }

$resultats = foreach ($ligne in $lignes) {
    $nom, $ip = $ligne -split ";"

    $obj = [PSCustomObject][ordered]@{
        Poste = $nom; AdresseIP = $ip; KB_Requises = $kbRequis.Count
        KB_Manquantes = "-"; Liste_KB_Manquantes = "-"; Etat = "INACCESSIBLE"
        Erreur = ""; DateControle = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    }

    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        $obj.Erreur = "Pas de reponse au ping"
    }
    else {
        try {
            $cred = Get-Credential -UserName "$nom\win_$($nom.ToLower())" -Message "Compte local de $nom"
            $installes = @(Invoke-Command -ComputerName $ip -Credential $cred -ErrorAction Stop -ScriptBlock {
                (Get-HotFix).HotFixID
            })
            $manquants = @($kbRequis | Where-Object { $installes -notcontains $_ })

            $obj.KB_Manquantes = $manquants.Count
            if ($manquants.Count -eq 0) {
                $obj.Etat = "CONFORME"
                $obj.Liste_KB_Manquantes = "Aucune"
            }
            else {
                $obj.Etat = "NON CONFORME"
                $obj.Liste_KB_Manquantes = $manquants -join ", "
            }
            $obj.DateControle = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
        }
        catch {
            $obj.Erreur = "WinRM : " + ($_.Exception.Message -replace '\s+', ' ')
        }
    }
    $obj
}

# Point 3 : tableau des etats
$resultats | Format-Table Poste, KB_Requises, KB_Manquantes, Etat -AutoSize

# Point 4 : KB manquantes + date et heure du controle
foreach ($m in ($resultats | Where-Object Etat -eq "NON CONFORME")) {
    Write-Host "$($m.Poste) : NON CONFORME - KB manquantes : $($m.Liste_KB_Manquantes) (controle du $($m.DateControle))" -ForegroundColor Red
}
$resultats | Where-Object Erreur | Format-Table Poste, Erreur -AutoSize -Wrap

# Point 5 : export
$resultats | Export-Csv -Path $export -NoTypeInformation -Delimiter ";" -Encoding UTF8
Write-Host "Rapport de conformite exporte : $export"

# Point 6 : taux global (postes inaccessibles exclus)
$nbConf  = @($resultats | Where-Object Etat -eq "CONFORME").Count
$nbNC    = @($resultats | Where-Object Etat -eq "NON CONFORME").Count
$nbInacc = @($resultats | Where-Object Etat -eq "INACCESSIBLE").Count
$evalues = $nbConf + $nbNC
if ($evalues -gt 0) {
    $taux = [math]::Round(100 * $nbConf / $evalues, 1)
    Write-Host "Taux global de conformite : $taux % ($nbConf conforme(s) sur $evalues poste(s) evalue(s), $nbInacc inaccessible(s) exclu(s))"
}
else {
    Write-Host "Aucun poste evalue, taux de conformite non calculable"
}