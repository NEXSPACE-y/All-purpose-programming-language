# Worker: runs official PHPT tests against the ALL PHP adapter IN-PROCESS (never calls php.exe).
# One JSON line per event is appended to -OutFile:
#   {"i":N,"start":true}            written before a test runs (lets the parent detect hangs/crashes)
#   {"i":N,"verdict":"...",...}     written after the test finished
# Windows PowerShell 5.1 compatible. ASCII only.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AdapterPath,
    [Parameter(Mandatory = $true)][string]$TestRoot,
    [Parameter(Mandatory = $true)][string]$ListFile,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [int]$StartIndex = 0
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$adapter = & $AdapterPath
if ($null -eq $adapter -or $adapter.Run -isnot [scriptblock]) { throw 'adapter did not load' }
$runPhp = $adapter.Run
$tests = @([IO.File]::ReadAllLines($ListFile, $utf8) | Where-Object { $_ })

# Sections that need a runtime facility the adapter entry point (-Code only) cannot be given.
$unrunnable = @('STDIN', 'ARGS', 'ENV', 'POST', 'POST_RAW', 'PUT', 'GET', 'COOKIE', 'CGI', 'PHPDBG',
    'GZIP_POST', 'DEFLATE_POST', 'FILE_EXTERNAL', 'REDIRECTTEST', 'CAPTURE_STDIO', 'EXPECTHEADERS',
    'EXPECT_EXTERNAL', 'EXPECTF_EXTERNAL', 'EXPECTREGEX_EXTERNAL')

function Read-Phpt([string]$path) {
    $text = [IO.File]::ReadAllText($path, $utf8)
    $sections = @{}
    $current = $null
    $buffer = New-Object System.Text.StringBuilder
    foreach ($line in [regex]::Split($text, '(?<=\n)')) {
        if ($line -cmatch '^--([_A-Z]+)--\s*$') {
            if ($null -ne $current) { $sections[$current] = $buffer.ToString() }
            $current = $Matches[1]
            [void]$buffer.Clear()
        } elseif ($null -ne $current) {
            [void]$buffer.Append($line)
        }
    }
    if ($null -ne $current) { $sections[$current] = $buffer.ToString() }
    return $sections
}

function Normalize([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace "`r`n", "`n").Trim()
}

# Same conversion as the official run-tests.php (EXPECTF -> regular expression).
function Convert-ExpectF([string]$wanted) {
    $sb = New-Object System.Text.StringBuilder
    $offset = 0
    $length = $wanted.Length
    while ($offset -lt $length) {
        $start = $wanted.IndexOf('%r', $offset, [StringComparison]::Ordinal)
        if ($start -ge 0) {
            $end = if ($start + 2 -le $length) { $wanted.IndexOf('%r', $start + 2, [StringComparison]::Ordinal) } else { -1 }
            if ($end -lt 0) { $start = $length; $end = $length }
        } else { $start = $length; $end = $length }
        [void]$sb.Append([regex]::Escape($wanted.Substring($offset, $start - $offset)))
        if ($end -gt $start) { [void]$sb.Append('(' + $wanted.Substring($start + 2, $end - $start - 2) + ')') }
        $offset = $end + 2
    }
    $re = $sb.ToString()
    $re = $re.Replace('%binary_string_optional%', 'string').Replace('%unicode_string_optional%', 'string')
    $re = $re.Replace('%unicode\|string%', 'string').Replace('%string\|unicode%', 'string')
    $re = $re.Replace('%u\|b%', '').Replace('%b\|u%', '')
    $re = $re.Replace('%e', '\\').Replace('%s', '[^\r\n]+').Replace('%S', '[^\r\n]*')
    $re = $re.Replace('%a', '.+').Replace('%A', '.*').Replace('%w', '\s*')
    $re = $re.Replace('%i', '[+-]?\d+').Replace('%d', '\d+').Replace('%x', '[0-9a-fA-F]+')
    $re = $re.Replace('%f', '[+-]?(?:\d+|(?=\.\d))(?:\.\d+)?(?:[Ee][+-]?\d+)?')
    $re = $re.Replace('%c', '.').Replace('%0', '\x00')
    return $re
}

