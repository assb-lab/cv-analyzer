#pragma rtGlobals=3
#pragma version=0.102
// Semantic version: 0.1.2 (Igor pragma uses a numeric version).

// BioLogic EC-Lab cyclic voltammetry viewer. Igor Pro 8 or later.
Menu "Macros"
    "CV Analyzer", CVA_OpenPanel()
End

Function CVA_OpenPanel()
    NewDataFolder/O root:Packages
    NewDataFolder/O root:Packages:CVAnalyzer
    DoWindow/F CVA_Panel
    if (V_flag)
        return 0
    endif
    Variable/G root:Packages:CVAnalyzer:mode = 1
    NewPanel/N=CVA_Panel/W=(20,50,385,595) as "CV Analyzer"
    TitleBox heading,pos={20,15},size={325,30},frame=0,title="CV Analyzer"
    TitleBox heading,fSize=20,fStyle=1,fColor=(6500,14000,29000)
    TitleBox version,pos={286,23},frame=0,title="v0.1.2",fSize=11,fColor=(24000,27000,32000)
    TitleBox subtitle,pos={20,48},size={325,20},frame=0,title="BioLogic EC-Lab  •  サイクリックボルタンメトリー"
    TitleBox subtitle,fSize=11,fColor=(24000,27000,32000)
    GroupBox inputGroup,pos={15,78},size={335,130},title="1  測定方法とファイル",fSize=12,fStyle=1
    PopupMenu cvMode,pos={30,110},size={305,22},title="測定方法",proc=CVA_ModeChanged
    PopupMenu cvMode,fSize=12,mode=1,value="通常 CV：酸化開始;通常 CV：還元開始;酸化側 stepwise（未実装）;還元側 stepwise（未実装）"
    TitleBox modeInfo,pos={30,143},size={300,20},frame=0,title="通常 CV：サイクル番号ごとに解析します。"
    TitleBox modeInfo,fSize=11,fColor=(22000,25000,30000)
    Button load,pos={30,172},size={220,25},title="MPT ファイルを選択して解析",proc=CVA_LoadButton
    Button load,fSize=12
    GroupBox outputGroup,pos={15,220},size={335,100},title="2  出力",fSize=12,fStyle=1
    TitleBox out1,pos={30,246},frame=0,title="・CV 曲線をサイクルごとに色分け",fSize=11
    TitleBox out2,pos={30,267},frame=0,title="・電位範囲・電流極値・電荷量を表に表示",fSize=11
    TitleBox out3,pos={30,288},frame=0,title="・元ファイルと行番号を wave Note に記録",fSize=11
    GroupBox fitGroup,pos={15,332},size={335,78},title="3  解析",fSize=12,fStyle=1
    Button fitOpen,pos={30,355},size={230,25},title="2接線フィッティングを開く",proc=CVA_FitOpenButton,fSize=12
    TitleBox fitInfo,pos={30,384},frame=0,title="対象グラフとサイクルを選択します。",fSize=11
    GroupBox notesGroup,pos={15,422},size={335,108},title="解析について",fSize=12,fStyle=1
    TitleBox note1,pos={30,448},frame=0,title="電位・電流は測定値を使用し、補正しません。",fSize=11
    TitleBox note2,pos={30,469},frame=0,title="電荷量は電流の正負別に時間積分します。",fSize=11
    TitleBox note3,pos={30,490},frame=0,title="stepwise は測定条件の確定後に対応予定です。",fSize=11
    return 0
End

Function CVA_ModeChanged(ctrlName,popNum,popStr) : PopupMenuControl
    String ctrlName,popStr
    Variable popNum
    NVAR mode=root:Packages:CVAnalyzer:mode
    mode=popNum
    if (popNum<=2)
        TitleBox modeInfo,win=CVA_Panel,title="通常 CV：サイクル番号ごとに解析します。"
    else
        TitleBox modeInfo,win=CVA_Panel,title="stepwise は未実装です。読み込みは行いません。"
    endif
End

Function CVA_LoadButton(ctrlName) : ButtonControl
    String ctrlName
    NVAR mode=root:Packages:CVAnalyzer:mode
    if (mode > 2)
        DoAlert 0, "stepwise CV は未実装です。ファイルは読み込まれません。"
        return 0
    endif
    Variable ref
    Open/D/R/F="MPT Files (*.mpt):.mpt;" ref
    String path=S_fileName
    if (strlen(path)==0)
        return 0
    endif
    CVA_Import(path,mode)
    return 0
End

// Return 0 on success; on error remove the incomplete import and explain why.
Function CVA_Import(path, mode)
    String path
    Variable mode
    String oldDF=GetDataFolder(1), problem="", folder, filename
    Variable ref, lineNo=0, n=0, capacity=4096
    Variable cT=-1,cE=-1,cI=-1,cC=-1
    if (mode != 1 && mode != 2)
        DoAlert 0, "Only normal CV is supported."
        return -1
    endif
    Open/R/Z ref as path
    if (V_flag != 0)
        DoAlert 0, "Cannot open the selected file."
        return -1
    endif
    problem=CVA_ReadHeader(ref,lineNo,cT,cE,cI,cC)
    folder=CVA_PrepareFolder(path,filename)
    Make/D/N=(capacity) time_s, Ewe_V, current_mA, cycle_number, source_line
    if (strlen(problem)==0)
        problem=CVA_ReadRows(ref,lineNo,cT,cE,cI,cC,n,capacity)
    endif
    Close ref
    if (n<2 && strlen(problem)==0)
        problem="The file contains fewer than two data rows."
    endif
    if (strlen(problem)>0)
        CVA_DiscardImport(folder,oldDF)
        DoAlert 0, "CV import failed: "+problem
        return -1
    endif
    Redimension/N=(n) time_s,Ewe_V,current_mA,cycle_number,source_line
    String/G source_file=path
    String/G source_filename=filename
    String/G measurement_type="Normal CV - oxidation start"
    if (mode==2)
        measurement_type="Normal CV - reduction start"
    endif
    CVA_SummarizeAndPlot()
    Print "CV Analyzer: imported "+num2str(n)+" rows from "+path+" into "+GetDataFolder(1)
    SetDataFolder $oldDF
    return 0
End

// Read and validate the EC-Lab header. The file remains open at the data rows.
Function/S CVA_ReadHeader(ref,lineNo,cT,cE,cI,cC)
    Variable ref
    Variable &lineNo,&cT,&cE,&cI,&cC
    String line,header="",problem="",technique="",headerToken
    Variable headerCount=NaN
    FReadLine ref,line
    lineNo+=1
    if (strsearch(line,"EC-Lab ASCII FILE",0)<0)
        return "Not an EC-Lab ASCII MPT file."
    endif
    FReadLine ref,line
    lineNo+=1
    if (strsearch(line,"Nb header lines",0)<0)
        return "Missing Nb header lines declaration."
    endif
    headerToken=StringFromList(1,line,":")
    headerToken=ReplaceString("\r",headerToken,"")
    headerToken=ReplaceString("\n",headerToken,"")
    headerCount=str2num(headerToken)
    if (!CVA_IsNumber(headerToken) || numtype(headerCount)!=0 || headerCount<3 || headerCount>100000 || headerCount!=floor(headerCount))
        return "Invalid header line count."
    endif
    do
        FReadLine ref,line
        lineNo+=1
        if (strlen(line)==0)
            problem="File ended before the column header."
            break
        endif
        if (lineNo==4)
            technique=line
        endif
    while (lineNo<headerCount)
    // Preserve the original diagnostic precedence, even after an early EOF.
    header=ReplaceString("\r",line,"")
    header=ReplaceString("\n",header,"")
    cT=WhichListItem("time/s",header,"\t")
    cE=WhichListItem("Ewe/V",header,"\t")
    cI=WhichListItem("<I>/mA",header,"\t")
    cC=WhichListItem("cycle number",header,"\t")
    if (cT<0 || cE<0 || cI<0 || cC<0)
        problem="Required columns missing: time/s, Ewe/V, <I>/mA, cycle number."
    endif
    if (strsearch(LowerStr(technique),"cyclic voltammetry",0)<0)
        problem="The header does not identify Cyclic Voltammetry."
    endif
    return problem
End

