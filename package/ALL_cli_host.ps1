# ALL native command entrypoint (used by all.cmd).
# This script is executed in a child PowerShell process so exit codes are reliable.
$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'ALL_cli.ps1'
$argv = @($args)
$verb = if ($argv.Count -gt 0) { [string]$argv[0] } else { 'help' }
try {
    switch -CaseSensitive ($verb) {
        'help' {
            [Console]::WriteLine('ALL command v1.2')
            [Console]::WriteLine('  all run <file.all> [script args ...]')
            [Console]::WriteLine('  all serve <server.all> <absolute-stop-file>')
            [Console]::WriteLine('  all serve-pool <server.all> <absolute-stop-file> [workers]')
            [Console]::WriteLine('  all stop <absolute-stop-file>')
            [Console]::WriteLine('  all version')
            exit 0
        }
        'version' {
            [Console]::WriteLine('ALL command v1.2')
            exit 0
        }
        'run' {
            if ($argv.Count -lt 2) { throw 'Usage: all run <file.all> [args...]' }
            $file = [string]$argv[1]
            $remaining = @()
            if ($argv.Count -gt 2) { $remaining = @($argv[2..($argv.Count - 1)]) }
            [Environment]::SetEnvironmentVariable('ALL_CLI_EXIT_CODE','0','Process')
            & $cli -Command run -File $file -Language ALL -ScriptArgs $remaining
            $resultCode = [Environment]::GetEnvironmentVariable('ALL_CLI_EXIT_CODE','Process')
            if ($resultCode -cnotmatch '^(?:0|[1-9][0-9]{0,2})$' -or [int]$resultCode -gt 255) {
                throw 'ALL CLI Error: Invalid exit code returned from program'
            }
            exit ([int]$resultCode)
        }
        'serve' {
            if ($argv.Count -ne 3) { throw 'Usage: all serve <server.all> <absolute-stop-file>' }
            $file = [string]$argv[1]
            $stopFile = [string]$argv[2]
            if (-not [System.IO.Path]::IsPathRooted($stopFile)) { throw 'Stop file must be an absolute path' }
            $stopFile = [System.IO.Path]::GetFullPath($stopFile)
            $parent = [System.IO.Path]::GetDirectoryName($stopFile)
            if (-not [System.IO.Directory]::Exists($parent)) { throw 'Stop file parent directory does not exist' }
            # A leftover signal from a previous run must not stop a new server immediately.
            if ([System.IO.File]::Exists($stopFile)) { [System.IO.File]::Delete($stopFile) }
            $oldStop = [Environment]::GetEnvironmentVariable('ALL_HTTP_STOP_FILE','Process')
            $oldLog = [Environment]::GetEnvironmentVariable('ALL_HTTP_ACCESS_LOG','Process')
            try {
                [Environment]::SetEnvironmentVariable('ALL_HTTP_STOP_FILE',$stopFile,'Process')
                [Environment]::SetEnvironmentVariable('ALL_HTTP_ACCESS_LOG','1','Process')
                & $cli -Command run -File $file -Language ALL
            } finally {
                [Environment]::SetEnvironmentVariable('ALL_HTTP_STOP_FILE',$oldStop,'Process')
                [Environment]::SetEnvironmentVariable('ALL_HTTP_ACCESS_LOG',$oldLog,'Process')
            }
            exit 0
        }
        'serve-pool' {
            if($argv.Count -lt 3 -or $argv.Count -gt 4){throw 'Usage: all serve-pool <server.all> <absolute-stop-file> [workers]'}
            $workerCount=4
            if($argv.Count -eq 4){
                $workerCount=0
                if(-not [int]::TryParse([string]$argv[3],[ref]$workerCount)){throw 'ALL CLI: invalid worker count'}
            }
            $pool=Join-Path $PSScriptRoot 'ALL_serve_pool.ps1'
            & $pool -File ([string]$argv[1]) -StopFile ([string]$argv[2]) -Workers $workerCount
            exit 0
        }
        'stop' {
            if ($argv.Count -ne 2) { throw 'Usage: all stop <absolute-stop-file>' }
            $stopFile = [string]$argv[1]
            if (-not [System.IO.Path]::IsPathRooted($stopFile)) { throw 'Stop file must be an absolute path' }
            $stopFile = [System.IO.Path]::GetFullPath($stopFile)
            $parent = [System.IO.Path]::GetDirectoryName($stopFile)
            if (-not [System.IO.Directory]::Exists($parent)) { throw 'Stop file parent directory does not exist' }
            [System.IO.File]::WriteAllText($stopFile,'stop',[System.Text.UTF8Encoding]::new($false))
            [Console]::WriteLine('Stop requested; check that the server process exits.')
            exit 0
        }
        default { throw "Unknown command: $verb" }
    }
} catch {
    [Console]::Error.WriteLine('ALL CLI Error: ' + $_.Exception.Message)
    exit 1
}
