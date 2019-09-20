﻿# Storj3Monitor script by Krey
# this script gathers, aggregate displays and monitor all you node thresholds
# if uptime or audit down by [threshold] script send email to you
# https://github.com/Krey81/Storj

$v = "0.4.1"

# Changes:
# v0.0    - 20190828 Initial version, only displays data
# v0.1    - 20190904 
#           Add monitoring 
#               -   lost node connection
#               -   outdate storj version
#               -   new satellite
#               -   audit score
#               -   uptime score
#               -   Warrant canary
#           Add mail senders
#               -   for windows & linux internal powershell mail agent
#               -   for linux via bash -c "cat | mail"
# v0.2    - 20190904 
#               -   Remove [ref] for string buffer
#               -   Move config to external file
# v0.3    - 20190910
#               -   Add warning on new wallet
#               -   Fix usage examples in script
#               -   Fix config path search routines
#               -   Add testmail command
#               -   Add config examples
# v0.4    - 20190919                            - [5 bottles withdraw]
#               -   Changes due new api 0.21.1
#               -   Add node summary
#               -   Add satellite graphs
#               -   Add pips
#               -   Add delete counter
#               -   Add wellknown satellite names in script
#               -   Add wallknow node names (your nodes) in config (please check updated examples)
#               -   Add last ping (older last contact) formated like d:h:m:s
# v0.4.1   - 20190920
#               -   fix for "new satellite" mails, thanks LordMerlin
#               -   replace some in-script symbols and pseudographics symbols with byte array for workaround bad text editors, change encoding to UTF-8 with BOM, thanks underflow17
#

#TODO-Drink-and-cheers
#               -   Early bird (1-bottle first), greatings for all versions of this script
#               -   Big thanks (10-bottles first), greatings for all versions of this script
#               -   Telegram bot (100-bottles, sum), development telegtam bot to send messages
#               -   The service (1000-bottles, sum), full time service for current and past functions on my dedicated servers
#               -   The world's fist bottled crypto-currency (1M [1kk for Russians], sum). You and I will create the world's first cryptocurrency, which is really worth something.

#TODO
#               -   MQTT
#               -   SVG graphics
#

#USAGE          !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
#RUN
#   Display only with default config: one node on 127.0.0.1:14002, no monitoring and mail
#       pwsh ./Storj3Monitor.ps1
#
#
#   Display only for specefied nodes
#       pwsh ./Storj3Monitor.ps1 -c <config-file>
#
#
#   Test config and mail sender
#       pwsh ./Storj3Monitor.ps1 -c <config-file> testmail
#
#
#   Monitor and mail
#       pwsh ./Storj3Monitor.ps1 -c <config-file> monitor
#
#
#   Dump default config to stdout
#       pwsh ./Storj3Monitor.ps1 example
#       also see config examples on github 
#
#   Full installation
#       1. Create config, specify all nodes and mailer configuration. Examples on github.
#       2. Create systemd service specify path to this script and configuration. Examples on github.
#

$wellKnownSat = @{
    "118UWpMCHzs6CvSgWd9BfFVjw5K9pZbJjkfZJexMtSkmKxvvAW" = "stefan-benten";
    "12EayRS2V1kEsWESU9QMRseFhdxYxKicsiFmxrsLZHeLUtdps3S" = "us-central-1";
    "121RTSDpyNZVcEU84Ticf2L1ntiuUimbWgfATz21tuvgk3vzoA6" = "asia-east-1";
    "12L9ZFwhzVpuEKMUNUqkaTLGzwY9G24tbiigLiXpmZWKwmcNDDs" = "europe-west-1"
}

 function Preamble{
    Write-Host ""
    Write-Host ("Storj3Monitor script by Krey ver {0}" -f $v)
    Write-Host "mail-to: krey@irinium.ru"
    Write-Host ""
    Write-Host -ForegroundColor Yellow "I work on beer. If you like my scripts please donate bottle of beer in STORJ or ETH to 0x7df3157909face2dd972019d590adba65d83b1d8"
    Write-Host -ForegroundColor Gray "This wallet only for beer. Only beer will be bought from this wallet."
    Write-Host -ForegroundColor Gray "Why should I send bootles if everything works like that ?"
    Write-Host -ForegroundColor Gray "... see TODO comments in the script body"
    Write-Host ""
}