// Create a distinct folder for this source and return its name.
Function/S CVA_PrepareFolder(path,filename)
    String path
    String &filename
    String folder,baseName
    Variable dot
    NewDataFolder/O root:CVAnalyzer
    SetDataFolder root:CVAnalyzer
    // Accept both Igor colon paths and POSIX paths.
    filename=ReplaceString("\\",path,"/")
    filename=ParseFilePath(0,filename,":",1,0)
    filename=ParseFilePath(0,filename,"/",1,0)
    baseName=filename
    dot=strsearch(LowerStr(baseName),".mpt",0)
    if (dot>=0 && dot==strlen(baseName)-4)
        baseName=baseName[0,dot-1]
    endif
    if (strlen(baseName)>0 && char2num(baseName[0])>=48 && char2num(baseName[0])<=57)
        baseName="A"+baseName
    endif
    baseName=CleanupName(baseName,0)
    if (strlen(baseName)==0)
        baseName="CV"
    endif
    folder=UniqueName(baseName,11,0)
    NewDataFolder/S $folder
    return folder
End

// Read validated data rows into the current import folder.
Function/S CVA_ReadRows(ref,lineNo,cT,cE,cI,cC,n,capacity)
    Variable ref,cT,cE,cI,cC
    Variable &lineNo,&n,&capacity
    String line,problem=""
    Variable t,e,current,cycle,lastT=-Inf,lastC=-Inf
    Wave time_s,Ewe_V,current_mA,cycle_number,source_line
    do
        FReadLine ref,line
        if (strlen(line)==0)
            break
        endif
        lineNo+=1
        line=ReplaceString("\r",line,"")
        line=ReplaceString("\n",line,"")
        if (strlen(line)==0)
            continue
        endif
        problem=CVA_ParseDataRow(line,lineNo,cT,cE,cI,cC,lastT,lastC,t,e,current,cycle)
        if (strlen(problem)>0)
            break
        endif
        if (n>=capacity)
            capacity+=4096
            Redimension/N=(capacity) time_s,Ewe_V,current_mA,cycle_number,source_line
        endif
        time_s[n]=t; Ewe_V[n]=e; current_mA[n]=current; cycle_number[n]=cycle; source_line[n]=lineNo
        lastT=t; lastC=cycle; n+=1
    while (1)
    return problem
End

// Validate lexical values before conversion, then enforce acquisition order.
Function/S CVA_ParseDataRow(line,lineNo,cT,cE,cI,cC,lastT,lastC,t,e,current,cycle)
    String line
    Variable lineNo,cT,cE,cI,cC,lastT,lastC
    Variable &t,&e,&current,&cycle
    if (!CVA_IsNumber(StringFromList(cT,line,"\t")) || !CVA_IsNumber(StringFromList(cE,line,"\t")) || !CVA_IsNumber(StringFromList(cI,line,"\t")) || !CVA_IsNumber(StringFromList(cC,line,"\t")))
        return "Invalid or missing required numeric value at line "+num2str(lineNo)+"."
    endif
    t=str2num(StringFromList(cT,line,"\t"))
    e=str2num(StringFromList(cE,line,"\t"))
    current=str2num(StringFromList(cI,line,"\t"))
    cycle=str2num(StringFromList(cC,line,"\t"))
    if (numtype(t)!=0 || numtype(e)!=0 || numtype(current)!=0 || numtype(cycle)!=0)
        return "Invalid or missing required numeric value at line "+num2str(lineNo)+"."
    endif
    if (t<lastT || cycle<lastC || cycle!=floor(cycle))
        return "Time or cycle number is out of order at line "+num2str(lineNo)+"."
    endif
    return ""
End

Function CVA_DiscardImport(folder,oldDF)
    String folder,oldDF
    SetDataFolder root:CVAnalyzer
    KillDataFolder $folder
    SetDataFolder $oldDF
End

// Per file cycle: extrema are raw, without baseline subtraction. Charge is
// trapezoidal integral of positive/negative current versus time in mAh.
// Intervals spanning different cycle numbers are deliberately excluded.
Function CVA_SummarizeAndPlot()
    Wave cycle_number
    SVAR source_filename
    Variable groups=CVA_CountCycles(cycle_number),j,start=0,finish
    CVA_CreateSummaryWaves(groups)
    String en,iname
    String legendText="",graphName="",commonNote="File: "+source_filename+"\rCycles and source lines (inclusive, 1-based):\r"
    for(j=0;j<groups;j+=1)
        finish=CVA_CycleEnd(cycle_number,start)
        CVA_SummarizeCycle(j,start,finish)
        en="E_cycle_"+num2str(j+1)
        iname="I_cycle_"+num2str(j+1)
        CVA_CreateCycleWaves(start,finish,en,iname)
        CVA_AppendCycleNotes(start,finish,en,iname,commonNote)
        CVA_PlotCycle(j,en,iname,graphName)
        CVA_ColorTrace(graphName,iname,j)
        CVA_AppendCycleLegend(j,iname,cycle_number[start],legendText)
        start=finish+1
    endfor
    CVA_AnnotateWaves(commonNote)
    CVA_StyleGraph(graphName,legendText)
    CVA_PadGraphAxes(graphName)
    CVA_ShowSummary()
End

Function CVA_CreateSummaryWaves(groups)
    Variable groups
    Make/D/N=(groups) summary_cycle, points, E_min_V, E_max_V, I_max_mA, E_at_Imax_V, I_min_mA, E_at_Imin_V, Q_positive_mAh, Q_negative_mAh, duration_s
End

Function CVA_CountCycles(cycle_number)
    Wave cycle_number
    Variable n=numpnts(cycle_number),groups=1,i
    for(i=1;i<n;i+=1)
        if(cycle_number[i]!=cycle_number[i-1])
            groups+=1
        endif
    endfor
    return groups
End

Function CVA_CycleEnd(cycle_number,start)
    Wave cycle_number
    Variable start
    Variable finish=start,n=numpnts(cycle_number)
    do
        if (finish+1>=n)
            break
        endif
        if (cycle_number[finish+1]!=cycle_number[start])
            break
        endif
        finish+=1
    while(1)
    return finish
End

// Calculate extrema and signed charge within this cycle only.
Function CVA_SummarizeCycle(j,start,finish)
    Variable j,start,finish
    Wave time_s,cycle_number
    Wave summary_cycle,points,duration_s
    summary_cycle[j]=cycle_number[start]; points[j]=finish-start+1
    duration_s[j]=time_s[finish]-time_s[start]
    CVA_SummarizeExtrema(j,start,finish)
    CVA_SummarizeCharge(j,start,finish)
End

// Strict comparisons keep the first point when an extremum is repeated.
Function CVA_SummarizeExtrema(j,start,finish)
    Variable j,start,finish
    Wave Ewe_V,current_mA
    Wave E_min_V,E_max_V,I_max_mA,E_at_Imax_V,I_min_mA,E_at_Imin_V
    Variable i
    E_min_V[j]=Ewe_V[start]; E_max_V[j]=Ewe_V[start]
    I_max_mA[j]=current_mA[start]; I_min_mA[j]=current_mA[start]
    E_at_Imax_V[j]=Ewe_V[start]; E_at_Imin_V[j]=Ewe_V[start]
    for(i=start;i<=finish;i+=1)
        E_min_V[j]=min(E_min_V[j],Ewe_V[i]); E_max_V[j]=max(E_max_V[j],Ewe_V[i])
        if(current_mA[i]>I_max_mA[j])
            I_max_mA[j]=current_mA[i]; E_at_Imax_V[j]=Ewe_V[i]
        endif
        if(current_mA[i]<I_min_mA[j])
            I_min_mA[j]=current_mA[i]; E_at_Imin_V[j]=Ewe_V[i]
        endif
    endfor
End

// Split a sign-changing interval at its linearly interpolated zero current.
Function CVA_SummarizeCharge(j,start,finish)
    Variable j,start,finish
    Wave time_s,current_mA
    Wave Q_positive_mAh,Q_negative_mAh
    Variable i,dt,a,b,frac,qp=0,qn=0
    for(i=start+1;i<=finish;i+=1)
        dt=(time_s[i]-time_s[i-1])/3600
        a=current_mA[i-1]; b=current_mA[i]
        if(a>=0 && b>=0)
            qp+=dt*(a+b)/2
            continue
        endif
        if(a<=0 && b<=0)
            qn+=dt*(a+b)/2
            continue
        endif
        frac=abs(a)/(abs(a)+abs(b))
        if(a>0)
            qp+=dt*frac*a/2; qn+=dt*(1-frac)*b/2
            continue
        endif
        qn+=dt*frac*a/2; qp+=dt*(1-frac)*b/2
    endfor
    Q_positive_mAh[j]=qp; Q_negative_mAh[j]=qn
