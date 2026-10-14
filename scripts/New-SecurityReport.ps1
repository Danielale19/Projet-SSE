$racine   = Split-Path $PSScriptRoot -Parent
$fichier  = Join-Path $racine "config\computers.txt"
$requis   = Join-Path $racine "config\required-patches.txt"
$csvOut   = Join-Path $racine "reports\SecurityReport.csv"
$htmlOut  = Join-Path $racine "reports\SecurityReport.html"
$logFile  = Join-Path $racine "logs\PatchManager.log"

function Write-Log {
    param([string]$Message)
    $ligne = "{0} ; {1}" -f (Get-Date -Format "dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $logFile -Value $ligne -Encoding UTF8
}
function Enc($t) { [System.Net.WebUtility]::HtmlEncode([string]$t) }

$lignes   = Get-Content $fichier | Where-Object { $_.Trim() -ne "" }
$kbRequis = @(Get-Content $requis | ForEach-Object { $_.Trim().ToUpper() } |
              Where-Object { $_ -ne "" -and -not $_.StartsWith("#") })
$dateCtrl = Get-Date -Format "dd/MM/yyyy HH:mm:ss"

Write-Log "Debut de l'audit"

# ---------- Point 1 : collecte et rapport par poste ----------
$rapport = foreach ($ligne in $lignes) {
    $nom, $ip = $ligne -split ";"

    $obj = [PSCustomObject][ordered]@{
        Poste = $nom; AdresseIP = $ip; Accessibilite = "Inaccessible"
        Windows = "N/A"; DernierDemarrage = "N/A"; WindowsUpdate = "N/A"
        KB_Requises = $kbRequis.Count; KB_Manquantes = "N/A"; Liste_KB_Manquantes = "N/A"
        Etat = "INACCESSIBLE"; Erreur = ""; DateControle = $dateCtrl
    }

    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        $obj.Erreur = "Pas de reponse au ping"
        Write-Log "$nom ; Inaccessible ; pas de reponse au ping"
    }
    else {
        try {
	    $credFile = Join-Path $racine "config\$nom.cred.xml"
	    $cred = if (Test-Path $credFile) { Import-Clixml $credFile } else { Get-Credential -UserName "$nom\win_$($nom.ToLower())" -Message "Compte local de $nom" }
            $r = Invoke-Command -ComputerName $ip -Credential $cred -ErrorAction Stop -ScriptBlock {
                $os = Get-CimInstance Win32_OperatingSystem
                [PSCustomObject]@{
                    Windows = "$($os.Caption) ($($os.Version))"
                    Boot    = $os.LastBootUpTime
                    WU      = (Get-Service wuauserv).Status.ToString()
                    KB      = @((Get-HotFix).HotFixID)
                }
            }
            Write-Log "$nom ; Accessible"

            $manquants = @($kbRequis | Where-Object { @($r.KB) -notcontains $_ })

            $obj.Accessibilite    = "Accessible"
            $obj.Windows          = $r.Windows
            $obj.DernierDemarrage = $r.Boot.ToString("dd/MM/yyyy HH:mm")
            $obj.WindowsUpdate    = $r.WU
            $obj.KB_Manquantes    = $manquants.Count

            if ($manquants.Count -eq 0) {
                $obj.Etat = "CONFORME"
                $obj.Liste_KB_Manquantes = "Aucune"
                Write-Log "$nom ; Conforme"
            }
            else {
                $obj.Etat = "NON CONFORME"
                $obj.Liste_KB_Manquantes = $manquants -join ", "
                Write-Log "$nom ; Non conforme ; $($manquants -join ', ')"
            }
        }
        catch {
            $obj.Erreur = "WinRM : " + ($_.Exception.Message -replace '\s+', ' ')
            Write-Log "$nom ; WinRM inaccessible"
        }
    }
    $obj
}

$rapport | Export-Csv -Path $csvOut -NoTypeInformation -Delimiter ";" -Encoding UTF8

# ---------- Point 2 : synthese globale ----------
$total    = @($rapport).Count
$nbAcc    = @($rapport | Where-Object Accessibilite -eq "Accessible").Count
$nbInacc  = $total - $nbAcc
$nbConf   = @($rapport | Where-Object Etat -eq "CONFORME").Count
$nbNC     = @($rapport | Where-Object Etat -eq "NON CONFORME").Count
$totManq  = (@($rapport | Where-Object Etat -eq "NON CONFORME") | Measure-Object KB_Manquantes -Sum).Sum
if (-not $totManq) { $totManq = 0 }
$evalues  = $nbConf + $nbNC
$tauxTxt  = if ($evalues -gt 0) { "$([math]::Round(100 * $nbConf / $evalues, 1)) %" } else { "non calculable" }

$synthese = [ordered]@{
    "Nombre total de postes"               = $total
    "Nombre de postes accessibles"         = $nbAcc
    "Nombre de postes inaccessibles"       = $nbInacc
    "Nombre de postes conformes"           = $nbConf
    "Nombre de postes non conformes"       = $nbNC
    "Nombre total de correctifs manquants" = $totManq
    "Taux de conformite"                   = $tauxTxt
}