function DefaultConfig{
    $config = @{
        Nodes = "127.0.0.1:14002"
        WaitSeconds = 300
        Threshold = 0.2
        Mail = @{
            MailAgent = "none"
        }
    }
    return $config
}

function GetFullPath($file)
{
    # full path
    if ([System.IO.File]::Exists($file)) { return $file }

    # full path fixed
    $file2 = [System.IO.Path]::GetFullPath($file)
    if ([System.IO.File]::Exists($file2)) { return $file2 }    

    #current dir
    $file3 = [System.IO.Path]::Combine(((Get-Location).Path), $file)
    if ([System.IO.File]::Exists($file3)) { return $file3 }
    
    # from script path
    $scriptPath = ((Get-Variable MyInvocation -Scope 2).Value).InvocationName | Split-Path -Parent
    $file4 = [System.IO.Path]::Combine($scriptPath, $file)
    if ([System.IO.File]::Exists($file4)) { return $file4 }

    return $null
}

function LoadConfig{
    param ($cmdlineArgs)
    $idx = $cmdlineArgs.IndexOf("-c")
    

    if ($idx -lt 0 -or ($cmdlineArgs.Length -le ($idx + 1)) ) {
        Write-Host -ForegroundColor Red "Please specify config file"
        Write-Host "Example: Storj3Monitor.ps1 -c Storj3Monitor.conf"

        Write-Host
        Write-Host -ForegroundColor Red "No config was specified. Use defaults."
        Write-Host "Run 'Storj3Monitor.ps1 example' to retrieve default config"
        $config = DefaultConfig        
        return $config
    }

    $argfile = $cmdlineArgs[$idx + 1]
    $file = GetFullPath -file $argfile
    if ([String]::IsNullOrEmpty($file) -or (-not [System.IO.File]::Exists($file))) {
        Write-Host -ForegroundColor Red ("config file {0} not found" -f $argfile)
        return $false
    }
    
    $config = Get-Content -Path $file | ConvertFrom-Json
    return $config
}

function GetJson
{
    param($uri)

    #RAW
    # ((Invoke-WebRequest -Uri http://192.168.156.4:4404/api/dashboard).content | ConvertFrom-Json).data
    # ((Invoke-WebRequest -Uri http://192.168.156.4:4404/api/satellite/118UWpMCHzs6CvSgWd9BfFVjw5K9pZbJjkfZJexMtSkmKxvvAW).content | ConvertFrom-Json).data

    $resp = Invoke-WebRequest -Uri $uri
    if ($resp.StatusCode -ne 200) { throw $resp.StatusDescription }
    $json = ConvertFrom-Json $resp.Content
    if (-not [System.String]::IsNullOrEmpty($json.Error)) { throw $json.Error }
    else { $json = $json.data }
    return $json
}

function GetNodes
{
    param ($config)
    $result = [System.Collections.Generic.List[PSCustomObject]]@()
    
    $config.Nodes | ForEach-Object {
        $address = $_
        try {
            $dash = GetJson -uri ("http://{0}/api/dashboard" -f $address)
            $dash | Add-Member -NotePropertyName Address -NotePropertyValue $address
            $dash | Add-Member -NotePropertyName Name -NotePropertyValue (GetNodeName -config $config -id $dash.nodeID)
            $dash | Add-Member -NotePropertyName Sat -NotePropertyValue ([System.Collections.Generic.List[PSCustomObject]]@())

            $dash.satellites | ForEach-Object {
                $satid = $_.id
                try {
                    $sat = GetJson -uri ("http://{0}/api/satellite/{1}" -f $address, $satid)
                    $sat | Add-Member -NotePropertyName Dq -NotePropertyValue ($_.disqualified)
                    $dash.Sat.Add($sat)
                }
                catch {
                    Write-Host -ForegroundColor Red ("Node on address {0} fail sat {1}: {2}" -f $address, $satid, $_.Exception.Message )        
                }
            }
            $result.Add($dash)
        }
        catch {
            Write-Host -ForegroundColor Red ("Node on address {0} fail: {1}" -f $address, $_.Exception.Message )
        }
    }
    return $result
}

