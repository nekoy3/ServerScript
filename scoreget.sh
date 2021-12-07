#!/usr/bin/bash

#サーバー起動時に実行され、サーバー停止時に終了する。
getRank () {
    #ファイルを読み込む
    python nbt_edit.py ./azi_server/data/scoreboard.dat 1,totalScoreXpl,t type:"[0] Score:[2]" > /dev/null
    rankText='./azi_server/data/export.txt'
    #区切り文字を改行に指定
    IFS=$'\n'
    ln=0
    rank=0
    file=(`cat "$rankText"`)
    for s in "${file[@]}"; do
        rank=$((rank += 1))
        rankText=`echo §l§8\#${rank} §r- §6${s}`
        rankText=${rankText// Score:/ §7Score:§c§o}
        if [ $rank -le 10 ]; then
            if [ $rank -eq 1 ]; then
                rankText=${rankText//§8\#${rank}/§4\#${rank}}
            elif [ $rank -eq 2 ]; then
                rankText=${rankText//§8\#${rank}/§5\#${rank}}
            elif [ $rank -eq 3 ]; then
                rankText=${rankText//§8\#${rank}/§9\#${rank}}
            fi
            if [ $1 = "call" ] ; then
                if [ `echo $rankText | grep ${name}` ]; then
                    my=${rankText}
                fi
                screen -p 0 -S aziServer -X eval 'stuff "tellraw '${name}' {"'
                screen -p 0 -S aziServer -X stuff \"text\":\"${rankText}\"}\\015
            elif [ $1 = "discord" ] ; then
                rankArray=("${rankArray[@]}" `echo ${rankText} | sed -e "s/§.//g"`)
            fi
        fi
    done
}
errorCnt=`grep Server\ thread/ERROR logs/latest.log | wc -l`
reloadCnt=`grep Reload\ complete. logs/latest.log | wc -l`
error=''
while (true); do
    log=`tail -n 2 logs/latest.log`
    if [ "`echo $log | grep "has called \[All\] ranking list."`" ]; then
        name=`echo $log | sed -r 's/ has called \[All\] ranking list.//g' | rev | awk '{ print $1 }' | rev`
        screen -p 0 -S aziServer -X eval 'stuff "save-all\015"'
        sleep 1
        screen -p 0 -S aziServer -X eval 'stuff "tellraw '$name' ["'
        screen -p 0 -S aziServer -X stuff \"\",{\"text\":\"§b--------------------\"},
        screen -p 0 -S aziServer -X stuff {\"text\":\"§aスコアランキング\"},{\"text\":\"§b--------------------\"}]
        screen -p 0 -S aziServer -X eval 'stuff "\015"'
        
        mode="call"
        getRank $mode $name
        
        screen -p 0 -S aziServer -X eval 'stuff "tellraw '$name' {"'
        screen -p 0 -S aziServer -X stuff \"text\":\"§b----------------------------------------------------\"}\\015
        screen -p 0 -S aziServer -X eval 'stuff "tellraw '${name}' {"'
        screen -p 0 -S aziServer -X stuff \"text\":\"${my}\"}\\015
        screen -p 0 -S aziServer -X eval 'stuff "w @s a\015"'
        screen -p 0 -S aziServer -X eval 'stuff "w @s a\015"'
    fi
    readonly DISCORD_BOT_TOKEN="トークン廃棄済み" 2>/dev/null
    readonly DISCORD_CHANNEL_ID="xxx" 2>/dev/null #azi_errorlog
    readonly DISCORD_CHANNEL_CMD="xxx" 2>/dev/null #azi_cmd
    readonly WEBHOOK_CMD="https://discord.com/api/webhooks/xxx" 2>/dev/null #azi_cmd
    readonly WEBHOOK_URL="https://discord.com/api/webhooks/xxx" 2>/dev/null #azi_ranking
    exportCheck=`tail -n 1 azi_server/data/export.txt`
    if [[ `date '+%H%M%S'` = '030000' || "${exportCheck::6}" = "reload" ]] ; then 
        rm baseRank.txt
        mode="discord"
        getRank $mode
        MESSAGE="AZI_Serverトータルスコアランキング(1~10th) with `date "+%Y/%m/%d %H:%M:%S"`"
        rankingTextAll=""
        for s in "${rankArray[@]}"; do
            rankingTextAll+=${s}'\n'
        done
        echo $rankingTextAll > baseRank.txt
        rank_message () {
            curl -X POST \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"\`\`\`$MESSAGE\`\`\`\"}" \
            "$1"  1>/dev/null 2>/dev/null
            
            curl -X POST \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"\`\`\`$rankingTextAll\`\`\`\"}" \
            "$1"  1>/dev/null 2>/dev/null
        }
        if [ `date '+%H%M%S'` = '030000' ] ; then
            rank_message $WEBHOOK_URL
        else
            rank_message $WEBHOOK_CMD
        fi
    fi

    #エラーのみをlatest_error.txt出力する
    errorCntTemp=`grep Server\ thread/ERROR logs/latest.log | wc -l`
    reloadTemp=`grep Reload\ complete. logs/latest.log | wc -l`
    
    if [ $errorCntTemp != $errorCnt ]; then
        grep -A 1 'Server thread/ERROR' logs/latest.log | tail -n $((($errorCntTemp-$errorCnt)*3)) >> errorTemp.txt
        errorCnt=$errorCntTemp
    fi

    if [ $reloadCnt != $reloadTemp ]; then
        errorAll=''
        cp errorTemp.txt latest_error.txt
        message=`date "+%Y/%m/%d %H:%M:%S"`のエラーを参照します。
        sed -i '1s/^/'$message'\n/' latest_error.txt
        while read s
        do
            curl \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
            -d "{\"content\": \"$s\"}" \
            "https://discordapp.com/api/channels/$DISCORD_CHANNEL_ID/messages" 1>/dev/null 2>/dev/null
            sleep 0.2
        done < latest_error.txt

        reloadCnt=$reloadTemp
        rm errorTemp.txt
    fi

    watchTmpCheck=`tail -n 1 watch.tmp`
    if [ "$watchTmpCheck" = 'restart' ] ; then
        ../server/restart.sh &
        echo '' > watch.tmp
        curl -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
            -d "{\"content\": \"[bash] serverを再起動しています・・・\"}" \ 
            "https://discordapp.com/api/channels/$DISCORD_CHANNEL_CMD/messages" 1>/dev/null 2>/dev/null
    elif [ "$watchTmpCheck" = 'restart_bot' ] ; then
        cd azi-bot/
        echo '' > ../watch.tmp
        kill `cat azi-bot.pid`
        node ./bot.js &
        echo $! > azi-bot.pid
        cd ..
        curl -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
            -d "{\"content\": \"[bash] botの再起動が完了しました。\"}" \
            "https://discordapp.com/api/channels/$DISCORD_CHANNEL_CMD/messages" 1>/dev/null 2>/dev/null
    elif [ "$watchTmpCheck" = 'restart_bash' ] ; then
        echo '' > watch.tmp
        ./scoreget.sh &
        sgpid=`cat scoreget.pid`
        echo $! > scoreget.pid
        curl -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
            -d "{\"content\": \"[bash] 管理スクリプトの再起動が完了しました。\"}" \
            "https://discordapp.com/api/channels/$DISCORD_CHANNEL_CMD/messages" 1>/dev/null 2>/dev/null
        kill $sgpid
    fi
    discordChatCheck=`tail -n 1 discordchat.tmp`
    if [ "$discordChatCheck" != "empty" ] ; then
        screen -p 0 -S aziServer -X eval 'stuff "tellraw @a {"'
        screen -p 0 -S aziServer -X stuff \"text\":\"
        for i in ${#discordChatCheck}; do
            screen -p 0 -S aziServer -X stuff ${discordChatCheck::$i}
        done
        screen -p 0 -S aziServer -X stuff \"
        screen -p 0 -S aziServer -X eval 'stuff "}\015"'
        echo 'empty' > discordchat.tmp
    fi
    sleep 0.1
done
#issued server command: /w @s ランキング参照
#sudo kill `ps aux | grep 'scoreget' | awk '{ print $2 }'`
#bot`s taken トークン廃棄済み
#cliant ID