End

// Duplicate only this cycle's measured potential and current.
Function CVA_CreateCycleWaves(start,finish,en,iname)
    Variable start,finish
    String en,iname
    Wave Ewe_V,current_mA
    Duplicate/O/R=[start,finish] Ewe_V,$en
    Duplicate/O/R=[start,finish] current_mA,$iname
End

// Cycle waves keep their own span; raw and summary waves receive all spans.
Function CVA_AppendCycleNotes(start,finish,en,iname,commonNote)
    Variable start,finish
    String en,iname
    String &commonNote
    Wave cycle_number,source_line
    SVAR source_filename
    Wave ew=$en, iw=$iname
    String cycleNote="File: "+source_filename+"\rCycle: "+num2str(cycle_number[start])+"\rStart line: "+num2istr(source_line[start])+"\rEnd line: "+num2istr(source_line[finish])+"\r"
    Note/K ew
    Note/K iw
    Note ew,cycleNote
    Note iw,cycleNote
    commonNote+="Cycle "+num2str(cycle_number[start])+": "+num2istr(source_line[start])+" - "+num2istr(source_line[finish])+"\r"
End

// Create the graph on the first cycle, then append the remaining traces.
Function CVA_PlotCycle(j,en,iname,graphName)
    Variable j
    String en,iname
    String &graphName
    Wave ew=$en, iw=$iname
    if(j==0)
        Display/K=1/W=(405,50,965,510) iw vs ew as "CV cycles"
        graphName=S_name
    else
        AppendToGraph/W=$graphName iw vs ew
    endif
End

Function CVA_AppendCycleLegend(j,iname,cycle,legendText)
    Variable j,cycle
    String iname
    String &legendText
    if (j>0)
        legendText+="\r"
    endif
    legendText+="\\s("+iname+") "+CVA_Ordinal(cycle)
End

// First ten colors follow the reference InoColors sequence; repeat after 10.
Function CVA_ColorTrace(graphName,iname,j)
    String graphName,iname
    Variable j
    String reds="65535;13106;0;59604;52428;0;51655;53173;869;12135"
    String greens="0;0;48704;35614;0;38659;52875;524;34359;62866"
    String blues="0;65535;25731;394;65535;43342;174;28486;65535;289"
    Variable colorIndex=mod(j,10)
    Variable red=str2num(StringFromList(colorIndex,reds))
    Variable green=str2num(StringFromList(colorIndex,greens))
    Variable blue=str2num(StringFromList(colorIndex,blues))
    ModifyGraph/W=$graphName rgb($iname)=(red,green,blue)
End

Function CVA_AnnotateWaves(commonNote)
    String commonNote
    String waveNames,waveName
    Variable k
    // Raw and summary waves cover all cycles; preserve each cycle's line span.
    waveNames=WaveList("*",";","")
    for (k=0;k<ItemsInList(waveNames);k+=1)
        waveName=StringFromList(k,waveNames)
        if (strsearch(waveName,"E_cycle_",0)==0 || strsearch(waveName,"I_cycle_",0)==0)
            continue
        endif
        Wave noteWave=$waveName
        Note/K noteWave
        Note noteWave,commonNote
    endfor
End

Function CVA_GraphAppearance(graphName)
    String graphName
    // Igor graph dimensions are points (72 points/inch), before expansion.
    ModifyGraph/W=$graphName mirror=1, tick=2, expand=2, gfSize=12, width=226.77165, height=170.07874, margin(left)=56, margin(bottom)=39, margin(right)=14, margin(top)=14
    ModifyGraph/W=$graphName manTick(bottom)={0,1,0,1},manMinor(bottom)={4,50}
    Label/W=$graphName bottom "\\Z14Cell Voltage \\f02V\\f00 / V"
    Label/W=$graphName left "\\Z14Current \\f02I\\f00 / mA"
End

Function CVA_StyleGraph(graphName,legendText)
    String graphName,legendText
    CVA_GraphAppearance(graphName)
    Legend/W=$graphName/C/N=text0/F=0/B=1/A=RB legendText
End

Function CVA_PadGraphAxes(graphName)
    String graphName
    // Get Igor's autoscaled limits first, then add 15% of that span per side.
    SetAxis/W=$graphName/A bottom
    SetAxis/W=$graphName/A left
    DoUpdate
    GetAxis/Q/W=$graphName bottom
    Variable lo=V_min, hi=V_max, margin=(V_max-V_min)*0.15
    if (numtype(margin)==0 && margin>0)
        SetAxis/W=$graphName bottom,lo-margin,hi+margin
    endif
    GetAxis/Q/W=$graphName left
    lo=V_min; hi=V_max; margin=(hi-lo)*0.15
    if (numtype(margin)==0 && margin>0)
        SetAxis/W=$graphName left,lo-margin,hi+margin
    endif
End

Function CVA_ShowSummary()
    Wave summary_cycle,points,E_min_V,E_max_V,I_max_mA,E_at_Imax_V,I_min_mA,E_at_Imin_V,Q_positive_mAh,Q_negative_mAh,duration_s
    String tableName
    Edit/K=1/W=(20,615,385,855) summary_cycle,points,E_min_V,E_max_V,I_max_mA,E_at_Imax_V,I_min_mA,E_at_Imin_V,Q_positive_mAh,Q_negative_mAh,duration_s as "CV cycle summary"
    tableName=S_name
    ModifyTable/W=$tableName size=12
End

// English ordinal suffix, including 11th, 12th and 13th.
Function/S CVA_Ordinal(number)
    Variable number
    Variable lastTwo=mod(abs(number),100), lastDigit=mod(abs(number),10)
    String suffix="th"
    if (lastTwo<11 || lastTwo>13)
        if (lastDigit==1)
            suffix="st"
        elseif (lastDigit==2)
            suffix="nd"
        elseif (lastDigit==3)
            suffix="rd"
        endif
    endif
    return num2istr(number)+suffix
End

// Require the entire field to be a decimal number, not a numeric prefix.
Function CVA_IsNumber(token)
    String token
    return GrepString(token, "^[ \t]*[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?[ \t]*$")
End

// Two-line intersection tool: operates on a copy of one existing cycle trace.
Function CVA_FitOpenButton(ctrlName) : ButtonControl
    String ctrlName
    CVA_FitOpen()
    return 0
End

// Candidate order follows the existing graph and trace lists.
Function/S CVA_FitGraphCandidates(graphs)
    String graphs
    String candidates="",graph,traces
    Variable i
    for(i=0;i<ItemsInList(graphs);i+=1)
        graph=StringFromList(i,graphs)
        traces=GrepList(TraceNameList(graph,";",1),"^I_cycle_[0-9]+$")
        if(ItemsInList(traces)>0)
            candidates+=graph+";"
        endif
    endfor
    return candidates
End

// Return true after bringing the dataset's existing editor to the front.
Function CVA_ActivateFitEditor(graphs,sourceDF)
    String graphs,sourceDF
    String graph,fitDF
    Variable i
    for(i=0;i<ItemsInList(graphs);i+=1)
        graph=StringFromList(i,graphs)
        fitDF=GetUserData(graph,"","fitDF")
        if(strlen(fitDF)==0)
            continue
        endif
        SVAR/Z openSource=$(fitDF+"source_folder")
        if(!SVAR_Exists(openSource))
            continue
        endif
        if(cmpstr(openSource,sourceDF)!=0)
            continue
        endif
        DoWindow/F $graph
        return 1
    endfor
    return 0
End

Function CVA_FitOpen()
    String graphs=WinList("*",";","WIN:1"),candidates=CVA_FitGraphCandidates(graphs)
    String sourceGraph,traces,selection,sourceDF
    Variable graphChoice=1
    if(ItemsInList(candidates)==0)
        DoAlert 0,"先に CV データを読み込んでグラフを作成してください。"
        return -1
    endif
    Prompt graphChoice,"対象グラフ",popup,candidates
    DoPrompt "フィットする CV グラフを選択",graphChoice
    if(V_flag)
        return 0
    endif
    sourceGraph=StringFromList(graphChoice-1,candidates)
    traces=GrepList(TraceNameList(sourceGraph,";",1),"^I_cycle_[0-9]+$")
    // The cycle selector lives in the fitting window; start from the first trace.
    selection=StringFromList(0,traces)
    Wave/Z sourceI=TraceNameToWaveRef(sourceGraph,selection)
    if (!WaveExists(sourceI))
        DoAlert 0, "対象の電流 wave が見つかりません。"
        return -1
    endif
    sourceDF=GetWavesDataFolder(sourceI,1)
    // A dataset has one editor: independent windows must not overwrite each
    // other's shared cursor/result state.
    if(CVA_ActivateFitEditor(graphs,sourceDF))
        return 0
    endif
    return CVA_CreateFitEditor(sourceGraph,selection,sourceDF)