function GetDayStatItem
{
   $p = @{
        'Start'     = 0
        'Ingress'   = 0
        'Egress'    = 0
        'Delete'    = 0
        'Bandwidth' = 0
    }
    return New-Object -TypeName PSObject –Prop $p
}

function GetScore
{
    param($nodes, [ref]$stat)
    #$result = [System.Collections.Generic.List[PSObject]]@()

    $m = $nodes | `
    Select-Object -ExpandProperty Sat | `
    Select-Object -ExpandProperty BandwidthDaily | `
    Select-Object -ExpandProperty intervalStart | `
    Measure-Object -Minimum -Maximum 

    $score = $nodes | Sort-Object nodeID | ForEach-Object {
        $node = $_
        $node.Sat | Sort-Object id | ForEach-Object {
            $sat = $_
            New-Object PSCustomObject -Property @{
                Key = ("{0}-{1}" -f $node.nodeID, $sat.id)
                NodeId = $node.nodeID
                NodeName = $node.Name
                SatelliteId = $sat.id
                Audit = $sat.audit.score
                Uptime = $sat.uptime.score
                BandwidthDaily = ($sat.bandwidthDaily | Where-Object {$_.intervalStart -eq $m.Maximum} | Select-Object -First 1)
            }
        }
    }

    #calc counters if needed
    if (($null -ne $stat) -and ($null -ne $stat.Value)) {
        $stat.Value.Start = $m.Maximum
        $stat.Value.Ingress = ($score | ForEach-Object {$_.BandwidthDaily.ingress.usage} | Measure-Object -Sum).Sum
        $stat.Value.Egress = ($score | ForEach-Object {$_.BandwidthDaily.egress.usage} | Measure-Object -Sum).Sum
        $stat.Value.Delete =  ($score | ForEach-Object {$_.BandwidthDaily.delete} | Measure-Object -Sum).Sum
    }

    $score
}

function Compact
{
    param($id)
    return $id.Substring(0,4) + "-" + $id.Substring($id.Length-2)
}

function GetNodeName{
    param ($config, $id)
    $name = $config.WellKnownNodes."$id"
    if ($null -eq $name) { $name = Compact($id) }
    else {$name+= " (" + (Compact($id)) + ")"}
    return $name
}

function Round
{
    param($value)
    return [Math]::Round($value * 100, 2)
}

function HumanBytes {
    param ([int64]$bytes)
    $suff = "bytes", "KiB", "MiB", "GiB", "TiB", "PiB"
    $level = 0
    $rest = [double]$bytes
    while ([Math]::Abs($rest/1024) -ge 1) {
        $level++
        $rest = $rest/1024
    }
    #if ($rest -lt 0.001) { return [String]::Empty }
    if ($rest -lt 0.001) { return "0" }
    $mant = [Math]::Max(3 - [Math]::Floor($rest).ToString().Length,0)
    return ("{0} {1}" -f [Math]::Round($rest,$mant), $suff[$level])
}

function HumanTime {
    param ([TimeSpan]$time)
    $str = ("{0:00}:{1:00}:{2:00}:{3:00}" -f $time.Days, $time.Hours, $time.Minutes, $time.Seconds)
    while ($str.StartsWith("00:")) { $str = $str.TrimStart("00:") }
    return $str
}


function Out-Buffer {
    param ($sb, $msg)
    $sb.AppendLine($msg) | Out-Null
    Write-Host $msg
}

