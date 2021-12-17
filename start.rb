# coding: utf-8
require 'fileutils'
require 'open3'

def now_time
    return Time.now.strftime('%Y_%m_%d__%H:%M:%S')
end

def write_log(string)
    open('LogFiles/LatestLogFile.log', 'a'){|f|
        logLine = "[" + now_time + "] " + string + "\n"
        f.puts logLine
        puts logLine unless ARGV[0] == "nocslog"
    }
end

def stop_script
    write_log("Stopping script.")
    File.rename("./LogFiles/LatestLogFile.log","./LogFiles/" + now_time + ".log")
    exit
end

#A unless B 条件式Bが適合しないときに限りAを実行する
Dir.mkdir("LogFiles") unless Dir.exist?("LogFiles")
FileUtils.touch("LogFiles/LatestLogFile.log") unless File.exist?("LogFiles/LatestLogFile.log")
write_log("Starting Script. Reading config.ini file...")

unless File.exist?("config.ini") then
    write_log("[ERROR]Can't find config.ini! Please setting config.ini and please run the script again.")
    FileUtils.touch("config.ini")
    File.open("config.ini", "a"){|f|
        f.puts "[General]\nGeyserSpigotURL=https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master/lastSuccessfulBuild/artifact/bootstrap/spigot/target/Geyser-Spigot.jar\n\n"
        f.puts "[testServer]\nServerJar=./testServer/testServer.jar\nBuildToolURL=http://(buildTools URL)\nScreenName=testServer\nParallelScript=None,None\n"
        f.puts "; Be sure to insert a blank line or comment line at the end of the section.\n; セクションの最後に必ず空白行またはコメント行を挿入してください。"
    }
    stop_script
end

file = nil
iniList = []
#eachはオブジェクトに含まれている要素を順に取り出すメソッド
File.readlines("config.ini").each{|line|
    line.chomp!
    line.sub!(/;.*/,"DELETED")
    iniList.push(line)
}
iniList.delete("DELETED")
iniList.push("") #セクション終了判定用

general = false
sectionFlag = false
secTemp = []
sections = []

for line in iniList do
    if (line =~ /\[(.+)\]/) != nil then
        sectionFlag = true
        sectionName = line.match(/^\[(.*)\]/)[0]
        secTemp.push(sectionName)
    elsif sectionFlag then
        if line == "" then
            sectionFlag = false
            sections.push(secTemp)
            secTemp = []
        else
            secTemp.push(line)
        end
    end
end
puts sections.to_s
write_log("Reading General section...")
if sections[0][0] != "[General]" then
    write_log("Description in an invalid format. Please set up the General section first.")
    stop_script
end
geyserURL = sections[0][1].sub("GeyserSpigotURL=","")
sections[0] = []

aligned = [] #jarパス→buildtoolリンク→スクリーン名→並列稼働スクリプト（複数ある場合はカンマ区切り）の順で二次元配列として格納する
for i in 0..sections.size - 1 do
    #ServerJar=./testServer/testServer.jar
    #BuildToolURL=http://(buildTools URL)
    #ScreenName=testServer
    #ParallelScript=testA,testB or None
    serverJar = ""
    buildToolURL = ""
    screenName = ""
    parallelScript = ""
    section[0].each {|sElement| #section内要素を一つずつsに引き渡してfor分のように繰り返し実行する
        case sElement
        when /^ServerJar=/ then
            serverJar = sElement.sub("ServerJar=","")
            write_log("ServerJar Loaded.")
        when /^BuildToolURL=/ then
            buildToolURL = sElement.sub("BuildToolURL=","")
            write_log("BuildToolURL Loaded.")
        when /^ScreenName=/ then
            screenName = sElement.sub("ScreenName=","")
            write_log("ScreenName Loaded.")
        when /^ParallelScript=/ then
            parallelScript = sElement.sub("ParallelScript=","")
            write_log("ParallelScript Loaded.")
        else
            write_log("[ERROR]Invalid setting item. ->" + sElement)
            stop_script       
        end
    }
    if serverJar == "" || buildToolURL == "" || screenName = "" || parallelScript = ""
        write_log("[ERROR]The setting item could not be read.")
        stop_script
    else
        alignedTemp = [serverJar, buildToolURL, screenName, parallelScript]
        aligned.push(alignedTemp)
    end
    sections[0] = []
end

#整形された設定項目がalignedに格納されている状態で処理を開始する
write_log("Server setup job started.")
aligned.each { |al|
    check=`screen -ls | grep -c #{al[2]}` #シェルに引き渡す前にRubyのレベルで変数を展開する
    if check then
        write_log("[ERROR]The server is already running.")
        next
    end
    write_log("Starting server...")
    result, err, status = Open3.capture3("screen -AdmSU #{al[2]} java -Xms2G -Xmx2G -jar #{al[0]} nogui") #スクリーンとサーバー起動
    if $? != 0 then
        write_log("[ERROR] <#{al[2]}> Server start failed. ->" + err + " // " + status)
        next
    else
        write_log("<#{al[2]}> Server start success.")
    end
}

stop_script