End

// Validate and prepare the scratch folder before building its graph.
Function CVA_CreateFitEditor(sourceGraph,selection,sourceDF)
    String sourceGraph,selection,sourceDF
    Wave sourceI=TraceNameToWaveRef(sourceGraph,selection)
    Variable cycleIndex,offset,initialCycle,initialSide
    if(CVA_ValidateEditorSource(selection,sourceDF,sourceI,cycleIndex,offset)!=0)
        return -1
    endif
    String oldDF=GetDataFolder(1)
    String fitDF=CVA_CreateFitScratch(selection,sourceDF,sourceI,cycleIndex,offset,initialCycle,initialSide)
    String graph=CVA_CreateFitGraph(fitDF,sourceDF,cycleIndex,initialCycle,initialSide)
    CVA_PlaceFitBelow(sourceGraph,graph)
    SetDataFolder $oldDF
    return 0
End

// This initial-open policy deliberately differs from switch/source-match checks.
Function CVA_ValidateEditorSource(selection,sourceDF,sourceI,cycleIndex,offset)
    String selection,sourceDF
    Wave sourceI
    Variable &cycleIndex,&offset
    Variable n,i
    String suffix=selection[strlen("I_cycle_"),inf]
    Wave/Z sourceE=$(sourceDF+"E_cycle_"+suffix)
    Wave/Z sourceLines=$(sourceDF+"source_line")
    Wave/Z allCycles=$(sourceDF+"summary_cycle")
    Wave/Z counts=$(sourceDF+"points")
    SVAR/Z sourceFilename=$(sourceDF+"source_file")
    cycleIndex=str2num(suffix)-1
    offset=0
    if (!WaveExists(sourceE) || !WaveExists(sourceLines) || !WaveExists(allCycles) || !WaveExists(counts) || !SVAR_Exists(sourceFilename))
        DoAlert 0, "元の電位・行番号・サイクル情報が見つかりません。"
        return -1
    endif
    n=numpnts(sourceI)
    if (numtype(cycleIndex)!=0 || cycleIndex!=floor(cycleIndex) || cycleIndex<0 || cycleIndex>=numpnts(counts) || cycleIndex>=numpnts(allCycles) || n<4 || numpnts(sourceE)!=n)
        DoAlert 0, "フィット対象のデータ点またはサイクル情報が不足しています。"
        return -1
    endif
    for(i=0;i<cycleIndex;i+=1)
        offset+=counts[i]
    endfor
    if (offset+n>numpnts(sourceLines))
        DoAlert 0, "元ファイルの行番号を対応付けできません。"
        return -1
    endif
    if(CVA_InitFitTable(sourceDF,allCycles)!=0)
        DoAlert 0, "酸化還元電位の表を準備できません。既存の結果は変更していません。"
        return -1
    endif
    return 0
End

// Leave the current data folder at the new isolated scratch copy for graph setup.
Function/S CVA_CreateFitScratch(selection,sourceDF,sourceI,cycleIndex,offset,initialCycle,initialSide)
    String selection,sourceDF
    Wave sourceI
    Variable cycleIndex,offset
    Variable &initialCycle,&initialSide
    String folder,fitDF,suffix=selection[strlen("I_cycle_"),inf]
    Wave sourceE=$(sourceDF+"E_cycle_"+suffix),sourceLines=$(sourceDF+"source_line"),allCycles=$(sourceDF+"summary_cycle")
    SVAR sourceFilename=$(sourceDF+"source_file")
    Variable n=numpnts(sourceI)
    NewDataFolder/O root:Packages
    NewDataFolder/O root:Packages:CVAFit
    SetDataFolder root:Packages:CVAFit
    folder=UniqueName("fit",11,0)
    NewDataFolder/S $folder
    fitDF=GetDataFolder(1)
    Duplicate/O sourceI,fitI
    Duplicate/O sourceE,fitE
    Duplicate/O/R=[offset,offset+n-1] sourceLines,fitLines
    String/G source_file=sourceFilename,source_folder=sourceDF
    NVAR lastCycle=$(sourceDF+"CVA_fit_last_cycle"),lastSide=$(sourceDF+"CVA_fit_last_side")
    initialCycle=lastCycle; initialSide=lastSide
    if(initialCycle<0 || initialCycle>=numpnts(allCycles) || initialCycle!=floor(initialCycle))
        initialCycle=0
    endif
    if(initialSide!=1 && initialSide!=2)
        initialSide=1
    endif
    Variable/G source_cycle=allCycles[cycleIndex], source_index=cycleIndex, selected_side=1, switching=0, valid=0, initialized=0
    return fitDF
End

Function/S CVA_CreateFitGraph(fitDF,sourceDF,cycleIndex,initialCycle,initialSide)
    String fitDF,sourceDF
    Variable cycleIndex,initialCycle,initialSide
    String graph
    Wave allCycles=$(sourceDF+"summary_cycle")
    Wave fitI,fitE,fitLines
    Display/K=1/W=(405,50,1100,620) fitI vs fitE as "CV 2接線フィット"
    graph=S_name
    SetWindow $graph,userdata(fitDF)=fitDF
    CVA_FitStyle(graph,allCycles[cycleIndex])
    CVA_ColorTrace(graph,"fitI",cycleIndex)
    CVA_PadGraphAxes(graph)
    CVA_FitControls(graph,sourceDF,allCycles,initialCycle,initialSide)
    SetWindow $graph,hook(CVAFit)=CVA_FitHook
    CVA_SwitchFit(graph,initialCycle,initialSide)
    return graph
End

// Keep the fitting control layout independent of scratch-data preparation.
Function CVA_FitControls(graph,sourceDF,allCycles,initialCycle,initialSide)
    String graph,sourceDF
    Wave allCycles
    Variable initialCycle,initialSide
    Variable i
    ControlBar/W=$graph 232
    TitleBox fitHelp,win=$graph,pos={10,7},frame=0,title="A–B と C–D をそれぞれ 1 つの走査枝に配置します。",fSize=11
    TitleBox fitNote,win=$graph,pos={10,27},frame=0,title="結果は選択範囲に依存します。酸化・還元は手動で選択します。",fSize=11
    String cycleMenu=""
    for(i=0;i<numpnts(allCycles);i+=1)
        cycleMenu+=CVA_Ordinal(allCycles[i])+";"
    endfor
    String cycleMenuExpr="\""+cycleMenu+"\""
    PopupMenu fitCycle,win=$graph,pos={10,48},size={130,21},title="サイクル",mode=(initialCycle+1),value=#cycleMenuExpr,proc=CVA_FitSelect
    PopupMenu fitSide,win=$graph,pos={155,48},size={120,21},title="対象",mode=initialSide,value="酸化側;還元側",proc=CVA_FitSelect
    Button fitGo,win=$graph,pos={285,48},size={150,21},title="計算・保存",proc=CVA_FitButton
    TitleBox fitTableLabel,win=$graph,pos={10,77},frame=0,title="保存済み交点電位 / V（* は外挿）",fSize=11
    Wave/T fitTable=$(sourceDF+"CVA_fit_table"),fitTitles=$(sourceDF+"CVA_fit_titles")
    ListBox fitTableView,win=$graph,pos={10,98},size={340,120},listWave=fitTable,titleWave=fitTitles,mode=1,fSize=11,widths={75,110,110}
    ShowInfo/W=$graph/CP={0,1}
End

// The fitting graph shows the cycle as an annotation, without a trace legend.
Function CVA_FitStyle(graph,cycle)
    String graph
    Variable cycle
    CVA_GraphAppearance(graph)
    String label=CVA_Ordinal(cycle)
    TextBox/W=$graph/C/N=fitCycleLabel/F=0/B=1/A=RB label
End

