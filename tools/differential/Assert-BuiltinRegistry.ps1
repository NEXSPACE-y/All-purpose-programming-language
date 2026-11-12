# Read-only consistency check for the cache's supported-builtin registry and the dispatcher.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$AdapterPath)
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $AdapterPath), [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw 'Adapter syntax errors' }
$registry = $ast.Find({ param($n)
    $n -is [Management.Automation.Language.ForEachStatementAst] -and
    $n.Variable.VariablePath.UserPath -eq 'builtinName'
}, $true)
$function = $ast.Find({ param($n)
    $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-PhpFunction'
}, $true)
if ($null -eq $registry -or $null -eq $function) { throw 'Registry or builtin dispatcher missing' }
$dispatch = $function.Body.Find({ param($n) $n -is [Management.Automation.Language.SwitchStatementAst] }, $true)
$wanted = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($clause in $dispatch.Clauses) {
    $values = $clause.Item1.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] }, $true)
    foreach ($value in $values) { [void]$wanted.Add($value.Value) }
}
$values = $registry.Condition.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] }, $true)
foreach ($value in $values) { [void]$actual.Add($value.Value) }
if (-not $wanted.SetEquals($actual)) {
    throw "Builtin registry differs from dispatcher: expected $($wanted.Count), registry $($actual.Count)"
}
Write-Output "Builtin registry matches all $($actual.Count) dispatcher names/aliases."
