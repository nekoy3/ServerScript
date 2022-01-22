# coding: utf-8

#引数 タイプ バージョン　を受け取る
def main_jarbuild(url, type, version, filename)
    write_sj("Started. -> " + type + " " + version + " " + filename)
        
    result = Benchmark.realtime do
      URI.open(url) { |file|
          File.open("BuildTools.jar", "w+b") { |out|
              out.write(file.read)
          }
      }
    end #ファイル名がfilenameになっているので変える
    write_sj("Downloaded BuildTools.jar." + " Time: " + result.round(2).to_s + " seconds.")
    #stop_scriptで該当のファイルを削除する
    case type
	when "spigot"
        spigot(version, filename)
    when "bukkit"
        bukkit(version, filename)
    when "paper"
        paper(version, filename)
    else
        write_sj("[ERROR] Unknown type.")
        stop_script_sj
    end
end

def stop_script_sj
  write_sj("Stopped.")
  exit
end

def write_sj(string)
    open('LogFiles/LatestLogFile.log', 'a'){|f|
        line = "[" + now_time + "] [serverjar_build.rb] " + string + "\n"
        f.puts line
        puts line unless ARGV[2] == "nocslog"
    }
end

def build_buildtool_sj(ver)
    Open3.capture3("java -jar BuildTools.jar --rev #{ver}")
end

#BuildTools.jarを新規ディレクトリ内に移動してjavaコマンドでシェルからビルドしてjarファイル以外削除するメソッド
def spigot(ver, name)
    #spigot.jarが存在する場合は実行をパスする(geyser-spigot.jarとは別に検知)
    if File.exist?("spigot.jar")
        write_sj("spigot.jar already exists.")
        return
    end
    FileUtils.rm_rf("./buildtool_built") if Dir.exist?("./buildtool_built")
    begin
        result = Benchmark.realtime do
            Dir.mkdir("./buildtool_built")
            write_sj("Building buildtool.")
            Dir.chdir("./buildtool_built") do
                FileUtils.mv("../BuildTools.jar", "./")

                build_buildtool_sj(ver)
                
                File.delete("BuildTools.jar")

                system("ls | grep -v -E 'jar$' | xargs rm -r") #jarファイル以外削除
                system("rename 's/.*/#{name}/' *.jar") #ファイル名を#{name}.jarに変更
                system("mv ./#{name} ../")
            end
        end
        write_sj("BuildTools.jar built. Time: " + result.round(2).to_s + " seconds.")
        write_sj("file -> " + Dir.glob("./#{name}")[0].to_s)
        #spigot.jarをサーバーディレクトリに移動する
    rescue Interrupt
        write_sj("[INFO] BuildTools.jar build skipped.")
    end
end
