#!/usr/bin/bash

START="スタート用スクリプトのパス"
STOP="停止用のスクリプトのパス"

func_re () {
    check=`screen -ls | grep -c $1`
    if (( check == 1 )); then
        echo $1 restarting now...
        screen -p 0 -S $1 -X eval 'stuff "say サーバーをあと10秒後に再起動します。 \015"'
        sleep 5
        for i in {5..1}; do
            screen -p 0 -S $1 -X eval 'stuff "say サーバー再起動まで残り'${i}'秒・・・ \015"'
            sleep  1
        done
	    ${STOP}
	    echo stopping...
	    sleep 3
	    cd $2..
	    if [ -d ./backup ]; then
	        cp -rp ${2}${3} backup/backup.`date "+%Y%m%d_%H%M"`.zip/
	    else
	        mkdir backup
	        cp -rp ${2}${3} backup/backup.`date "+%Y%m%d_%H%M"`.zip/
	    fi
	    echo Backup Done.
    else
	    echo screen not found
    fi
}

SCREEN_NAME="aziServer"
JARPASS="サーバーディレクトリパス"
worldName="azi_server"
func_re $SCREEN_NAME $JARPASS $worldName

${START} $1
