#pragma TextEncoding = "UTF-8"
#pragma IgorVersion = 8.00
#pragma rtFunctionErrors=1
#pragma rtGlobals=3

// Load this procedure together with CVAnalyzer.ipf in a disposable Igor Pro 8
// experiment, compile, and run CVAT_Run(). No imported/user waves are modified;
// the split-import check writes two temporary MPT files and removes its own
// root:CVAnalyzer folder, windows and files afterwards.
// These are native Igor tests; merely reading this file is not an execution pass.
Function CVAT_Assert(condition,message)
    Variable condition
    String message
    if(!condition)
        Abort "CV Analyzer regression failed: "+message
    endif
End

Function CVAT_Run()
    String oldDF=GetDataFolder(1)
    NewDataFolder/O root:Packages
    SetDataFolder root:Packages
    String folder=UniqueName("CVAReview",11,0)
    NewDataFolder/S $folder
    String testDF=GetDataFolder(1)
    CVAT_Math()
    CVAT_CrossBranch()
    CVAT_DataRows()
    CVAT_Split()
    CVAT_SplitImport()
    CVAT_Charge(testDF)
    CVAT_State(testDF)
    CVAT_Editor(testDF)
    SetDataFolder $oldDF
    KillDataFolder $testDF
    Print "CV Analyzer native Igor regression checks passed."
End

Function CVAT_DataRows()
    Variable t,e,current,cycle
    String problem=CVA_ParseDataRow("1\t0.5\t-2\t3",12,0,1,2,3,1,3,t,e,current,cycle)
    CVAT_Assert(strlen(problem)==0 && t==1 && e==0.5 && current==-2 && cycle==3,"numeric row allows equal time and cycle")
    problem=CVA_ParseDataRow("2s\t0.5\t-2\t3",13,0,1,2,3,1,3,t,e,current,cycle)
    CVAT_Assert(cmpstr(problem,"Invalid or missing required numeric value at line 13.")==0,"numeric prefix rejected with source line")
    problem=CVA_ParseDataRow("2\t0.5\t-2",14,0,1,2,3,1,3,t,e,current,cycle)
    CVAT_Assert(cmpstr(problem,"Invalid or missing required numeric value at line 14.")==0,"missing cycle rejected")
    problem=CVA_ParseDataRow("2\t1e999\t-2\t3",15,0,1,2,3,1,3,t,e,current,cycle)
    CVAT_Assert(cmpstr(problem,"Invalid or missing required numeric value at line 15.")==0,"nonfinite conversion rejected before ordering")
    problem=CVA_ParseDataRow("0\t0.5\t-2\t3",16,0,1,2,3,1,3,t,e,current,cycle)
    CVAT_Assert(cmpstr(problem,"Time or cycle number is out of order at line 16.")==0,"decreasing time rejected")
    problem=CVA_ParseDataRow("2\t0.5\t-2\t2",17,0,1,2,3,1,3,t,e,current,cycle)
    CVAT_Assert(cmpstr(problem,"Time or cycle number is out of order at line 17.")==0,"decreasing cycle rejected")
    problem=CVA_ParseDataRow("2\t0.5\t-2\t3.5",18,0,1,2,3,1,3,t,e,current,cycle)
    CVAT_Assert(cmpstr(problem,"Time or cycle number is out of order at line 18.")==0,"fractional cycle rejected")
End

