$racine  = Split-Path $PSScriptRoot -Parent
$fichier = Join-Path $racine "config\computers.txt"
$export  = Join-Path $racine "reports\Inventory.csv"
$lignes  = Get-Content $fichier | Where-Object { $_.Trim() -ne "" }

$inventaire = foreach ($ligne in $lignes) {
    $nom, $ip = $ligne -split ";"

    $obj = [PSCustomObject][ordered]@{
        Poste = $nom; AdresseIP = $ip; Etat = "Inaccessible"
        Modele = "N/A"; BIOS = "N/A"; Windows = "N/A"; Version = "N/A"; Architecture = "N/A"
        DernierDemarrage = "N/A"; RAM_Go = "N/A"; DisqueLibre_Go = "N/A"
        DerniereMAJ = "N/A"; NbMAJ = "N/A"; WindowsUpdate = "N/A"; Erreur = ""
    }

    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        $obj.Erreur = "Pas de reponse au ping"
    }
    else {
        try {
            $cred = Get-Credential -UserName "$nom\win_$($nom.ToLower())" -Message "Compte local de $nom"
            $r = Invoke-Command -ComputerName $ip -Credential $cred -ErrorAction Stop -ScriptBlock {
                $cs   = Get-CimInstance Win32_ComputerSystem
                $bios = Get-CimInstance Win32_BIOS
                $os   = Get-CimInstance Win32_OperatingSystem
                $dq   = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
                $hf   = @(Get-HotFix)
                $dernier = $hf | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
                [PSCustomObject]@{
                    Nom          = $env:COMPUTERNAME
                    Modele       = "$($cs.Manufacturer) $($cs.Model)"
                    BIOS         = $bios.SMBIOSBIOSVersion
                    Windows      = $os.Caption
                    Version      = $os.Version
                    Architecture = $os.OSArchitecture
                    Boot         = $os.LastBootUpTime
                    RAM          = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                    Disque       = [math]::Round($dq.FreeSpace / 1GB, 1)
                    DerniereMAJ  = $dernier.InstalledOn
                    NbMAJ        = $hf.Count
                    WU           = (Get-Service wuauserv).Status.ToString()
                }
            }
            $obj.Poste            = $r.Nom
            $obj.Modele           = $r.Modele
            $obj.BIOS             = $r.BIOS
            $obj.Windows          = $r.Windows
            $obj.Version          = $r.Version
            $obj.Architecture     = $r.Architecture
            $obj.DernierDemarrage = $r.Boot.ToString("dd/MM/yyyy HH:mm")
            $obj.RAM_Go           = $r.RAM
            $obj.DisqueLibre_Go   = $r.Disque
            $obj.DerniereMAJ      = if ($r.DerniereMAJ) { $r.DerniereMAJ.ToString("dd/MM/yyyy") } else { "N/A" }
            $obj.NbMAJ            = $r.NbMAJ
            $obj.WindowsUpdate    = $r.WU
            $obj.Etat             = "Accessible"
        }
        catch {
            $obj.Erreur = "WinRM : " + ($_.Exception.Message -replace '\s+', ' ')
        }
    }
    $obj
}

$inventaire | Format-Table Poste, AdresseIP, Windows, Architecture, DernierDemarrage, WindowsUpdate, Etat -AutoSize
$inventaire | Where-Object Erreur | Format-Table Poste, Erreur -AutoSize -Wrap
$inventaire | Export-Csv -Path $export -NoTypeInformation -Delimiter ";" -Encoding UTF8
Write-Host "Inventaire exporte : $export"