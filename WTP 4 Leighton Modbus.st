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
    
    (* Setpoint Notifikasi Chlorine (Bisa diubah di HMI) *)
    HMI_SP_CL_NOTIF_L := 0.1;
    HMI_SP_CL_NOTIF_H := 0.3;
    
    (* 2. Setpoint Alarm & Trip (LL, L, H, HH) - BISA DIUBAH DI HMI *)
    (* Flowmeter (FT-101) *)
    HMI_SP_FT101_HH := 10.5; HMI_SP_FT101_H := 10.0; HMI_SP_FT101_L := 8.5; HMI_SP_FT101_LL := 8.0;
    (* Raw Tank (LT-101) *)
    HMI_SP_LT101_HH := 95.0; HMI_SP_LT101_H := 80.0; HMI_SP_LT101_L := -20.0; HMI_SP_LT101_LL := -30.0;
    (* Treated Tank (LT-102) *)
    HMI_SP_LT102_HH := 90.0; HMI_SP_LT102_H := 80.0; HMI_SP_LT102_L := 30.0; HMI_SP_LT102_LL := 20.0;
    
    (* Parameter AE hanya untuk patokan scaling/limit instrumen lama *)
    HMI_SP_AE101_HH := 0.05; HMI_SP_AE101_H := 0.03; HMI_SP_AE101_L := 0.01; HMI_SP_AE101_LL := 0.00;
    HMI_SP_AE102_HH := 8.5;  HMI_SP_AE102_H := 8.0;  HMI_SP_AE102_L := 6.5;  HMI_SP_AE102_LL := 6.0;

    (* 3. Konfigurasi Scaling Analog (Raw & EU) *)
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
SP_TIME_PUMP_SHIFT   := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_SHIFT_HR * 3600000.0));
SP_TIME_BW_RUN       := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_BW_MIN * 60000.0));
SP_TIME_RINSE        := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_RINSE_MIN * 60000.0));
SP_TIME_FLOW_DELAY   := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_DELAY_SEC * 1000.0));
SP_TIME_LINE_SHIFT   := ANY_TO_TIME(ANY_TO_DINT(HMI_SP_LINE_SHIFT_HR * 3600000.0));

(* ================= 1. INPUT MONITORING & SCALING ================= *)

(* Safety Guard Scaling *)
IF (HMI_Raw_Max - HMI_Raw_Min) = 0.0 THEN
    HMI_Raw_Max := 20000.0;
    HMI_Raw_Min := 4000.0;
END_IF;

(* A. Analog 4-20mA (Scaling Dinamis) *)
FLOW_VALUE_CMH := (((ANY_TO_REAL(AI_01_FT101) - HMI_Raw_Min) / (HMI_Raw_Max - HMI_Raw_Min)) * (HMI_FT101_Max - HMI_FT101_Min)) + HMI_FT101_Min;
LEVEL_RWT_PCT  := (((ANY_TO_REAL(_IO_X2_AI_01) - HMI_Raw_Min) / (HMI_Raw_Max - HMI_Raw_Min)) * (HMI_LT101_Max - HMI_LT101_Min)) + HMI_LT101_Min;
LEVEL_TWT_PCT  := (((ANY_TO_REAL(_IO_X2_AI_02) - HMI_Raw_Min) / (HMI_Raw_Max - HMI_Raw_Min)) * (HMI_LT102_Max - HMI_LT102_Min)) + HMI_LT102_Min;

(* B. Pembacaan Modbus RS-485 (AE-101 & AE-102) *)
(* RC-5 FIX: MB_AE101_RAW sudah dalam bentuk mg/L (FLOAT 32-bit), hapus pembagian 100 *)
CL_VALUE_PPM := MB_AE101_RAW;

(* C. Kondisi Level Interlock (Murni pakai variabel HMI) *)
LEVEL_RAW_IS_LOW := LEVEL_RWT_PCT <= HMI_SP_LT101_LL; (* Pompa Raw Mati jika sentuh LL *)
TARGET_TANK_FULL := LEVEL_TWT_PCT >= HMI_SP_LT102_HH; (* Mencegah pompa Raw nyala jika sentuh HH *)

(* Flow Alarm hanya dibaca ketika Pompa Raw aktif dan delay selesai *)
TMR_FLOW_DELAY(IN := AUTO_MODE AND ((_IO_EM_DO_02 OR _IO_EM_DO_03) AND (NOT SHIFT_TRIGGER.Q)), PT := SP_TIME_FLOW_DELAY);