// Split CV: grouping by segment, labels and one-sided window checks.
Function CVAT_Split()
    Make/FREE/D cycles={1,1,2,2,2,2,3,3}
    Make/FREE/D segments={1,1,1,1,2,2,2,2}
    Wave/Z none=$""
    CVAT_Assert(CVA_CountCycles(cycles,none)==3,"normal CV groups by cycle number only")
    CVAT_Assert(CVA_CountCycles(cycles,segments)==4,"segment change splits a repeated cycle number")
    CVAT_Assert(CVA_CycleEnd(cycles,segments,2)==3 && CVA_CycleEnd(cycles,none,2)==5,"group end respects segment")
    CVAT_Assert(cmpstr(CVA_SegmentLabel(1,1,1),"Ox-side 1st")==0 && cmpstr(CVA_SegmentLabel(1,2,3),"Red-side 3rd")==0,"half-window labels")
    CVAT_Assert(cmpstr(CVA_SegmentLabel(2,2,2),"Full 2nd")==0 && cmpstr(CVA_SegmentLabel(0,1,11),"11th")==0,"full-window and plain labels")
    Make/FREE/D e={2,2.001,2.003,2.01,2.2,2.0}
    CVAT_Assert(CVA_SplitStartDirection(e,0,5)==1,"upward start detected past threshold")
    e={2,1.999,1.99,1.8,2.0,2.0}
    CVAT_Assert(CVA_SplitStartDirection(e,0,5)==-1,"downward start detected")
    e={2,2.001,1.999,2.002,2.0,2.0}
    CVAT_Assert(CVA_SplitStartDirection(e,0,5)==0,"start within threshold is undetermined")
    Make/FREE/D ox={2,2.2,2.4,2.2,2.0,1.98}
    CVAT_Assert(strlen(CVA_CheckHalfWindow(ox,0,5,1))==0,"oxidation half window accepted with small return overshoot")
    CVAT_Assert(strlen(CVA_CheckHalfWindow(ox,0,5,2))>0,"oxidation half window rejected in reduction mode")
    Make/FREE/D full={2,2.2,2.4,2.2,2.0,1.6}
    CVAT_Assert(strlen(CVA_CheckHalfWindow(full,0,5,1))>0,"full window rejected as oxidation half window")
    Make/FREE/D red={2,1.5,1.0,1.5,2.0,2.02}
    CVAT_Assert(strlen(CVA_CheckHalfWindow(red,0,5,2))==0,"reduction half window accepted")
    CVAT_Assert(strlen(CVA_CheckHalfWindow(red,0,5,1))>0,"reduction half window rejected in oxidation mode")
End

Function CVAT_WriteMPT(path,rows)
    String path,rows
    Variable ref,i
    Open ref as path
    fprintf ref,"EC-Lab ASCII FILE\nNb header lines : 5\n\nCyclic Voltammetry\ntime/s\tEwe/V\t<I>/mA\tcycle number\n"
    for(i=0;i<ItemsInList(rows);i+=1)
        fprintf ref,"%s\n",StringFromList(i,rows)
    endfor
    Close ref
End

