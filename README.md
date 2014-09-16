# 実行方法（要 root 権限）
sudo ./run.rb <level config> <load balancer> <network config>

Ex.) `sudo ./run.rb conf/level-1.conf load_balancer.rb conf/network.conf`


# run.rb
trema，サーバ，クライアントを実行するスクリプト
* 各動作の間に処理待ちのためにスリープを入れており，スリープ時間を計算機の動作速度に合わせて調整する必要あり
* trema，サーバ，クライアントのパスを適切に設定する必要あり

## 指定できるパラメータ（[xxx] は初期値）

|-- TREMA          : 実行ファイル "trema" のパス [../trema/trema]

|-- CLIENT         : 実行ファイル "client" のパス [./bin/client]

|-- SERVER         : 実行ファイル "server" のパス [./bin/server]

|-- DIR_HP_FILE    : HP ファイルを置くディレクトリ [/tmp/]

|-- HP_FILE_PREFIX : HP ファイルの名前の先頭 [server] # server_<IP address>_<MAC address>

|-- PID_PATH       : 実行したプロセスを記憶しておくための PID ファイルのディレクトリを置くディレクトリ [/tmp/]

|-- PID_DIR        : PID ファイルを置くディレクトリの名前 [OpenFlow-LB]

|-- PID_FILE_PREFIX_CLIENT : クライアント用の PID ファイルの名前の先頭 [client.] # client.<PID>

`-- PID_FILE_PREFIX_SERVER : サーバ用の PID ファイルの名前の先頭 [server.] # server.<PID>

## 動作
1) 実行中の trema およびサーバ，クライアントのプロセスを kill する．

2) HP ファイルを削除し，クリーンする．

3) trema を起動する．

4) クライアントを起動する．

5) サーバを起動する．

6) サーバ，クライアントが終了後，得点を取得し，合計を計算する．

7) 実行したプロセスを kill する．


# 設定ファイル（level-?.conf）
json 形式で記述

*クライアントは，設定ファイル中で指定されたパケット数もしくは送信時間の上限に達するまでパケットを送信

*なお，いずれかの上限に達した時点で送信を終了する．

## 指定できるパラメータ
|-- n_pkts   : 送信するパケット数（0 は無限に送信）

|-- duration : 送信する時間（0 は無限に送信）

|-+ client   : クライアントに関する設定

| |- netns       : netns 名

| |- ip          : IP アドレス

| `- ack_timeout : ACK タイムアウト時間

`-+ server   : サーバに関する設定

  |- netns       : netns 名

  |- ip          : IP アドレス

  |- port        : 待ち受けポート番号

  |- max_life    : HP の最大値

  |- dec_life    : HP の減少幅

  `- sleep_time  : HP が 0 になった後に回復するまでのスリープ時間

## 設定ファイルの例
サーバ 1 台，クライアント 1 台で構成され，パケットを 10 秒間送信し続ける．

ただし，送信パケット数の上限はなし

`{
    "n_pkts" : 0,
    "duration" : 10,
    "client" : [
	{
            "netns" : "netns0", 
            "ip" : "192.168.0.1",
            "ack_timeout" : 1
        }
    ],
    "server" : [
	{
	    "netns" : "netns10",
	    "ip" : "192.168.0.250",
	    "port" : 12345,
            "max_life" : 10000,
	    "dec_life" : 20,
	    "sleep_time" : 5
	}
    ]
}`


# サーバ，クライアント
サーバ，クライアント間でパケットおよび ACK をやりとりし，サーバが受信できたパケット数に応じて得点を与える．

## 動作
下記の手順 1，2 を繰り返す．

0) クライアントは，サーバに向けてデータパケットを 1 つだけ送信し，待機

1) サーバは，データパケットを受信すると，送信元に向けて ACK パケットを送信

2) クライアントは，ACK パケットを受信すると，サーバに向けてデータパケットを 1 つだけ送信し，待機

なお，ACK が返らなかった場合に処理が止まることを避けるために，クライアントは，データパケットを送信後，
設定ファイルに指定された「ACK タイムアウト時間」の間に ACK パケットを受信できなければ，
データパケットもしくは ACK パケットが棄却されたと判断し，新たにデータパケットを送信して，上記の手順を繰り返す．

## server
サーバプログラム

自身の IP アドレスを取得するために /sys/class/net/ 中の "trema" で始まるインターフェースの IP アドレスを利用

 （少なくとも）"eth0" 的な形式で "trema0" のようなインターフェース名が振られている．

!! Ubuntu 10.04（kernel 3.2.0）で動作を確認しているが，kernel および trema のバージョンが変わると

!! ファイル名などが変わる可能性があるため要注意

!! また，"trema" で始まるインターフェースが複数ある場合は正しく動作しない

### 動作
サーバは，アクティブな状態にあるときにパケットを受け取ると，得点を加算し，送信元に対して ACK を送信する．

そして，設定ファイルに指定されただけ HP を減じる．

HP が 0 に達した場合，状態を非アクティブに遷移させ，HP を設定ファイルに指定された最大値に設定する．

サーバは，非アクティブな状態にあるときにパケットを受け取ると，得点を減じて，受け取ったパケットを破棄する．

## client
クライアントプログラム

### 動作
設定ファイルに指定されたサーバのうち，「先頭のサーバ」に対してパケットを送信する．

* 負荷分散しなければ，「先頭のサーバ」のみがパケットを受け取り，HP が減少するため，得点が伸びない．

設定ファイルに指定されたパケット数および送信時間の上限のうち，いずれかに達した時点で終了する．

なお，0 が指定された場合は無限と解釈する．
