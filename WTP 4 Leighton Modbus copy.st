(* ============================================================ *)
(* WTP CONTROL SYSTEM - LEIGHTON SPEC - V5 (ATT-ULTIMATE)       *)
(* ============================================================ *)

(* ================= 0. INITIALIZATION & SAFETY ================= *)
IF __SYSVA_FIRST_SCAN THEN
    (* 1. Setpoint Waktu *)
    HMI_SP_SERVICE_HR    := 48.0; 
    HMI_SP_BW_MIN        := 10.0; 
    HMI_SP_RINSE_MIN     := 5.0;  
    HMI_SP_INTERVAL_HR   := 24.0; 
    HMI_SP_SHIFT_HR      := 8.0;  
    HMI_SP_DELAY_SEC     := 10.0; 
    HMI_SP_LINE_SHIFT_HR := 48.0; 
    
    (* Setpoint Notifikasi Chlorine *)
    HMI_SP_CL_NOTIF_L := 0.1;
    HMI_SP_CL_NOTIF_H := 0.3;
    
    (* 2. Setpoint Alarm & Trip *)
    HMI_SP_FT101_HH := 10.5; HMI_SP_FT101_H := 10.0; HMI_SP_FT101_L := 8.5; HMI_SP_FT101_LL := 8.0;
    HMI_SP_LT101_HH := 20.0; HMI_SP_LT101_H := -30.0; HMI_SP_LT101_L := -80.0; HMI_SP_LT101_LL := -90.0;
    HMI_SP_LT102_HH := 20.0; HMI_SP_LT102_H := -30.0; HMI_SP_LT102_L := -80.0; HMI_SP_LT102_LL := -90.0;
    
    HMI_SP_AE101_HH := 0.05; HMI_SP_AE101_H := 0.03; HMI_SP_AE101_L := 0.01; HMI_SP_AE101_LL := 0.00;
    HMI_SP_AE102_HH := 8.5;  HMI_SP_AE102_H := 8.0;  HMI_SP_AE102_L := 6.5;  HMI_SP_AE102_LL := 6.0;

    (* 3. Konfigurasi Scaling Analog *)
    HMI_Raw_Min   := 4000.0;     HMI_Raw_Max   := 20000.0; 
    HMI_FT101_Min := 0.0;        HMI_FT101_Max := 50.0;    
    HMI_LT101_Min := 0.0;        HMI_LT101_Max := 100.0;   
    HMI_LT102_Min := 0.0;        HMI_LT102_Max := 100.0;   
    
    (* 4. Default Duty Selector (3 = Auto) *)
    HMI_TPXX_Duty_Sel := 3;
    HMI_TP01_Duty_Sel := 3;
    HMI_Line_Sel := 3;
    
    (* Reset *)
    STEP_SEQUENCE := 0;
    BW_STEP_SEQUENCE := 0;
    AUTO_MODE := FALSE; 
END_IF;

(* Konversi Parameter HMI ke Timer *)
SP_TIME_SERVICE      := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_SERVICE_HR * 3600000.0));
SP_TIME_BW_INTERVAL  := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_INTERVAL_HR * 3600000.0));
SP_TIME_PUMP_SHIFT   := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_SHIFT_HR * 3600000.0)); (* Setpoint Jam dari HMI *)
SP_TIME_BW_RUN       := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_BW_MIN * 60000.0));
SP_TIME_RINSE        := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_RINSE_MIN * 60000.0));
SP_TIME_FLOW_DELAY   := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_DELAY_SEC * 1000.0));
SP_TIME_LINE_SHIFT   := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_LINE_SHIFT_HR * 3600000.0)); (* DIPERBAIKI: Sekarang baca Jam dari HMI *)

(* ======================================================= *)
(* OVERRIDE UNTUK TESTING (HAPUS/COMMENT KALAU SUDAH SELESAI) *)
SP_TIME_PUMP_SHIFT := T#20s;
SP_TIME_LINE_SHIFT := T#45s;
(* ======================================================= *)