# ---------- Point 3 : postes a traiter ----------
$aTraiter = @($rapport | Where-Object Etat -ne "CONFORME")

# ---------- Affichage console ----------
Write-Host "`n=== Rapport par poste (controle du $dateCtrl) ===" -ForegroundColor Cyan
$rapport | Format-Table Poste, AdresseIP, Accessibilite, WindowsUpdate, KB_Requises, KB_Manquantes, Etat -AutoSize
Write-Host "=== Synthese globale ===" -ForegroundColor Cyan
$synthese.GetEnumerator() | ForEach-Object { "{0,-40} : {1}" -f $_.Key, $_.Value }
Write-Host "`n=== Postes necessitant une intervention ===" -ForegroundColor Cyan
if ($aTraiter.Count -eq 0) { Write-Host "Aucun" }
else {
    $aTraiter | ForEach-Object {
        $detail = if ($_.Etat -eq "NON CONFORME") { "KB manquantes : $($_.Liste_KB_Manquantes)" } else { $_.Erreur }
        Write-Host ("{0} ({1}) : {2} - {3}" -f $_.Poste, $_.AdresseIP, $_.Etat, $detail) -ForegroundColor Yellow
    }
}

# ---------- Point 4 : version HTML ----------
$lignesTout = ($rapport | ForEach-Object {
    $cls = switch ($_.Etat) { "CONFORME" { "ok" } "NON CONFORME" { "nc" } default { "inac" } }
    "<tr class='$cls'><td>$(Enc $_.Poste)</td><td>$(Enc $_.AdresseIP)</td><td>$(Enc $_.Accessibilite)</td><td>$(Enc $_.Windows)</td><td>$(Enc $_.DernierDemarrage)</td><td>$(Enc $_.WindowsUpdate)</td><td>$(Enc $_.KB_Requises)</td><td>$(Enc $_.KB_Manquantes)</td><td>$(Enc $_.Liste_KB_Manquantes)</td><td><b>$(Enc $_.Etat)</b></td><td>$(Enc $_.DateControle)</td></tr>"
}) -join "`n"

$lignesSynth = ($synthese.GetEnumerator() | ForEach-Object { "<tr><td>$(Enc $_.Key)</td><td><b>$(Enc $_.Value)</b></td></tr>" }) -join "`n"

$lignesInter = if ($aTraiter.Count -eq 0) { "<tr><td colspan='4'>Aucun poste ne necessite d'intervention.</td></tr>" }
else {
    ($aTraiter | ForEach-Object {
        $cls = if ($_.Etat -eq "NON CONFORME") { "nc" } else { "inac" }
        $detail = if ($_.Etat -eq "NON CONFORME") { "KB manquantes : $($_.Liste_KB_Manquantes)" } else { $_.Erreur }
        "<tr class='$cls'><td>$(Enc $_.Poste)</td><td>$(Enc $_.AdresseIP)</td><td><b>$(Enc $_.Etat)</b></td><td>$(Enc $detail)</td></tr>"
    }) -join "`n"
}

$html = @"
<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><title>Rapport de securite - Patch Management</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:30px;color:#222}
h1{border-bottom:3px solid #2b5797;padding-bottom:6px}
h2{margin-top:30px;color:#2b5797}
table{border-collapse:collapse;margin-top:8px}
th,td{border:1px solid #bbb;padding:6px 10px;text-align:left;font-size:14px}
th{background:#2b5797;color:#fff}
tr.ok{background:#e3f4e3} tr.nc{background:#fde8c8} tr.inac{background:#f8d4d4}
</style></head><body>
<h1>Rapport de s&eacute;curit&eacute; - Patch Management</h1>
<p>Date du contr&ocirc;le : $dateCtrl</p>
<h2>Synth&egrave;se globale du parc</h2>
<table>$lignesSynth</table>
<h2>Postes n&eacute;cessitant une intervention</h2>
<table><tr><th>Poste</th><th>Adresse IP</th><th>&Eacute;tat</th><th>D&eacute;tail</th></tr>
$lignesInter</table>
<h2>D&eacute;tail par poste</h2>
<table><tr><th>Poste</th><th>Adresse IP</th><th>Accessibilit&eacute;</th><th>Windows</th><th>Dernier d&eacute;marrage</th><th>Windows Update</th><th>KB requis</th><th>KB manquants</th><th>Liste des KB manquants</th><th>&Eacute;tat</th><th>Date du contr&ocirc;le</th></tr>
$lignesTout</table>
</body></html>
"@
Set-Content -Path $htmlOut -Value $html -Encoding UTF8
Write-Log "Rapport genere"
Write-Host "`nRapport CSV  : $csvOut`nRapport HTML : $htmlOut`nJournal      : $logFile"

Write-Log "Fin de l'audit"
