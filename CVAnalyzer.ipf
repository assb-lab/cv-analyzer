#pragma rtGlobals=3
#pragma version=0.001
// Semantic version: 0.0.1 (Igor pragma uses a numeric version).

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
    NewPanel/N=CVA_Panel/W=(20,50,385,510) as "CV Analyzer"
    TitleBox heading,pos={20,15},size={325,30},frame=0,title="CV Analyzer"
    TitleBox heading,fSize=20,fStyle=1,fColor=(6500,14000,29000)
    TitleBox version,pos={286,23},frame=0,title="v0.0.1",fSize=11,fColor=(24000,27000,32000)
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
    GroupBox notesGroup,pos={15,332},size={335,108},title="解析について",fSize=12,fStyle=1
    TitleBox note1,pos={30,358},frame=0,title="電位・電流は測定値を使用し、補正しません。",fSize=11
    TitleBox note2,pos={30,379},frame=0,title="電荷量は電流の正負別に時間積分します。",fSize=11
    TitleBox note3,pos={30,400},frame=0,title="stepwise は測定条件の確定後に対応予定です。",fSize=11
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
        problem="Not an EC-Lab ASCII MPT file."
    endif
    if (strlen(problem)==0)
        FReadLine ref,line
        lineNo+=1
        if (strsearch(line,"Nb header lines",0)<0)
            problem="Missing Nb header lines declaration."
        else
            headerToken=StringFromList(1,line,":")
            headerToken=ReplaceString("\r",headerToken,"")
            headerToken=ReplaceString("\n",headerToken,"")
            headerCount=str2num(headerToken)
            if (!CVA_IsNumber(headerToken) || numtype(headerCount)!=0 || headerCount<3 || headerCount>100000 || headerCount!=floor(headerCount))
                problem="Invalid header line count."
            endif
        endif
    endif
    if (strlen(problem)==0)
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
        if (!CVA_IsNumber(StringFromList(cT,line,"\t")) || !CVA_IsNumber(StringFromList(cE,line,"\t")) || !CVA_IsNumber(StringFromList(cI,line,"\t")) || !CVA_IsNumber(StringFromList(cC,line,"\t")))
            problem="Invalid or missing required numeric value at line "+num2str(lineNo)+"."
            break
        endif
        t=str2num(StringFromList(cT,line,"\t"))
        e=str2num(StringFromList(cE,line,"\t"))
        current=str2num(StringFromList(cI,line,"\t"))
        cycle=str2num(StringFromList(cC,line,"\t"))
        if (numtype(t)!=0 || numtype(e)!=0 || numtype(current)!=0 || numtype(cycle)!=0)
            problem="Invalid or missing required numeric value at line "+num2str(lineNo)+"."
            break
        endif
        if (t<lastT || cycle<lastC || cycle!=floor(cycle))
            problem="Time or cycle number is out of order at line "+num2str(lineNo)+"."
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
    Make/D/N=(groups) summary_cycle, points, E_min_V, E_max_V, I_max_mA, E_at_Imax_V, I_min_mA, E_at_Imin_V, Q_positive_mAh, Q_negative_mAh, duration_s
    String legendText="",graphName="",commonNote="File: "+source_filename+"\rCycles and source lines (inclusive, 1-based):\r"
    for(j=0;j<groups;j+=1)
        finish=CVA_CycleEnd(cycle_number,start)
        CVA_SummarizeCycle(j,start,finish)
        CVA_PlotCycle(j,start,finish,graphName,legendText,commonNote)
        start=finish+1
    endfor
    CVA_AnnotateWaves(commonNote)
    CVA_StyleGraph(graphName,legendText)
    CVA_ShowSummary()
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
    Variable start,finish=start,n=numpnts(cycle_number)
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
    Wave time_s,Ewe_V,current_mA,cycle_number
    Wave summary_cycle,points,E_min_V,E_max_V,I_max_mA,E_at_Imax_V,I_min_mA,E_at_Imin_V,Q_positive_mAh,Q_negative_mAh,duration_s
    Variable i,dt,a,b,frac,qp,qn
    summary_cycle[j]=cycle_number[start]; points[j]=finish-start+1
    duration_s[j]=time_s[finish]-time_s[start]
    E_min_V[j]=Ewe_V[start]; E_max_V[j]=Ewe_V[start]
    I_max_mA[j]=current_mA[start]; I_min_mA[j]=current_mA[start]
    E_at_Imax_V[j]=Ewe_V[start]; E_at_Imin_V[j]=Ewe_V[start]
    qp=0; qn=0
    for(i=start;i<=finish;i+=1)
        E_min_V[j]=min(E_min_V[j],Ewe_V[i]); E_max_V[j]=max(E_max_V[j],Ewe_V[i])
        if(current_mA[i]>I_max_mA[j])
            I_max_mA[j]=current_mA[i]; E_at_Imax_V[j]=Ewe_V[i]
        endif
        if(current_mA[i]<I_min_mA[j])
            I_min_mA[j]=current_mA[i]; E_at_Imin_V[j]=Ewe_V[i]
        endif
        if(i>start)
            dt=(time_s[i]-time_s[i-1])/3600
            a=current_mA[i-1]; b=current_mA[i]
            if(a>=0 && b>=0)
                qp+=dt*(a+b)/2
            elseif(a<=0 && b<=0)
                qn+=dt*(a+b)/2
            else
                frac=abs(a)/(abs(a)+abs(b))
                if(a>0)
                    qp+=dt*frac*a/2; qn+=dt*(1-frac)*b/2
                else
                    qn+=dt*frac*a/2; qp+=dt*(1-frac)*b/2
                endif
            endif
        endif
    endfor
    Q_positive_mAh[j]=qp; Q_negative_mAh[j]=qn
