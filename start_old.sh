#!/bin/bash
echo 'job started.'

func_start() {
	check=$(screen -ls | grep -c $1)
	if ((check == 1)); then
		echo "started '$1' screen."
	else
		echo 'Geyser-spigot.jar downloading...'
		cd "$2/plugins"
		curl -z Geyser-Spigot.jar -R -o Geyser-Spigot.jar https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master/lastSuccessfulBuild/artifact/bootstrap/spigot/target/Geyser-Spigot.jar -\#
		if [ $# = 2 ]; then
			read -p "spigotの最新ビルドを確認しますか? (y/N): " yn
		elif [ $# = 3 ]; then
			yn=${3}
		fi
		if [ $yn = "y" ]; then
			echo 'checking spigot...'
			cd $2/
			spigotNameOld=$(echo | find . -type f | grep -e "spigot-" | cut -c 3-)
			cd "startbuild"
			oldTime=$(date +%Y%m%d -r BuildTools.jar)
			curl -z BuildTools.jar -R -o BuildTools.jar https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar -\#
			newTime=$(date +%Y%m%d -r BuildTools.jar)
			if [ "$oldTime" -eq "$newTime" ]; then
				echo 前回のBuildTools.jarと更新時刻が同じため、展開をスキップします。
			else
				java -jar BuildTools.jar --rev latest
				ls | grep -v -E 'jar$' | xargs rm -r
				spigotNameNew=$(echo | find . -type f | grep -e "spigot-" | cut -c 3-)
				echo "現在のspigotは '${spigotNameOld}' で、最新版のspigotは '${spigotNameNew}' です。"
				cd $2/
				if [ $# = 2 ]; then
					read -n 1 -p "最新版とファイルを置き換えますか? (y/N): " yn
				elif [ $# = 3 ]; then
					yn=${3}
				fi
				case "$yn" in [yY]*)
					echo "ファイルを置き換えて起動します。"
					rm ${spigotNameOld}
					cp startbuild/${spigotNameNew} .
					rm startbuild/${spigotNameNew}
					;;
				*)
					echo "既存のバージョンを使用します。."
					rm startbuild/${spigotNameNew}
					;;
				esac
			fi
		fi
		cd $2
		filename=$(find . -type f | grep -e "spigot-" | cut -c 3-)
		JAR="$2$filename"
		screen -AdmSU $1 java -Xms2G -Xmx2G -jar $JAR nogui
		sleep 3
		check=$(screen -ls | grep -c $1)
		if ((check == 1)); then
			echo "successed start for '$1' screen."
		else
			echo "failed start for '$1' screen."
		fi
	fi
}

SCREEN_NAME="aziServer"
JARPASS="サーバーディレクトリパス"
func_start $SCREEN_NAME $JARPASS $1
cd $JARPASS
./scoreget.sh &
echo scoreget.sh $!
echo $! >scoreget.pid
cd ./azi-bot
node ./bot.js &
echo azi-bot $!
echo $! >azi-bot.pid

echo 'all job ended.'
#https://getbukkit.org/
#アップデート用jarファイルはここから取得
