# coding: utf-8
require 'benchmark'
require 'fileutils'
require 'open-uri'
require 'open3'
require 'zip'

#メインメソッド
def main
    #プラグインとbuildtoolが一度でもダウンロード失敗すればFalseにして、以降のダウンロードとビルドをスキップする
    download_done = TRUE

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

    plugin_list = ["geyser-spigot.jar", "floodgate.jar", "ViaVersion.jar", "ViaBackwards.jar"]
    ini_s = ["GeyserSpigotURL=", "FloodgateURL=", "ViaVersionURL=", "ViaBackwardsURL="]
    plugin_hash = {}
    
    begin
        (plugin_list.count).times { |p|
            plugin_hash[plugin_list[p]] = sections[0][p+1].sub(ini_s[p],"")
        }
        auto_update_mode = sections[0][5].sub("AutoUpdateMode=","")
    rescue => exception
        write_log("[ERROR] Can't read GeyserSpigotURL or FloodgateURL or AutoUpdateMode. Please set up the General section first.")
        stop_script
    end

    plugin_hash.each{|n, u|
        write_log(n + " : " + u)
    }
    write_log("AutoUpdateMode = " + auto_update_mode)
    
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

    #更新するためのプラグイン群を保存する
    write_log("Saving plugins to update...")
    begin
        plugin_hash.each{ |key,value|
            save_file(value, key, auto_update_mode)
        }
    rescue Interrupt
        write_log("Skipped saving plugins to update.")
    end

    #整形された設定項目がsection_hashesに格納されている状態で処理を開始する
    write_log("Server setup job started.")
    section_hashes.each { |al|
        write_log("Running server setup <" + al["serverJar"] + "> ...")
        check = %x( screen -ls | grep -c #{al['screenName']} ) 
        if check.to_i == 1 then
            write_log("[ERROR] The server is already running.")
            next
        end

        #buildtoolをダウンロードする
        write_log("Download and checking BuildTools.jar...")
        save_file(al['buildToolURL'], "BuildTools.jar", auto_update_mode)
        #BuildTools.jarをjavaコマンドでシェルからビルドする
        write_log("Building BuildTools.jar...")
        jarname = File.basename(al['serverJar'])
        buildtool_build(jarname, auto_update_mode) #BuildTools.jarをビルドする buildtool_built/(server_jar).jar

        dir = File.dirname(al['serverJar']) #移動するためのディレクトリを取得
        name = File.basename(al['serverJar']) #実行するためのファイル名を取得

        #geyser,floodgate,ビルドしたserverのjarをアーカイブに移動し、新しく取得したjarを保存するメソッド
        if auto_update_mode
            write_log("Moving server jar to archive and new jar files...")
            move_jar(dir, name, now_time)
        end

        #サーバー起動フェーズ
        write_log("<" + al['screenName'] + "> Starting server...")
        Dir.chdir(dir) {
            result, err, status = Open3.capture3("screen -AdmSU #{al['screenName']} java -Xms2G -Xmx2G -jar #{name} nogui") #スクリーンとサーバー起動
        }

        loop {
            b, time, err = check_log_and_startup_done(dir)
            if err
                write_log("[ERROR]  <#{al['screenName']}> Server start failed.")
                #リトライメソッドを呼び出す
                retry_start_server(al, name)
                break
            elsif b
                write_log("<#{al['screenName']}> Server start success. " + time)
                break
            end
        }
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
    file_list = ["geyser-spigot.jar", "floodgate.jar", "ViaVersion.jar", "ViaBackwards.jar"]
    file_list.each{ |file|
        File.delete(file) if File.exist?(file)
    }
    FileUtils.rm_r("buildtool_built") if File.exist?("buildtool_built")
    exit
end

#config.iniが存在しないときに呼び出してスクリプトを停止するメソッド
def config_file_not_found
    write_log("[ERROR] Can't find config.ini! Please setting config.ini and please run the script again.")
    FileUtils.touch("config.ini")
    File.open("config.ini", "a"){|f|
        f.puts "[General]\nGeyserSpigotURL=https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master/lastSuccessfulBuild/artifact/bootstrap/spigot/target/Geyser-Spigot.jar\nFloodgateURL=https://ci.opencollab.dev/job/GeyserMC/job/Floodgate/job/master/lastSuccessfulBuild/artifact/spigot/target/floodgate-spigot.jar\nAutoUpdateMode=True\n\n"
        f.puts "[testServer]\nServerJar=./testServer/testServer.jar\nBuildToolURL=http://(buildTools URL)\nScreenName=testServer\nParallelScript=None,None\nServerType=Spigot\n"
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
    server_jar, buildtool_url, screen_name, parallel_script = nil
    lines.each { |line|
        case line
        when /^ServerJar=/ then
            server_jar = line.sub("ServerJar=","")
            write_log("ServerJar Loaded. -> " + server_jar)
        when /^BuildToolURL=/ then
            buildtool_url = line.sub("BuildToolURL=","")
            write_log("BuildToolURL Loaded.")
        when /^ScreenName=/ then
            screen_name = line.sub("ScreenName=","")
            write_log("ScreenName Loaded.")
        when /^ParallelScript=/ then
            parallel_script = line.sub("ParallelScript=","")
            write_log("ParallelScript Loaded.")
        else
            write_log("[ERROR] Invalid setting item. ->" + line)
            stop_script
        end
    }
    begin
        section_hash = {"serverJar" => server_jar, "buildToolURL" => buildtool_url, "screenName" => screen_name, "parallelScript" => parallel_script} #Hash(辞書型)に格納
    rescue => e
        write_log("[ERROR] Can't get section hash. ->" + e.to_s)
        stop_script
    end
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
def save_file(url, filename, mode)
    if mode != "True" then
        write_log("[INFO] AutoUpdateMode is False. Skip downloading.")
        return
    end
    begin
        write_log("Downloading " + filename + "...")
        result = Benchmark.realtime do
            URI.open(url) { |file|
                if url =~ /\.zip$/ then
                    File.open("archive.zip", "wb") { |out|
                        out.write(file.read)
                    }
                else
                    File.open(filename, "w+b") { |out|
                        out.write(file.read)
                    }
                end
            }
        end
        size = File.size(filename) if File.exist?(filename)
        size = File.size("archive.zip") if File.exist?("archive.zip")
        write_log("Downloaded " + filename + ". Size: " + (size/1024).to_s + " Kbytes. Time: " + result.round(2).to_s + " seconds.")
    rescue Interrupt
        write_log("[INFO] download skipped.")
    end
    if url =~ /\.zip$/ then
        unzip_jar(filename)
    end
end

#ログディレクトリ(logs)のlatest.logを監視しDoneを検出したらtrueを返すメソッド。二つ目の帰り値は起動時間文字列、三つ目の帰り値は異常停止時にtrueを返す
def check_log_and_startup_done(dir)
    latest_log = dir + "/logs/latest.log"
    sleep(5)
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
        write_log("[ERROR] No latest.log. (No logs directory or no latest.log.) -> " + latest_log)
        stop_script
    end
    return false, nil, nil
end

#BuildTools.jarを新規ディレクトリ内に移動してjavaコマンドでシェルからビルドしてjarファイル以外削除するメソッド
def buildtool_build(jarname, mode)
    FileUtils.rm_rf("./buildtool_built") if Dir.exist?("./buildtool_built")
    if mode != "True" then
        write_log("AutoUpdateMode is False. Skip building.")
        return
    end

    begin
        result = Benchmark.realtime do
            Dir.mkdir("./buildtool_built") unless Dir.exist?("./buildtool_built")
            Dir.chdir("./buildtool_built") do
                system("cp ../BuildTools.jar ./")
                system("rm ../BuildTools.jar")
                s, err, status = Open3.capture3("java -jar BuildTools.jar")
                File.delete("BuildTools.jar")
                system("ls | grep -v -E 'jar$' | xargs rm -r")
                system("rename 's/.*/" + jarname + "/' *.jar")
            end
        end
        write_log("BuildTools.jar built. Time: " + result.round(2).to_s + " seconds.")
        begin
            write_log("file -> " + Dir.glob("./bundler/versions/*.jar")[0].to_s)
        rescue
            return
        end
        #FileUtils.rm_rf("./bundler") if Dir.exist?("./bundler")

    rescue Interrupt
        write_log("[INFO] BuildTools.jar build skipped.")
    end
end

#サーバーの起動に失敗した場合session.lockを削除しリトライする
def retry_start_server(al, name)
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
        elsif b
            write_log("<#{al['screenName']}> Server start success. " + time)
            break
        end
    }
end

#jarファイルを定位置に移動し、バックアップも取得するメソッド
def move_jar(dir, name, now_time)
    #既存のgeyser,floodgate,jarnameをbackup_jar/日付.gzアーカイブに移動する
    write_log("Moving plugins to backup_jar/...")
    #dir + "/backup_jar/" + name + "." + nowtime ディレクトリを作成
    bkjar_dir = dir + "/backup_jar/" #バックアップディレクトリ
    bk_file = name + "_" + now_time + ".zip" #バックアップディレクトリに保存するzipファイル
    Dir.mkdir(bkjar_dir) unless Dir.exist?(bkjar_dir)
    Dir.chdir(bkjar_dir) do
        Dir.mkdir("temp") unless Dir.exist?("temp")
    end
    files = ["geyser-spigot.jar", "floodgate.jar", "ViaVersion.jar", "ViaBackwards.jar"]
    files.each{ |f|
        if File.exist?(dir + "/plugins/" + f ) then
            FileUtils.mv(dir + "/plugins/" + f, bkjar_dir + "temp" )
            write_log(dir + "/plugins/" + f + " moved to " + bkjar_dir + "temp")
        else
            write_log(dir + "/plugins/" + f + " not found.")
        end
    }
    FileUtils.mv(name, bkjar_dir + "temp") if File.exist?(name)

    #"temp"ディレクトリをzipアーカイブ(bk_file)化してbkjar_dirに移動する
    write_log("Compressing backup_jar/...")
    Zip::File.open(bkjar_dir + bk_file, Zip::File::CREATE) do |zipfile|
        Dir.glob(bkjar_dir + "temp/*").each do |file|
            zipfile.add(File.basename(file), file)
            write_log(file + " added to " + bkjar_dir + bk_file)
        end
    end
    FileUtils.rm_rf(bkjar_dir + "temp")
    write_log("Removed " + bkjar_dir + "temp")

    #カレントディレクトリのgeyser,floodgate,./buildtool_built/nameをcopyする
    write_log("Moving plugins to " + dir + "/...")
    files.each{ |f|
        FileUtils.cp("./" + f, dir + "/plugins/" + f )
    }
    FileUtils.mv("./buildtool_built/" + name, dir + "/" + name)
end

#zipファイルを解凍し中身をカレントディレクトリに展開するメソッド ※archive.zipであること viaversionの構成に準拠　必要であれば別途メソッドを用意する必要がある
def unzip_jar(filename)
    write_log("Unzipping archive.zip...")
    system("unzip -o archive.zip")
    Dir.chdir("./archive/build/libs/") {
        system("rename 's/.*/" + filename + "/' *.jar")
    }
    FileUtils.mv("./archive/build/libs/" + filename, "./")
    FileUtils.rm_rf("./archive.zip")
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