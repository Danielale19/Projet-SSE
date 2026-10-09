$file = Join-Path $PSScriptRoot "..\config\computers.txt"
$lines = Get-Content $file | Where-Object { $_.Trim() -ne "" }

$results = foreach ($line in $lines) {
    $name, $ip = $line -split ";"
    $up = Test-Connection -ComputerName $ip -Count 1 -Quiet
    [PSCustomObject]@{
        Poste     = $name
        AdresseIP = $ip
        Etat      = if ($up) { "Accessible" } else { "Inaccessible" }
    }
}

$results | Format-Table -AutoSize