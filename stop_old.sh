 #!/bin/bash
 
echo 'job stop started.'

func_stop () {
    check=`screen -ls | grep -c $1`
    if (( check == 0 )); then
        echo "stopped '$1' screen."
    else
    	screen -p 0 -S $1 -X eval 'stuff "kick @a サーバー再起動。一分ほどして接続し直してください。 \015"'
	    sleep 1
        screen -p 0 -S $1 -X eval 'stuff "stop \015"'
        sleep 4
        check=`screen -ls | grep -c $1`
        while (( check == 1 )); do
            echo "please wait... stopping now."
            sleep 5
            check=`screen -ls | grep -c $1`
        done
    echo "successed stop for '$1' screen."
    fi
}

SCREEN_NAME="aziServer"
JARPASS="サーバーディレクトリパス"
worldName='azi_server'
func_stop $SCREEN_NAME
cd $JARPASS
kill `cat scoreget.pid`
kill `cat azi-bot/azi-bot.pid`

echo 'all stop job ended.'
