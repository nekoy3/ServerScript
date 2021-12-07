// discord.js モジュールのインポート
const Discord = require('discord.js');
const fs = require('fs');
require('date-utils');
var osu = require('node-os-utils')
var https= require('https');
var cpu = osu.cpu
var drive = osu.drive
var mem = osu.mem
var ipget = ''

// Discord Clientのインスタンス作成
const client = new Discord.Client();

const token = 'ODg2OTgwOTgwOTY2MDYwMDQy.YT9faQ.KctQ0ExTwlSW3YPwAfivnBtCiis';

client.on('ready', () => {
    console.log(`${client.user.tag} でログインしています。`)
    client.user.setActivity('AZI_Server working now | CPU ')
})

client.on('message', msg => {
    if (msg.content.startsWith('!ch!')) {
        fs.writeFileSync('../discordchat.tmp', `\<${msg.member.displayName}\>${msg.content}`);
        console.log(`\<${msg.member.displayName}\>${msg.content}`)
    }
    if (!msg.content.startsWith(':')) return
    if (msg.content === ':help') {
        msg.channel.send(`\`\`\`AZI Server bot help\n:help このメッセージを表示します。\n:ナン！ 受け答えを行います。\n:jointime サーバーに参加している日数を表示します。\n:azi AZI_Serverの情報を取得します。\`\`\``)
    }
    else if (msg.content === ':ナン！') {
        msg.channel.send(`${msg.member.displayName} 様。ナンが食べたいのですか。`)
    }
    else if (msg.content === ':jointime') {
        const period = Math.round((Date.now() - msg.member.joinedAt) / 86400000)
        msg.channel.send(`${msg.member.displayName} は ${period} 日サーバーに参加しています。`)
    }
    else if (msg.content.indexOf(':azi ') != -1) {
        if (msg.content.indexOf(' stat') != -1) {
            getipfunction();
            Promise.all(
                [cpu.usage(), drive.info(), mem.info()]
            ).then(([cpuPercentage, info, memInfo]) => {
                msg.channel.send(`\`\`\`CPUコア数：${cpu.count()}\nCPU使用率：${cpuPercentage}%\nストレージ空き容量：${info.freeGb}GB/${info.totalGb}GB(${info.freePercentage}%の空き)\nメモリ空き容量：${memInfo.freeMemMb}MB/${memInfo.totalMemMb}MB(${memInfo.freeMemPercentage}%の空き)\nIPアドレス：${ipget}\`\`\``)
            })
        }
        else if (msg.content.indexOf(' ranking') != -1) {
            let now = new Date();
            msg.channel.send(`${now.toFormat('YYYY/MM/DD/ HH24時MI分SS秒')}にランキングデータを照会...`)
            fs.writeFileSync('../azi_server/data/export.txt', 'reload'); //bashに受け渡す
            //let data = fs.readFileSync('../baseRank.txt', 'utf8').split('\\n');
            //msg.channel.send(`\`\`\` ${data} \`\`\``)
        }
        else if (msg.content.indexOf(' RESTART') != -1) {
            if (msg.guild.ownerID == msg.author.id) {
                msg.channel.send("オーナー権限の行使によりサーバーを再起動。")
                fs.writeFileSync('../watch.tmp', 'restart');
            } else {
                msg.channel.send("サーバーオーナーのみこのコマンドを使用できます。")
            }
        }
        else if (msg.content.indexOf(' re_bot') != -1) {
            if (msg.guild.ownerID == msg.author.id) {
                msg.channel.send("オーナー権限の行使によりbotを再起動。")
                fs.writeFileSync('../watch.tmp', 'restart_bot');
            } else {
                msg.channel.send("サーバーオーナーのみこのコマンドを使用できます。")
            }
        }
        else if (msg.content.indexOf(' re_bash') != -1) {
            if (msg.guild.ownerID == msg.author.id) {
                msg.channel.send("オーナー権限の行使により管理スクリプトを再起動。")
                fs.writeFileSync('../watch.tmp', 'restart_bash');
            } else {
                msg.channel.send("サーバーオーナーのみこのコマンドを使用できます。")
            }
        }
        else {
            msg.channel.send(`\`\`\`:azi 使用方法：\n\`\`\``)
        }
    } else {
        msg.channel.send(`Unknown Command. Please use \`\`\`":help"\`\`\``)
    }


    function getipfunction() {
        var callback = function (err, ip) {
            if (err) {
                return console.log(err);
            }
            ipget = ip;
            //do something here with the IP address
        };
        https.get({
            host: 'api.ipify.org',
        }, function (response) {
            var ip = '';
            response.on('data', function (d) {
                ip += d;
            });
            response.on('end', function () {
                if (ip) {
                    callback(null, ip);
                } else {
                    callback('could not get public ip address :(');
                }
            });
        });
    }
})


// Discordへの接続
client.login(token);

//https://liginc.co.jp/370260
//https://discord.com/developers/applications/886980980966060042/information
