# coding: utf-8
require 'fileutils'

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
    puts line
    #if line == "[General]" then
    #    general = true
    #elsif general then
    #    if line.include?("GeyserSpigotURL=") then
    #        gsURL = line.sub("GeyserSpigotURL=","")
    #        general = false
    #    else
    #        write_log("[ERROR]Can't read GeyserSpigotURL.")
    #        stop_script
    #    end
    if (line =~ /\[(.+)\]/) != nil then
        puts "sectionフラグ開始"
        sectionFlag = true
        sectionName = line.match(/^\[(.*)\]/)[0]
        secTemp.push(sectionName)
    elsif sectionFlag then
        if line == "" then
            puts "sectionフラグ終了"
            sectionFlag = false
            sections.push(secTemp)
            secTemp = []
        else
            secTemp.push(line)
        end
    else
        puts "空白行"
    end
end
puts sections.to_s
stop_script