<?php
namespace MiXeD {const VaL=1; function FnX(){} class Cn {const VaL=2; public $Prop=3; public function Meth(){}}}
namespace {echo json_encode([
'constant_exact'=>defined('MiXeD\\VaL'),
'constant_namespace_ascii_case'=>defined('mixed\\VaL'),
'constant_leaf_ascii_case'=>defined('MiXeD\\val'),
'function_namespace_ascii_case'=>function_exists('mixed\\fnx'),
'class_namespace_ascii_case'=>class_exists('mixed\\cn'),
'method_ascii_case'=>method_exists('mixed\\cn','meth'),
'property_ascii_case'=>property_exists('MiXeD\\Cn','prop'),
'class_constant_class_case'=>defined('mixed\\cn::VaL'),
'class_constant_leaf_case'=>defined('MiXeD\\Cn::val')
], JSON_THROW_ON_ERROR);}