// End-to-end split import. The full-window file deliberately continues the
// cycle counter (2) so the segment boundary alone must separate the groups.
Function CVAT_SplitImport()
    String oldDF=GetDataFolder(1),dir=SpecialDirPath("Temporary",0,0,0)
    String halfPath=dir+"CVATSplitHalf.mpt",fullPath=dir+"CVATSplitFull.mpt"
    String half="0\t2.0\t0.01\t1;10\t2.1\t0.02\t1;20\t2.2\t0.03\t1;30\t2.1\t-0.01\t1;40\t2.0\t-0.02\t1;50\t2.1\t0.02\t2;60\t2.2\t0.03\t2;70\t2.1\t-0.01\t2;80\t2.0\t-0.02\t2"
    String full="90\t2.0\t0.01\t2;100\t2.2\t0.02\t2;110\t2.4\t0.05\t2;120\t2.2\t-0.01\t2;130\t2.0\t-0.02\t2;140\t1.8\t-0.05\t3;150\t1.6\t-0.08\t3;160\t1.8\t-0.03\t3;170\t2.0\t0.01\t3"
    CVAT_WriteMPT(halfPath,half)
    CVAT_WriteMPT(fullPath,full)
    Variable createdRoot=!DataFolderExists("root:CVAnalyzer")
    NewDataFolder/O root:CVAnalyzer
    SetDataFolder root:CVAnalyzer
    String folder="root:CVAnalyzer:"+UniqueName("CVATSplitHalf",11,0)+":"
    SetDataFolder $oldDF
    String windowsBefore=WinList("*",";","WIN:3")
    CVAT_Assert(CVA_ImportSplit(halfPath,fullPath,3)==0,"split import succeeds")
    CVAT_Assert(cmpstr(GetDataFolder(1),oldDF)==0,"split import restores current data folder")
    String windowsAfter=WinList("*",";","WIN:3"),win
    Variable i
    for(i=0;i<ItemsInList(windowsAfter);i+=1)
        win=StringFromList(i,windowsAfter)
        if(WhichListItem(win,windowsBefore)<0)
            DoWindow/K $win
        endif
    endfor
    Wave/T labels=$(folder+"summary_label")
    Wave segments=$(folder+"summary_segment"),points=$(folder+"points"),cycles=$(folder+"summary_cycle"),lines=$(folder+"source_line")
    CVAT_Assert(numpnts(labels)==4 && numpnts(points)==4,"four groups across two files")
    CVAT_Assert(cmpstr(labels[0],"Ox-side 1st")==0 && cmpstr(labels[1],"Ox-side 2nd")==0 && cmpstr(labels[2],"Full 2nd")==0 && cmpstr(labels[3],"Full 3rd")==0,"split labels")
    CVAT_Assert(segments[1]==1 && segments[2]==2 && cycles[1]==2 && cycles[2]==2,"repeated cycle number separated by segment")
    CVAT_Assert(points[0]==5 && points[1]==4 && points[2]==5 && points[3]==4,"group point counts")
    CVAT_Assert(lines[0]==6 && lines[9]==6 && lines[17]==14,"source lines restart for the second file")
    Wave e3=$(folder+"E_cycle_3")
    CVAT_Assert(strsearch(note(e3),"File: CVATSplitFull.mpt\r",0)>=0 && strsearch(note(e3),"Segment: Full 2nd\r",0)>=0,"full-window cycle note names its file")
    CVAT_Assert(cmpstr(CVA_CycleSourceFile(folder,2),fullPath)==0 && cmpstr(CVA_CycleSourceFile(folder,1),halfPath)==0,"cycle source file follows segment")
    CVAT_Assert(cmpstr(CVA_CycleLabelAt(folder,3),"Full 3rd")==0,"cycle label lookup")
    CVAT_Assert(CVA_InitFitTable(folder,cycles)==0,"split fit table initialized")
    Wave/T table=$(folder+"CVA_fit_table")
    NVAR lastSide=$(folder+"CVA_fit_last_side")
    CVAT_Assert(cmpstr(table[2][0],"Full 2nd")==0 && lastSide==1,"fit table labels and oxidation-first side")
    NVAR splitSide=$(folder+"split_side")
    splitSide=2
    KillVariables/Z $(folder+"CVA_fit_last_side")
    CVAT_Assert(CVA_InitFitTable(folder,cycles)==0,"split fit table re-initialized")
    NVAR reducedSide=$(folder+"CVA_fit_last_side")
    CVAT_Assert(reducedSide==2 && cmpstr(CVA_SegmentLabel(1,splitSide,1),"Red-side 1st")==0,"reduction-first side selected initially")
    SVAR kind=$(folder+"measurement_type")
    CVAT_Assert(strsearch(kind,"oxidation side",0)>=0,"measurement type records the split side")
    KillDataFolder $folder
    if(createdRoot)
        KillDataFolder root:CVAnalyzer
    endif
    DeleteFile/Z halfPath
    DeleteFile/Z fullPath
End

Function CVAT_Charge(testDF)
    String testDF
    NewDataFolder/S charge
    Make/D/N=2 time_s={0,3600},current_mA={2,4}
    Make/D/N=1 Q_positive_mAh,Q_negative_mAh
    CVA_SummarizeCharge(0,0,1)
    CVAT_Assert(Q_positive_mAh[0]==3 && Q_negative_mAh[0]==0,"positive trapezoid charge")
    current_mA={-2,-4}
    CVA_SummarizeCharge(0,0,1)
    CVAT_Assert(Q_positive_mAh[0]==0 && Q_negative_mAh[0]==-3,"negative trapezoid charge")
    current_mA={2,-2}
    CVA_SummarizeCharge(0,0,1)
    CVAT_Assert(Q_positive_mAh[0]==0.5 && Q_negative_mAh[0]==-0.5,"positive-to-negative zero crossing")
    current_mA={-2,2}
    CVA_SummarizeCharge(0,0,1)
    CVAT_Assert(Q_positive_mAh[0]==0.5 && Q_negative_mAh[0]==-0.5,"negative-to-positive zero crossing")
    current_mA={0,0}
    CVA_SummarizeCharge(0,0,1)
    CVAT_Assert(Q_positive_mAh[0]==0 && Q_negative_mAh[0]==0,"zero current charge")
    SetDataFolder $testDF
