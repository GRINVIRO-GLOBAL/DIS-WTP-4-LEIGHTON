(* ======================================================== *)
(* BAGIAN 1: INPUT MAPPING & SCALING                        *)
(* ======================================================== *)

FLOW_VALUE_CMH := (ANY_TO_REAL(AI_01_FT101) / 65535.0) * 50.0;

(* Mapping Sensor Level (_IO_EM_DI_05) *)
IF _IO_EM_DI_05 = FALSE THEN
    LEVEL_IS_LOW := TRUE;
ELSE
    LEVEL_IS_LOW := FALSE;
END_IF;

(* ======================================================== *)
(* BAGIAN 2: INTERLOCK & PROTEKSI (FAIL-SAFE)               *)
(* ======================================================== *)

(* KONDISI 1: Emergency Stop (DI_00) = FALSE (Putus/Tekan) *)
IF (_IO_EM_DI_00 = FALSE) THEN
    _IO_EM_DO_02 := FALSE; (* Matikan Pompa A *)
    _IO_EM_DO_03 := FALSE; (* Matikan Pompa B *)
    _IO_EM_DO_05 := FALSE;
    _IO_EM_DO_06 := FALSE;
    AUTO_MODE := FALSE;
    STEP_SEQUENCE := 0;
    TMR_ENABLE := FALSE;
    RUN_SHIFT_TMR_PUMP_XX := FALSE;

(* KONDISI 2: Level Low (DI_05) HANYA SAAT AUTO *)
ELSIF (LEVEL_IS_LOW = TRUE) AND (AUTO_MODE = TRUE) THEN
    _IO_EM_DO_02 := FALSE; 
    _IO_EM_DO_03 := FALSE; 
    _IO_EM_DO_05 := FALSE;
    _IO_EM_DO_06 := FALSE;
    
    AUTO_MODE := FALSE; 
    STEP_SEQUENCE := 0;
    TMR_ENABLE := FALSE;
    RUN_SHIFT_TMR_PUMP_XX := FALSE;
END_IF;

(* ======================================================== *)
(* BAGIAN 3: SEQUENCE CONTROL (LOGIKA UTAMA)                *)
(* ======================================================== *)

IF (AUTO_MODE = TRUE) AND (LEVEL_IS_LOW = FALSE) THEN

    CASE STEP_SEQUENCE OF
        0:  (* Step 0: Standby *)
            _IO_EM_DO_02 := FALSE;
            _IO_EM_DO_03 := FALSE;
            _IO_EM_DO_05 := FALSE;
            _IO_EM_DO_06 := FALSE;
            TMR_ENABLE := FALSE;
            RUN_SHIFT_TMR_PUMP_XX := FALSE; (* Timer Shift Stop dulu *)
            
            (* Syarat Start *)
            IF (_IO_EM_DI_05 = TRUE) THEN
                STEP_SEQUENCE := 1; 
            END_IF;

        1:  (* Step 1: Filtrasi Jalur 1 *)
            _IO_EM_DO_05 := TRUE;  (* BUKA Valve 1 *)
            _IO_EM_DO_06 := FALSE;
            
            (* === LOGIKA SHIFTING POMPA === *)
            (* Cek: Giliran Siapa? *)
            IF PUMP_A_TURN = TRUE THEN
                _IO_EM_DO_02 := TRUE;  (* Jalan Pompa A *)
                _IO_EM_DO_03 := FALSE; (* Mati Pompa B *)
            ELSE
                _IO_EM_DO_02 := FALSE; (* Mati Pompa A *)
                _IO_EM_DO_03 := TRUE;  (* Jalan Pompa B *)
            END_IF;
            
            (* Jalankan Timer Sequence & Timer Shifting *)
            TMR_ENABLE := TRUE;
            RUN_SHIFT_TMR_PUMP_XX := TRUE; 
            
            IF TIMER_SERVICE.Q THEN
                TMR_ENABLE := FALSE; 
                STEP_SEQUENCE := 3;
            END_IF;

        3:  (* Step 3: Filtrasi Jalur 2 *)
            _IO_EM_DO_05 := FALSE;
            _IO_EM_DO_06 := TRUE;  (* BUKA Valve 2 *)
            
            (* === LOGIKA SHIFTING POMPA === *)
            (* Tetap pertahankan giliran yang sedang aktif *)
            IF PUMP_A_TURN = TRUE THEN
                _IO_EM_DO_02 := TRUE;
                _IO_EM_DO_03 := FALSE;
            ELSE
                _IO_EM_DO_02 := FALSE;
                _IO_EM_DO_03 := TRUE;
            END_IF;
            
            TMR_ENABLE := TRUE;
            RUN_SHIFT_TMR_PUMP_XX := TRUE;
            
            IF TIMER_SERVICE.Q THEN
                TMR_ENABLE := FALSE;
                STEP_SEQUENCE := 1;
            END_IF;
            
        5:  (* Step 5: Stop *)
            _IO_EM_DO_02 := FALSE;
            _IO_EM_DO_03 := FALSE;
            _IO_EM_DO_05 := FALSE;
            _IO_EM_DO_06 := FALSE;
            RUN_SHIFT_TMR_PUMP_XX := FALSE;
            STEP_SEQUENCE := 0;
    END_CASE;

ELSE
    (* MODE MANUAL: Reset Logic *)
    TMR_ENABLE := FALSE;
    RUN_SHIFT_TMR_PUMP_XX := FALSE;
    STEP_SEQUENCE := 0;
    (* Output bebas dikendalikan manual *)
END_IF;

(* ======================================================== *)
(* BAGIAN 4: TIMERS (Sequence & Shifting)                   *)
(* ======================================================== *)

(* 1. Timer Sequence (Perpindahan Valve) *)
TIMER_SERVICE(IN := TMR_ENABLE, PT := T#10s);

(* 2. Timer Shifting (Perpindahan Pompa A/B) *)
(* Timer ini jalan kalau RUN_SHIFT_TMR aktif *)
(* Durasi diambil dari variabel SHIFT_DURATION *)
SHIFT_TIMER(IN := RUN_SHIFT_TMR_PUMP_XX, PT := SHIFT_DURATION_PUMP_XX);

(* Jika Timer Shifting Habis (.Q), Tukar Giliran! *)
IF SHIFT_TIMER.Q THEN
    (* Balik Nilai Boolean: Kalau TRUE jadi FALSE, FALSE jadi TRUE *)
    PUMP_A_TURN := NOT PUMP_A_TURN; 
    
    (* Reset Timer sesaat biar ngitung ulang dari 0 *)
    SHIFT_TIMER(IN := FALSE); 
    (* (Di scan berikutnya dia akan otomatis TRUE lagi karena RUN_SHIFT_TMR masih nyala) *)
END_IF;

(* ======================================================== *)
(* BAGIAN 5: ALARM                                          *)
(* ======================================================== *)

(* Alarm Low Flow: Cek Pompa manapun yang lagi nyala *)
IF ((_IO_EM_DO_02 = TRUE) OR (_IO_EM_DO_03 = TRUE)) AND (FLOW_VALUE_CMH < 5.0) THEN 
    NewVariable2 := TRUE; 
ELSE
    NewVariable2 := FALSE;
END_IF;