(* Latch Alarm Instrumen *)
IF AUTO_MODE THEN 
    IF TMR_FLOW_DELAY.Q THEN
        IF (FLOW_VALUE_CMH >= HMI_SP_FT101_HH) OR (FLOW_VALUE_CMH <= HMI_SP_FT101_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
    END_IF;
    IF (LEVEL_RWT_PCT >= HMI_SP_LT101_HH) OR (LEVEL_RWT_PCT <= HMI_SP_LT101_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
    IF (LEVEL_TWT_PCT >= HMI_SP_LT102_HH) OR (LEVEL_TWT_PCT <= HMI_SP_LT102_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
    IF (PH_VALUE >= HMI_SP_AE102_HH) OR (PH_VALUE <= HMI_SP_AE102_LL) THEN ANY_INST_ALARM := TRUE; END_IF;
END_IF;

(* D. Pump Faults (Dibaca murni dari fisik Overload Relay NC) *)
FAULT_TP01A := _IO_EM_DI_01; 
FAULT_TP01B := _IO_EM_DI_02; 
FAULT_TPXXA := _IO_EM_DI_03; 
FAULT_TPXXB := _IO_EM_DI_04; 

(* --- ALARM & WARNING LOGIC --- *)
(* Tambahkan Timer Delay untuk Stabilisasi Pembacaan Sensor/Modbus *)
TMR_PH_DELAY(IN := AUTO_MODE, PT := T#5s);

IF AUTO_MODE THEN 
    IF TMR_FLOW_DELAY.Q THEN
        ALARM_FLOW := (FLOW_VALUE_CMH >= HMI_SP_FT101_HH) OR (FLOW_VALUE_CMH <= HMI_SP_FT101_LL);
    ELSE
        ALARM_FLOW := FALSE;
    END_IF;
    
    (* NOTIFIKASI CHLORINE - Hanya trigger flag, tidak memicu buzzer/trip *)
    WARNING_CHLORINE := (CL_VALUE_PPM <= HMI_SP_CL_NOTIF_L) OR (CL_VALUE_PPM >= HMI_SP_CL_NOTIF_H);
    
    (* ALARM PH SEKARANG DILINDUNGI TIMER DELAY 5 DETIK *)
    IF TMR_PH_DELAY.Q THEN
        ALARM_PH := (PH_VALUE >= HMI_SP_AE102_HH) OR (PH_VALUE <= HMI_SP_AE102_LL);
    ELSE
        ALARM_PH := FALSE;
    END_IF;
END_IF;

(* --- E-STOP & RESET ALARM LOGIC --- *)
IF HMI_RESET_BTN THEN 
    ALARM_FLOW := FALSE;
    WARNING_CHLORINE := FALSE;
    ALARM_PH := FALSE;
    HMI_RESET_BTN := FALSE; 
END_IF;

(* Gabungan E-Stop Fisik & HMI *)
E_Stop_Active := NOT _IO_EM_DI_00 OR HMI_EMERGENCY_STOP;

(* Deteksi Double Fault *)
TPXX_DOUBLE_FAULT := FAULT_TPXXA AND FAULT_TPXXB;
TP01_DOUBLE_FAULT := FAULT_TP01A AND FAULT_TP01B;

(* SAFETY TRIP HIERARCHY *)
IF AUTO_MODE THEN
    TRIP_STATUS    := E_Stop_Active OR TPXX_DOUBLE_FAULT OR TP01_DOUBLE_FAULT;      
    TRIP_PUMP_ONLY := LEVEL_RAW_IS_LOW;   
ELSE
    TRIP_STATUS    := E_Stop_Active;
    TRIP_PUMP_ONLY := FALSE;
END_IF;

(* ================= 1.5 BUZZER ALARM LOGIC ================= *)
(* Buzzer Trigger: Menyala saat ada Fault Pompa ATAU Alarm Instrumen, tapi Chlorine dikecualikan *)
Buzzer_Trigger := FAULT_TP01A OR FAULT_TP01B OR FAULT_TPXXA OR FAULT_TPXXB OR ALARM_FLOW;

IF Buzzer_Trigger AND NOT HMI_MUTE_BUZZER THEN 
    OUT_BUZZER := TRUE; 
ELSE 
    OUT_BUZZER := FALSE; 
END_IF;

(* Otomatis matikan Mute kalau semua alarm sudah clear *)
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

    (* B. EVALUASI STATUS LINE *)
    LINE1_IN_SERVICE := ATT_SVC_MMF1 OR ATT_SVC_ACF1;
    LINE2_IN_SERVICE := ATT_SVC_MMF2 OR ATT_SVC_ACF2;
    ANY_LINE_SERVICE := LINE1_IN_SERVICE OR LINE2_IN_SERVICE;

    BW_ACTIVE_FLAG := ATT_BW_MMF1 OR ATT_BW_ACF1 OR ATT_BW_MMF2 OR ATT_BW_ACF2;

    (* --- RAW WATER PUMP (TP-XX) --- *)
    AUTO_CMD_PUMP_RUN := ANY_LINE_SERVICE AND (NOT TARGET_TANK_FULL) AND (NOT BW_ACTIVE_FLAG) AND (NOT TRIP_PUMP_ONLY);

    (* --- LINE SHIFTING (SEKARANG TETAP JALAN MESKI BACKWASH) --- *)
    TMR_LINE_SHIFT(IN := (HMI_Line_Sel = 3) AND NOT SHIFT_PENDING, PT := SP_TIME_LINE_SHIFT);
    
    IF TMR_LINE_SHIFT.Q THEN
        SHIFT_PENDING := TRUE;
    END_IF;

    (* Eksekusi Shift SEKARANG JUGA *)
    IF SHIFT_PENDING THEN
        IF Duty_Line1 THEN 
            Duty_Line1 := FALSE; Duty_Line2 := TRUE;
        ELSE 
            Duty_Line1 := TRUE; Duty_Line2 := FALSE;
        END_IF;
        SHIFT_PENDING := FALSE; (* Reset timer *)
    END_IF;

    (* Evaluasi Selector Line *)
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
	
    (* --- LINE INLET VALVES (VES-101 & VES-107) --- *)
    IF NOT BW_ACTIVE_FLAG THEN
        AUTO_CMD_VES101 := LINE1_IN_SERVICE AND Duty_Line1 AND AUTO_CMD_PUMP_RUN;
        AUTO_CMD_VES107 := LINE2_IN_SERVICE AND Duty_Line2 AND AUTO_CMD_PUMP_RUN;
    ELSE
        AUTO_CMD_VES101 := FALSE; 
        AUTO_CMD_VES107 := FALSE;
    END_IF;

(* ================= 4. OUTPUT LOGIC GENERATION ================= *)

    SHIFT_TIMER(IN := AUTO_CMD_PUMP_RUN, PT := SP_TIME_PUMP_SHIFT);
    SHIFT_TRIGGER(CLK := SHIFT_TIMER.Q);
    IF SHIFT_TRIGGER.Q THEN
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
    
    LEVEL_TREATED_IS_LOW := LEVEL_TWT_PCT <= HMI_SP_LT102_L;

    (* --- BACKWASH PUMP (TP-01) --- *)
    AUTO_CMD_TP01_RUN := BW_ACTIVE_FLAG AND (NOT LEVEL_TREATED_IS_LOW);
    
    F_TRIG_BW(CLK := BW_ACTIVE_FLAG);
    IF F_TRIG_BW.Q THEN
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

    (* --- DOSING PUMP (DP-01) --- *)
    (* Murni ikut nyala Pompa Raw, tidak ada interlock AE *)
    AUTO_CMD_DP01_RUN := AUTO_CMD_PUMP_RUN;
    
    (* --- BACKWASH VALVES DENGAN OFF-DELAY --- *)
    (* Valve akan telat mati 5 detik setelah sinyal DI dari ATT hilang *)
    TOF_VES119(IN := ATT_BW_MMF1, PT := T#5s);
    TOF_VES120(IN := ATT_BW_ACF1, PT := T#5s);
    TOF_VES121(IN := ATT_BW_MMF2, PT := T#5s);
    TOF_VES122(IN := ATT_BW_ACF2, PT := T#5s);

    AUTO_CMD_VES119 := TOF_VES119.Q;
    AUTO_CMD_VES120 := TOF_VES120.Q;
    AUTO_CMD_VES121 := TOF_VES121.Q;
    AUTO_CMD_VES122 := TOF_VES122.Q;

ELSE
    INT_CMD_TPXXA := FALSE; INT_CMD_TPXXB := FALSE;
    INT_CMD_TP01A := FALSE; INT_CMD_TP01B := FALSE;
    AUTO_CMD_DP01_RUN := FALSE;
    AUTO_CMD_VES101 := FALSE; AUTO_CMD_VES107 := FALSE;
    AUTO_CMD_VES119 := FALSE; AUTO_CMD_VES120 := FALSE;
    AUTO_CMD_VES121 := FALSE; AUTO_CMD_VES122 := FALSE;
END_IF;

(* ================= 5. PHYSICAL OUTPUT MAPPING ================= *)
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
    _IO_EM_DO_00 := HMI_MAN_TP01A AND NOT FAULT_TP01A; 
    _IO_EM_DO_01 := HMI_MAN_TP01B AND NOT FAULT_TP01B;
    _IO_EM_DO_02 := HMI_MAN_TPXXA AND NOT FAULT_TPXXA; 
    _IO_EM_DO_03 := HMI_MAN_TPXXB AND NOT FAULT_TPXXB;
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

(* ================= 6. HMI FEEDBACK (Murni dari Status ATT) ================= *)
VIS_MMF1_SVC := ATT_SVC_MMF1; VIS_MMF1_BW := ATT_BW_MMF1;
VIS_ACF1_SVC := ATT_SVC_ACF1; VIS_ACF1_BW := ATT_BW_ACF1;
VIS_MMF2_SVC := ATT_SVC_MMF2; VIS_MMF2_BW := ATT_BW_MMF2;
VIS_ACF2_SVC := ATT_SVC_ACF2; VIS_ACF2_BW := ATT_BW_ACF2;

(* ================= 7. HMI ACTUAL TIME MONITORING ================= *)
HMI_ACT_SHIFT_HR  := ANY_TO_REAL(ANY_TO_DINT(SHIFT_TIMER.ET)) / 3600000.0;
HMI_ACT_DELAY_SEC := ANY_TO_REAL(ANY_TO_DINT(TMR_FLOW_DELAY.ET)) / 1000.0;

(* ================= 8. MODBUS RS-485 POLLING (AE-101 & AE-102) ================= *)
TMR_MB_Delay(IN := MB_Delay_EN, PT := T#500ms);

MB_LocalCfg.Channel := 2;
MB_LocalCfg.TriggerType := 0;
MB_LocalCfg.Cmd := 3;        (* Command Type 03: Read Holding Registers *)
MB_LocalCfg.ElementCnt := 2; (* Membaca 2 Register (4 bytes) untuk tipe FLOAT 32-bit *)

CASE MB_Step OF

0:  (* Read AE101 (Chlorine) - Slave ID 1 *)
    MB_TargetCfg.Node := 1;  (* FIX RC-1: Sensor Modbus slave ID HARUS = 1 *)
    MB_TargetCfg.Addr := 1;  (* CATATAN RC-3: Jika data aneh/0, coba ubah Addr := 0 di sini *)

    MB_Delay_EN := TRUE;

    IF TMR_MB_Delay.Q THEN
        MB_Trigger := TRUE;
        MB_Delay_EN := FALSE;
        MB_Step := 1;
    END_IF;

1:  (* Evaluasi Data AE101 (Chlorine) *)
    IF MB_Block.Q THEN
        (* RC-0 FIX: Trigger COP untuk menyalin data dari Buffer ke Variabel REAL *)
        Trigger_COP_CL := TRUE; 
        
        MB_Trigger := FALSE;
        MB_Step := 0; (* Kembali ke Step 0 *)
    ELSIF MB_Block.Error THEN
        MB_Trigger := FALSE;
        MB_Step := 0; (* Jika Error (misal 55), langsung coba lagi *)
    END_IF;

END_CASE;

(* ---- EKSEKUSI MODBUS ---- *)
MB_Block(
    IN := MB_Trigger,
    LocalCfg := MB_LocalCfg,
    TargetCfg := MB_TargetCfg,
    LocalAddr := MB_Buffer
);

(* === SALIN DATA BUFFER KE VARIABEL SENSOR (RC-0 FIX) === *)
IF Trigger_COP_CL THEN
    (* CCW memanggil fungsi COP langsung berdasarkan urutan (Positional) *)
    (* dan otomatis mendeteksi panjang dari variabel REAL (4 bytes) *)
    COP(MB_Buffer[1], MB_AE101_RAW);
    
    Trigger_COP_CL := FALSE;
END_IF;
