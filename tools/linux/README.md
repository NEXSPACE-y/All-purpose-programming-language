# Linux x64 環境の事前確認

`linux_preflight.py` はPATH、既知の導入先、対象リポジトリとバックエンドの読み取り専用一覧を確認し、JSONを保存する。WSL/VM/コンテナの起動・導入、SSH接続、資格情報探索、依存の導入は行わない。

```powershell
python tools/linux/linux_preflight.py --output reports/linux-preflight-20261112.json
```

Linux側でも同じファイルを`python3`で実行できる。`uname`、64bit、既存コンパイラ等のバージョンを記録するだけで、ビルド成功・PHP8.5.12オラクルの同一性・ALL実行・Web/ABIの合格を認定しない。

今回の現物確認と次の実行経路は [LINUX_VALIDATION_ROUTE.md](LINUX_VALIDATION_ROUTE.md) に記録する。