End

// Create cycle waves and record their source lines.
Function CVA_CreateCycleWaves(j,start,finish,commonNote)
    Variable j,start,finish
    String &commonNote
    Wave Ewe_V,current_mA,cycle_number,source_line
    SVAR source_filename
    String en="E_cycle_"+num2str(j+1), iname="I_cycle_"+num2str(j+1)
    Duplicate/O/R=[start,finish] Ewe_V,$en
    Duplicate/O/R=[start,finish] current_mA,$iname
    Wave ew=$en, iw=$iname
    String cycleNote="File: "+source_filename+"\rCycle: "+num2str(cycle_number[start])+"\rStart line: "+num2istr(source_line[start])+"\rEnd line: "+num2istr(source_line[finish])+"\r"
    Note/K ew
    Note/K iw
    Note ew,cycleNote
    Note iw,cycleNote
    commonNote+="Cycle "+num2str(cycle_number[start])+": "+num2istr(source_line[start])+" - "+num2istr(source_line[finish])+"\r"
End

Function CVA_PlotCycle(j,start,finish,graphName,legendText,commonNote)
    Variable j,start,finish
    String &graphName,&legendText,&commonNote
    Wave cycle_number
    CVA_CreateCycleWaves(j,start,finish,commonNote)
    String en="E_cycle_"+num2str(j+1), iname="I_cycle_"+num2str(j+1)
    Wave ew=$en, iw=$iname
    if(j==0)
        Display/K=1/W=(405,50,965,510) iw vs ew as "CV cycles"
        graphName=S_name
    else
        AppendToGraph/W=$graphName iw vs ew
    endif
    CVA_ColorTrace(graphName,iname,j)
    if (j>0)
        legendText+="\r"
    endif
    legendText+="\\s("+iname+") "+CVA_Ordinal(cycle_number[start])
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

Function CVA_StyleGraph(graphName,legendText)
    String graphName,legendText
    // Igor graph dimensions are points (72 points/inch), before expansion.
    ModifyGraph/W=$graphName mirror=1, tick=2, expand=2, gfSize=12, width=226.77165, height=170.07874, margin(left)=56, margin(bottom)=39, margin(right)=14, margin(top)=14
    ModifyGraph/W=$graphName manTick(bottom)={0,1,0,1},manMinor(bottom)={4,50}
    Label/W=$graphName bottom "\\Z14Cell Voltage \\f02E\\f00\\Bwe\\M\\Z14 / V"
    Label/W=$graphName left "\\Z14Current \\f02I\\f00 / mA"
    Legend/W=$graphName/C/N=text0/F=0/B=1/A=RB legendText
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
    Edit/K=1/W=(20,530,385,770) summary_cycle,points,E_min_V,E_max_V,I_max_mA,E_at_Imax_V,I_min_mA,E_at_Imin_V,Q_positive_mAh,Q_negative_mAh,duration_s as "CV cycle summary"
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