(* ================= 1. INPUT MONITORING & SCALING ================= *)

IF (HMI_Raw_Max - HMI_Raw_Min) = 0.0 THEN
    HMI_Raw_Max := 20000.0;
    HMI_Raw_Min := 4000.0;
END_IF;

FLOW_VALUE_CMH := (((ANY_TO_REAL(AI_01_FT101) - HMI_Raw_Min) / (HMI_Raw_Max - HMI_Raw_Min)) * (HMI_FT101_Max - HMI_FT101_Min)) + HMI_FT101_Min;
LEVEL_RWT_PCT  := (((ANY_TO_REAL(_IO_X2_AI_01) - HMI_Raw_Min) / (HMI_Raw_Max - HMI_Raw_Min)) * (HMI_LT101_Max - HMI_LT101_Min)) + HMI_LT101_Min;
LEVEL_TWT_PCT  := (((ANY_TO_REAL(_IO_X2_AI_02) - HMI_Raw_Min) / (HMI_Raw_Max - HMI_Raw_Min)) * (HMI_LT102_Max - HMI_LT102_Min)) + HMI_LT102_Min;

CL_VALUE_PPM := MB_AE101_RAW;

LEVEL_RAW_IS_LOW := LEVEL_RWT_PCT <= HMI_SP_LT101_LL; 
TARGET_TANK_FULL := LEVEL_TWT_PCT >= HMI_SP_LT102_HH; 

TMR_FLOW_DELAY(IN := AUTO_MODE AND ((_IO_EM_DO_02 OR _IO_EM_DO_03) AND (NOT SHIFT_TRIGGER.Q)), PT := SP_TIME_FLOW_DELAY);

