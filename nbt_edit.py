import sys
import os
import re
import codecs
import gzip

args = sys.argv
try:
    srcPath = args[1].replace('\\','/')
except:
    print("読み込むファイルパスを入力")
    srcPath = input().replace('\\','/')

if os.path.exists(srcPath):
    print("ファイルパスを認識")
else:
    print("ファイルパスが無効です。")
    exit()

with gzip.open(srcPath) as f:
    mainText = f.read()

#「Name」「Objective」「Score」の文字がオブジェクトや名前で使用されていてもある程度動作するように修正

#不要な部分は削除する。Objectives以降のコードを削除
num = str(mainText.hex()).find('4f626a65637469766573') #sは0x73
searchText = mainText.hex()[:num]
scoreList = searchText.split('00080009')

scoreHex = '000553636f7265'
nameHex = '00044e616d65'
objectiveHex = '4f626a656374697665'
dataList = []
for i in range(1,len(scoreList)):

    score = scoreList[i].count(scoreHex)
    if score == 0:
        score = 'None'
    elif score == 1:
        score = re.search(scoreHex + r'.{8}', str(scoreList[i])).group().replace(scoreHex,'') #Score+32bitデータを取得してScoreの文字を削除する
    else:
        score = scoreList[i].rfind(scoreHex) + len(scoreHex)
        score = scoreList[i][score:score+8]

    #符号ビット処理
    score = int(score, 16) #16進数を整数として代入する。整数であってもMSBが符号ビットであることに変わりはないので下行で計算する。
    score = (int(score^0xffffffff) * -1)-1  if (score & 0x80000000) else int(score)

    try:
        nameStr = re.search(nameHex + r'.{4}' , str(scoreList[i])).group().replace(nameHex,'') #name後の2byteで文字列の長さを表示
    except:
        name = 'None'
    else:
        nameStr = int(nameStr, 16)
        base = scoreList[i].find(nameHex) + len(nameHex) + 4 #4はname文字数を格納する2byte領域分を指す。objectでも同じ
        name = scoreList[i][base:base + nameStr*2] #一文字を4bit*2で表現するため文字数*2ケタを指定する
        name = str(codecs.decode(name, "hex"),'utf-8') #文字列へ変換する。日本語文字列もあるためutf-8を使用

    try:
        objectStr = re.search(objectiveHex + r'.{4}',str(scoreList[i])).group().replace(objectiveHex,'')
    except:
        object = 'None'
    else:
        objectStr = int(objectStr, 16)
        base = scoreList[i].find(objectiveHex) + len(objectiveHex) + 4
        object = scoreList[i][base:base + objectStr*2]
        object = str(codecs.decode(object, "hex"),'utf-8')

    dataList.append([name,object,score])

getDataList = dataList
resultList = []

def dataSort(resultList, scList, type):
    for j in range(len(resultList)):
        scList.append(resultList[j][2])
    for j in range(len(scList)):
        for k in range(j+1,len(scList)):
            if scList[j] < scList[k] and type == 't':
                scList[j],scList[k] = scList[k],scList[j]
                resultList[j],resultList[k] = resultList[k],resultList[j]
            if scList[j] > scList[k] and type == 'f':
                scList[j],scList[k] = scList[k],scList[j]
                resultList[j],resultList[k] = resultList[k],resultList[j]

if dataList == []:
    print('データが見つかりませんでした。')
    exit()

dirname = os.path.dirname(srcPath)
i = 0
while True:
    try:
        act = args[i+2].rstrip().split(',')
    except:
        print('絞り込む場合、検索タイプとキーワードを入力してください。(コンマ区切り)\n0/name 1/objective 2/score(範囲mt(最小number) */1と2を兼ねる lt(最大number))\n検索ワードに*指定すると全表示します。\nもう一つt/fでスコアソート順を設定できます。tは降順、fは昇順。ソートしない場合はnを入力。\n例：0,nekoyama_cmd,t  2,mt7 lt42,f\n終了する場合はexitを入力してください。\n引数でexport指定するとファイルとして出力します。')
        act = input().rstrip().split(',')

    if act[0].startswith('type:'):
        #typeの入力例 "[0] Score:[2]" この後は強制的にexportに移動する
        finallyList = []
        for i in range(len(getDataList)):
            fiTemp = act[0].replace('type:','').replace('\"','')
            for j in range(3):
                fiTemp = fiTemp.replace('[' + str(j) + ']',str(getDataList[i][j]))
            finallyList.append(fiTemp + '\n')
        with open(dirname + '/export.txt', 'w') as f:
            f.writelines(finallyList)
        exit()

    if act[0] == 'exit':
        exit()

    if act[0] == 'export':
        exportList = []
        for j in range(len(getDataList)):
            exportList.append('Name:' + str(getDataList[j][0]) + ' Obj:' + str(getDataList[j][1]) + ' Score:' + str(getDataList[j][2]) + '\n')
        with open(dirname + '/export.txt', 'w') as f:
            f.writelines(exportList)
        exit()

    if act[1] == '*':
        resultList = getDataList
    else:
        if act[0] != '*':
            s_i = int(act[0]) #検索対象
        else:
            s_i = -1
        if s_i == 2:
            try:
                minScore = int(re.search(r'mt-?[0-9]+',act[1]).group().replace('mt',''))
            except:
                print('スコア指定が不正です。')
                exit()
            try:
                maxScore = int(re.search(r'lt-?[0-9]+',act[1]).group().replace('lt',''))
            except:
                print('スコア指定が不正です。')
                exit()
        elif s_i <= -2 or s_i >= 3:
            print('検索対象指定が不正です。')
            exit()
        elif s_i == 0 or s_i == 1:
            for j in range(len(getDataList)):
                find = getDataList[j][s_i].find(act[1])
                if find != -1:
                    resultList.append(getDataList[j])
        elif s_i == -1:
            for k in range(2):
                for j in range(len(getDataList)):
                    find = getDataList[j][k].find(act[1])
                    if find != -1:
                        resultList.append(getDataList[j])
        elif s_i == 2:
            for j in range(len(getDataList)):
                find = getDataList[j][s_i]
                if find >= minScore and find <= maxScore:
                    resultList.append(getDataList[j])
    
    if resultList == []:
        print('データが見つかりませんでした。')
        exit()

    try:
        act[2]
    except:
        None
    else:
        scList = []
        if act[2] == 't' or act[2] == 'f':
            dataSort(resultList, scList, act[2])

    getDataList = resultList

    nameLength = 0
    for k in range(0,2):
        for j in range(len(resultList)): #最長長さの文字数を保持
            if nameLength < len(resultList[j][k]):
                nameLength = len(resultList[j][k])
        for j in range(len(resultList)): #最長長さに合わせて空白を追加
            while nameLength+2 > len(resultList[j][k]):
                resultList[j][k] += ' '

    try:
        args[i+3]
    except:
        for j in range(len(resultList)):
            print('Name:' + str(resultList[j][0]) + ' Obj:' + str(resultList[j][1]) + ' Score:' + str(resultList[j][2]))
    resultList = []
    i += 1