End

Function CVAT_Math()
    Make/FREE/D/N=12 x=p/10,y=2*x+1
    Variable m,b
    CVAT_Assert(CVA_FitLine(x,y,0,11,m,b)==0,"increasing OLS succeeds")
    CVAT_Assert(abs(m-2)<1e-12 && abs(b-1)<1e-12,"increasing OLS coefficients")
    CVAT_Assert(CVA_FitSameBranch(x,0,11),"increasing branch")
    x=1.1-p/10; y=2*x+1
    CVAT_Assert(CVA_FitLine(x,y,0,11,m,b)==0,"decreasing OLS succeeds")
    CVAT_Assert(abs(m-2)<1e-12 && abs(b-1)<1e-12,"decreasing OLS coefficients")
    CVAT_Assert(CVA_FitSameBranch(x,0,11),"decreasing branch")
    CVAT_Assert(CVA_FitLine(x,y,0,1,m,b)!=0,"two points rejected")
    x=1
    CVAT_Assert(CVA_FitLine(x,y,0,11,m,b)!=0,"constant potential rejected")
    CVAT_Assert(!CVA_FitSameBranch(x,0,11),"flat branch rejected")
    x=p/10; x[4]=x[3]
    CVAT_Assert(CVA_FitSameBranch(x,0,11),"flat step allowed")
    x[4]=x[3]-1e-12
    CVAT_Assert(!CVA_FitSameBranch(x,0,11),"tiny reversal rejected")
    x=p/10; x[4]=NaN
    CVAT_Assert(!CVA_FitSameBranch(x,0,11),"nonfinite potential rejected")
    CVAT_Assert(CVA_FitLine(x,y,0,11,m,b)!=0,"nonfinite OLS input rejected")
End

// Two intervals may use opposite branches, but neither interval may turn.
Function CVAT_CrossBranch()
    Make/FREE/D/N=12 x={0,0.2,0.4,0.6,0.8,1,0.8,0.6,0.4,0.2,0,-0.2},y
    y=(p<=5) ? 2*x+1 : 4*x-0.5
    Variable m1,b1,m2,b2,xe,ye,extrap
    CVAT_Assert(CVA_FitRangesOnBranches(x,0,3,7,10),"opposite branches accepted")
    CVAT_Assert(!CVA_FitRangesOnBranches(x,3,7,8,10),"first interval crossing turn rejected")
    CVAT_Assert(!CVA_FitRangesOnBranches(x,0,3,3,7),"second interval crossing turn rejected")
    CVAT_Assert(CVA_FitRangesOnBranches(x,0,2,2,4),"same branch remains accepted")
    CVAT_Assert(CVA_CalculateFit(x,y,0,3,7,10,m1,b1,m2,b2,xe,ye,extrap)==0,"opposite branch calculation")
    CVAT_Assert(abs(m1-2)<1e-12 && abs(b1-1)<1e-12 && abs(m2-4)<1e-12 && abs(b2+0.5)<1e-12,"opposite branch coefficients")
    CVAT_Assert(abs(xe-0.75)<1e-12 && abs(ye-2.5)<1e-12,"opposite branch intersection")
    CVAT_Assert(CVA_CalculateFit(x,y,10,7,3,0,m1,b1,m2,b2,xe,ye,extrap)==0,"reversed order calculation")
    CVAT_Assert(abs(xe-0.75)<1e-12 && abs(ye-2.5)<1e-12,"reversed order intersection unchanged")
End

Function CVAT_Cursors(graph,a,b,c,d)
    String graph
    Variable a,b,c,d
    Cursor/P/W=$graph A,fitI,a
    Cursor/P/W=$graph B,fitI,b
    Cursor/P/W=$graph C,fitI,c
    Cursor/P/W=$graph D,fitI,d
End

