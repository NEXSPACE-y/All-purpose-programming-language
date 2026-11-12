[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Core,[Parameter(Mandatory=$true)][string]$Extension,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'AllNativeBridge.cs')
$bridge=New-Object AllPhp85Abi.Bridge([IO.Path]::GetFullPath($Core))
$bridge.LoadExtension([IO.Path]::GetFullPath($Extension))
$checks=[ordered]@{}
$catalog=ConvertFrom-Json -InputObject $bridge.FunctionCatalog
$checks.dynamic_catalog_count=($catalog.Count -eq 3)
$checks.catalog_required_arity=(@($catalog|Where-Object{$_.name-ceq'dl_test_frameless'-and$_.required_args-eq1-and$_.declared_args-eq1}).Count-eq1)
$checks.case_insensitive_has_function=$bridge.HasFunction('DL_TEST_TEST2')
$checks.unknown_function_absent=(-not $bridge.HasFunction('all_nonexistent_native_function'))
$checks.NUL_identifier_not_bound=(-not $bridge.HasFunction("dl_test_test2`0junk"))
$checks.invalid_UTF16_identifier_not_bound=(-not $bridge.HasFunction([string][char]0xd800))
$bridge.Start()
try {
 $unicode=[string]([char]0x65e5)+[char]0x672c+[char]0x8a9e
 $r=$bridge.InvokeScalar('DL_TEST_TEST2',[object[]]@($unicode),$false)
 $checks.valid_UTF8_value=($r.Ok-and$r.Value-ceq('Hello '+$unicode))
 $r=$bridge.InvokeScalar('dl_test_test2',[object[]]@("A`0B"),$false)
 $checks.embedded_NUL_follows_original_native_printf_semantics=($r.Ok-and$r.Value-ceq'Hello A')
 $r=$bridge.InvokeScalar('dl_test_frameless',[object[]]@([long]::MinValue),$false)
 $checks.int64_minimum_exact=($r.Ok-and$r.Value-is[long]-and$r.Value-eq[long]::MinValue)
 $r=$bridge.InvokeScalar('dl_test_frameless',[object[]]@('19'),$true)
 $checks.PHP_type_error_carried=((-not$r.Ok)-and$r.ErrorClass-ceq'TypeError'-and$r.ErrorMessage-ceq'dl_test_frameless(): Argument #1 ($value) must be of type int, string given')
 $r=$bridge.InvokeScalar('dl_test_test1',[object[]]@(),$false)
 $checks.output_bytes_once=($r.Ok-and[Convert]::ToBase64String($r.Output)-ceq[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("The extension dl_test is loaded and working!`r`n")))
 $r=$bridge.InvokeScalar('dl_test_frameless',[object[]]@($null),$false)
 $checks.structured_diagnostic_event=($r.Ok-and$r.DiagnosticEvents.Count-eq1-and$r.DiagnosticEvents[0].Level-eq8192-and$r.DiagnosticEvents[0].Message-ceq'dl_test_frameless(): Passing null to parameter #1 ($value) of type int is deprecated')
 $before=($bridge.Stats|ConvertFrom-Json).native_invocations
 $identifierChecks=[ordered]@{}
 try{$null=$bridge.InvokeScalar("dl_test_test2`0junk",[object[]]@('value'),$false);$identifierChecks.function=$false}catch{$identifierChecks.function=$true}
 try{$null=$bridge.Call("DlTest`0junk",'test',[AllPhp85Abi.Argument[]]@(),$false,$false);$identifierChecks.scope=$false}catch{$identifierChecks.scope=$true}
 try{$null=$bridge.Ini("dl_test.long`0junk");$identifierChecks.ini_key=$false}catch{$identifierChecks.ini_key=$true}
 try{$null=$bridge.Parent("DlTest`0junk");$identifierChecks.class=$false}catch{$identifierChecks.class=$true}
 try{$null=$bridge.Constant("DL_TEST_CONST`0junk");$identifierChecks.constant=$false}catch{$identifierChecks.constant=$true}
 try{$null=$bridge.Property('DlTestSuperClass',"a`0junk");$identifierChecks.property=$false}catch{$identifierChecks.property=$true}
 try{$null=$bridge.SetIni('dl_test.string',"A`0B");$identifierChecks.current_INI_NUL_value_explicitly_unsupported=$false}catch{$identifierChecks.current_INI_NUL_value_explicitly_unsupported=$true}
 foreach($pair in $identifierChecks.GetEnumerator()){$checks[('reject_NUL_'+$pair.Key)]=$pair.Value}
 $bad=New-Object 'Collections.Generic.Dictionary[string,object]'
 $bad.Add('populated_array',[object[]]@(1,2));$bad.Add('raw_byte_array',[byte[]]@(255));$bad.Add('decimal',[decimal]1.25);$bad.Add('invalid_UTF16',[string][char]0xd800)
 foreach($pair in $bad.GetEnumerator()){
  $one=[Array]::CreateInstance([object],1);$one.SetValue($pair.Value,0)
  $rejected=$false
  try{$null=$bridge.InvokeScalar('dl_test_test2',$one,$false)}catch{$rejected=$true}
  $checks[('reject_'+$pair.Key)]=$rejected
 }
 $after=($bridge.Stats|ConvertFrom-Json).native_invocations
 $checks.unsupported_values_rejected_before_native_side_effect=($before-eq$after)
} finally {$bridge.End();$bridge.Shutdown()}
$record=[ordered]@{method='scalar_C_bridge_contract_probe_not_full_PHP_evaluator_integration';checks=$checks;all_passed=(@($checks.Values|Where-Object{-not$_}).Count-eq0);catalog=$catalog;core_path=$bridge.CorePath;stats=$bridge.Stats|ConvertFrom-Json}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output),($record|ConvertTo-Json -Depth 10)+[Environment]::NewLine,$utf8)
if(-not$record.all_passed){throw 'Native scalar bridge contract has failed checks'}
Write-Output ('Native scalar bridge '+$checks.Count+' checks passed')