// Align with the selected CV graph, including when the user has moved it.
Function CVA_PlaceFitBelow(sourceGraph,fitGraph)
    String sourceGraph,fitGraph
    DoUpdate
    GetWindow $sourceGraph wsize
    Variable left=V_left, top=V_bottom+20
    GetWindow $fitGraph wsize
    Variable width=V_right-V_left, height=V_bottom-V_top
    MoveWindow/W=$fitGraph left,top,left+width,top+height
End

// A single fitting interval must not reverse potential; flat steps are allowed.
Function CVA_FitSameBranch(x,lo,hi)
    Wave x
    Variable lo,hi
    Variable i,direction=0,delta
    if(lo<0 || hi>=numpnts(x) || hi<=lo)
        return 0
    endif
    for(i=lo;i<=hi;i+=1)
        if(numtype(x[i])!=0)
            return 0
        endif
        if(i==lo)
            continue
        endif
        delta=x[i]-x[i-1]
        if((delta>0 && direction<0) || (delta<0 && direction>0))
            return 0
        endif
        if(delta>0)
            direction=1
        elseif(delta<0)
            direction=-1
        endif
    endfor
    return direction!=0
End

// Each interval must stay on one branch; the two branches may differ.
Function CVA_FitRangesOnBranches(x,a,b,c,d)
    Wave x
    Variable a,b,c,d
    return CVA_FitSameBranch(x,a,b) && CVA_FitSameBranch(x,c,d)
End

Function CVA_FitHook(s)
    STRUCT WMWinHookStruct &s
    // Igor suppresses cursormoved when Option/Alt is held. Check after mouse
    // release, keyboard/window changes and before leaving the editor as well.
    if(s.eventCode==0 || s.eventCode==1 || s.eventCode==2 || s.eventCode==5 || s.eventCode==7 || s.eventCode==8 || s.eventCode==11)
        String df=GetUserData(s.winName,"","fitDF")
        NVAR/Z switching=$(df+"switching"),initialized=$(df+"initialized"),valid=$(df+"valid")
        if(NVAR_Exists(switching) && NVAR_Exists(initialized) && NVAR_Exists(valid))
            if(!switching && initialized)
                switching=1
                Variable changed=CVA_StoreCursors(s.winName)
                if(valid && (changed>0 || !CVA_FitSourceMatches(s.winName)))
                    CVA_FitInvalidate(s.winName)
                endif
                switching=0
            endif
        endif
    endif
    return 0
End

Function CVA_FitInvalidate(graph)
    String graph
    String df=GetUserData(graph,"","fitDF")
    NVAR/Z valid=$(df+"valid")
    if(NVAR_Exists(valid))
        valid=0
    endif
    RemoveFromGraph/Z/W=$graph lineAB,lineCD,intersectionY
    if(WhichListItem("fitResult",AnnotationList(graph))>=0)
        TextBox/K/W=$graph/N=fitResult
    endif
    Wave/Z oldResult=$(df+"intersectionY")
    if(WaveExists(oldResult))
        Note/K oldResult
        oldResult=NaN
    endif
End

Function CVA_FitButton(ba) : ButtonControl
    STRUCT WMButtonAction &ba
    if(ba.eventCode!=2)
        return 0
    endif
    String df=GetUserData(ba.win,"","fitDF")
    NVAR/Z direction=$(df+"selected_side")
    if(NVAR_Exists(direction))
        CVA_FitRun(ba.win,direction)
    endif
    return 0
End

// A fit uses an isolated copy. Reject it if the imported cycle or row mapping
// changed since selection, instead of saving old data under current provenance.
Function CVA_FitSourceMatches(graph)
    String graph
    String df=GetUserData(graph,"","fitDF")
    SVAR/Z sourceFolder=$(df+"source_folder")
    NVAR/Z cycleIndex=$(df+"source_index"),cyc=$(df+"source_cycle")
    Wave/Z x=$(df+"fitE"),y=$(df+"fitI"),lines=$(df+"fitLines")
    if(!SVAR_Exists(sourceFolder) || !NVAR_Exists(cycleIndex) || !NVAR_Exists(cyc) || !WaveExists(x) || !WaveExists(y) || !WaveExists(lines))
        return 0
    endif
    return CVA_FitCopyMatchesSource(sourceFolder,cycleIndex,cyc,x,y,lines)
End

Function CVA_FitCopyMatchesSource(sourceFolder,cycleIndex,cyc,x,y,lines)
    String sourceFolder
    Variable cycleIndex,cyc
    Wave x,y,lines
    Wave/Z cycles=$(sourceFolder+"summary_cycle"),counts=$(sourceFolder+"points"),allLines=$(sourceFolder+"source_line")
    if(!WaveExists(cycles) || !WaveExists(counts) || !WaveExists(allLines))
        return 0
    endif
    if(cycleIndex<0 || cycleIndex!=floor(cycleIndex) || cycleIndex>=numpnts(cycles) || cycleIndex>=numpnts(counts))
        return 0
    endif
    Wave/Z sourceE=$(sourceFolder+"E_cycle_"+num2istr(cycleIndex+1)),sourceI=$(sourceFolder+"I_cycle_"+num2istr(cycleIndex+1))
    if(!WaveExists(sourceE) || !WaveExists(sourceI))
        return 0
    endif
    if(cyc!=cycles[cycleIndex] || counts[cycleIndex]!=numpnts(x) || numpnts(lines)!=numpnts(x) || !EqualWaves(x,sourceE,1,0) || !EqualWaves(y,sourceI,1,0))
        return 0
    endif
    return CVA_FitLinesMatch(lines,counts,allLines,cycleIndex)
End

// Compare the selected cycle's original file rows with the isolated copy.
Function CVA_FitLinesMatch(lines,counts,allLines,cycleIndex)
    Wave lines,counts,allLines
    Variable cycleIndex
    Variable i,offset=0
    for(i=0;i<cycleIndex;i+=1)
        if(numtype(counts[i])!=0 || counts[i]<0 || counts[i]!=floor(counts[i]))
            return 0
        endif
        offset+=counts[i]
    endfor
    if(offset+numpnts(lines)>numpnts(allLines))
        return 0
    endif
    for(i=0;i<numpnts(lines);i+=1)
        if(numtype(lines[i])!=0 || lines[i]!=allLines[offset+i])
            return 0
        endif
    endfor
    return 1
End

// Ordinary least squares on acquisition-index interval; centered sums reduce cancellation.
Function CVA_FitLine(x,y,lo,hi,slope,intercept)
    Wave x,y
    Variable lo,hi
    Variable &slope,&intercept
    Variable i,n=hi-lo+1,mx=0,my=0,sxx=0,sxy=0,scale=0,dx
    if(n<3 || lo<0 || hi>=numpnts(x) || hi>=numpnts(y))
        return -1
    endif
    for(i=lo;i<=hi;i+=1)
        if(numtype(x[i])!=0 || numtype(y[i])!=0)
            return -1
        endif
        mx+=x[i]/n; my+=y[i]/n
        scale=max(scale,abs(x[i]))
    endfor
    for(i=lo;i<=hi;i+=1)
        dx=x[i]-mx
        sxx+=dx*dx; sxy+=dx*(y[i]-my)
    endfor
    if(numtype(sxx)!=0 || numtype(sxy)!=0 || sxx<=1e-24*max(1,scale*scale)*n)
        return -1
    endif
    slope=sxy/sxx; intercept=my-slope*mx
    return (numtype(slope)!=0 || numtype(intercept)!=0) ? -1 : 0
End

