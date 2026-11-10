#pragma rtGlobals=3

// Load this procedure together with CVAnalyzer.ipf in a disposable Igor Pro 8
// experiment, compile, and run CVAT_Run(). No imported/user waves are modified.
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
    CVAT_State(testDF)
    SetDataFolder $oldDF
    KillDataFolder $testDF
    Print "CV Analyzer native Igor regression checks passed."
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
    GetAxis/Q/W=$graph bottom
    CVAT_Assert(V_min<1 && V_max>1,"intersection visible on voltage axis")
    GetAxis/Q/W=$graph left
    CVAT_Assert(V_min<3 && V_max>3,"intersection visible on current axis")
    Cursor/P/W=$graph A,fitI,1
    CVAT_Assert(CVA_SwitchFit(graph,1,2)==0,"switch captures outgoing cursor")
    CVAT_Assert(CVA_SwitchFit(graph,0,1)==0,"return to oxidation")
    CVAT_Assert(pcsr(A,graph)==1 && valid==0,"changed selection restored without stale fit")
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
    DoWindow/K $graph
    SetDataFolder $testDF
End
