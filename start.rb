# coding: utf-8
require 'benchmark'
require 'fileutils'
require 'open-uri'
require 'open3'
require 'zip'

$download_continue_flug = true
#メインメソッド
def main
    #プラグインとbuildtoolが一度でもダウンロード失敗すればFalseにして、以降のダウンロードとビルドをスキップする

    #A unless B 条件式Bが適合しないときに限りAを実行する
    Dir.mkdir("LogFiles") unless Dir.exist?("LogFiles")
    File.delete("LogFiles/LatestLogFile.log") if File.exist?("LogFiles/LatestLogFile.log") #ログ出力ファイル
    FileUtils.touch("LogFiles/LatestLogFile.log") 
    File.delete("running_process.pid") if File.exist?("running_process.pid") #プロセスIDファイル
    FileUtils.touch("running_process.pid")
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
    
    sections.delete_at(0) #Generalのhashを削除する                   
    section_hashes = [] #jarパス→buildtoolリンク→スクリーン名→並列稼働スクリプト（複数ある場合はカンマ区切り）の順でまとめたhashを配列として格納する

    sections.size.times{ |i|
        write_log("Reading section " + sections[i][0] + "...")
        sections[i].delete_at(0)
        section_hash = get_section_hash(sections[i])
        write_log("section_hash " + section_hash.to_s)
    
        section_hash.each{|key,value|
            write_log("checking format of " + key + "...")
            checking_format(key,value)
        }
        section_hashes.push(section_hash)
    }

    #更新するためのプラグイン群を保存する
    write_log("Saving plugins to update...")
    plugin_hash.each{ |key,value|
        save_file(value, key, auto_update_mode)
    }

    #整形された設定項目がsection_hashesに格納されている状態で処理を開始する
    write_log("Server setup job started.")
    section_hashes.each { |al|
        if al['serverStart'] == "false" then
            write_log("<#{al['screenName']}> Server setup job skipped.")
            next
        end
        write_log("Running server setup <" + al["serverJar"] + "> ...")
        check = %x( screen -ls | grep -c #{al['screenName']} ) 
        if check.to_i == 1 then
            write_log("[ERROR] The server is already running.")
            next
        end

        #buildtoolをダウンロードする
        if al['jarUpdate'] == "false" then
            write_log("[INFO] jar update skipped.")
        else
            save_file(al['buildToolURL'], "BuildTools.jar", auto_update_mode)
            if $download_continue_flug then
                jarname = File.basename(al['serverJar'])
            end
            if auto_update_mode && $download_continue_flug then
                require './serverjar_build.rb'
                main_jarbuild(al['buildToolURL'], al['serverType'], al['serverVersion'], jarname)
            else
                write_log("Server jar build skipped.")
            end
        end

        dir = File.dirname(al['serverJar']) #移動するためのディレクトリを取得
        name = File.basename(al['serverJar']) #実行するためのファイル名を取得

        #geyser,floodgate,ビルドしたserverのjarをアーカイブに移動し、新しく取得したjarを保存するメソッド
        if auto_update_mode && $download_continue_flug
            write_log("Moving server jar to archive and new jar files...")
            backup_and_copy_jar(dir, name, now_time, al['jarUpdate'])
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
                parallel_script(al)
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
        line = "[" + now_time + "] [start.rb] " + string + "\n"
        f.puts line
        puts line unless ARGV[0] == "nocslog"
    }
end

def stop_script
    write_log("Stopping script.")
    File.rename("./LogFiles/LatestLogFile.log","./LogFiles/" + now_time + ".log")
    file_list = ["geyser-spigot.jar", "floodgate.jar", "ViaVersion.jar", "ViaBackwards.jar", "spigot.jar"],+
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
        f.puts "[General]\n;プラグインに導入するgeyser-spigotのURLを記述\nGeyserSpigotURL=https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master/lastSuccessfulBuild/artifact/bootstrap/spigot/target/Geyser-Spigot.jar\n;プラグインに使うfloodgateのurlを記述\nFloodgateURL=https://ci.opencollab.dev/job/GeyserMC/job/Floodgate/job/master/lastSuccessfulBuild/artifact/spigot/target/floodgate-spigot.jar\n;プラグインとjarファイルをアップデートするかを設定します。\nViaVersionURL=https://ci.viaversion.com/job/ViaVersion/lastSuccessfulBuild/artifact/*zip*/archive.zip\nViaBackwardsURL=https://ci.viaversion.com/view/ViaBackwards/job/ViaBackwards/lastSuccessfulBuild/artifact/*zip*/archive.zip\nAutoUpdateMode=True\n\n"
        f.puts "\n;セクションごとに1つのサーバーとして認識して起動する。\n[testServer]\n;サーバーのjarファイルのパス(サーバーディレクトリも含める)\n;falseにするとサーバーの起動をスキップする\nServerStart=True\nServerJar=./testServer/testServer.jar\n;jarファイルを更新するためのbuildtoolのurl(Tuinity等これで更新できない場合はJarUpdate=falseにして空欄にする)\nBuildToolURL=http://(buildTools URL)\n;サーバーを起動するscreenの名前を指定する（被り不可）\nScreenName=testServer\n;並行で起動する常駐スクリプトのファイルパス(不要ならNoneを入力)\nParallelScript=None\n;サーバーのjarファイルを自動でアップデートするか（ビルドに約二分かかります。）\nJarUpdate=true\n;サーバータイプを指定する。現在対応しているのはspigot,bukkit,paper\nServerType=spigot\n;サーバーのバージョンを指定する。存在しないバージョンであればinvilid versionを返しサーバーのjar取得をスキップする\nServerVersion=1.18.1\n\n"
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
    server_jar, buildtool_url, screen_name, parallel_script, jar_update, server_start, server_type, server_version = nil
    lines.each { |line|
        write_log("[DEBUG]  <#{line}>")
        case line
        when /^ServerJar=/ then
            server_jar = line.sub("ServerJar=","")
            write_log("ServerJar Loaded. -> " + server_jar)
        when /^BuildToolURL=/ then
            buildtool_url = line.sub("BuildToolURL=","")
            write_log("BuildToolURL Loaded. -> " + buildtool_url)
        when /^ScreenName=/ then
            screen_name = line.sub("ScreenName=","")
            write_log("ScreenName Loaded. -> " + screen_name)
        when /^ParallelScript=/ then
            parallel_script = line.sub("ParallelScript=","")
            write_log("ParallelScript Loaded. -> " + parallel_script)
        when /^JarUpdate=/ then
            jar_update = line.sub("JarUpdate=","").downcase
            write_log("JarUpdate Loaded. -> " + jar_update)
        when /^ServerStart=/ then
            server_start = line.sub("ServerStart=","").downcase
            write_log("ServerStart Loaded. -> " + server_start)
        when /^ServerType=/ then
            server_type = line.sub("ServerType=","").downcase
            write_log("ServerType Loaded. -> " + server_type)
        when /^ServerVersion=/ then
            server_version = line.sub("ServerVersion=","")
            write_log("ServerVersion Loaded. -> " + server_version)
        else
            write_log("[ERROR] Invalid setting item. ->" + line)
            stop_script
        end
    }

    buildtool_url = "https://example.com/" if jar_update == "false"
    begin
        section_hash = {"serverJar" => server_jar, "buildToolURL" => buildtool_url, "screenName" => screen_name, "parallelScript" => parallel_script, "jarUpdate" => jar_update, "serverStart" => server_start, "serverType" => server_type, "serverVersion" => server_version} #Hash(辞書型)に格納
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
    elsif $download_continue_flug == false then
        write_log("[INFO] Downloading is skipped.")
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
        $download_continue_flug = false
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

#サーバーの起動に失敗した場合session.lockを削除しリトライする
def retry_start_server(al, name)
    write_log("[ERROR]  <#{al['screenName']}> Server start failed. remove session.lock and retrying...")
    Dir.glob("**/*").each{ |fn|
        if fn =~ /.*session.lock$/ then
            File.delete(fn)
        end
    }
    sleep(3)
    dir = File.dirname(al['serverJar'])
    File.delete(dir + "/logs/latest.log")
    result, err, status = Open3.capture3("screen -AdmSU #{al['screenName']} java -Xms2G -Xmx2G -jar #{name} nogui")
    loop{ 
        b, time, err_flag = check_log_and_startup_done(dir)
        if err_flag
            write_log("[ERROR]  <#{al['screenName']}> Server start failed. ->" + err)
            break
        elsif b
            write_log("<#{al['screenName']}> Server start success. " + time)
            break
        end
    }
end

#jarファイルを定位置にコピーし、バックアップも取得するメソッド
def backup_and_copy_jar(dir, name, now_time, jar_update)
    return if jar_update == "false"
    #既存のgeyser,floodgate,jarnameをbackup_jar/日付.gzアーカイブに移動する
    #dir + "/backup_jar/" + name + "." + nowtime ディレクトリを作成
    bkjar_dir = dir + "/backup_jar/" #バックアップディレクトリ
    bk_file = name + "_" + now_time + ".zip" #バックアップディレクトリに保存するzipファイル
    Dir.mkdir(bkjar_dir) unless Dir.exist?(bkjar_dir)

    Dir.chdir(bkjar_dir) do
        Dir.mkdir("temp")
    end

    #実行中のサーバーディレクトリ内のbkjar_dir/tempにjarファイルを移動する
    files = ["geyser-spigot.jar", "floodgate.jar", "ViaVersion.jar", "ViaBackwards.jar"]
    files.each{ |f|
        if File.exist?(dir + "/plugins/" + f ) then
            FileUtils.mv(dir + "/plugins/" + f, bkjar_dir + "temp" )
            write_log(dir + "/plugins/" + f + " moved to " + bkjar_dir + "temp")
        else
            write_log(dir + "/plugins/" + f + " not found.")
        end
    }
    if File.exist?(dir + "/" + name)
        FileUtils.mv(dir + "/" + name, bkjar_dir + "temp")
        write_log(dir + "/" + name + " moved to " + bkjar_dir + "temp")
    else
        write_log(dir + "/" + name + " not found.")
    end

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
    
    #カレントディレクトリのgeyser,floodgate,./をcopyする
    write_log("Moving plugins to " + dir + "/...")
    files.each{ |f|
        FileUtils.cp("./" + f, dir + "/plugins/" + f )
    }

    write_log("Copying jar to " + dir + "/... " + name)
    FileUtils.cp(name, dir + "/" + name)
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

#al['parallelScript']のシェルスクリプトを全て実行するメソッド
def parallel_script(al)
    scripts = al['parallelScript'].chomp.split(",")
    return if scripts[0].downcase == "none"
    write_log("[INFO] Parallel script start.")
    scripts.each{ |script|
        begin
            script_file = File.basename(script)
        rescue
            write_log("[ERROR]  < " + script_path + " / " + script_file + " > Script not found. please write script path include directory name.")
            return
        end
        script_path = File.dirname(script)
        write_log("[INFO]  < " + script_path + " / " + script_file + " > Script start.")
        $pid = nil
        Dir.chdir(script_path) do
            $pid = spawn("nohup ./" + script_file + " & > /dev/null 2>&1")
        end

        write_log("[INFO]  < " + script_path + "/" + script_file + " > Script success.")

        #running_process.pidにプロセスIDをで書き込む
        #File.open("running_process.pid", "a") { |f|
        #    f.puts($pid)
        #}
        write_log("[INFO] Parallel script end.")
    }
    write_log("[INFO] Resident scripts should get their own PID at startup and add to running_process.pid (echo $$ >> ../running_process.pid)")
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