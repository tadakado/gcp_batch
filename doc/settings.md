----
# 環境設定
---- 

## プロジェクトの作成

環境設定作業は、ブロジェクトでインスタンスを立ち上げるか、Cloud Shellで行う。
ただし、Cloud Shellは60分で切れるので注意。
インスタンスを立ち上げる場合には、アクセススコープを"すべてのCloud APIに完全アクセス権を許可"(`--scopes cloud-platform`)にする。

プロジェクト(`my-analysis`)の作成は、Cloud Shellで行う。
`PROJECT_ID`は**必ず変更する**こと。

```
PROJECT_ID=my-analysis

gcloud projects create $PROJECT_ID
gcloud config set project $PROJECT_ID
```

## プロジェクトの請求先アカウントをリンク (GCP Console)

支払い手段が確定していない場合は、次の作業ができないので先に設定する。

`お支払い` > `請求先アカウントをリンク`

## メンバーを追加 (GCP Console)

必要に応じてメンバーを追加する。

`IAMと管理` > `リソースの管理` > (右上)`情報パネルを表示` > `メンバーを追加` > `役割 => オーナーなど`

## Pub/Sub (GCP Console)

バッチのキューとして使う。


`APIとサービス` > `ライブラリ` > `Pub/Sub` > `有効にする`

## Logging

ワーカインスタンスからのログ出力先。何も設定しなくて使える。

## Compute Engene

ただ、数分待つ。GCP Console上で確認する。

## 環境設定作業用のインスタンスの立ち上げ

Cloud Shellで行う。
`PROJECT_ID`は**必ず変更する**こと。

```
PROJECT_ID=my-analysis
ZONE=us-west1-b
INSTANCE=temp-00
IMAGE_FAMILY=debian-10
IMAGE_PROJECT=debian-cloud
DISK_SIZE=10GB

gcloud compute --project $PROJECT_ID instances create $INSTANCE \
    --zone $ZONE --machine-type f1-micro --scopes cloud-platform \
    --image-family $IMAGE_FAMILY --image-project $IMAGE_PROJECT \
    --boot-disk-size $DISK_SIZE --boot-disk-type pd-standard
```

以後は、立ち上げたインスタンスで実行する。

## 各種パラメータの設定

特に理由がなければ、使用料の安いリージョン(us-west1,us-central1,us-east1)を選ぶ。
`PROJECT_ID`, `USER`, `PUB_KEY1`, `PUB_KEY2`は**必ず変更する**こと。

```
## Project & Location
PROJECT_ID=my-analysis
REGION=us-west1
ZONE=us-west1-b

## Cloud Storage
STORAGE_CLASS=regional
BUCKET_LOCATION=$REGION
BUCKET_NAME=${PROJECT_ID}-01

## Instance (for making custom image)
INSTANCE=instance-00
IMAGE_FAMILY=debian-10
IMAGE_PROJECT=debian-cloud

## User information
USER=alphonse
PUB_KEY1="ssh-ed25519 XXXX...."
PUB_KEY2="ssh-ed25519 XXXX...."

## Custum image
IMAGE=conda-`date +%Y%m%d`
DESCRIPTION=conda3
SNAPSHOT=$IMAGE
```

## デフォルトのゾーンとリージョンの設定

```
gcloud compute project-info add-metadata \
    --metadata google-compute-default-region=$REGION,google-compute-default-zone=$ZONE -q
```

## Cloud Storage バケットの作成

```
gsutil mb -p $PROJECT_ID -c $STORAGE_CLASS -l $BUCKET_LOCATION -b on gs://$BUCKET_NAME/
```

## SSH公開鍵の登録

ワーカインスタンスにログインするためのssh公開鍵を登録する。

メタデータを利用する場合、

```
gcloud compute project-info add-metadata --metadata enable-oslogin=FALSE
echo -e "$USER:$PUB_KEY1\n$USER:$PUB_KEY2" > tmpfile
gcloud compute project-info add-metadata --metadata-from-file ssh-keys=tmpfile
rm -f tmpfile
```

OSログインを利用する場合、(ユーザ名を自由に指定できないので不便)

```
gcloud compute project-info add-metadata --metadata enable-oslogin=TRUE
echo $PUB_KEY1 > tmpfile
gcloud compute os-login ssh-keys add --key-file tmpfile --ttl 0
echo $PUB_KEY2 > tmpfile
gcloud compute os-login ssh-keys add --key-file tmpfile --ttl 0
rm -f tmpfile
```

## VMインスタンスの起動

ワーカインスタンス用のイメージをDebianをベースに構築する。

```
gcloud compute instances create $INSTANCE \
    --image-family $IMAGE_FAMILY \
    --image-project $IMAGE_PROJECT \
    --boot-disk-size=10GB \
    --zone=$ZONE
INSTANCE_IP=`gcloud compute instances list --filter "name=$INSTANCE" \
    --format "get(networkInterfaces[0].accessConfigs[0].natIP)"`
```

## 一度ログインする

認証キーを作るために、`gcloud`コマンドを用いてログインする。
その後、`ssh`で直接ログインできるか確認。

```
echo -e "\n\n" | gcloud compute ssh $USER@$INSTANCE --command "ls .ssh" --zone $ZONE
ssh -o StrictHostkeyChecking=no -i ~/.ssh/google_compute_engine $USER@$INSTANCE_IP ls .ssh
```

## ソフトのインストール

`gcp/package_install.sh`をインスタンス上で実行して、必要なソフトをインストールする。

### gcp/package_install.shの取得