function CheckNodes{
    param(
        $config, 
        $sb,
        [ref]$oldNodesRef
    )
    $oldNodes = $oldNodesRef.Value
    ;
    $newNodes = GetNodes -config $config

    #DEBUG drop some satellites and reset update
    #$newNodes = $newNodes | Select-Object -First 2
    #$newNodes[1].upToDate = $false

    # Check absent nodes
    $failNodes = ($oldNodes | Where-Object { ($newNodes | Select-Object -ExpandProperty nodeID) -notcontains $_.nodeID })
    if ($failNodes.Count -gt 0) {
        $failNodes | ForEach-Object {
            Out-Buffer -sb ($sb) -msg ("Disconnected from node {0}" -f $_.nodeID)
        }
    }

    ;
    # Check versions
    $oldVersion = ($newNodes | Where-Object {-not $_.upToDate})
    if ($oldVersion.Count -gt 0) {
        $oldVersion | ForEach-Object {
            $testNode = $_
            $oldVersionStatus = $oldNodes | Where-Object { $_.nodeID -eq $testNode.nodeID } | Select-Object -First 1 -ExpandProperty upToDate
            if ($oldVersionStatus) {
                Out-Buffer -sb ($sb) -msg ("Node {0} is old ({1}.{2}.{3})" -f $testNode.nodeID, $testNode.version.major, $testNode.version.minor, $testNode.version.patch)
            }
        }
    }
    
    # Check new wallets
    $oldWal = $oldNodes | Select-Object -ExpandProperty wallet -Unique
    $newWal = $newNodes | Select-Object -ExpandProperty wallet -Unique | Where-Object {$oldWal -notcontains $_ }
    if ($newWal.Count -gt 0) {
        $newWal | ForEach-Object {
            Out-Buffer -sb $sb -msg ("!WARNING! NEW WALLET {0}" -f $_)
        }
    }


    # Check new satellites
    $oldSat = $oldNodes.satellites | Select-Object -ExpandProperty id -Unique

    #DEBUG drop some satellites
    #$oldSat = $oldSat | Sort-Object | Select-Object -First 2

    $newSat = $newNodes.satellites | Select-Object -ExpandProperty id -Unique | Where-Object {$oldSat -notcontains $_ }
    if ($newSat.Count -gt 0) {
        $newSat | ForEach-Object {
            Out-Buffer -sb $sb -msg ("New satellite {0}" -f $_)
        }
    }

    $oldNodesRef.Value = $newNodes
}

function CheckScore{
    param(
        $config, 
        $sb,
        $nodes,
        $oldScore
    )
    $newScore = GetScore -nodes $nodes

    #DEBUG drop scores
    #$newScore[0].Audit = 0.2
    #$newScore[3].Uptime = 0.6

    $newScore | ForEach-Object {
        $new = $_
        $old = $oldScore | Where-Object { $_.Key -eq $new.Key }
        if ($null -ne $old){
            $idx = $oldScore.IndexOf($old)
            if ($old.Audit -ge ($new.Audit + $config.Threshold)) {
                Out-Buffer -sb ($sb) -msg ("Node {0} down audit from {1} to {2} on {3}" -f $new.nodeID, $old.Audit, $new.Audit, $new.SatelliteId)
                $oldScore[$idx].Audit = $new.Audit
            }
            elseif ($new.Audit -gt $old.Audit) { $oldScore[$idx].Audit = $new.Audit }

            if ($old.Uptime -ge ($new.Uptime + $config.Threshold)) {
                Out-Buffer -sb ($sb) -msg ("Node {0} down uptime from {1} to {2} on {3}" -f $new.nodeID, $old.Uptime, $new.Uptime, $new.SatelliteId)
                $oldScore[$idx].Uptime = $new.Uptime
            }
            elseif ($new.Uptime -gt $old.Uptime) { $oldScore[$idx].Uptime = $new.Uptime }
        }
    }
}


function ExecCommand {
    param ($path, $params, [switch]$out)

    $content = $null
    if ($out) { 
    $temp = [System.IO.Path]::GetTempFileName()
    #Write-Host ("Exec {0} {1}" -f $path, $params)
    #Write-Host ("Output redirected to {0}" -f $temp)
    $proc = Start-Process -FilePath $path -ArgumentList $params -RedirectStandardOutput $temp -Wait -PassThru
    #Write-Host done
	$content = Get-Content -Path $temp
	[System.IO.File]::Delete($temp)
	if ($proc.ExitCode -ne 0) { throw $content }
	else { return $content }
    }
    else { 
	$proc = Start-Process -FilePath $path -ArgumentList $params -Wait -PassThru
	if ($proc.ExitCode -ne 0) { return $false }
	else { return $true }
    }
}

