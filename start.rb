# coding: utf-8
require 'fileutils'
require 'open-uri'
require 'open3'

#メインメソッド
def main
    #A unless B 条件式Bが適合しないときに限りAを実行する
    Dir.mkdir("LogFiles") unless Dir.exist?("LogFiles")
    FileUtils.touch("LogFiles/LatestLogFile.log") unless File.exist?("LogFiles/LatestLogFile.log")
    write_log("Starting Script. Reading config.ini file...")

    unless File.exist?("config.ini") then
        config_file_not_found
    end

    iniList = []
    #eachはオブジェクトに含まれている要素を順に取り出すメソッド
    File.readlines("config.ini").each{|line|
        line.chomp!
        line.sub!(/;.*/,"DELETED")
        iniList.push(line)
    }
    iniList.delete("DELETED")
    iniList.push("") #セクション終了判定用

    sections = get_section(iniList)

    #puts sections.to_s
    write_log("Reading General section...")
    if sections[0][0] != "[General]" then
        write_log("Description in an invalid format. Please set up the General section first.")
        stop_script
    end
    begin
        geyserURL = sections[0][1].sub("GeyserSpigotURL=","")
        floodgateURL = sections[0][2].sub("FloodgateURL=","")
    rescue => exception
        write_log("[ERROR] Can't read GeyserSpigotURL or FloodgateURL. Please set up the General section first.")
        stop_script
    end
    write_log("GeyserSpigotURL = " + geyserURL)
    write_log("FloodgateURL = " + floodgateURL)
    sections.delete_at(0)

    orderedAll = [] #jarパス→buildtoolリンク→スクリーン名→並列稼働スクリプト（複数ある場合はカンマ区切り）の順で二次元配列として格納する
    for i in 0..sections.size - 1 do
    
        write_log("Reading section " + sections[i][0] + "...")
        sections[0].delete_at(0)
        ordered = get_section_order(sections[0])
        write_log("ordered " + ordered.to_s)
    
        ordered.each{|key,value|
            write_log("checking format of " + key + "...")
            checking_format(key,value)
        }
        orderedAll.push(ordered)
    end

    #比較元のgeyserとfloodgateを取得しておく
    save_file(geyserURL, "geyser-spigot.jar")
    save_file(floodgateURL, "floodgate.jar")

    #整形された設定項目がorderedAllに格納されている状態で処理を開始する
    write_log("Server setup job started.")
    orderedAll.each { |al|
        check = %x( screen -ls | grep -c #{al['screenName']} ) 
        write_log("check = " + check)
        if check.to_i == 1 then
            write_log("[ERROR] The server is already running.")
            next
        end
        write_log("Starting server...") 

        dir = File.dirname(al['serverJar']) #移動するためのディレクトリを取得
        Dir::open(dir) do
            name = File.basename(al['serverJar']) #実行するためのファイル名を取得
            result, err, status = Open3.capture3("screen -AdmSU #{al['screenName']} java -Xms2G -Xmx2G -jar #{name} nogui") #スクリーンとサーバー起動
        end
        if err != "" then
            write_log("[ERROR]  <#{al['screenName']}> Server start failed. ->" + err + " // " + status)
            next
        else
            write_log("<#{al['screenName']}> Server start success. <" + status.to_s + "> ")
        end
    }
    stop_script
end

#screenでサーバーを実行する事が出来るようになったが、floodgateもGeyserと同じように更新する仕組みが必要
#geyserの更新処理やbuildtoolurlからの処理も必要

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
    fileList = ["geyser-spigot.jar", "buildtool.jar", "floodgate.jar"]
    fileList.each{ |file|
        File.delete(file) if File.exist?(file)
    }
    exit
end

#config.iniが存在しないときに呼び出してスクリプトを停止するメソッド
def config_file_not_found
    write_log("[ERROR] Can't find config.ini! Please setting config.ini and please run the script again.")
    FileUtils.touch("config.ini")
    File.open("config.ini", "a"){|f|
        f.puts "[General]\nGeyserSpigotURL=https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master/lastSuccessfulBuild/artifact/bootstrap/spigot/target/Geyser-Spigot.jar\nFloodgateURL=https://ci.opencollab.dev/job/GeyserMC/job/Floodgate/job/master/lastSuccessfulBuild/artifact/spigot/target/floodgate-spigot.jar\n\n"
        f.puts "[testServer]\nServerJar=./testServer/testServer.jar\nBuildToolURL=http://(buildTools URL)\nScreenName=testServer\nParallelScript=None,None\n"
        f.puts "; Be sure to insert a blank line or comment line at the end of the section.\n; セクションの最後に必ず空白行またはコメント行を挿入してください。"
    }
    stop_script
end

#sectionの中身を取得して返すメソッド
def get_section(iniList)
    general = false
    sectionFlag = false
    secTemp = []
    sections = []

    iniList.each{|line|
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
    }
    return sections
end

#sectionの配列を受け取り順番に配列に格納して返すメソッド
def get_section_order(s)
    #nil比較か例外処理でこの初期化処理不要に出来る？
    serverJar = ""
    buildToolURL = ""
    screenName = ""
    parallelScript = ""
    s.each { |sElement|
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
            write_log("[ERROR] Invalid setting item. ->" + sElement)
            stop_script
        end
    }
    ordered = {"serverJar" => serverJar, "buildToolURL" => buildToolURL, "screenName" => screenName, "parallelScript" => parallelScript} #Hash(辞書型)に格納
    return ordered
end

#入力値を受け取り、その値が正しいかどうかを判別し、異なる場合はスクリプトを停止するメソッド
def checking_format(key,value)
    if value == "" then
        write_log("[ERROR] No " + key + " setting. (Don't value is not empty please.)")
        stop_script
    end
    #keyにURLを含む場合、valueがhttp://かhttps://で始まってない場合をエラーとする
    if key =~ /URL/ then
        if value !~ /^https?:\/\// then
            write_log("[ERROR] Invalid " + key + " setting. (Don't start with http:// or https://.)")
            stop_script
        end
    end
    #valueに空白を含む場合をエラーとする
    if value =~ /\s/ then
        write_log("[ERROR] Invalid " + key + " setting. ->" + value + " (Space is not allowed.)")
        stop_script
    end
end

#ファイルをURLから取得し同階層に保存するメソッド
def save_file(url, filename)
    write_log("Downloading " + url + " to " + filename + ".")
    open(urlL) { |file|
        open(filename, "w+b") { |out|
            out.write(file.read)
        }
    }
    write_log("Downloaded " + url + " to " + filename + ".")
end
main