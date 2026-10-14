$racine = Split-Path $PSScriptRoot -Parent
$lignes = Get-Content (Join-Path $racine "config\computers.txt") | Where-Object { $_.Trim() -ne "" }

foreach ($ligne in $lignes) {
    $nom, $ip = $ligne -split ";"
    $cred = Get-Credential -UserName "$nom\win_$($nom.ToLower())" -Message "Compte local de $nom (sera enregistre chiffre)"
    $cred | Export-Clixml -Path (Join-Path $racine "config\$nom.cred.xml")
}

$smtp = Get-Credential -UserName "patchmanager@entreprise.local" -Message "Compte SMTP (mot de passe bidon pour le serveur de test)"
$smtp | Export-Clixml -Path (Join-Path $racine "config\smtp.cred.xml")

Write-Host "Identifiants enregistres dans config\*.cred.xml"