IF AUTO_MODE THEN 
    IF TMR_FLOW_DELAY.Q THEN
        IF (FLOW_VALUE_CMH >= HMI_SP_FT101_HH) OR (FLOW_VALUE_CMH <= HMI_SP_FT101_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
    END_IF;
    IF (LEVEL_RWT_PCT >= HMI_SP_LT101_HH) OR (LEVEL_RWT_PCT <= HMI_SP_LT101_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
    IF (LEVEL_TWT_PCT >= HMI_SP_LT102_HH) OR (LEVEL_TWT_PCT <= HMI_SP_LT102_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
    IF (PH_VALUE >= HMI_SP_AE102_HH) OR (PH_VALUE <= HMI_SP_AE102_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
END_IF;

FAULT_TP01A := _IO_EM_DI_01; 
FAULT_TP01B := _IO_EM_DI_02; 
FAULT_TPXXA := _IO_EM_DI_03; 
FAULT_TPXXB := _IO_EM_DI_04; 

TMR_PH_DELAY(IN := AUTO_MODE, PT := T#5s);

IF AUTO_MODE THEN 
    IF TMR_FLOW_DELAY.Q THEN
        ALARM_FLOW := (FLOW_VALUE_CMH >= HMI_SP_FT101_HH) OR (FLOW_VALUE_CMH <= HMI_SP_FT101_LL);
    ELSE
        ALARM_FLOW := FALSE;
    END_IF;
    
    WARNING_CHLORINE := (CL_VALUE_PPM <= HMI_SP_CL_NOTIF_L) OR (CL_VALUE_PPM >= HMI_SP_CL_NOTIF_H);
    
    IF TMR_PH_DELAY.Q THEN
        ALARM_PH := (PH_VALUE >= HMI_SP_AE102_HH) OR (PH_VALUE <= HMI_SP_AE102_LL);
    ELSE
        ALARM_PH := FALSE;
    END_IF;
END_IF;

IF HMI_RESET_BTN THEN 
    ALARM_FLOW := FALSE;
    WARNING_CHLORINE := FALSE;
    ALARM_PH := FALSE;
    HMI_RESET_BTN := FALSE; 
END_IF;

E_Stop_Active := NOT _IO_EM_DI_00 OR HMI_EMERGENCY_STOP;
TPXX_DOUBLE_FAULT := FAULT_TPXXA AND FAULT_TPXXB;
TP01_DOUBLE_FAULT := FAULT_TP01A AND FAULT_TP01B;

IF AUTO_MODE THEN
    TRIP_STATUS    := E_Stop_Active OR TPXX_DOUBLE_FAULT OR TP01_DOUBLE_FAULT;      
    TRIP_PUMP_ONLY := LEVEL_RAW_IS_LOW;   
ELSE
    TRIP_STATUS    := E_Stop_Active;
    TRIP_PUMP_ONLY := FALSE;
END_IF;

(* ================= 1.5 BUZZER ALARM LOGIC ================= *)
Buzzer_Trigger := FAULT_TP01A OR FAULT_TP01B OR FAULT_TPXXA OR FAULT_TPXXB OR ALARM_FLOW;

IF Buzzer_Trigger AND NOT HMI_MUTE_BUZZER THEN 
    OUT_BUZZER := TRUE; 
ELSE 
    OUT_BUZZER := FALSE; 
END_IF;

IF NOT Buzzer_Trigger THEN 
    HMI_MUTE_BUZZER := FALSE; 
END_IF;

(* ================= 2. MODE SELECTION & RESET ================= *)
IF HMI_BTN_SET_AUTO THEN
    IF NOT TRIP_STATUS THEN AUTO_MODE := TRUE; END_IF;
    HMI_MAN_TP01A := FALSE; HMI_MAN_TP01B := FALSE;
    HMI_MAN_TPXXA := FALSE; HMI_MAN_TPXXB := FALSE;
    HMI_MAN_DP01 := FALSE;
    HMI_MAN_VES101 := FALSE; HMI_MAN_VES107 := FALSE;
    HMI_MAN_VES119 := FALSE; HMI_MAN_VES120 := FALSE;
    HMI_MAN_VES121 := FALSE; HMI_MAN_VES122 := FALSE;
    HMI_BTN_SET_AUTO := FALSE; 
    HMI_BTN_SET_MANUAL := FALSE;
END_IF;

IF HMI_BTN_SET_MANUAL THEN
    AUTO_MODE := FALSE;
    HMI_BTN_SET_MANUAL := FALSE; 
    HMI_BTN_SET_AUTO := FALSE;
END_IF;

IF TRIP_STATUS THEN
    AUTO_MODE := FALSE;
    INT_CMD_TPXXA := FALSE; INT_CMD_TPXXB := FALSE;
    INT_CMD_TP01A := FALSE; INT_CMD_TP01B := FALSE;
    AUTO_CMD_DP01_RUN := FALSE;
    AUTO_CMD_VES101 := FALSE; AUTO_CMD_VES107 := FALSE;
    AUTO_CMD_VES119 := FALSE; AUTO_CMD_VES120 := FALSE;
    AUTO_CMD_VES121 := FALSE; AUTO_CMD_VES122 := FALSE;
    HMI_MAN_TP01A := FALSE; HMI_MAN_TP01B := FALSE;
    HMI_MAN_TPXXA := FALSE; HMI_MAN_TPXXB := FALSE;
    HMI_MAN_DP01 := FALSE;
    HMI_MAN_VES101 := FALSE; HMI_MAN_VES107 := FALSE;
    HMI_MAN_VES119 := FALSE; HMI_MAN_VES120 := FALSE;
    HMI_MAN_VES121 := FALSE; HMI_MAN_VES122 := FALSE;
END_IF;

(* ================= 3. AUTO SEQUENCE LOGIC (ATT-DRIVEN) ================= *)
IF AUTO_MODE AND (NOT TRIP_STATUS) THEN

    (* A. BACA SINYAL RUNXIN ATT *)
    ATT_SVC_MMF1 := _IO_X1_DI_03; ATT_BW_MMF1 := _IO_X1_DI_04;
    ATT_SVC_ACF1 := _IO_X1_DI_05; ATT_BW_ACF1 := _IO_X1_DI_06;
    ATT_SVC_MMF2 := _IO_X1_DI_07; ATT_BW_MMF2 := _IO_X1_DI_08;
    ATT_SVC_ACF2 := _IO_X1_DI_09; ATT_BW_ACF2 := _IO_X1_DI_10;

    LINE1_IN_SERVICE := ATT_SVC_MMF1 OR ATT_SVC_ACF1;
    LINE2_IN_SERVICE := ATT_SVC_MMF2 OR ATT_SVC_ACF2;
    ANY_LINE_SERVICE := LINE1_IN_SERVICE OR LINE2_IN_SERVICE;

    BW_ACTIVE_FLAG := ATT_BW_MMF1 OR ATT_BW_ACF1 OR ATT_BW_MMF2 OR ATT_BW_ACF2;

	(* --- LINE SHIFTING --- *)
    (* Self-Resetting Timer: Timer otomatis reset saat mencapai target berkat NOT TMR_LINE_SHIFT.Q *)
    TMR_LINE_SHIFT(IN := (HMI_Line_Sel = 3) AND NOT TMR_LINE_SHIFT.Q, PT := SP_TIME_LINE_SHIFT);
    
    IF TMR_LINE_SHIFT.Q THEN
        IF Duty_Line1 THEN 
            Duty_Line1 := FALSE; Duty_Line2 := TRUE;
        ELSE 
            Duty_Line1 := TRUE; Duty_Line2 := FALSE;
        END_IF;
    END_IF;

    IF SHIFT_PENDING THEN
        IF Duty_Line1 THEN 
            Duty_Line1 := FALSE; Duty_Line2 := TRUE;
        ELSE 
            Duty_Line1 := TRUE; Duty_Line2 := FALSE;
        END_IF;
        SHIFT_PENDING := FALSE; 
    END_IF;

    IF HMI_Line_Sel = 1 THEN
        Duty_Line1 := TRUE; Duty_Line2 := FALSE;
        SHIFT_PENDING := FALSE; 
    ELSIF HMI_Line_Sel = 2 THEN
        Duty_Line1 := FALSE; Duty_Line2 := TRUE;
        SHIFT_PENDING := FALSE;
    ELSIF HMI_Line_Sel = 3 THEN
        IF NOT Duty_Line1 AND NOT Duty_Line2 THEN Duty_Line1 := TRUE; END_IF;
    ELSE
        Duty_Line1 := FALSE; Duty_Line2 := FALSE;
        SHIFT_PENDING := FALSE;
    END_IF;

    (* === 3.A STRICT SEQUENCING RAW WATER (TP-XX) DENGAN FEEDBACK FISIK DI === *)
    (* 1. Syarat Buka Valve *)
    IF NOT BW_ACTIVE_FLAG AND NOT TARGET_TANK_FULL AND NOT TRIP_PUMP_ONLY THEN
        AUTO_CMD_VES101 := LINE1_IN_SERVICE AND Duty_Line1;
        AUTO_CMD_VES107 := LINE2_IN_SERVICE AND Duty_Line2;
    ELSE
        AUTO_CMD_VES101 := FALSE;
        AUTO_CMD_VES107 := FALSE;
    END_IF;

    (* 2. TP-XX Nyala HANYA jika Feedback Limit Switch Valve Fisik OPEN *)
    REQ_PUMP_RUN := AUTO_CMD_VES101 OR AUTO_CMD_VES107;
    AUTO_CMD_PUMP_RUN := REQ_PUMP_RUN AND (_IO_EM_DI_05 OR _IO_EM_DI_07);

    (* === 3.B STRICT SEQUENCING BACKWASH (TP-01) DENGAN FEEDBACK FISIK DI === *)
    LEVEL_TREATED_IS_LOW := LEVEL_TWT_PCT <= HMI_SP_LT102_L;

    (* 1. Syarat Buka Valve Backwash *)
    IF BW_ACTIVE_FLAG AND NOT LEVEL_TREATED_IS_LOW THEN
        AUTO_CMD_VES119 := ATT_BW_MMF1;
        AUTO_CMD_VES120 := ATT_BW_ACF1;
        AUTO_CMD_VES121 := ATT_BW_MMF2;
        AUTO_CMD_VES122 := ATT_BW_ACF2;
    ELSE
        AUTO_CMD_VES119 := FALSE;
        AUTO_CMD_VES120 := FALSE;
        AUTO_CMD_VES121 := FALSE;
        AUTO_CMD_VES122 := FALSE;
    END_IF;

    (* 2. TP-01 Nyala HANYA jika Feedback Limit Switch Valve BW Fisik OPEN *)
    REQ_TP01_RUN := AUTO_CMD_VES119 OR AUTO_CMD_VES120 OR AUTO_CMD_VES121 OR AUTO_CMD_VES122;
    AUTO_CMD_TP01_RUN := REQ_TP01_RUN AND (_IO_EM_DI_09 OR _IO_EM_DI_11 OR _IO_EM_DI_13 OR _IO_X1_DI_01);

    (* Dosing Pump mengikuti Pompa Raw *)
    AUTO_CMD_DP01_RUN := AUTO_CMD_PUMP_RUN;

(* ================= 4. OUTPUT LOGIC GENERATION ================= *)

    (* Self-Resetting Timer selama pompa menyala *)
    SHIFT_TIMER(IN := AUTO_CMD_PUMP_RUN AND (HMI_TPXX_Duty_Sel = 3) AND NOT SHIFT_TIMER.Q, PT := SP_TIME_PUMP_SHIFT);
    
    IF SHIFT_TIMER.Q THEN
        IF Duty_TPXXA THEN 
            Duty_TPXXA := FALSE; Duty_TPXXB := TRUE;
        ELSE                
            Duty_TPXXA := TRUE;  Duty_TPXXB := FALSE; 
        END_IF;
    END_IF;

    IF HMI_TPXX_Duty_Sel = 3 THEN
        IF NOT Duty_TPXXA AND NOT Duty_TPXXB THEN Duty_TPXXA := TRUE; END_IF;
        IF Duty_TPXXA AND FAULT_TPXXA THEN Duty_TPXXA := FALSE; Duty_TPXXB := TRUE; END_IF;
        IF Duty_TPXXB AND FAULT_TPXXB THEN Duty_TPXXB := FALSE; Duty_TPXXA := TRUE; END_IF;
        IF FAULT_TPXXA AND FAULT_TPXXB THEN Duty_TPXXA := FALSE; Duty_TPXXB := FALSE; END_IF;
    ELSIF (HMI_TPXX_Duty_Sel = 1 AND NOT FAULT_TPXXA) OR (HMI_TPXX_Duty_Sel = 2 AND FAULT_TPXXB) THEN
        Duty_TPXXA := TRUE;  Duty_TPXXB := FALSE;
    ELSIF (HMI_TPXX_Duty_Sel = 2 AND NOT FAULT_TPXXB) OR (HMI_TPXX_Duty_Sel = 1 AND FAULT_TPXXA) THEN
        Duty_TPXXA := FALSE; Duty_TPXXB := TRUE;
    ELSE 
        Duty_TPXXA := FALSE; Duty_TPXXB := FALSE; 
    END_IF;

    IF AUTO_CMD_PUMP_RUN THEN
        INT_CMD_TPXXA := Duty_TPXXA;
        INT_CMD_TPXXB := Duty_TPXXB;
    ELSE
        INT_CMD_TPXXA := FALSE; INT_CMD_TPXXB := FALSE;
    END_IF;
	
	(* Logic Shift TP-01 *)
    F_TRIG_BW(CLK := BW_ACTIVE_FLAG);
    IF F_TRIG_BW.Q AND (HMI_TP01_Duty_Sel = 3) THEN
        IF Duty_TP01A THEN 
            Duty_TP01A := FALSE; Duty_TP01B := TRUE;
        ELSE                
            Duty_TP01A := TRUE;  Duty_TP01B := FALSE; 
        END_IF;
    END_IF;

    IF HMI_TP01_Duty_Sel = 3 THEN
        IF NOT Duty_TP01A AND NOT Duty_TP01B THEN Duty_TP01A := TRUE; END_IF;
        IF Duty_TP01A AND FAULT_TP01A THEN Duty_TP01A := FALSE; Duty_TP01B := TRUE; END_IF;
        IF Duty_TP01B AND FAULT_TP01B THEN Duty_TP01B := FALSE; Duty_TP01A := TRUE; END_IF;
        IF FAULT_TP01A AND FAULT_TP01B THEN Duty_TP01A := FALSE; Duty_TP01B := FALSE; END_IF;
    ELSIF (HMI_TP01_Duty_Sel = 1 AND NOT FAULT_TP01A) OR (HMI_TP01_Duty_Sel = 2 AND FAULT_TP01B) THEN
        Duty_TP01A := TRUE;  Duty_TP01B := FALSE;
    ELSIF (HMI_TP01_Duty_Sel = 2 AND NOT FAULT_TP01B) OR (HMI_TP01_Duty_Sel = 1 AND FAULT_TP01A) THEN
        Duty_TP01A := FALSE; Duty_TP01B := TRUE;
    ELSE 
        Duty_TP01A := FALSE; Duty_TP01B := FALSE; 
    END_IF;

    IF AUTO_CMD_TP01_RUN THEN
        INT_CMD_TP01A := Duty_TP01A;
        INT_CMD_TP01B := Duty_TP01B;
    ELSE
        INT_CMD_TP01A := FALSE; INT_CMD_TP01B := FALSE;
    END_IF;

ELSE
    INT_CMD_TPXXA := FALSE; INT_CMD_TPXXB := FALSE;
    INT_CMD_TP01A := FALSE; INT_CMD_TP01B := FALSE;
    AUTO_CMD_DP01_RUN := FALSE;
    AUTO_CMD_VES101 := FALSE; AUTO_CMD_VES107 := FALSE;
    AUTO_CMD_VES119 := FALSE; AUTO_CMD_VES120 := FALSE;
    AUTO_CMD_VES121 := FALSE; AUTO_CMD_VES122 := FALSE;
END_IF;

(* ================= 5. PHYSICAL OUTPUT MAPPING ================= *)

(* Bikin flag peringatan kalau user nyalain pompa manual padahal Feedback Valve fisik belum Open *)
WARNING_MAN_TP_BLOCKED := NOT AUTO_MODE AND (HMI_MAN_TPXXA OR HMI_MAN_TPXXB) AND NOT (_IO_EM_DI_05 OR _IO_EM_DI_07);
WARNING_MAN_TP01_BLOCKED := NOT AUTO_MODE AND (HMI_MAN_TP01A OR HMI_MAN_TP01B) AND NOT (_IO_EM_DI_09 OR _IO_EM_DI_11 OR _IO_EM_DI_13 OR _IO_X1_DI_01);

IF TRIP_STATUS THEN
    _IO_EM_DO_00 := FALSE; _IO_EM_DO_01 := FALSE; 
    _IO_EM_DO_02 := FALSE; _IO_EM_DO_03 := FALSE; 
    _IO_EM_DO_04 := FALSE; _IO_EM_DO_05 := FALSE; 
    _IO_EM_DO_06 := FALSE; _IO_EM_DO_07 := FALSE; 
    _IO_EM_DO_08 := FALSE; _IO_EM_DO_09 := FALSE; 
    _IO_P3_DO_00  := FALSE; 
ELSIF AUTO_MODE THEN
    _IO_EM_DO_00 := INT_CMD_TP01A; 
    _IO_EM_DO_01 := INT_CMD_TP01B;
    _IO_EM_DO_02 := INT_CMD_TPXXA; 
    _IO_EM_DO_03 := INT_CMD_TPXXB;
    _IO_EM_DO_04 := AUTO_CMD_DP01_RUN; 
    _IO_EM_DO_05 := AUTO_CMD_VES107; 
    _IO_EM_DO_06 := AUTO_CMD_VES101; 
    _IO_EM_DO_07 := AUTO_CMD_VES119; 
    _IO_EM_DO_08 := AUTO_CMD_VES120; 
    _IO_EM_DO_09 := AUTO_CMD_VES121; 
    _IO_P3_DO_00  := AUTO_CMD_VES122; 
ELSE
    (* Strict Interlock Manual: Hanya nyala kalau Feedback Valve (Limit Switch) beneran aktif/Open *)
    _IO_EM_DO_00 := HMI_MAN_TP01A AND NOT FAULT_TP01A AND (_IO_EM_DI_09 OR _IO_EM_DI_11 OR _IO_EM_DI_13 OR _IO_X1_DI_01); 
    _IO_EM_DO_01 := HMI_MAN_TP01B AND NOT FAULT_TP01B AND (_IO_EM_DI_09 OR _IO_EM_DI_11 OR _IO_EM_DI_13 OR _IO_X1_DI_01);
    
    _IO_EM_DO_02 := HMI_MAN_TPXXA AND NOT FAULT_TPXXA AND (_IO_EM_DI_05 OR _IO_EM_DI_07); 
    _IO_EM_DO_03 := HMI_MAN_TPXXB AND NOT FAULT_TPXXB AND (_IO_EM_DI_05 OR _IO_EM_DI_07);
    
    _IO_EM_DO_04 := HMI_MAN_DP01; 
    _IO_EM_DO_05 := HMI_MAN_VES107; 
    _IO_EM_DO_06 := HMI_MAN_VES101; 
    _IO_EM_DO_07 := HMI_MAN_VES119; 
    _IO_EM_DO_08 := HMI_MAN_VES120; 
    _IO_EM_DO_09 := HMI_MAN_VES121; 
    _IO_P3_DO_00  := HMI_MAN_VES122; 
END_IF;

(* Buzzer Output *)
_IO_P3_DO_01 := OUT_BUZZER;

(* ================= 6. HMI FEEDBACK (Murni & Smart Auto/Manual) ================= *)
(* HMI Feedback ini akan menyesuaikan diri. Di mode AUTO dia membaca putaran Duty_Line. *)
(* Di mode MANUAL, dia membaca tombol Valve mana yang sedang kamu aktifkan. *)

IF AUTO_MODE THEN
    VIS_MMF1_SVC := ATT_SVC_MMF1 AND Duty_Line1; 
    VIS_MMF1_BW  := ATT_BW_MMF1; 

    VIS_ACF1_SVC := ATT_SVC_ACF1 AND Duty_Line1; 
    VIS_ACF1_BW  := ATT_BW_ACF1;

    VIS_MMF2_SVC := ATT_SVC_MMF2 AND Duty_Line2; 
    VIS_MMF2_BW  := ATT_BW_MMF2;

    VIS_ACF2_SVC := ATT_SVC_ACF2 AND Duty_Line2; 
    VIS_ACF2_BW  := ATT_BW_ACF2;
ELSE
    VIS_MMF1_SVC := ATT_SVC_MMF1 AND HMI_MAN_VES101; 
    VIS_MMF1_BW  := ATT_BW_MMF1 AND HMI_MAN_VES119; 

    VIS_ACF1_SVC := ATT_SVC_ACF1 AND HMI_MAN_VES101; 
    VIS_ACF1_BW  := ATT_BW_ACF1 AND HMI_MAN_VES120;

    VIS_MMF2_SVC := ATT_SVC_MMF2 AND HMI_MAN_VES107; 
    VIS_MMF2_BW  := ATT_BW_MMF2 AND HMI_MAN_VES121;

    VIS_ACF2_SVC := ATT_SVC_ACF2 AND HMI_MAN_VES107; 
    VIS_ACF2_BW  := ATT_BW_ACF2 AND HMI_MAN_VES122;
END_IF;

(* ================= 7. HMI ACTUAL TIME MONITORING ================= *)
//HMI_ACT_SHIFT_HR  := ANY_TO_REAL(ANY_TO_DINT(SHIFT_TIMER.ET)) / 3600000.0;
//HMI_ACT_DELAY_SEC := ANY_TO_REAL(ANY_TO_DINT(TMR_FLOW_DELAY.ET)) / 1000.0;

(* ================= 7. HMI ACTUAL TIME MONITORING ================= *)
(* Aktual waktu berjalan Shift Raw Pump (TP-XX) dalam Menit *)
HMI_ACT_SHIFT_MIN := ANY_TO_REAL(ANY_TO_DINT(SHIFT_TIMER.ET)) / 60000.0;

(* Aktual waktu berjalan Shift Autotrol Line dalam Menit *)
HMI_ACT_LINE_SHIFT_MIN := ANY_TO_REAL(ANY_TO_DINT(TMR_LINE_SHIFT.ET)) / 60000.0;

(* Aktual delay flow tetap dalam Detik (karena setpointnya hanya 10 detik) *)
HMI_ACT_DELAY_SEC := ANY_TO_REAL(ANY_TO_DINT(TMR_FLOW_DELAY.ET)) / 1000.0;

(* ================= 8. MODBUS RS-485 POLLING (AE-101) ================= *)
TMR_MB_Delay(IN := MB_Delay_EN, PT := T#2000ms); 

MB_LocalCfg.Channel := 2;    
MB_LocalCfg.TriggerType := 0;
MB_LocalCfg.Cmd := 3;        
MB_LocalCfg.ElementCnt := 2; 
MB_TargetCfg.Node := 1;      

CASE MB_Step OF

0:  
    CASE Test_Index OF
        1: MB_TargetCfg.Addr := 0;   
        2: MB_TargetCfg.Addr := 1;   
        3: MB_TargetCfg.Addr := 100; 
        4: MB_TargetCfg.Addr := 256; 
        ELSE Test_Index := 1;
    END_CASE;

    MB_Delay_EN := TRUE;

    IF TMR_MB_Delay.Q THEN
        MB_Trigger := TRUE;
        MB_Delay_EN := FALSE;
        MB_Step := 1;
    END_IF;

1:  
    IF MB_Block.Q THEN
        Trigger_COP_CL := TRUE; 
        
        MB_Trigger := FALSE;
        MB_Step := 0;
        
    ELSIF MB_Block.Error THEN
        Test_Index := Test_Index + 1;
        IF Test_Index > 4 THEN
            Test_Index := 1;
        END_IF;

        MB_Trigger := FALSE;
        MB_Step := 0; 
    END_IF;

END_CASE;

(* ---- EKSEKUSI MODBUS ---- *)
MB_Block(
    IN := MB_Trigger,
    LocalCfg := MB_LocalCfg,
    TargetCfg := MB_TargetCfg,
    LocalAddr := MB_Buffer
);

(* === SALIN DATA BUFFER KE VARIABEL SENSOR === *)
IF Trigger_COP_CL THEN
    Convert_CL(MB_Buffer[1], MB_Buffer[2]);
    
    MB_AE101_RAW := Convert_CL.Out_Real;
    
    Trigger_COP_CL := FALSE;
END_IF;