function Test-Regex([string]$pattern, [string]$text) {
    $rx = New-Object System.Text.RegularExpressions.Regex(
        ('\A(?:' + $pattern + ')\z'),
        [System.Text.RegularExpressions.RegexOptions]::Singleline,
        [TimeSpan]::FromSeconds(5))
    return $rx.IsMatch($text)
}

function Write-Line($obj) {
    [IO.File]::AppendAllText($OutFile, (($obj | ConvertTo-Json -Compress -Depth 3) + "`n"), $utf8)
}

function Clip([string]$s, [int]$n) {
    if ($null -eq $s) { return '' }
    if ($s.Length -le $n) { return $s }
    return $s.Substring(0, $n)
}

for ($i = $StartIndex; $i -lt $tests.Count; $i++) {
    $rel = $tests[$i]
    Write-Line ([ordered]@{ i = $i; start = $true })
    $row = [ordered]@{ i = $i; test = $rel; verdict = ''; detail = ''; expects_fatal = $false; ms = 0 }
    try {
        $sec = Read-Phpt (Join-Path $TestRoot $rel)
        $blocked = @($unrunnable | Where-Object { $sec.ContainsKey($_) })
        $code = $null
        if ($sec.ContainsKey('FILE')) { $code = $sec['FILE'] }
        elseif ($sec.ContainsKey('FILEEOF')) { $code = $sec['FILEEOF'] -replace "\r?\n\z", '' }
        $kind = $null
        foreach ($k in 'EXPECT', 'EXPECTF', 'EXPECTREGEX') { if ($sec.ContainsKey($k)) { $kind = $k; break } }
        if ($blocked.Count -gt 0) {
            $row.verdict = 'NOT_RUNNABLE'; $row.detail = 'needs --' + ($blocked -join '--, --') + '--'
        } elseif ($null -eq $code -or $null -eq $kind) {
            $row.verdict = 'NOT_RUNNABLE'; $row.detail = 'no FILE or EXPECT section'
        } else {
            $wanted = Normalize $sec[$kind]
            $row.expects_fatal = [bool]($wanted -cmatch '(Fatal error|Parse error)')
            $writer = New-Object System.IO.StringWriter([System.Globalization.CultureInfo]::InvariantCulture)
            $saved = [Console]::Out
            $failure = $null
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                [Console]::SetOut($writer)
                $null = @(& $runPhp -Code $code)
            } catch {
                $failure = [string]$_.Exception.Message
            } finally {
                [Console]::SetOut($saved)
            }
            $row.ms = [int]$sw.ElapsedMilliseconds
            $actual = Normalize $writer.ToString()
            $writer.Dispose()
            if ($null -ne $failure) {
                $row.verdict = 'ALL_ERROR'; $row.detail = Clip $failure 300
            } else {
                $ok = $false
                try {
                    if ($kind -ceq 'EXPECT') { $ok = ($actual -ceq $wanted) }
                    elseif ($kind -ceq 'EXPECTF') { $ok = Test-Regex (Convert-ExpectF $wanted) $actual }
                    else { $ok = Test-Regex $wanted $actual }
                    if ($ok) { $row.verdict = 'PASS' }
                    else { $row.verdict = 'OUTPUT_DIFF'; $row.detail = Clip $actual 300 }
                } catch {
                    $row.verdict = 'MATCHER_ERROR'; $row.detail = Clip ([string]$_.Exception.Message) 300
                }
            }
        }
    } catch {
        $row.verdict = 'HARNESS_ERROR'; $row.detail = Clip ([string]$_.Exception.Message) 300
    }
    Write-Line $row
}
Write-Line ([ordered]@{ done = $true })