Function CVAT_State(testDF)
    String testDF
    NewDataFolder/S source
    String sourceDF=GetDataFolder(1)
    String/G source_file="Synthetic CV regression data"
    Make/D/N=2 summary_cycle={1,2},points={12,12}
    Make/D/N=24 source_line=p+101
    Make/D/N=12 E_cycle_1=p/10,I_cycle_1
    I_cycle_1=(p<6) ? 2*E_cycle_1+1 : 4*E_cycle_1-1
    Make/D/N=12 E_cycle_2=1.1-p/10,I_cycle_2
    I_cycle_2=(p<6) ? 2*E_cycle_2+1 : 4*E_cycle_2-1
    CVAT_Assert(CVA_InitFitTable(sourceDF,summary_cycle)==0,"initialize result table")
    SetDataFolder $testDF
    NewDataFolder/S scratch
    String fitDF=GetDataFolder(1)
    String/G source_folder=sourceDF,source_file="Synthetic CV regression data"
    Variable/G source_cycle=1,source_index=0,selected_side=1,switching=0,valid=0,initialized=0
    Make/D/N=12 fitE,fitI,fitLines
    Display/K=1 fitI vs fitE as "CV Analyzer disposable regression graph"
    String graph=S_name
    SetWindow $graph,userdata(fitDF)=fitDF
    // Deliberately omit the hook: switching/calculation must capture cursors
    // even when Igor suppresses or has not delivered a cursor event.
    CVAT_Assert(CVA_SwitchFit(graph,0,1)==0,"initial cycle selection")
    CVAT_Cursors(graph,0,4,7,11)
    CVAT_Assert(CVA_FitSourceMatches(graph),"source matches copied cycle")
    CVAT_Assert(CVA_FitRun(graph,1)==0 && valid==1,"oxidation fit saved")
    Wave ox=$(sourceDF+"CVA_ox_1"),oxData=$(sourceDF+"CVA_ox_1_data")
    CVAT_Assert(abs(ox[0]-1)<1e-12 && abs(ox[1]-3)<1e-12,"known intersection (1 V, 3 mA)")
    CVAT_Assert(ox[2]==1 && DimSize(oxData,0)==12 && DimSize(oxData,1)==3,"extrapolation and source snapshot")
    CVAT_Assert(oxData[0][0]==0 && oxData[0][2]==101,"snapshot potential/source row")
    Wave displayX=$(fitDF+"lineX"),displayAB=$(fitDF+"lineAB"),displayCD=$(fitDF+"lineCD"),displayY=$(fitDF+"intersectionY")
    Duplicate/FREE displayX,expectedX
    Duplicate/FREE displayAB,expectedAB
    Duplicate/FREE displayCD,expectedCD
    String expectedNote=note(ox)
    CVAT_Assert(cmpstr(note(displayY),expectedNote)==0,"calculated display retains saved provenance")
    CVAT_Assert(strsearch(expectedNote,"A line: 101\r",0)>=0 && strsearch(expectedNote,"Side selected: Oxidation\r",0)>=0,"provenance records row and selected side")
    CVAT_Assert(CVA_SwitchFit(graph,0,1)==0 && valid==1,"same selection restores saved fit")
    CVAT_Assert(EqualWaves(displayX,expectedX,1,0) && EqualWaves(displayAB,expectedAB,1,0) && EqualWaves(displayCD,expectedCD,1,0),"restoration reproduces calculated display waves")
    CVAT_Assert(cmpstr(note(displayY),expectedNote)==0,"restoration retains saved provenance")
    CVAT_Assert(ItemsInList(TraceNameList(graph,";",1))==4,"restoration draws each fit trace once")
    CVAT_Assert(CVA_SavedFitMatches(ox,oxData,$(sourceDF+"CVA_fit_cursors"),fitE,fitI,fitLines,0,1),"saved result eligibility")
    Variable originalSlope=ox[3]
    ox[3]=NaN
    CVAT_Assert(!CVA_SavedFitMatches(ox,oxData,$(sourceDF+"CVA_fit_cursors"),fitE,fitI,fitLines,0,1),"nonfinite saved coefficient blocks restoration")
    ox[3]=originalSlope
    oxData[5][2]+=1
    CVAT_Assert(!CVA_SavedFitMatches(ox,oxData,$(sourceDF+"CVA_fit_cursors"),fitE,fitI,fitLines,0,1),"snapshot row outside selected cursors still checked")
    oxData[5][2]-=1
    Wave/T table=$(sourceDF+"CVA_fit_table")
    String savedCell=table[0][1]
    Wave positions=$(sourceDF+"CVA_fit_cursors")
    Duplicate/FREE positions,expectedPositions
    CVAT_Assert(CVA_SwitchFit(graph,2,1)!=0,"invalid next cycle rejected")
    CVAT_Assert(valid==1 && source_index==0 && selected_side==1 && switching==0,"failed switch preserves selected state")
    CVAT_Assert(EqualWaves(positions,expectedPositions,1,0) && cmpstr(table[0][1],savedCell)==0,"failed switch preserves cursors and saved table")
    CVAT_Assert(pcsr(A,graph)==0 && cmpstr(note(displayY),expectedNote)==0,"failed switch preserves displayed result")
    GetAxis/Q/W=$graph bottom
    CVAT_Assert(V_min<1 && V_max>1,"intersection visible on voltage axis")
    GetAxis/Q/W=$graph left
    CVAT_Assert(V_min<3 && V_max>3,"intersection visible on current axis")
    Cursor/P/W=$graph A,fitI,1
    CVAT_Assert(CVA_SwitchFit(graph,1,2)==0,"switch captures outgoing cursor")
    CVAT_Assert(CVA_SwitchFit(graph,0,1)==0,"return to oxidation")
    CVAT_Assert(pcsr(A,graph)==1 && valid==0,"changed selection restored without stale fit")
    CVAT_Assert(cmpstr(table[0][1],savedCell)==0,"invalidating display retains saved cell")
    CVAT_Cursors(graph,0,4,7,11)
    CVAT_Assert(CVA_FitRun(graph,1)==0,"recalculate oxidation")
    CVAT_Assert(CVA_SwitchFit(graph,0,2)==0,"switch side")
    CVAT_Cursors(graph,0,4,7,11)
    CVAT_Assert(CVA_FitRun(graph,2)==0,"reduction result saved separately")
    Wave red=$(sourceDF+"CVA_red_1")
    CVAT_Assert(abs(red[0]-1)<1e-12 && abs(ox[0]-1)<1e-12,"both side results retained")
    CVAT_Assert(CVA_SwitchFit(graph,0,1)==0 && valid==1,"unchanged saved fit restored")
    Wave originalE=$(sourceDF+"E_cycle_1")
    originalE[0]=0.001
    CVAT_Assert(!CVA_FitSourceMatches(graph),"edited source detected")
    CVAT_Assert(CVA_SwitchFit(graph,0,1)==0 && valid==0,"edited source blocks old-fit restoration")
    CVAT_Assert(CVA_FitRun(graph,1)==0 && valid==1,"edited source can be explicitly recalculated")
    Wave originalRows=$(sourceDF+"source_line")
    originalRows[0]=1001
    CVAT_Assert(!CVA_FitSourceMatches(graph),"changed row mapping detected")
    CVAT_Assert(CVA_SwitchFit(graph,0,1)==0 && valid==0,"row change blocks restoration")
    CVAT_Assert(CVA_SwitchFit(graph,1,2)==0,"select decreasing cycle")
    CVAT_Cursors(graph,0,4,7,11)
    CVAT_Assert(CVA_FitRun(graph,2)==0,"decreasing cycle fit")
    Wave red2=$(sourceDF+"CVA_red_2")
    CVAT_Assert(abs(red2[0]-1)<1e-12 && abs(red2[1]-3)<1e-12,"decreasing intersection (1 V, 3 mA)")
    Wave current2=$(sourceDF+"I_cycle_2"),potential2=$(sourceDF+"E_cycle_2")
    current2=(p<6) ? 2*potential2+1 : 4*potential2-3
    CVAT_Assert(CVA_SwitchFit(graph,1,2)==0 && valid==0,"new extrapolation source invalidates old fit")
    CVAT_Assert(CVA_FitRun(graph,2)==0,"intersection outside full measured cycle")
    CVAT_Assert(abs(red2[0]-2)<1e-12 && abs(red2[1]-5)<1e-12,"extrapolated intersection (2 V, 5 mA)")
    GetAxis/Q/W=$graph bottom
    CVAT_Assert(V_min<2 && V_max>2,"out-of-cycle intersection visible on voltage axis")
    GetAxis/Q/W=$graph left
    CVAT_Assert(V_min<5 && V_max>5,"out-of-cycle intersection visible on current axis")
    potential2={0,0.2,0.4,0.6,0.8,1,0.8,0.6,0.4,0.2,0,-0.2}
    current2=(p<=5) ? 2*potential2+1 : 4*potential2-0.5
    CVAT_Assert(CVA_SwitchFit(graph,1,1)==0,"select cycle for cross-branch oxidation")
    CVAT_Cursors(graph,0,3,7,10)
    CVAT_Assert(CVA_FitRun(graph,1)==0,"save cross-branch oxidation")
    Wave crossResult=$(sourceDF+"CVA_ox_2")
    CVAT_Assert(abs(crossResult[0]-0.75)<1e-12 && abs(crossResult[1]-2.5)<1e-12,"saved cross-branch intersection")
    CVAT_Assert(CVA_SwitchFit(graph,1,2)==0 && CVA_SwitchFit(graph,1,1)==0 && valid==1,"restore cross-branch result")
    CVAT_Assert(pcsr(A,graph)==0 && pcsr(B,graph)==3 && pcsr(C,graph)==7 && pcsr(D,graph)==10,"restore cross-branch cursors")
    CVAT_Assert(strsearch(note(crossResult),"C line: 120",0)>=0,"cross-branch result records source line")
    DoWindow/K $graph
    SetDataFolder $testDF