Function CVA_FitRun(graph,direction)
    String graph
    Variable direction
    String df=GetUserData(graph,"","fitDF"),provenance
    Wave/Z x=$(df+"fitE"), y=$(df+"fitI"), lines=$(df+"fitLines")
    NVAR/Z valid=$(df+"valid"),cyc=$(df+"source_cycle"),cycleIndex=$(df+"source_index")
    SVAR/Z filename=$(df+"source_file"),sourceFolder=$(df+"source_folder")
    Variable pA,pB,pC,pD,m1,b1,m2,b2,xe,ye,extrap
    CVA_FitInvalidate(graph)
    if(!WaveExists(x) || !WaveExists(y) || !WaveExists(lines) || !NVAR_Exists(valid) || !NVAR_Exists(cyc) || !NVAR_Exists(cycleIndex) || !SVAR_Exists(filename) || !SVAR_Exists(sourceFolder))
        DoAlert 0,"フィット用データが見つかりません。"
        return -1
    endif
    CVA_StoreCursors(graph)
    if(!CVA_FitSourceMatches(graph))
        DoAlert 0,"元データが変更されています。サイクルを選び直してから再計算してください。"
        return -1
    endif
    if(CVA_ReadFitCursors(graph,pA,pB,pC,pD)!=0)
        return -1
    endif
    if(CVA_CalculateFit(x,y,pA,pB,pC,pD,m1,b1,m2,b2,xe,ye,extrap)!=0)
        return -1
    endif
    provenance=CVA_FitProvenance(filename,cyc,direction,x,y,lines,pA,pB,pC,pD,m1,b1,m2,b2,xe,ye,extrap)
    CVA_BuildFitDisplay(df,x,pA,pB,pC,pD,m1,b1,m2,b2,xe,ye,provenance)
    if(CVA_SaveFitResult(sourceFolder,cycleIndex,direction,xe,ye,extrap,m1,b1,m2,b2,pA,pB,pC,pD,provenance,x,y,lines)!=0)
        DoAlert 0,"結果表を更新できません。保存済み結果は変更していません。"
        return -1
    endif
    CVA_ShowFitDisplay(graph,direction,xe)
    valid=1
    return 0
End

// Validate attached measured-point cursors before reading their indices.
Function CVA_ReadFitCursors(graph,pA,pB,pC,pD)
    String graph
    Variable &pA,&pB,&pC,&pD
    String names="A;B;C;D",info,trace
    Variable i
    for(i=0;i<4;i+=1)
        String cursorName=StringFromList(i,names)
        info=CsrInfo($cursorName,graph)
        trace=StringByKey("TNAME",info)
        if(strlen(info)==0 || cmpstr(trace,"fitI")!=0 || NumberByKey("ISFREE",info)!=0)
            DoAlert 0,"カーソル A–D をすべて実測曲線に配置してください。"
            return -1
        endif
    endfor
    pA=pcsr(A,graph); pB=pcsr(B,graph); pC=pcsr(C,graph); pD=pcsr(D,graph)
    if(numtype(pA+pB+pC+pD)!=0 || pA!=floor(pA) || pB!=floor(pB) || pC!=floor(pC) || pD!=floor(pD))
        DoAlert 0,"カーソルをデータ点上に配置してください。"
        return -1
    endif
    return 0
End

// Preserve the branch check, centered OLS, parallel threshold and extrapolation rules.
Function CVA_CalculateFit(x,y,pA,pB,pC,pD,m1,b1,m2,b2,xe,ye,extrap)
    Wave x,y
    Variable pA,pB,pC,pD
    Variable &m1,&b1,&m2,&b2,&xe,&ye,&extrap
    Variable a,b,c,d
    a=min(pA,pB); b=max(pA,pB); c=min(pC,pD); d=max(pC,pD)
    if(a<0 || c<0 || b>=numpnts(x) || d>=numpnts(x))
        DoAlert 0,"カーソル範囲がデータの外にあります。"
        return -1
    endif
    if(!CVA_FitRangesOnBranches(x,a,b,c,d))
        DoAlert 0,"A–B または C–D の範囲内に電位の反転があるか、電位が一定です。各範囲をそれぞれ 1 つの走査枝に配置してください。"
        return -1
    endif
    if(CVA_FitLine(x,y,a,b,m1,b1)!=0 || CVA_FitLine(x,y,c,d,m2,b2)!=0)
        DoAlert 0,"各範囲に 3 点以上の有効な点と十分な電位幅が必要です。"
        return -1
    endif
    if(abs(m1-m2)<=1e-8*max(1e-12,max(abs(m1),abs(m2))))
        DoAlert 0,"2 本の傾きが等しいか近すぎるため、交点を求められません。"
        return -1
    endif
    xe=(b2-b1)/(m1-m2); ye=m1*xe+b1
    if(numtype(xe)!=0 || numtype(ye)!=0)
        DoAlert 0,"交点の計算に失敗しました。"
        return -1
    endif
    extrap=(xe<min(x[a],x[b]) || xe>max(x[a],x[b]) || xe<min(x[c],x[d]) || xe>max(x[c],x[d]))
    return 0
End

Function/S CVA_FitProvenance(filename,cyc,direction,x,y,lines,pA,pB,pC,pD,m1,b1,m2,b2,xe,ye,extrap)
    String filename
    Wave x,y,lines
    Variable cyc,direction,pA,pB,pC,pD,m1,b1,m2,b2,xe,ye,extrap
    String provenance
    sprintf provenance, "AB slope (mA/V): %.17g\rAB intercept (mA): %.17g\rCD slope (mA/V): %.17g\rCD intercept (mA): %.17g\rIntersection E (V): %.17g\rIntersection I (mA): %.17g\r",m1,b1,m2,b2,xe,ye
    String cursorDetails
    sprintf cursorDetails,"A point (0-based): %d; E (V): %.17g; I (mA): %.17g\rB point (0-based): %d; E (V): %.17g; I (mA): %.17g\rC point (0-based): %d; E (V): %.17g; I (mA): %.17g\rD point (0-based): %d; E (V): %.17g; I (mA): %.17g\r",pA,x[pA],y[pA],pB,x[pB],y[pB],pC,x[pC],y[pC],pD,x[pD],y[pD]
    String side="Oxidation"
    if(direction==2)
        side="Reduction"
    endif
    provenance="File: "+filename+"\rCycle: "+num2str(cyc)+"\rSide selected: "+side+"\rA line: "+num2istr(lines[pA])+"\rB line: "+num2istr(lines[pB])+"\rC line: "+num2istr(lines[pC])+"\rD line: "+num2istr(lines[pD])+"\r"+cursorDetails+provenance+"Extrapolated: "+num2istr(extrap)+"\rEstimate depends on selected ranges. Side is user-selected; reference electrode is not inferred.\r"
    return provenance
End

// Prepare display waves before saving. A save failure must not append traces.
Function CVA_BuildFitDisplay(df,x,a,b,c,d,m1,b1,m2,b2,xe,ye,provenance)
    String df,provenance
    Wave x
    Variable a,b,c,d,m1,b1,m2,b2,xe,ye
    Make/O/D/N=2 $(df+"lineX"),$(df+"lineAB"),$(df+"lineCD")
    Make/O/D/N=1 $(df+"intersectionX"),$(df+"intersectionY")
    Wave lx=$(df+"lineX"),ly1=$(df+"lineAB"),ly2=$(df+"lineCD"),ix=$(df+"intersectionX"),iy=$(df+"intersectionY")
    lx[0]=min(min(x[a],x[b]),min(min(x[c],x[d]),xe)); lx[1]=max(max(x[a],x[b]),max(max(x[c],x[d]),xe))
    ly1=m1*lx+b1; ly2=m2*lx+b2; ix[0]=xe; iy[0]=ye
    Note/K iy
    Note iy,provenance
End

// Calculation and saved-result restoration share all trace/annotation styling.
Function CVA_ShowFitDisplay(graph,direction,xe)
    String graph
    Variable direction,xe
    String df=GetUserData(graph,"","fitDF"),result
    Wave lx=$(df+"lineX"),ly1=$(df+"lineAB"),ly2=$(df+"lineCD"),ix=$(df+"intersectionX"),iy=$(df+"intersectionY")
    AppendToGraph/W=$graph ly1 vs lx
    AppendToGraph/W=$graph ly2 vs lx
    AppendToGraph/W=$graph iy vs ix
    ModifyGraph/W=$graph rgb(lineAB)=(8738,8738,8738),rgb(lineCD)=(8738,8738,8738),rgb(intersectionY)=(8738,8738,8738),mode(intersectionY)=3,marker(intersectionY)=19
    result=CVA_FitLabel(direction,xe)
    TextBox/W=$graph/C/N=fitResult/F=0/B=1/A=LT result
    CVA_PadGraphAxes(graph)
End

