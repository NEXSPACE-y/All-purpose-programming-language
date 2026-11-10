param(
    [Parameter(Mandatory=$true)][int]$Port,
    [Parameter(Mandatory=$true)][string]$StopPath
)
$ErrorActionPreference = 'Stop'
$env:ALL_HTTP_STOP_FILE = $StopPath
$env:ALL_HTTP_ACCESS_LOG = '0'
$source = @'
関数 API(要求) {
    もし (要求["path"] == "/health") {
        返す {"status":200,"body":"OK"}
    }
    返す {"status":404,"body":"Not found"}
}
HTTP常時配信(__ALL_PORT__,"API")
'@
$source = $source.Replace('__ALL_PORT__',[string]$Port)
try {
    & (Join-Path $HOME 'ALL\ALL.ps1') -Language ALL -Code $source
    exit 0
} catch {
    [Console]::Error.WriteLine('ALL QA server error: ' + $_.Exception.Message)
    exit 1
}