function SendMailLinux{
    param(
        $config, 
        $sb
    )

    ;
    $body = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($body, $sb.ToString())

        $catParam = "'{0}'" -f $body
        $mailParam = "-s '{0}' {1}" -f $config.Mail.Subj, $config.Mail.To
        $bashParam = ('-c "cat {0} | mail {1}"' -f $catParam, $mailParam)
        $output = ExecCommand -path $config.Mail.Path -params $bashParam -out

        Write-Host ("Mail sent to {0} via linux agent" -f $config.Mail.To)
        if ($output.Length -gt 0) { Write-Host $output }
        $sb.Clear() | Out-Null
        Write-Host "Buffer cleared"
    }
    catch {
        Write-Host -ForegroundColor Red ($_.Exception.Message)        
    }
    finally {
        try {
            #if ([System.IO.File]::Exists($body)) { [System.IO.File]::Delete($body) }    
        }
        catch { }
    }

}

function SendMailPowershell{
    param(
        $config, 
        $sb
    )
    try {
        $pd = $config.Mail.AuthPass | ConvertTo-SecureString -asPlainText -Force

        if ([String]::IsNullOrEmpty($config.Mail.AuthUser)) { $user = $config.Mail.From }
        else { $user = $config.Mail.AuthUser }

        $credential = New-Object System.Management.Automation.PSCredential($user, $pd)

        $ssl = $true
        if ($config.Mail.Port -eq 25) { $ssl = $false }

        try {
            Send-MailMessage  `
                -To ($config.Mail.To) `
                -From ($config.Mail.From) `
                -Subject ($config.Mail.Subj) `
                -Body ($sb.ToString()) `
                -UseSsl: $ssl `
                -SmtpServer ($config.Mail.Smtp) `
                -Port ($config.Mail.Port) `
                -Credential $credential `
                -ErrorAction Stop
            
            Write-Host ("Mail sent to {0} via powershell agent" -f $config.Mail.To)
            $sb.Clear() | Out-Null
            Write-Host "Buffer cleared"
        }
        catch 
        {

            if ($config.Mail.From -match "gmail.com") { $msg = ("google is bad mail sender. try other service: {0}" -f $_.Exception.Message) }
            else { $msg = ("Bad mail sender or something wrong in mail config: {0}" -f $_.Exception.Message) }
            throw $msg
        }
    }
    catch {
        Write-Host -ForegroundColor Red ($_.Exception.Message)
    }

}

#SendMail -config $config -sb (sb)
function SendMail{
    param(
        $config, 
        $sb
    )

    if ($null -eq $config.Mail -or $config.Mail.MailAgent -eq "none") { 
        $sb.Clear() | Out-Null
    }
    elseif ($config.Mail.MailAgent -eq "powershell") { SendMailPowershell -config $config -sb $sb }
    elseif ($config.Mail.MailAgent -eq "linux") { SendMailLinux -config $config -sb $sb }
    else {
        Write-Host -ForegroundColor Red "Mail not properly configuried"
    }
}

function Monitor {
    param (
        $config, 
        $sb, 
        $oldNodes,
        $oldScore
    )

    while ($true) {
        Start-Sleep -Seconds $config.WaitSeconds
        CheckNodes -config $config -sb $sb -oldNodesRef ([ref]$oldNodes)
        CheckScore -config $config -sb $sb -nodes $oldNodes -oldScore $oldScore

        ;
        if ([System.DateTimeOffset]::Now.Day -ne $config.Canary.Day -and [System.DateTimeOffset]::Now.Hour -gt 9) {
            $config.Canary = [System.DateTimeOffset]::Now
            Out-Buffer -sb $sb -msg ("storj3monitor is alive {0}" -f $config.Canary)
        }

        if ($sb.Length -gt 0) { SendMail -config $config -sb $sb }
    }
    Write-Host "Stop monitoring"
}

function GetPips {
    param ($width, $max, $current)
    $val = $current/$max
    $pips = [int]($width * $val )
    $str = "[" + "".PadRight($pips, "-").PadRight($width, " ") + "] "
    return $str
}

function DisplayNodes {
    param ($nodes)
    Write-Host
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "N O D E S    S U M M A R Y"

    $nodes | Sort-Object Name | Format-Table `
    @{n="Node"; e={$_.Name}}, `
    @{n="LastContact"; e={HumanTime([DateTimeOffset]::Now - [DateTimeOffset]::Parse($_.lastPinged))}}, `
    @{n="Disk"; e={("{0} ({1} free)" -f ((GetPips -width 30 -max $_.diskSpace.available -current $_.diskSpace.used)), (HumanBytes(($_.diskSpace.available - $_.diskSpace.used) * 1024 * 1024 * 1024)))}}, `
    @{n="Bandwidth"; e={("{0} ({1} free)" -f ((GetPips -width 10 -max $_.bandwidth.available -current $_.bandwidth.used)), (HumanBytes(($_.bandwidth.available - $_.bandwidth.used) * 1024 * 1024 * 1024)))}}
    Write-Host
}

function DisplayScore {
    param ($score, $stat)

    Write-Host
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "S A T E L L I T E S    S U M M A R Y"

    $score | Sort-Object SatelliteId, NodeName | Format-Table `
    @{n="Satellite";e={("{0} ({1})" -f $wellKnownSat[$_.SatelliteId], (Compact($_.SatelliteId))) }}, `
    @{n="Node"; e={$_.NodeName}}, `
    @{n="Ingress    :";e={("{0} {1}" -f (GetPips -width 10 -max $stat.Ingress -current $_.BandwidthDaily.ingress.usage), (HumanBytes($_.BandwidthDaily.ingress.usage))) }}, `
    @{n="Egress     :";e={("{0} {1}" -f (GetPips -width 10 -max $stat.Egress -current $_.BandwidthDaily.egress.usage), (HumanBytes($_.BandwidthDaily.egress.usage))) }}, `
    @{n="Delete     :";e={("{0} {1}" -f (GetPips -width 10 -max $stat.Delete -current $_.BandwidthDaily.delete), (HumanBytes($_.BandwidthDaily.delete))) }}, `
    @{n="Audit";e={Round($_.Audit)}}, `
    @{n="Uptime";e={Round($_.Uptime)}}

    Write-Host ("`t* Ingress, Egress, Delete counters starts from {0}" -f $stat.Start)
    Write-Host
}

function GraphTimeline 
{
    param ($title, $decription, [int]$height, $fromTime, $toTime, $timeline)
    $width = 160
    if ($height -eq 0) { $height = 10 }
    if ($fromTime -ge $toTime) {
        Write-Host -ForegroundColor Red ("{0}: Bad timeline params. exiting." -f $title)
        return
    }
    $lastSlot = ($timeline.Keys | Measure-Object -Maximum).Maximum


    [int]$idx = 0
    $colWidth = [int]([Math]::Floor([Math]::Max(1.0, $lastSlot / $width)))
    $lastCol = [int][Math]::Ceiling($lastSlot/$colWidth)
    $data = new-object long[] ($lastCol + 1)

    #grouping to fit width
    for ($i = 0; $i -le $lastCol; $i++)
    {
        for ($j = 0; $j -lt $colWidth; $j++)
        {
            $idx = $i * $colWidth + $j
            if ($timeline.ContainsKey($idx)) { $data[$i]+=$timeline[$idx] }
        }
    }
   
    #max in groups while min in original data. otherwise min was zero in empty data cells
    $dataMin = ($timeline.Values | Measure-Object -Minimum).Minimum
    $dataMax = ($data | Measure-Object -Maximum).Maximum

    #limit height to actual data
    $rowWidth = ($dataMax - $dataMin) / $height
    if ($rowWidth -lt $dataMin) { $rowWidth = $dataMin }
    if ($dataMax / $rowWidth -lt $height) { $height = $dataMax / $rowWidth }

    $graph = New-Object System.Collections.Generic.List[string]

    #workaround for bad text editors
    $pseudoGraphicsSymbols = [System.Text.Encoding]::UTF8.GetString(([byte]226, 148,148,226,148,130,45,226,148,128))
    if ($pseudoGraphicsSymbols.Length -ne 4) { throw "Error with pseudoGraphicsSymbols" }
    $graph.Add($pseudoGraphicsSymbols[0].ToString().PadRight($lastCol + 1, $pseudoGraphicsSymbols[3]))

    1..$height | ForEach-Object {
        $r = $_
        $line = $pseudoGraphicsSymbols[1]
        1..$lastCol | ForEach-Object {
            $c = $_
            $v = $data[$c-1]
            $h = $v / $rowWidth
            if ($h -ge $r ) {$line+=$pseudoGraphicsSymbols[2]}
            else {$line+=" "}
        }
        $graph.Add($line)
    }
    $graph.Reverse()

    Write-Host $title -NoNewline -ForegroundColor Yellow
    if (-not [String]::IsNullOrEmpty($decription)) {Write-Host (" - {0}" -f $decription) -ForegroundColor Gray -NoNewline}
    Write-Host
    Write-Host ("Y-axis from {0} to {1}, cell = {2}" -f (HumanBytes($dataMin)), (HumanBytes($dataMax)), (HumanBytes($rowWidth))) -ForegroundColor Gray
    $graph | ForEach-Object {Write-Host $_}
    Write-Host -ForegroundColor Gray ("X-axis from {0:$hformat2} to {1:$hformat2}, cell = 1 day, total = {2} hours" -f $fromTime, $toTime, ([int](($toTime - $fromTime).TotalHours)))
    Write-Host
    Write-Host
}

function DisplaySat {
    param ($nodes)
    Write-Host
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "S A T E L L I T E S   B A N D W I D T H"
    Write-Host "Y-axis ingress + egress"
    Write-Host
    $now = [System.DateTimeOffset]::Now
    ($nodes | Select-Object -ExpandProperty Sat) | Group-Object id | ForEach-Object {
        #Write-Host $_.Name
        $sat = $_
        $bw = $sat.Group | Select-Object -ExpandProperty bandwidthDaily | Where-Object { ($_.IntervalStart.Year -eq $now.Year) -and ($_.IntervalStart.Month -eq $now.Month)}
        $m = $bw | Measure-Object -Minimum -Maximum IntervalStart
        $bd = $bw | Group-Object {$_.intervalStart.Day} | Sort-Object {[Int]::Parse($_.Name)}
        $data = $bd | ForEach-Object {
            $item = GetDayStatItem
            $item.Start = $_.Name
            $item.ingress = ($_.Group | ForEach-Object {$_.ingress.usage} | Measure-Object -Sum).Sum
            $item.egress = ($_.Group | ForEach-Object {$_.egress.usage} | Measure-Object -Sum).Sum
            $item.bandwidth = $item.ingress + $item.egress
            $item
        }
        $timeline = New-Object "System.Collections.Generic.SortedList[int,long]"
        $data | ForEach-Object { $timeline.Add([Int]::Parse($_.Start), $_.bandwidth) }
        $title = ("{0}`t{1}" -f $wellKnownSat[$sat.Name], $sat.Name)
        GraphTimeline -title $title -from $m.Minimum -to $m.Maximum -timeline $timeline
    }
    Write-Host
}

Preamble
if ($args.Contains("example")) {
    $config = DefaultConfig
    $config | ConvertTo-Json
    return
}

$config = LoadConfig -cmdlineArgs $args
#DEBUG
#$config = LoadConfig -cmdlineArgs "-c", ".\ConfigSamples\Storj3Monitor.Debug.conf"

if (-not $config) { return }

$config | Add-Member -NotePropertyName StartTime -NotePropertyValue ([System.DateTimeOffset]::Now)
$config | Add-Member -NotePropertyName Canary -NotePropertyValue $config.StartTime

#DEBUG check Canary
#$config.Canary = [System.DateTimeOffset]::Now.Subtract([System.TimeSpan]::FromDays(1))

$nodes = GetNodes -config $config
$stat = GetDayStatItem
$score = GetScore -nodes $nodes -stat ([ref]$stat)

    
if ($args.Contains("monitor")) {
    [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine(("Start monitoring {0} entries at {1}, {2} seconds cycle" -f $score.Count, $config.StartTime, $config.WaitSeconds)) | Out-Null
    #$sb.Append(($tab | Out-String)) | Out-Null
    $sb.ToString()

    Monitor -config $config -sb $sb -oldNodes $nodes -oldScore $score
}
elseif ($args.Contains("testmail")) {
    [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("Test mail. Configured {0} entries" -f $score.Count) | Out-Null
    #$sb.Append(($tab | Out-String)) | Out-Null
    SendMail -config $config -sb $sb
}
elseif ($nodes.Count -gt 0) {
    DisplaySat -nodes $nodes
    DisplayNodes -nodes $nodes
    DisplayScore -score $score -stat $stat
}

