# coding: utf-8

#引数 タイプ バージョン　を受け取る
def main_jarbuild(url, type, version, filename)
    write_sj("Started. -> " + type + " " + version + " " + filename)
    result = Benchmark.realtime do
      URI.open(url) { |file|
          File.open(filename, "w+b") { |out|
              out.write(file.read)
          }
      }
    end #ファイル名がfilenameになっているので変える
    write_sj("Downloaded " + filename + "." + " Time: " + result.round(2).to_s + " seconds.")
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

#BuildTools.jarを新規ディレクトリ内に移動してjavaコマンドでシェルからビルドしてjarファイル以外削除するメソッド
def spigot(ver, name)
    FileUtils.rm_rf("./buildtool_built") if Dir.exist?("./buildtool_built")

    begin
        result = Benchmark.realtime do
            Dir.mkdir("./buildtool_built")
            Dir.chdir("./buildtool_built") do
                system("cp ../BuildTools.jar ./")
                system("rm ../BuildTools.jar")
                s, err, status = Open3.capture3("java -jar BuildTools.jar --rev #{ver}")
                File.delete("BuildTools.jar")
                system("ls | grep -v -E 'jar$' | xargs rm -r")
                system("rename 's/.*/" + namename + "/' *.jar")
            end
        end
        write_sj("BuildTools.jar built. Time: " + result.round(2).to_s + " seconds.")
        begin
            write_sj("file -> " + Dir.glob("./bundler/versions/*.jar")[0].to_s)
        rescue
            return
        end

    rescue Interrupt
        write_sj("[INFO] BuildTools.jar build skipped.")
    end
end