End

// Exercise the editor construction path without an interactive graph prompt.
Function CVAT_Editor(testDF)
    String testDF
    String sourceDF=testDF+"source:",beforeDF=GetDataFolder(1)
    Wave sourceE=$(sourceDF+"E_cycle_1"),sourceI=$(sourceDF+"I_cycle_1")
    NVAR lastCycle=$(sourceDF+"CVA_fit_last_cycle"),lastSide=$(sourceDF+"CVA_fit_last_side")
    lastCycle=1; lastSide=2
    Wave/T table=$(sourceDF+"CVA_fit_table")
    String savedCell=table[0][1]
    Wave positions=$(sourceDF+"CVA_fit_cursors")
    Redimension/N=(2,2,3) positions
    CVAT_Assert(CVA_InitFitTable(sourceDF,$(sourceDF+"summary_cycle"))!=0,"malformed existing cursor table rejected")
    CVAT_Assert(cmpstr(table[0][1],savedCell)==0,"failed table initialization preserves saved cell")
    Redimension/N=(2,2,4) positions
    Display/K=1 sourceI vs sourceE as "CV Analyzer disposable source graph"
    String sourceGraph=S_name
    CVAT_Assert(WhichListItem(sourceGraph,CVA_FitGraphCandidates(WinList("*",";","WIN:1")))>=0,"source graph is a fit candidate")
    CVAT_Assert(CVA_CreateFitEditor(sourceGraph,"I_cycle_1",sourceDF)==0,"create fitting editor")
    String graph=WinName(0,1),fitDF=GetUserData(graph,"","fitDF")
    CVAT_Assert(cmpstr(GetDataFolder(1),beforeDF)==0,"editor creation restores current data folder")
    NVAR cycleIndex=$(fitDF+"source_index"),side=$(fitDF+"selected_side"),switching=$(fitDF+"switching")
    CVAT_Assert(cycleIndex==1 && side==2 && switching==0,"editor restores last selected cycle and side")
    ControlInfo/W=$graph fitCycle
    CVAT_Assert(V_value==2,"cycle control reflects last selection")
    ControlInfo/W=$graph fitSide
    CVAT_Assert(V_value==2,"side control reflects last selection")
    Variable graphCount=ItemsInList(WinList("*",";","WIN:1"))
    DoWindow/F $sourceGraph
    CVAT_Assert(CVA_ActivateFitEditor(WinList("*",";","WIN:1"),sourceDF)==1,"existing dataset editor found")
    CVAT_Assert(cmpstr(WinName(0,1),graph)==0 && ItemsInList(WinList("*",";","WIN:1"))==graphCount,"existing editor raised without duplicate graph")
    DoWindow/K $graph
    DoWindow/K $sourceGraph
    KillDataFolder $fitDF
End