// One read-only table per imported dataset; rows follow summary_cycle order.
Function CVA_InitFitTable(sourceDF,cycles)
    String sourceDF
    Wave cycles
    Wave/T/Z existing=$(sourceDF+"CVA_fit_table")
    Wave/T/Z headings=$(sourceDF+"CVA_fit_titles")
    NVAR/Z lastCycle=$(sourceDF+"CVA_fit_last_cycle"),lastSide=$(sourceDF+"CVA_fit_last_side")
    if(!NVAR_Exists(lastCycle))
        Variable/G $(sourceDF+"CVA_fit_last_cycle")=0
    endif
    if(!NVAR_Exists(lastSide))
        Variable/G $(sourceDF+"CVA_fit_last_side")=1
    endif
    Wave/Z cursors=$(sourceDF+"CVA_fit_cursors")
    if(!CVA_ExistingCursorTableValid(cursors,numpnts(cycles)))
        return -1
    endif
    if(WaveExists(existing) || WaveExists(headings))
        if(!CVA_ExistingFitTableValid(existing,headings,numpnts(cycles)))
            return -1
        endif
        if(!WaveExists(cursors))
            Make/D/N=(numpnts(cycles),2,4) $(sourceDF+"CVA_fit_cursors")=NaN
        endif
        return 0
    endif
    Make/T/N=(numpnts(cycles),3) $(sourceDF+"CVA_fit_table")
    Make/T/N=3 $(sourceDF+"CVA_fit_titles")
    if(!WaveExists(cursors))
        Make/D/N=(numpnts(cycles),2,4) $(sourceDF+"CVA_fit_cursors")=NaN
    endif
    Wave/T table=$(sourceDF+"CVA_fit_table"),titles=$(sourceDF+"CVA_fit_titles")
    titles[0]="Cycle"; titles[1]="酸化 / V"; titles[2]="還元 / V"
    Variable i
    for(i=0;i<numpnts(cycles);i+=1)
        table[i][0]=num2str(cycles[i])
        table[i][1]="—"; table[i][2]="—"
    endfor
    return 0
End

// Missing cursors may be initialized, but an existing table must have this shape.
Function CVA_ExistingCursorTableValid(cursors,cycleCount)
    Wave/Z cursors
    Variable cycleCount
    if(!WaveExists(cursors))
        return 1
    endif
    return !(DimSize(cursors,0)!=cycleCount || DimSize(cursors,1)!=2 || DimSize(cursors,2)!=4)
End

Function CVA_ExistingFitTableValid(table,headings,cycleCount)
    Wave/T/Z table,headings
    Variable cycleCount
    if(!WaveExists(table) || !WaveExists(headings))
        return 0
    endif
    return !(DimSize(table,0)!=cycleCount || DimSize(table,1)!=3 || numpnts(headings)!=3)
End

// Explicit button press replaces only the selected cycle/side's saved result.
Function CVA_SaveFitResult(sourceDF,cycleIndex,direction,xe,ye,extrap,m1,b1,m2,b2,pA,pB,pC,pD,provenance,x,y,lines)
    String sourceDF,provenance
    Wave x,y,lines
    Variable cycleIndex,direction,xe,ye,extrap,m1,b1,m2,b2,pA,pB,pC,pD
    Wave/T/Z table=$(sourceDF+"CVA_fit_table")
    if(!WaveExists(table) || cycleIndex<0 || cycleIndex>=DimSize(table,0) || (direction!=1 && direction!=2))
        return -1
    endif
    String resultName="CVA_ox_"+num2istr(cycleIndex+1)
    if(direction==2)
        resultName="CVA_red_"+num2istr(cycleIndex+1)
    endif
    // Retain the data used for this fit, not only coefficients and indices.
    Make/O/D/N=(numpnts(x),3) $(sourceDF+resultName+"_data")
    Wave snapshot=$(sourceDF+resultName+"_data")
    snapshot[][0]=x[p]; snapshot[][1]=y[p]; snapshot[][2]=lines[p]
    Note/K snapshot
    Note snapshot,"Columns: potential (V), current (mA), source line (1-based).\r"+provenance
    Make/O/D/N=11 $(sourceDF+resultName)
    Wave saved=$(sourceDF+resultName)
    saved[0]=xe; saved[1]=ye; saved[2]=extrap
    saved[3]=m1; saved[4]=b1; saved[5]=m2; saved[6]=b2
    saved[7]=pA; saved[8]=pB; saved[9]=pC; saved[10]=pD
    Note/K saved
    Note saved,provenance
    table[cycleIndex][direction]=num2str(xe)
    if(extrap)
        table[cycleIndex][direction]+="*"
    endif
    return 0
End

// Record measured-point cursor positions independently for every cycle and side.
Function CVA_StoreCursors(graph)
    String graph
    String df=GetUserData(graph,"","fitDF"), names="A;B;C;D",cursorName,info
    SVAR/Z sourceFolder=$(df+"source_folder")
    NVAR/Z cycleIndex=$(df+"source_index"),side=$(df+"selected_side")
    if(!SVAR_Exists(sourceFolder) || !NVAR_Exists(cycleIndex) || !NVAR_Exists(side))
        return -1
    endif
    Wave/Z positions=$(sourceFolder+"CVA_fit_cursors")
    if(!WaveExists(positions))
        return -1
    endif
    if(cycleIndex<0 || cycleIndex!=floor(cycleIndex) || cycleIndex>=DimSize(positions,0) || (side!=1 && side!=2) || DimSize(positions,1)!=2 || DimSize(positions,2)!=4)
        return -1
    endif
    Variable i,point,changed=0
    for(i=0;i<4;i+=1)
        cursorName=StringFromList(i,names)
        info=CsrInfo($cursorName,graph)
        point=-1
        if(strlen(info)>0 && cmpstr(StringByKey("TNAME",info),"fitI")==0 && NumberByKey("ISFREE",info)==0)
            point=pcsr($cursorName,graph)
        endif
        if(numtype(positions[cycleIndex][side-1][i])!=0 || positions[cycleIndex][side-1][i]!=point)
            changed=1
            positions[cycleIndex][side-1][i]=point
        endif
    endfor
    return changed
End

Function CVA_FitSelect(pa) : PopupMenuControl
    STRUCT WMPopupAction &pa
    if(pa.eventCode!=2)
        return 0
    endif
    String graph=pa.win,df=GetUserData(pa.win,"","fitDF")
    NVAR/Z cycleIndex=$(df+"source_index"),side=$(df+"selected_side")
    if(!NVAR_Exists(cycleIndex) || !NVAR_Exists(side))
        return 0
    endif
    Variable nextCycle=cycleIndex,nextSide=side
    if(cmpstr(pa.ctrlName,"fitCycle")==0)
        nextCycle=pa.popNum-1
    elseif(cmpstr(pa.ctrlName,"fitSide")==0)
        nextSide=pa.popNum
    endif
    if(CVA_SwitchFit(pa.win,nextCycle,nextSide)!=0)
        PopupMenu fitCycle,win=$graph,mode=(cycleIndex+1)
        PopupMenu fitSide,win=$graph,mode=side
        DoAlert 0,"選択したサイクルを開けません。既存の解析状態は保持されています。"
    endif
    return 0
End

// Replace only the scratch waves; imported cycle waves and saved fits stay intact.
Function CVA_SwitchFit(graph,nextCycle,nextSide)
    String graph
    Variable nextCycle,nextSide
    String df=GetUserData(graph,"","fitDF")
    SVAR/Z sourceFolder=$(df+"source_folder")
    NVAR/Z cycleIndex=$(df+"source_index"),side=$(df+"selected_side"),cyc=$(df+"source_cycle"),switching=$(df+"switching"),initialized=$(df+"initialized")
    if(!SVAR_Exists(sourceFolder) || !NVAR_Exists(cycleIndex) || !NVAR_Exists(side) || !NVAR_Exists(cyc) || !NVAR_Exists(switching) || !NVAR_Exists(initialized))
        return -1
    endif
    Variable offset
    if(CVA_ValidateFitSwitch(df,sourceFolder,nextCycle,nextSide,offset)!=0)
        return -1
    endif
    Wave allCycles=$(sourceFolder+"summary_cycle"),allLines=$(sourceFolder+"source_line"),positions=$(sourceFolder+"CVA_fit_cursors")
    Wave x=$(df+"fitE"),y=$(df+"fitI"),lines=$(df+"fitLines")
    String suffix=num2istr(nextCycle+1)
    Wave sourceE=$(sourceFolder+"E_cycle_"+suffix),sourceI=$(sourceFolder+"I_cycle_"+suffix)
    Variable n=numpnts(sourceE)
    if(initialized)
        CVA_StoreCursors(graph)
    endif
    switching=1
    CVA_FitInvalidate(graph)
    Redimension/N=(n) x,y,lines
    x=sourceE[p]; y=sourceI[p]; lines=allLines[p+offset]
    cycleIndex=nextCycle; side=nextSide; cyc=allCycles[nextCycle]
    NVAR lastCycle=$(sourceFolder+"CVA_fit_last_cycle"),lastSide=$(sourceFolder+"CVA_fit_last_side")
    lastCycle=nextCycle; lastSide=nextSide
    CVA_FitStyle(graph,cyc)
    CVA_ColorTrace(graph,"fitI",nextCycle)
    CVA_PadGraphAxes(graph)
    CVA_RestoreFitCursors(graph,positions,nextCycle,nextSide,n)
    initialized=1
    CVA_RestoreFit(graph)
    switching=0
    return 0
