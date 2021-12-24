# coding: utf-8
require 'benchmark'
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

    lines = get_ini_file("config.ini")
    sections = get_section(lines)

    #puts sections.to_s
    write_log("Reading General section...")
    if sections[0][0] != "[General]" then
        write_log("Description in an invalid format. Please set up the General section first.")
        stop_script
    end
    begin
        geyser_url = sections[0][1].sub("GeyserSpigotURL=","")
        floodgate_url = sections[0][2].sub("FloodgateURL=","")
    rescue => exception
        write_log("[ERROR] Can't read GeyserSpigotURL or FloodgateURL. Please set up the General section first.")
        stop_script
    end
    write_log("GeyserSpigotURL = " + geyser_url)
    write_log("FloodgateURL = " + floodgate_url)
    sections.delete_at(0)

    section_hashes = [] #jarパス→buildtoolリンク→スクリーン名→並列稼働スクリプト（複数ある場合はカンマ区切り）の順でまとめたhashを配列として格納する

    sections.size.times{ |i|
        write_log("Reading section " + sections[i][0] + "...")
        sections[0].delete_at(0)
        section_hash = get_section_hash(sections[0])
        write_log("section_hash " + section_hash.to_s)
    
        section_hash.each{|key,value|
            write_log("checking format of " + key + "...")
            checking_format(key,value)
        }
        section_hashes.push(section_hash)
    }

    #比較元のgeyserとfloodgateを取得しておく
    save_file(geyser_url, "geyser-spigot.jar")
    save_file(floodgate_url, "floodgate.jar")

    #整形された設定項目がsection_hashesに格納されている状態で処理を開始する
    write_log("Server setup job started.")
    section_hashes.each { |al|
        check = %x( screen -ls | grep -c #{al['screenName']} ) 
        if check.to_i == 1 then
            write_log("[ERROR] The server is already running.")
            next
        end
        write_log("Starting server...") 

        dir = File.dirname(al['serverJar']) #移動するためのディレクトリを取得
        name = File.basename(al['serverJar']) #実行するためのファイル名を取得
        Dir.chdir(dir) {
            #puts "screen -AdmSU #{al['screenName']} java -Xms2G -Xmx2G -jar #{name} nogui"
            result, err, status = Open3.capture3("screen -AdmSU #{al['screenName']} java -Xms2G -Xmx2G -jar #{name} nogui") #スクリーンとサーバー起動
        }

        if defined? err
            write_log("[ERROR]  <#{al['screenName']}> Server start failed. ->" + err)
            next
        else
            write_log("[INFO]  <#{al['screenName']}> Server is starting...")
            time = ""
            loop {
                b, time, err = check_log_and_startup_done(dir)
                if err then
                    err = nil
                    write_log("[ERROR]  <#{al['screenName']}> Server start failed. remove session.lock and retrying...")
                    Dir.glob("**/*").each{ |fn|
                        if fn =~ /.*session.lock$/ then
                            File.delete(fn)
                        end
                    }
                    sleep(3)
                    File.delete(dir + "/logs/latest.log")
                    result, err, status = Open3.capture3("screen -AdmSU #{al['screenName']} java -Xms2G -Xmx2G -jar #{name} nogui")
                    loop{ 
                        b, time, err = check_log_and_startup_done(dir)
                        if err
                            write_log("[ERROR]  <#{al['screenName']}> Server start failed. ")
                            break
                        elsif b then
                            write_log("[INFO]  <#{al['screenName']}> Server start success. " + time)
                            break
                        end
                    }
                    break
                
                elsif b then
                    write_log("[INFO]  <#{al['screenName']}> Server start success. " + time)
                    break
                end
            }
        end
    }
    stop_script
end

#screenでサーバーを実行する事が出来るようになったが、floodgateもGeyserと同じように更新する仕組みが必要
#geyserの更新処理やbuildtool_urlからの処理も必要

def now_time
    return Time.now.strftime('%Y_%m_%d__%H:%M:%S')
end

def write_log(string)
    open('LogFiles/LatestLogFile.log', 'a'){|f|
        line = "[" + now_time + "] " + string + "\n"
        f.puts line
        puts line unless ARGV[0] == "nocslog"
    }
end

def stop_script
    write_log("Stopping script.")
    File.rename("./LogFiles/LatestLogFile.log","./LogFiles/" + now_time + ".log")
    file_list = ["geyser-spigot.jar", "buildtool.jar", "floodgate.jar"]
    file_list.each{ |file|
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
def get_section(lines)
    in_section_flag = false
    section = []
    sections = []

    lines.each{|line|
        if (line =~ /\[(.+)\]/) != nil then
            in_section_flag = true
            section_name = line.match(/^\[(.*)\]/)[0]
            section.push(section_name)
        elsif in_section_flag then
            if line == "" then
                in_section_flag = false
                sections.push(section)
                section = []
            else
                section.push(line)
            end
        end
    }
    return sections
end

#sectionの配列を受け取り順番にhashに格納して返すメソッド
def get_section_hash(lines)
    #nil比較か例外処理でこの初期化処理不要に出来る？
    server_jar = ""
    buildtool_url = ""
    screen_nane = ""
    parallel_script = ""
    lines.each { |line|
        case line
        when /^ServerJar=/ then
            server_jar = line.sub("ServerJar=","")
            write_log("ServerJar Loaded.")
        when /^BuildToolURL=/ then
            buildtool_url = line.sub("BuildToolURL=","")
            write_log("BuildToolURL Loaded.")
        when /^ScreenName=/ then
            screen_nane = line.sub("ScreenName=","")
            write_log("ScreenName Loaded.")
        when /^ParallelScript=/ then
            parallel_script = line.sub("ParallelScript=","")
            write_log("ParallelScript Loaded.")
        else
            write_log("[ERROR] Invalid setting item. ->" + line)
            stop_script
        end
    }
    section_hash = {"serverJar" => server_jar, "buildToolURL" => buildtool_url, "screenName" => screen_nane, "parallelScript" => parallel_script} #Hash(辞書型)に格納
    return section_hash
end
#eachはオブジェクトに含まれている要素を順に取り出すメソッド
def get_ini_file(fname)
    lines = []
    File.readlines(fname).each{ |line|
        line.sub!(/;.*/,"DELETED")
        lines << line.chomp #lines.push(line.chomp)と同じ
    }
    lines.delete("DELETED")
    lines.push("") #セクション終了判定用
    return lines
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
    begin
        write_log("Downloading " + filename + "...")
        result = Benchmark.realtime do
            URI.open(url) { |file|
                open(filename, "w+b") { |out|
                    out.write(file.read)
                }
            }
        end
        size = File.size(filename)
        write_log("Downloaded " + filename + ". Size: " + (size/1024).to_s + " Kbytes. Time: " + result.round(2).to_s + " seconds.")
    rescue Interrupt
        write_log("[INFO] download skipped.")
    end
end

#ログディレクトリ(logs)のlatest.logを監視しDoneを検出したらtrueを返すメソッド
def check_log_and_startup_done(dir)
    latest_log = dir + "/logs/latest.log"
    sleep(1)
    if File.exist?(latest_log) then
        File.open(latest_log, "r") { |f|
            f.each_line { |line|
                if line =~ /Done \(.{7}\)/ then
                    return true, line.match(/\(.{7}\)/)[0], nil
                elsif line =~ /Stopping server/
                    return true, nil, true
                end
            }
        }
    else
        write_log("[ERROR] No latest.log. (No logs directory or no latest.log.)")
        stop_script
    end
    return false, nil, nil
end

begin
    main
rescue Interrupt
    write_log("[INFO] Interrupt signal received. Stopping script.")
    stop_script
#rescue => e
#    write_log("[ERROR] Unknown error occurred. Stopping script.")
#    write_log("detail -> " + e.message)
#    stop_script
end