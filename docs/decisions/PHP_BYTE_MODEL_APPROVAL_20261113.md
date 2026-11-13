# PHP byte値モデル方式1の所有者承認

2026-11-13、この開発セッションで所有者が **「方式1を承認する（不変byte値＋typed key）」** と明示回答した。

対象資料：[PHP_BYTE_STRING_DESIGN.md](../design/PHP_BYTE_STRING_DESIGN.md)。同資料の「採用判断待ち」はcomponent固定時点の履歴であり、現在の承認状態は本記録を参照する。

承認された方針は、PHP文字列を不変byte値へ移し、typed配列key、演算・比較・入出力・native境界を段階的に改修する方式1。元のPHP8.5.12、Windows11x64/Linuxx64、既存native binaries、CLI/Web各対象という範囲を縮めない。64bit storage等の未実装部分も実装・検証対象に残る。

案Aのnative ABI境界だけを再承認した記録ではなく、仕様9.1に基づく値モデル全体の設計判断である。既存PS評価器からnative実行core全体へ移す案B、追加のPHP実装component採用、公式PHPへの実行委譲を承認したものではない。

現時点で完成したのは設計と隔離componentの実測。production byte runtime、symbol/array key、PS interpreter全経路、raw I/O、native境界への適用は作業中であり、この承認は実行検証やPHP完全互換の認定ではない。mainと導入済みALLは変更しない。