End

// Preflight must finish before storing cursors or mutating the active editor.
Function CVA_ValidateFitSwitch(df,sourceFolder,nextCycle,nextSide,offset)
    String df,sourceFolder
    Variable nextCycle,nextSide
    Variable &offset
    Wave/Z allCycles=$(sourceFolder+"summary_cycle"),counts=$(sourceFolder+"points"),allLines=$(sourceFolder+"source_line")
    Wave/Z positions=$(sourceFolder+"CVA_fit_cursors")
    Wave/Z x=$(df+"fitE"),y=$(df+"fitI"),lines=$(df+"fitLines")
    if(!WaveExists(allCycles) || !WaveExists(counts) || !WaveExists(allLines) || !WaveExists(positions) || !WaveExists(x) || !WaveExists(y) || !WaveExists(lines))
        return -1
    endif
    if(!CVA_FitSwitchSelectionValid(nextCycle,nextSide,allCycles,counts,positions))
        return -1
    endif
    String suffix=num2istr(nextCycle+1)
    Wave/Z sourceE=$(sourceFolder+"E_cycle_"+suffix),sourceI=$(sourceFolder+"I_cycle_"+suffix)
    if(!WaveExists(sourceE) || !WaveExists(sourceI))
        return -1
    endif
    return CVA_FitSwitchRowsValid(sourceE,sourceI,counts,allLines,nextCycle,offset)
End

// Unlike source matching, a requested switch explicitly rejects nonfinite indices.
Function CVA_FitSwitchSelectionValid(nextCycle,nextSide,allCycles,counts,positions)
    Variable nextCycle,nextSide
    Wave allCycles,counts,positions
    if(numtype(nextCycle)!=0 || nextCycle!=floor(nextCycle) || nextCycle<0 || nextCycle>=numpnts(allCycles) || nextCycle>=numpnts(counts) || (nextSide!=1 && nextSide!=2))
        return 0
    endif
    if(DimSize(positions,0)!=numpnts(allCycles) || DimSize(positions,1)!=2 || DimSize(positions,2)!=4)
        return 0
    endif
    return 1
End

Function CVA_FitSwitchRowsValid(sourceE,sourceI,counts,allLines,nextCycle,offset)
    Wave sourceE,sourceI,counts,allLines
    Variable nextCycle
    Variable &offset
    Variable n=numpnts(sourceE),i
    offset=0
    if(n<4 || numpnts(sourceI)!=n || counts[nextCycle]!=n)
        return -1
    endif
    for(i=0;i<nextCycle;i+=1)
        if(numtype(counts[i])!=0 || counts[i]<0 || counts[i]!=floor(counts[i]))
            return -1
        endif
        offset+=counts[i]
    endfor
    if(offset+n>numpnts(allLines))
        return -1
    endif
    return 0
End

Function CVA_RestoreFitCursors(graph,positions,nextCycle,nextSide,n)
    String graph
    Wave positions
    Variable nextCycle,nextSide,n
    String names="A;B;C;D",cursorName,info
    Variable i,point
    for(i=0;i<4;i+=1)
        cursorName=StringFromList(i,names)
        point=positions[nextCycle][nextSide-1][i]
        if(numtype(point)!=0)
            point=floor((n-1)*i/6)
            positions[nextCycle][nextSide-1][i]=point
        endif
        if(point>=0 && point<n && point==floor(point))
            Cursor/P/W=$graph $cursorName,fitI,point
        else
            info=CsrInfo($cursorName,graph)
            if(strlen(info)>0)
                Cursor/K/W=$graph $cursorName
            endif
        endif
    endfor
End

// A saved fit is current only if its four saved cursor indices still match.
Function CVA_RestoreFit(graph)
    String graph
    String df=GetUserData(graph,"","fitDF"),resultName
    SVAR/Z sourceFolder=$(df+"source_folder")
    NVAR/Z cycleIndex=$(df+"source_index"),side=$(df+"selected_side"),valid=$(df+"valid")
    if(!SVAR_Exists(sourceFolder) || !NVAR_Exists(cycleIndex) || !NVAR_Exists(side) || !NVAR_Exists(valid))
        return -1
    endif
    resultName="CVA_ox_"+num2istr(cycleIndex+1)
    if(side==2)
        resultName="CVA_red_"+num2istr(cycleIndex+1)
    endif
    Wave/Z saved=$(sourceFolder+resultName),snapshot=$(sourceFolder+resultName+"_data"),positions=$(sourceFolder+"CVA_fit_cursors"),x=$(df+"fitE"),y=$(df+"fitI"),lines=$(df+"fitLines")
    if(!CVA_SavedFitMatches(saved,snapshot,positions,x,y,lines,cycleIndex,side))
        return 0
    endif
    Variable xe=saved[0],ye=saved[1],m1=saved[3],b1=saved[4],m2=saved[5],b2=saved[6]
    Variable a=saved[7],b=saved[8],c=saved[9],d=saved[10]
    CVA_BuildFitDisplay(df,x,a,b,c,d,m1,b1,m2,b2,xe,ye,note(saved))
    CVA_ShowFitDisplay(graph,side,xe)
    valid=1
    return 0
End

// A complete finite snapshot and four exact saved cursor positions are required.
Function CVA_SavedFitMatches(saved,snapshot,positions,x,y,lines,cycleIndex,side)
    Wave/Z saved,snapshot,positions,x,y,lines
    Variable cycleIndex,side
    if(!WaveExists(saved) || !WaveExists(snapshot) || !WaveExists(positions) || !WaveExists(x) || !WaveExists(y) || !WaveExists(lines))
        return 0
    endif
    if(!CVA_SavedFitValuesValid(saved,snapshot,x))
        return 0
    endif
    if(!CVA_FitSnapshotMatches(snapshot,x,y,lines))
        return 0
    endif
    return CVA_SavedCursorsMatch(saved,positions,x,cycleIndex,side)
End

// All eleven stored values must be finite, including the extrapolation flag.
Function CVA_SavedFitValuesValid(saved,snapshot,x)
    Wave saved,snapshot,x
    if(numpnts(saved)!=11 || DimSize(snapshot,0)!=numpnts(x) || DimSize(snapshot,1)!=3)
        return 0
    endif
    Variable i
    for(i=0;i<11;i+=1)
        if(numtype(saved[i])!=0)
            return 0
        endif
    endfor
    return 1
End

// Check all acquisition points, not just the selected ranges.
Function CVA_FitSnapshotMatches(snapshot,x,y,lines)
    Wave snapshot,x,y,lines
    Variable i
    for(i=0;i<numpnts(x);i+=1)
        if(numtype(snapshot[i][0]+snapshot[i][1]+snapshot[i][2])!=0 || snapshot[i][0]!=x[i] || snapshot[i][1]!=y[i] || snapshot[i][2]!=lines[i])
            return 0
        endif
    endfor
    return 1
End

Function CVA_SavedCursorsMatch(saved,positions,x,cycleIndex,side)
    Wave saved,positions,x
    Variable cycleIndex,side
    Variable i
    for(i=0;i<4;i+=1)
        if(saved[7+i]!=floor(saved[7+i]) || numtype(positions[cycleIndex][side-1][i])!=0 || saved[7+i]!=positions[cycleIndex][side-1][i] || saved[7+i]<0 || saved[7+i]>=numpnts(x))
            return 0
        endif
    endfor
    return 1
End

// Italic voltage symbol, upright subscript and unit.
Function/S CVA_FitLabel(side,voltage)
    Variable side,voltage
    String subscript="ox.",formattedVoltage
    if(side==2)
        subscript="red."
    endif
    sprintf formattedVoltage, "%.3f", voltage
    return "\\Z14\\f02V\\f00\\B"+subscript+"\\M\\Z14 = "+formattedVoltage+" V"
End
