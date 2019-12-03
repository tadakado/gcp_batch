----
# 環境設定
----

[`doc/settins.md`](settings.md)を参照

----
# マスタコントローラからバッチを投入する
----

## 支援スクリプト

gcp/master/queue.sh : キューへの解析パラメータの登録  
gcp/master/batch.sh : インスタンス起動 (1, 2)  
gcp/master/monitor.sh : モニタリングインスタンス起動 (1, 3)  

1: インスタンス上で、gcp/worker/startup.sh & gcp/worker/shutdown.shが実行される。  
2: gcp/worker/start.shがgcp/worker/run.shを実行し、そこから、解析コマンドを実行する。  
3: gcp/worker/monitor.shを実行。

## ファイルのコピー

`scp -pr some_where/foo.tar.bz2; tar xjvf foo.tar.bz2; cd foo`あるいは`git clone some_where/foo.git; cd foo`

## パラメータ設定 1

`gcp/master/config.sh`を編集。

## パラメータ設定 2

`PROJECT_ID`,`IMAGE`,`USER`,`GS_URI`は必ず変更すること。

```
PROJECT_ID=my-analysis
ZONE=us-west1-b

IMAGE=conda-20191101
IMAGE_PROJECT=$PROJECT_ID
MACHINE_TYPE=n1-standard-1
N_INSTANCES=2
USER=alphonse
GS_URI=gs://my-analysis/analysis
ANALYSIS_NAME=inverse
COMMAND="script/inverse_matrix.sh foo"
```

## パラメータをキューに入れる

`-c`オプションは古いキューをクリアしてから、新しいキューの登録する。

```
> tmpfile
for l in 1000 2000; do
    for i in `seq -w 10`; do
        echo L_$l-$i $l >> tmpfile
    done
done
gcp/master/queue.sh -c $ANALYSIS_NAME < tmpfile
rm -f tmpfile
```

## バッチ処理ワーカの立ち上げ

- デバック(`-d`)オプションは解析完了後もワーカを停止しない。(実行ログ`$HOME/Batch/log.txt`を参照するなど)
- 上書き(`-f`)オプションは、解析プログラムを更新する。(古いプログラムは別フォルダにバックアップされる)

実行したいコマンドが空白を含む(オプション込みなど)場合は、ダブルクォーテーションで囲うこと。

```
gcp/master/batch.sh -f $IMAGE $IMAGE_PROJECT $MACHINE_TYPE $N_INSTANCES \
    $USER $GS_URI $ANALYSIS_NAME "$COMMAND"
```

ワーカのインスタンス名は`worker-$ANALYSIS_NAME-nnn`。

インスタンス数のみ変更して再度実行すると、足りない数だけインスタンスを増やす。

## ワーカのモニタリング

ワーカをモニタして、落ちたワーカを自動的に復活させる。

- デバック(`-d`)オプションは解析完了後もモニタを停止しない。(実行ログ`$HOME/Batch/log.txt`を参照するなど)
- 再利用(`-r`)オプションは、停止インスタンスを再利用する。指定されない場合は、インスタンスを削除して、新規のインスタンスを立ち上げる。

```
gcp/master/monitor.sh -r $IMAGE $IMAGE_PROJECT $GS_URI $ANALYSIS_NAME
```

モニタのインスタンス名は`monitor-$ANALYSIS_NAME`。

## 結果ファイル

- Cloud Storageの`$GS_URI/$ANALYSIS_NAME`で指定したフォルダに結果ファイルがアップロードされる。
- 上記の例では、`gs://my-analysis/analysis/inverse`となる。

## 解析プログラムの実行環境

- インスタンス上の`$HOME/Batch`の下に、`gcp`フォルダ、`script`および`data`フォルダ(`gcp/master/config.sh`で設定)がアップロードされる。 
- その後、`gcp/master/batch.sh`の引数に指定された`script`フォルダ内にある解析プログラムが実行される。
- 解析プログラムは`$HOME/Batch/results`の下に結果を書き出す。
  - バッチ間でファイル名が一意になるようにする。
- `$GS_URI/$ANALYSIS_NAME/results,data`には、`$HOME/Batch/results,data`がそれぞれアップロードされる。
- `gcp/master/batch.sh`で`-r`オプションを指定すると、インスタンスの異常終了後の再度起動で、`$HOME/Batch/run/results`フォルダに途中結果ファイルが復元される。
  (解析プログラムがこのファイルを読み込むように設計すると、途中結果から解析を再開できる。)
- 異常終了時、途中結果ファイルは常に退避される。`gcp/master/monitor.sh`の`-r`オプションにより、インスタンス起動時に復元する。

## 実際のプロジェクトでの利用

```
git clone ..... gcp_batch_original
mkdir myproject
cd myproject
mkdir script data
ln -s ../gcp_batch_original/gcp .
#上記に従い、queue, batch, monitorを実行
```

## 異常終了により失敗した解析の再解析

最終的な解析ファイル以外は、`$GS_URI/$ANALYSIS_NAME/run`フォルダの下に作成される。 
- 解析プログラム: `$GS_URI/$ANALYSIS_NAME/run/script.tar.bz2`
- インスタンス起動オプション: `$GS_URI/$ANALYSIS_NAME/run/INSTANCE_OPTIONS.txt`
- インスタンスのステータス: `$GS_URI/$ANALYSIS_NAME/run/workers/`
- 解析パラメータ: `$GS_URI/$ANALYSIS_NAME/run/params/` (解析完了時には消える)  
- 解析途中ファイル: `$GS_URI/$ANALYSIS_NAME/run/results/`
- 実行ログ: `$GS_URI/$ANALYSIS_NAME/run/logs/`

再解析の実行
- 解析パラメータと途中結果が上記フォルダに保存されている場合は、落ちたインスタンスを再起動する。
  - モニタインスタンスを立ち上げておくと、再起動を自動で行う。
  - 自動的に途中結果ファイルをインスタンスに展開する。(要`batch.sh`の`-r`オプション)
    - ただし、途中結果ファイルを読んで再開するように、解析プログラムを作る必要がある。
    - 途中結果ファイルを使わない(無視する)プログラムの場合、下記と同じ振る舞いとなる。
- 解析パラメータのみ上記フォルダに保存されている場合は、落ちたインスタンスを再起動する。
  - モニタインスタンスを立ち上げておくと、再起動を自動で行う。
  - 解析パラメータを読んで、最初から解析を行う。
- 途中結果が保存されていない場合は、キューに同じパラメータをもう一度入れる。
  - インスタンスが立ち上がっていればキューを読んで自動的に解析を実施。
  - インスタンスが停止している場合は立ち上げる。
  - 前の結果を破棄して再解析する場合は、途中結果のファイルを削除してから再開する。

補足
- クリーンな再解析を行う際はあらかじめ、ワーカとモニタのインスタンス、`$GS_URI/$ANALYSIS_NAME/run`フォルダ、Pub/Subのトピックとサブスクリプションを削除する。
- ワーカインスタンスは、`gcp/worker/run.sh`により、各解析の開始時に、解析パラメータを`$GS_URI/$ANALYSIS_NAME/run/params`に保存し、解析終了時に削除する。
- 解析パラメータが保存されている場合は、キューよりも優先して実行する。
- ワーカインスタンスは、`gcp/worker/shutdown.sh`により、異常終了時に、`$HOME/Batch/results`フォルダを`$GS_URI/$ANALYSIS_NAME/run/params`に保存する。
- 途中結果ファイルが保存されている場合は、起動時にインスタンス上にコピーされ、Storage上からは削除される。
