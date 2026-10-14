$racine   = Split-Path $PSScriptRoot -Parent
$csv      = Join-Path $racine "reports\SecurityReport.csv"
$html     = Join-Path $racine "reports\SecurityReport.html"
$smtpCred = Join-Path $racine "config\smtp.cred.xml"
$logFile  = Join-Path $racine "logs\PatchManager.log"

$eac = [char]233   # e accent aigu
$agr = [char]224   # a accent grave
$destinataire = "admin@entreprise.local"
$expediteur   = "patchmanager@entreprise.local"
$smtpServer   = "localhost"
$smtpPort     = 25

function Write-Log {
    param([string]$Message)
    $ligne = "{0} ; {1}" -f (Get-Date -Format "dd/MM/yyyy HH:mm:ss"), $Message
    Add-Content -Path $logFile -Value $ligne -Encoding UTF8
}

if (-not (Test-Path $csv)) {
    Write-Warning "SecurityReport.csv introuvable : lancer New-SecurityReport.ps1 d'abord"
    return
}

$rapport   = @(Import-Csv -Path $csv -Delimiter ";")
$anomalies = @($rapport | Where-Object { $_.Etat -ne "CONFORME" })

# Pas d'anomalie : on s'arrete sans rien envoyer
if ($anomalies.Count -eq 0) {
    Write-Host "Aucune anomalie : pas de notification."
    Write-Log "Aucune anomalie ; pas de notification"
    return
}

$nbNC    = @($rapport | Where-Object Etat -eq "NON CONFORME").Count
$nbInacc = @($rapport | Where-Object Etat -eq "INACCESSIBLE").Count
$dateCtl = ($rapport[0].DateControle -split " ")[0]

$lignes = @()
$lignes += "Date du contr${eac}le : $dateCtl"
$lignes += ""
$lignes += "Postes contr${eac}l${eac}s     : $($rapport.Count)"
$lignes += "Postes non conformes : $nbNC"
$lignes += "Postes inaccessibles : $nbInacc"
foreach ($p in $anomalies) {
    $lignes += ""
    $lignes += "$($p.Poste) : $($p.Etat)"
    if ($p.Etat -eq "NON CONFORME") {
        foreach ($kb in ($p.Liste_KB_Manquantes -split ",\s*")) { $lignes += "       $kb manquante" }
    }
}
$corps = $lignes -join "`r`n"
$sujet = "[PATCH MANAGEMENT] Anomalies d${eac}tect${eac}es"

$params = @{
    From = $expediteur; To = $destinataire; Subject = $sujet; Body = $corps
    SmtpServer = $smtpServer; Port = $smtpPort
    Encoding = [System.Text.Encoding]::UTF8
    ErrorAction = "Stop"
}
if (Test-Path $html)     { $params.Attachments = $html }
if (Test-Path $smtpCred) { $params.Credential  = Import-Clixml $smtpCred }

try {
    Send-MailMessage @params
    Write-Host "Notification envoy${eac}e ${agr} $destinataire"
    Write-Log "Notification envoy${eac}e ${agr} $destinataire"
}
catch {
    Write-Warning "Echec de l'envoi : $($_.Exception.Message)"
    Write-Log "ERREUR ; Notification non envoy${eac}e"
}