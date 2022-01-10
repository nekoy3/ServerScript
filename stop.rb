# coding: utf-8

#メインメソッド
def main
    unless File.exist?("config.ini")
        write_log("[ERROR] Can't find config.ini! Please setting config.ini and please run the script again.")
        stop_script
    else
        write_log("[INFO] config.ini found.")
    end
    write_log("Started.")

    lines = get_ini_file("config.ini")
    section_hashs = get_section(lines)
    #screenNameとserverJarの場所を取得する。serverJarからログファイルを読みだして停止が出来たか監視する。

    if File.exist?("running_process.pid")
        write_log("stopping scripts.")
        File.open("running_process.pid", "r"){|f|
            f.each_line{|line|
                pid = line.chomp
                write_log("killing #{pid}")

                begin
                    Process.kill("KILL", pid.to_i)
                rescue => exception
                    write_log("[ERROR] #{pid} is cant kill. -> #{exception}")
                end
            }
        }
        File.delete("running_process.pid")
    else
        write_log("[ERROR] Can't find running_process.pid. skipped script stopping.")
    end

    write_log(section_hashs.to_s)
    section_hashs.each{ |section_hash|
        server_jar = section_hash["serverJar"]
        screen_name = section_hash["screenName"]
        write_log("Stopping <#{screen_name}>.")
        text = "\"say 10秒後に再起動/停止します・・・再起動の場合は五分ほどお待ちください。 \\015\""
        system("screen -p 0 -S #{screen_name} -X eval 'stuff #{text}'")
        sleep 5
        5.times { |i|
            text = "\"say #{(5-i).to_s}秒前・・・ \\015\""
            system("screen -p 0 -S #{screen_name} -X eval 'stuff #{text}'")
            sleep 1
        }
        cmd = "\"stop\\015\""
        system("screen -S #{screen_name} -X eval 'stuff #{cmd}'")
        if read_screen_log(server_jar) then
            write_log("[INFO] <#{screen_name}> is stopped.")
        end
    }
    write_log("Screen stopped successfully.")
    stop_script
end 

def now_time
    return Time.now.strftime('%Y_%m_%d__%H:%M:%S')
end

def write_log(string)
    open('LogFiles/LatestLogFile.log', 'a'){|f|
        line = "[" + now_time + "] [stop.rb] " + string + "\n"
        f.puts line
        puts line unless ARGV[0] == "nocslog"
    }
end

def stop_script
    write_log("Stopping script.")
    exit
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
            elsif line.include?("ScreenName") or line.include?("ServerJar") then
                section.push(line)
            end
        end
    }

    section_hashs = []
    sections.each{ |section_list| 
        server_jar, screen_name, = nil

        section_list.each { |line|
            case line
            when /^ServerJar=/ then
                server_jar = line.sub("ServerJar=","")
                write_log("ServerJar Loaded. -> " + server_jar)
            when /^ScreenName=/ then
                screen_name = line.sub("ScreenName=","")
                write_log("ScreenName Loaded. -> " + screen_name)
            end
        }
        begin
            section_hash = {"serverJar" => server_jar, "screenName" => screen_name} #Hash(辞書型)に格納
        rescue => e
            write_log("[ERROR] Can't get section hash. ->" + e.to_s)
            stop_script
        end
        section_hashs << section_hash
    }
    section_hashs.delete_at(0) #Generalセクションを削除
    
    return section_hashs
end

#iniファイルを読み込んで配列に格納して返すメソッド
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

#末尾行のみ取得し続けるメソッド
def tail(filename)
    lines = []
    File.open(filename, "r"){|f|
        f.seek(-1024, IO::SEEK_END)
        lines = f.readlines
    }
    return lines[-1]
end

#ログファイルを読み出して最新行を監視し"Stopping server"がでたらtrueを返すメソッド
def read_screen_log(server_jar)
    log_file = File.dirname(server_jar) + "/logs/latest.log"
    latest_line = tail(log_file)
    15.times{
        latest_line = tail(log_file)
        if latest_line.include?("All dimensions are saved") then
            return true
        end
        sleep(1)
    }
    #15秒経過したらタイムアウトを出力
    write_log("[ERROR] Timeout. -> " + latest_line)
    return false
end

begin
    main
rescue Interrupt
    write_log("[INFO] Interrupt signal received. Stopping script.")
    stop_script
end