コンソール上からコピー&ペーストが一番シンプル。`cat > ...`でコンソールからペーストする。

```
mkdir gcp
cat > gcp/package_install.sh
chmod +x gcp/package_install.sh
```

### gcp/package_install.shの実行

sshを使用する場合、

```
scp -i ~/.ssh/google_compute_engine gcp/package_install.sh $USER@$INSTANCE_IP:~
ssh -i ~/.ssh/google_compute_engine $USER@$INSTANCE_IP \
    "./package_install.sh ; rm -f package_install.sh" | tee output1.txt
```

Ansibleを使用する場合、

```
sudo pip3 install ansible
ansible all -i $USER@$INSTANCE_IP, --ssh-common-args="-i ~/.ssh/google_compute_engine" \
    -m script -a "gcp/package_install.sh" | tee output1.txt
```

## イメージの作成

作業したインスタンスを停止し、スナップショット、ディスクを経由して、イメージを作成する。

```
( gcloud compute instances stop $INSTANCE --zone $ZONE &&
  gcloud compute disks snapshot $INSTANCE --zone $ZONE --snapshot-names $SNAPSHOT &&
  gcloud compute disks create $IMAGE --source-snapshot $SNAPSHOT --zone $ZONE &&
  gcloud compute images create $IMAGE --source-disk $IMAGE --source-disk-zone $ZONE \
      --description "$DESCRIPTION" &&
  gcloud compute disks delete $IMAGE --zone $ZONE -q &&
  gcloud compute snapshots delete $SNAPSHOT -q &&
  gcloud compute instances delete $INSTANCE --zone $ZONE -q
2>&1) | tee output2.txt
```

## 環境構築作業おしまい

環境構築作業に用いたインスタンスは、ログアウトして、削除する。

```
sudo shutdown -h now
```

----
# 解析環境
----

解析環境の構築例。
データ解析および、バッチのマスタコントローラを兼用するインスタンスを作成する。
データ用にディスクを用意する。

## データ用ディスクの作成 (データ解析&保存用)

Cloud Shell上で実行。
`PROJECT_ID`は**必ず変更する**こと。

```
PROJECT_ID=my-analysis
ZONE=us-west1-b

DISK_NAME=data-01
DISK_SIZE=50GB
```

HDDの場合、

```
gcloud compute disks create $DISK_NAME --size $DISK_SIZE --type pd-standard --zone $ZONE
```

SSDの場合、(マウント時にdiscardオプションをつける)

```
gcloud compute disks create $DISK_NAME --size $DISK_SIZE --type pd-ssd --zone $ZONE
```

## マスタコントローラを立ち上げる (データ用ディスクを接続)

Cloud Shell上で実行。
`PROJECT_ID`, `IMAGE`は**必ず変更する**こと。

```
PROJECT_ID=my-analysis
ZONE=us-west1-b

INSTANCE=master-00
MACHINE_TYPE=n1-standard-1
IMAGE=conda-20191101         # custum image name
IMAGE_PROJECT=$PROJECT_ID
DISK_SIZE=20GB
DATA_DISK=data-01

gcloud compute instances create $INSTANCE --zone $ZONE --machine-type $MACHINE_TYPE \
  --scopes cloud-platform --image $IMAGE --image-project $IMAGE_PROJECT \
  --boot-disk-size $DISK_SIZE --boot-disk-type pd-standard \
  --boot-disk-device-name $INSTANCE --disk=name=$DATA_DISK,device-name=datadisk
```

以後は、立ち上げたマスターコントローラ上で実行する。

## データ用ディスクのマウント

データディスクは`/dev/sdb`を想定。

HDDの場合、

```
sudo mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0 /dev/sdb
sudo mkdir /mnt/sdb
sudo mount /dev/sdb /mnt/sdb
sudo chmod 1777 /mnt/sdb
```

SSDの場合、

```
sudo mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb
sudo mkdir /mnt/sdb
sudo mount -o discard,defaults /dev/sdb /mnt/sdb
sudo chmod 1777 /mnt/sdb
```

## HOMEへリンク

```
mkdir /mnt/sdb/Work
ln -s /mnt/sdb/Work .
```

----
# バッチによる解析の実行
----

[`doc/execution.md`](execution.md)を参照

----
# 参考情報 (運用しているうちに必要)
----

## ディスクサイズの変更

https://cloud.google.com/compute/docs/disks/add-persistent-disk#resize_pd

ディスクサイズの変更と、システム上での設定変更が必要になる。

```
gcloud compute disks resize [DISK_NAME] --size [DISK_SIZE]
```

ほとんどのシステムでは起動時に自動的にファイルシステムの変更をおこなってくれる。
再起動せずに手動でおこなうにはresize2fsを実行する(要インストール)。

## Cloud Storageのアクセス権 (他のプロジェクトとのデータのやり取りなど)

https://cloud.google.com/storage/docs/access-control/create-manage-lists?hl=ja#set-an-acl
https://cloud.google.com/dataprep/docs/concepts/gcs-buckets

他のプロジェクトのCloud Storageを利用するにはACLの設定が必要。プロジェクト番号に紐づくメールアドレスを利用して登録する。

```
gsutil defacl ch -u [USER_EMAIL]:[PERMISSION] gs://[BUCKET_NAME]
(gsutil acl ch -u [USER_EMAIL]:[PERMISSION] gs://[BUCKET_NAME])
```

USER_EMAIL: `IAMと管理` > `サービスアカウント` にあるプロジェクトのメールアドレス  
PERMISSION: `OWNER`あるいは`READER`
