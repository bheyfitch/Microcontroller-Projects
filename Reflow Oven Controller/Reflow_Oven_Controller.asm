;----------------------------------------------------------------------
; 76E003 ADC test program (reflow oven controller + push buttons)
; Reads channel 7 on P1.1, pin 14
; This version uses the LM4040 voltage reference connected to pin 6 (P1.7/AIN0)
; Incorporates push-button control to set up times/temperatures and start FSM.
;----------------------------------------------------------------------

$NOLIST
$MODN76E003
$LIST

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

;----------------------------------------------------------------------
; System/Timer/Constants
;----------------------------------------------------------------------
CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200   ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))

TIMER2_RATE       EQU 100      ; 100 Hz -> 10ms tick
TIMER2_RELOAD     EQU ((65536-(CLK/(16*TIMER2_RATE))))

TIMER0_RATE          EQU 2250
TIMER0_RELOAD        EQU (0x10000-(CLK/TIMER0_RATE))

SAMPLES_PER_DISPLAY EQU 150
REFRESHES_PER_SECOND EQU 15

ORG 0x0000
    ljmp main

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; Timer/Counter 2 overflow interrupt vector
org 0x002B
    ljmp Timer2_ISR

;----------------------------------------------------------------------
; Hardware Pin Definitions
;----------------------------------------------------------------------

; PUSH BUTTONS (single-pin read approach)
PB_INPUT_PIN   EQU P1.5  ; The single pin used to read all 5 PBs
MUX_CONTROL_0  EQU P1.3  
MUX_CONTROL_1  EQU P0.0  
MUX_CONTROL_2  EQU P0.1  
MUX_CONTROL_3  EQU P0.2  
MUX_CONTROL_4  EQU P0.3  
SOUND_OUT      EQU P3.0

; LCD assignments
LCD_RS  equ P1.3
LCD_E   equ P1.4
LCD_D4  equ P0.0
LCD_D5  equ P0.1
LCD_D6  equ P0.2
LCD_D7  equ P0.3
SSR_BOX equ P0.4

; Strings for LCD
test_message:     db 'Current Temp.:', 0
value_message:    db 'Deg. C', 0

temp_soak_string: db 'Temp Soak:    ', 0
time_soak_string: db 'Time Soak:    ', 0
temp_refl_string: db 'Temp Reflow: ', 0
time_refl_string: db 'Time Reflow: ', 0

degree_label: db ' C', 0
seconds_label: db ' s', 0


cseg

$NOLIST
$include(LCD_4bit.inc)      ; LCD library
$LIST

;----------------------------------------------------------------------
; 32-bit math placeholders
;----------------------------------------------------------------------
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
VAL_LM4040: ds 2

; Variables
state:              ds 1
StoreMeasurements:  ds 4
Store:          ds 2
MeasurementCounter: ds 2
SamplesPerDisplay:  ds 2
TimePerSample:      ds 1
LastMeasurement:    ds 4
StoreThermocouple:  ds 4
CurrentTemp:        ds 4
FinalLM335:         ds 4
FinalTemp:          ds 4
selected_state:		ds 1

save_x:             ds 4

Count1ms:      ds 2
pwm_counter:   ds 1
pwm:           ds 1

debounce_count_0 :ds 1
debounce_count_1 :ds 1
debounce_count_2 :ds 1
debounce_count_3 :ds 1
debounce_count_4 :ds 1

; Oven settings
temp_soak: ds 1  ; For state 1
time_soak: ds 1  ; For state 2
temp_refl: ds 1  ; For state 3
time_refl: ds 1  ; For state 4

seconds: ds 1
state_sec: ds 1

;----------------------------------------------------------------------
; Bit variables (BSEG)
;----------------------------------------------------------------------
BSEG
mf:            dbit 1
m_flag:        dbit 1
s_flag:        dbit 1
err_tmp:       dbit 1
err_tmp_150:   dbit 1
display_flag:  dbit 1

inc_lock:      dbit 1

start:         dbit 1  ; Start the FSM
temp_state1:   dbit 1
temp_state3:   dbit 1
temp_state5:   dbit 1

debug_bit:     dbit 1 ;Set to true to check which lines of code actually execute
debug_bit1:    dbit 1
kill_flag:      dbit 1 ; kill switch

; For push buttons
PB0: dbit 1  ; Start/Pause
PB1: dbit 1  ; Toggle selected parameter
PB2: dbit 1  ; Increment
PB3: dbit 1  ; Decrement
PB4: dbit 1  ; Unused or extra

PB0_db: dbit 1
PB1_db: dbit 1
PB2_db: dbit 1
PB3_db: dbit 1
PB4_db: dbit 1

sound_flag: dbit 1

;SETATS

; We include math32 at the end of initialization
$NOLIST
$include(math32.inc)
$LIST

;----------------------------------------------------------------------
; Timer2 Initialization & ISR
;----------------------------------------------------------------------






Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	; Timer 0 doesn't have 16-bit auto-reload, so
	clr TR0
	mov TH0, #high(TIMER0_RELOAD) ;TH0 and TL0 are only 8 bits, so we need to load each half individually
	mov TL0, #low(TIMER0_RELOAD) ; For 0xF830 for example, #high gives 0xF8, #low gives #0x30
	setb TR0 ; Start timer 0
	jb sound_flag, Timer0_ISR_Sound
	clr SOUND_OUT
	sjmp Timer0_ISR_Done
Timer0_ISR_Sound:
	cpl SOUND_OUT
	sjmp Timer0_ISR_Done
Timer0_ISR_Done:
	reti


Timer2_Init:
    mov T2CON, #0       ; Stop timer, mode = auto-reload
    mov TH2, #high(TIMER2_RELOAD)
    mov TL2, #low(TIMER2_RELOAD)
    orl T2MOD, #0b1010_0000    ; Enable auto-reload
    mov RCMP2H, #high(TIMER2_RELOAD)
    mov RCMP2L, #low(TIMER2_RELOAD)
    clr  a
    mov  Count1ms+0, a
    mov  Count1ms+1, a
    orl  EIE, #0x80     ; Enable timer2 interrupt (ET2=1)
    setb TR2            ; Start Timer2
    ret

Timer2_ISR:
    clr TF2 ; Must clear TF2 manually on N76
    push acc
    push psw
    mov save_x+0, x+0
    mov save_x+1, x+1
    mov save_x+2, x+2
    mov save_x+3, x+3

    ;---------------------------------
    ; PWM for SSR control
    ;---------------------------------
    inc pwm_counter ;Every 10ms, pwm_counter is incremented
    clr c
    mov a, pwm
    subb a, pwm_counter ; if pwm_counter <= pwm, c=1, so if pwm=20 for example, if 210ms has passed, c = 0, and the SSR box is always on
    ;cpl c
    mov SSR_BOX, c
    
CheckButton0:
    jb PB0, CheckButton1 ;Skip to CheckPWM if a button is not pushed
    inc debounce_count_0
    mov a, debounce_count_0
    cjne a, #15, CheckButton1
	clr PB0_db
    mov debounce_count_0, #0
    clr a

CheckButton1:
    jb PB1, CheckButton2 ;Skip to CheckPWM if a button is not pushed
    inc debounce_count_1
    mov a, debounce_count_1
    cjne a, #15, CheckButton2
	clr PB1_db
    mov debounce_count_1, #0
    clr a

CheckButton2:
    jb PB2, CheckButton3 ;Skip to CheckPWM if a button is not pushed
    inc debounce_count_2
    mov a, debounce_count_2
    cjne a, #15, CheckButton3
	clr PB2_db
    mov debounce_count_2, #0
    clr a

CheckButton3:
    jb PB3, CheckButton4 ;Skip to CheckPWM if a button is not pushed
    inc debounce_count_3
    mov a, debounce_count_3
    cjne a, #15, CheckButton4
	clr PB3_db
    mov debounce_count_3, #0
    clr a

CheckButton4:
    jb PB4, CheckPWM ;Skip to CheckPWM if a button is not pushed
    inc debounce_count_4
    mov a, debounce_count_4
    cjne a, #15, CheckPWM
	clr PB4_db
    mov debounce_count_4, #0
    clr a


CheckPWM:
    mov a, pwm_counter
    cjne a, #100, State_0 ; If 1 second has not passed, skip to State_0
    mov pwm_counter, #0 ; Reset pwm_counter
    mov a, state
    cjne a, #0, SecondsLogic
    ljmp State_0


SecondsLogic:
    inc seconds ; Increment seconds
    inc state_sec ; Will only increment in states 2 and 4, gets reset to 0 in all other states otherrwise
    clr a
    mov a, state
    cjne a, #1, State_0
    mov a, seconds
    cjne a, #60, State_0 ;If exactly 60 seconds has not passed, skip to State_0, otherwise set m_flag to indicate a minute has passed
    setb m_flag
    ljmp State_0


State_0:
    mov a, state
	cjne a, #0, State_1
    clr a
    mov state_sec, #0
	mov pwm, #0
	jnb start, jumpy 
	mov state, #1
	ljmp Display_1
	
State_1:
    jb kill_flag, jumpyError
	mov a, state
	cjne a, #1, State_2
	mov state_sec, #0
	mov pwm, #100 					; set pwm for relfow oven to 100%
	jb m_flag, Cond_check
    setb debug_bit1
	jnb temp_state1, jumpy 	; mf = 1 if oven temp <= set temp, jump out of ISR. mf = 0 if oven temp > set temp, thus move onto next state 			
	clr a						
	mov state, #2
    mov state_sec, #0
	ljmp State_2

Cond_check: ; cjne is not bit-addressable, therefore we must move bits into byte registers (i.e. accumulator and register b)
	setb debug_bit
    jnb err_tmp, jumpyErrorKill
    clr m_flag
	ljmp jumpy


State_2: ;transition to state three if more than 60 seconds have passed
    jb kill_flag, jumpyError
	mov a, state
	cjne a, #2, State_3
	mov pwm, #20
	jb err_tmp_150, jumpyErrorKill
    clr a 	

    
    mov a, state_sec
    clr c
    subb a, time_soak ; If state_sec - time_soak is negative (so not enough time has passed), then c = 1, 
    jc jumpy
	mov state, #3
    mov state_sec, #0

jumpy:
    ljmp Display_0
jumpyError:
    ljmp State_error
jumpyErrorkill:
    ljmp State_error_kill


State_3: 
    jb kill_flag, State_error
	mov a, state
	cjne a, #3, State_4 ; check if state = 3, if not, move to state_4
	mov pwm, #100 ; set pwm to 100%
    mov state_sec, #0
	jb err_tmp_150, State_error_kill
	;mov c, temp_state3
	;clr a 							; clear the accumulator
	;mov acc.0, c
	;clr c 							; clear the carry bit
	;cjne a, #0, Timer2_ISR_done ;
    jnb temp_state3, jumpy
	clr a
    mov state_sec, #0
	mov state, #4

State_4:
    jb kill_flag, State_error
	mov a, state
	cjne a, #4, State_5
	mov pwm, #20
	jb err_tmp_150, State_error_kill
    clr a
    mov a, state_sec
    subb a, time_refl
    jc jumpy    
	mov state, #5
    mov state_sec, #0

State_5:
	setb sound_flag
    jb kill_flag, State_error
	mov a, state
	cjne a, #5, jumpy
	mov pwm, #0
    mov state_sec, #0
    jb err_tmp_150, State_error_kill
    jnb temp_state5, jumpy
	mov state, #0
    mov state_sec, #0
    sjmp State_end


State_error_kill:
	mov a, #0
	mov state, a
    sjmp State_end
    
State_error:
	mov a, #0
	mov state, a
    sjmp Display_0

State_end:
    clr c
    mov c, start
    clr a
    mov acc.0, c
    cpl a                 		; set the flag to 1, indicating that the FSM should begin
    mov c, acc.0
    mov start, c
    clr a
    clr c
    mov c, kill_flag
    mov acc.0, c
    cpl a                    ; compliment kill
    mov c, acc.0 
    mov kill_flag, c
    clr m_flag
    mov seconds, #0
    sjmp Display_0

	; probably should put branch for warning message here

; Second FSM for displaying values for each state

Display_0: ; Displays state 0 - Oven On
    ljmp Display_1 ;Temporary, test until we set up Display_0
    mov a, selected_state
    cjne a, #0, Display_1
    ljmp Timer2_ISR_done

Display_1: ; Displays state 1 - Soak Temp.
    mov a, selected_state
    cjne a, #1, Display_2
    jnb display_flag, jumpyEnd
    Set_Cursor(1,1)
    Send_Constant_String(#temp_soak_string)
    clr display_flag
    Load_x(0)
    mov x+0, temp_soak
    lcall hex2bcd
    Set_Cursor(2,1)
    Display_BCD(bcd+1)
    Display_BCD(bcd+0)
    Load_x(0) 
    ljmp Timer2_ISR_done

jumpyEnd:
    ljmp Timer2_ISR_done

Display_2: ; Displays state 2 - Soak Time
    mov a, selected_state
    cjne a, #2, Display_3
    jnb display_flag, jumpyEnd
    Set_Cursor(1,1)
    Send_Constant_String(#time_soak_string)
    clr display_flag
    Load_X(0)
    mov x+0, time_soak
    lcall hex2bcd
    Set_Cursor(2,1)
    Display_BCD(bcd+1)            ; x is 8 bits, we represent in hex as 0xFF, therefore FF is displayed
    Display_BCD(bcd+0)
    Load_x(0) 
    ljmp Timer2_ISR_done



Display_3: ; Displays state 3 - Reflow Temp.
    mov a, selected_state
    cjne a, #3, Display_4
    jnb display_flag, jumpyEnd
    Set_Cursor(1,1)
    Send_Constant_String(#temp_refl_string)
    clr display_flag
    Load_X(0)
    mov x+0, temp_refl
    lcall hex2bcd
    Set_Cursor(2,1)
    Display_BCD(bcd+1)
    Display_BCD(bcd+0)
    Load_X(0) 
    ljmp Timer2_ISR_done
    

Display_4: ; Displays state 4 - Reflow Time
    mov a, selected_state
    cjne a, #4, Timer2_ISR_Done
    jnb display_flag, Timer2_ISR_done
    Set_Cursor(1,1)
    Send_Constant_String(#time_refl_string)
    clr display_flag
    Load_X(0)
    mov x+0, time_refl
    lcall hex2bcd
    Set_Cursor(2,1)
    Display_BCD(bcd+1)            ; x is 8 bits, we represent in hex as 0xFF, therefore FF is displayed
    Display_BCD(bcd+0)
    Load_X(0)               
    ljmp Timer2_ISR_done
    

Timer2_ISR_done:
    pop psw
    pop acc
    mov x+0, save_x+0 
    mov x+1, save_x+1
    mov x+2, save_x+2
    mov x+3, save_x+3
    reti

;----------------------------------------------------------------------
; Initialization
;----------------------------------------------------------------------
Init_All:
    ; Configure all the pins for bidirectional I/O
    mov P3M1, #0x00
    mov P3M2, #0x00
    mov P1M1, #0x00
    mov P1M2, #0x00
    mov P0M1, #0x00
    mov P0M2, #0x00

    lcall Timer2_Init

    ; Timer1 for UART
    orl  CKCON, #0x10     ; Timer1 uses system clock
    orl  PCON,  #0x80     ; SMOD=1 -> double baud
    mov  SCON,  #0x52     ; UART mode 1, REN=1
    anl  T3CON, #0b11011111
    anl  TMOD,  #0x0F
    orl  TMOD,  #0x20     ; Timer1 Mode2 (8-bit auto-reload)
    mov  TH1, #TIMER1_RELOAD
    setb TR1

    ; Timer0 for waitms
    clr TR0
    orl CKCON, #0x08
    anl TMOD,  #0xF0
    orl TMOD,  #0x01      ; 16-bit mode
    mov TH0, #high(TIMER0_RELOAD)
    mov TL0, #low(TIMER0_RELOAD)
    setb ET0 ; Enable timer 0  interrupt
    setb TR0 ; Start timer 0
    ; ADC pins: P1.1 (AIN7), P1.7 (AIN0)
    orl P1M1, #0b10000010 ; Set P1.1 & P1.7 as input
    anl P1M2, #0b01111101

    ; Initialize ADC
    anl ADCCON0, #0xF0
    orl ADCCON0, #0x07    ; default to channel 7
    mov AINDIDS, #0x00    ; disable all digital inputs
    orl AINDIDS, #0b10000001 ; activate AIN0 and AIN7
    orl ADCCON1, #0x01    ; enable ADC
    ret

;----------------------------------------------------------------------
; Delay Routines
;----------------------------------------------------------------------
wait_1ms:
    clr TR0
    clr TF0
    mov TH0, #high(TIMER0_RELOAD)
    mov TL0, #low(TIMER0_RELOAD)
    setb TR0
    jnb TF0, $
    ret

; Wait R2 milliseconds
waitms:
    lcall wait_1ms
    djnz R2, waitms
    ret

;----------------------------------------------------------------------
; LCD_PB: Read the 5 push buttons into PB0..PB4 bits
;----------------------------------------------------------------------
LCD_PB:
    ; Default all PB bits to 1 (released)
    setb PB0 
    setb PB1
    setb PB2
    setb PB3
    setb PB4
    ; The input pin is idle-high (pull-up)
    setb PB_INPUT_PIN

    ; Set MUX lines to 0 first
    clr MUX_CONTROL_0
    clr MUX_CONTROL_1
    clr MUX_CONTROL_2
    clr MUX_CONTROL_3
    clr MUX_CONTROL_4

    ;---------------------------------
    ; Debouncing
    ;---------------------------------

    ; Now set all MUX lines = 1 to read them individually
    setb MUX_CONTROL_0
    setb MUX_CONTROL_1
    setb MUX_CONTROL_2
    setb MUX_CONTROL_3
    setb MUX_CONTROL_4

    ; Check PB4
    clr MUX_CONTROL_4
    mov c, PB_INPUT_PIN
    mov PB4, c
    setb MUX_CONTROL_4

    ; Check PB3
    clr MUX_CONTROL_3
    mov c, PB_INPUT_PIN
    mov PB3, c
    setb MUX_CONTROL_3

    ; Check PB2
    clr MUX_CONTROL_2
    mov c, PB_INPUT_PIN
    mov PB2, c
    setb MUX_CONTROL_2

    ; Check PB1
    clr MUX_CONTROL_1
    mov c, PB_INPUT_PIN
    mov PB1, c
    setb MUX_CONTROL_1

    ; Check PB0
    clr MUX_CONTROL_0
    mov c, PB_INPUT_PIN
    mov PB0, c
    setb MUX_CONTROL_0


LCD_PB_Done:
    setb LCD_RS
    setb LCD_E
    ret

;----------------------------------------------------------------------
; Display_formated_BCD: Display the result with decimal
;----------------------------------------------------------------------
Display_formated_BCD:
    Set_Cursor(2, 8)
    Display_BCD(bcd+2)
    Display_BCD(bcd+1)
    Display_char(#'.')
    Display_BCD(bcd+0)
    Display_char(#0xDF)    ; Degree symbol
    Display_char(#'C')
    Set_Cursor(2,8)
    Display_char(#' ')
    Set_Cursor(1,15)
    Display_BCD(state)
    ret

;----------------------------------------------------------------------
; Read_ADC: reads current ADC channel into R0:R1 (12-bit)
;----------------------------------------------------------------------
Read_ADC:
    clr  ADCF
    setb ADCS
    jnb  ADCF, $          ; Wait conversion
    mov  a, ADCRL
    anl  a, #0x0F
    mov  R0, a
    mov  a, ADCRH
    swap a
    push acc
    anl  a, #0x0F
    mov  R1, a
    pop  acc
    anl  a, #0xF0
    orl  a, R0
    mov  R0, a
    ret

;----------------------------------------------------------------------
; New code for push-button-based FSM parameter updates
; We intercept button presses in SendSerial
;----------------------------------------------------------------------
SendBCD:

	mov a, bcd+2
	anl a, #0x0F ; Isolate ones place
	add a, #'0' ; Convert value to ASCII
	lcall SendSerial

	mov a, bcd+1
	anl a, #0xF0 ; Isolate tens place
	swap a ; Put high nibble into lower nibble
	add a, #'0' ; Convert value to ASCII
	lcall SendSerial

	mov a, bcd+1
	anl a, #0x0F ; Isolate ones place
	add a, #'0' ; Convert value to ASCII
	lcall SendSerial

	mov a, #'.'
	lcall SendSerial

	mov a, bcd+0
	anl a, #0xF0 ; Isolate 0.1 place
	swap a ; Put high nibble into lower nibble
	add a, #'0' ; Convert value to ASCII
	lcall SendSerial

	mov a, bcd+0
	anl a, #0x0F ; Isolate 0.01 place
	add a, #'0' ; Convert value to ASCII
	lcall SendSerial

	mov a, #'\n'
	lcall SendSerial

	mov a, #'\r'
	lcall SendSerial

	ret

SendSerial:
	clr TI
	mov SBUF, a
	jnb TI, $
	ret

button_logic:
    jnb PB0_db, start_oven
    jnb PB1_db, toggle_state
    jnb PB2_db, inc_value
    jnb PB3_db, dec_value
    ; PB4 is unused for now, do nothing if pressed.

    ret

; Start the FSM
start_oven:
    setb PB0_db
	clr c
    mov c, start
    clr a
    mov acc.0, c
    cpl a                 		; set the flag to 1, indicating that the FSM should begin
    mov c, acc.0
    mov start, c
    clr a
    clr c
    mov c, kill_flag
    mov acc.0, c
    cpl a                    ; compliment kill
    mov c, acc.0 
    mov kill_flag, c
    ;mov start, # 1                                ; return to main or update display as needed
    ljmp end_button_logic           ; jump to exit logic

; Toggle which parameter is selected (1..4)
toggle_state:
    setb display_flag
    setb PB1_db
    mov a, selected_state           ; load the selected state to the accumulator
    add a, #1                       ; icnrement the selection
    cjne a, #5, noWrap              ; if not greater than 4, jump to noWrap
    mov a, #1                       ; if (selected_state == 5), reset the selected state, i.e. selected_state == 1
noWrap:
    mov selected_state, a           ; store the updated selected_state
    ljmp end_button_logic           ; jump to exit logic

; Increment whichever parameter is selected
; ** DOUBLE CHECK THIS LOGIC IM NOT TOO SURE **
inc_value:
    setb display_flag
    setb PB2_db
    mov a, selected_state           ; load the selected state into the accumulator
    cjne a, #1, checkState2         ; if selected_state != temp_soak, check the next selected state
    inc temp_soak                   ; increment temp_soak if above condition not true
    ljmp end_button_logic           ; jump to exit logic

checkState2:                    
    cjne a, #2, checkState3         ; if not time_soak, check the next parameter
    inc time_soak                   ; increment time_soak
    ljmp end_button_logic           ; jump to exit logic

checkState3:
    cjne a, #3, checkState4         ; if not temp_refl, check next parameter
    inc temp_refl                   ; increment temp_refl
    ljmp end_button_logic           ; jump to exit logic

checkState4:                        
    cjne a, #4, end_button_logic    ; if not time_refl, exit 
    inc time_refl                   ; inc time_refl
    ljmp end_button_logic           ; jump to exit logic

; Decrement whichever parameter is selected
; ** SAME IDEA BUT CHECK THE LOGIC PLEASE ** 
dec_value:
    setb display_flag
    setb PB3_db
    mov a, selected_state
    
    cjne a, #1, dcheckState2
    djnz temp_soak, end_button_logic
    ljmp end_button_logic

dcheckState2:
    cjne a, #2, dcheckState3
    djnz time_soak, end_button_logic
    ljmp end_button_logic

dcheckState3:
    cjne a, #3, dcheckState4
    djnz temp_refl, end_button_logic
    ljmp end_button_logic

dcheckState4:
    cjne a, #4, end_button_logic
    djnz time_refl, end_button_logic
    ljmp end_button_logic

end_button_logic:
    ret


;----------------------------------------------------------------------
; main
;----------------------------------------------------------------------
main:
    mov sp, #0x7F
    lcall Init_All
    lcall LCD_4BIT
    lcall Timer2_Init ; initialize interupts 
    setb EA

    clr SSR_BOX

    mov MeasurementCounter+0, #1
    mov MeasurementCounter+1, #0
    mov TimePerSample, #2

    mov SamplesPerDisplay+0, #low(SAMPLES_PER_DISPLAY)
    mov SamplesPerDisplay+1, #high(SAMPLES_PER_DISPLAY)

    ; We start with "state=0" (idle)
    mov state, #0
    clr start ; compliment in start_oven
    clr m_flag
    setb kill_flag

    ; Default setpoints
    mov temp_soak, #100
    mov time_soak, #55
    mov temp_refl, #210
    mov time_refl, #40

    ; Which parameter we are currently adjusting: 1=temp_soak,2=time_soak,3=temp_refl,4=time_refl
    mov selected_state, #1

    mov LastMeasurement+0, #0
    mov LastMeasurement+1, #0
    mov LastMeasurement+2, #0
    mov LastMeasurement+3, #0
    
    clr temp_state1
    clr temp_state3
    clr debug_bit
    clr debug_bit1
    clr err_tmp
    clr err_tmp_150
    setb display_flag
    mov seconds, #0
    mov state_sec, #0
    mov pwm_counter, #0
    mov pwm, #0
    setb PB0_db
    setb PB1_db
    setb PB2_db
    setb PB3_db
    setb PB4_db
    clr sound_flag
    ; Show initial LCD message
    ;Set_Cursor(1, 1)
    ;Send_Constant_String(#test_message)

Forever:
    ; Always read the push buttons each pass
	lcall LCD_PB
	lcall button_logic
	

SkipCheck:
    ; Example read reference (AIN0)
    anl  ADCCON0, #0xF0
    orl  ADCCON0, #0x00 ; Channel0
    lcall Read_ADC
    mov  VAL_LM4040+0, R0
    mov  VAL_LM4040+1, R1

    ; Read LM335 on AIN7
    anl  ADCCON0, #0xF0
    orl  ADCCON0, #0x07
    lcall Read_ADC

    ; Convert to "voltage" in x
    mov  x+0, R0
    mov  x+1, R1
    mov  x+2, #0
    mov  x+3, #0
    Load_y(40959)       ; e.g. 4.0959 => times 10000 in math
    lcall mul32
    mov  y+0, VAL_LM4040+0
    mov  y+1, VAL_LM4040+1
    mov  y+2, #0
    mov  y+3, #0
    lcall div32

    ; Add partial result to StoreMeasurements
    mov  y+0, StoreMeasurements+0
    mov  y+1, StoreMeasurements+1
    mov  y+2, StoreMeasurements+2
    mov  y+3, StoreMeasurements+3
    lcall add32
    mov  StoreMeasurements+0, x+0
    mov  StoreMeasurements+1, x+1
    mov  StoreMeasurements+2, x+2
    mov  StoreMeasurements+3, x+3

    ; Read thermocouple on AIN4
    anl  ADCCON0, #0xF0
    orl  ADCCON0, #0x04
    lcall Read_ADC

    mov  x+0, R0
    mov  x+1, R1
    mov  x+2, #0
    mov  x+3, #0
    Load_y(40959)
    lcall mul32
    mov  y+0, VAL_LM4040+0
    mov  y+1, VAL_LM4040+1
    mov  y+2, #0
    mov  y+3, #0
    lcall div32

    Load_y(10000)
    lcall mul32

	Load_y(9700)
    lcall div32
    
    Load_y(200)
    lcall add32
    
	


    ; Add partial result to StoreThermocouple
    mov  y+0, StoreThermocouple+0
    mov  y+1, StoreThermocouple+1
    mov  y+2, StoreThermocouple+2
    mov  y+3, StoreThermocouple+3
    lcall add32
    mov  StoreThermocouple+0, x+0
    mov  StoreThermocouple+1, x+1
    mov  StoreThermocouple+2, x+2
    mov  StoreThermocouple+3, x+3

    ; Delay between samples
    mov R2, TimePerSample
    lcall waitms

    ; Decrement measurement counter
    dec MeasurementCounter+0
    mov a, MeasurementCounter+0
    cjne a, #0xFF, CheckHigh
    dec MeasurementCounter+1
CheckHigh:
    mov a, MeasurementCounter+0
    orl a, MeasurementCounter+1
    jz  DisplayValue
    ljmp EndForever

;----------------------------------------------------------------------
; If enough measurements collected -> compute final temperature
;----------------------------------------------------------------------
DisplayValue:
    Load_y(0)
    ; Combine for LM335 reading
    mov x+0, StoreMeasurements+0
    mov x+1, StoreMeasurements+1
    mov x+2, StoreMeasurements+2
    mov x+3, StoreMeasurements+3
    mov a, SamplesPerDisplay+0
    mov y+0, a
    mov MeasurementCounter+0, a
    mov a, SamplesPerDisplay+1
    mov y+1, a
    mov MeasurementCounter+1, a
    lcall div32

    ; Subtract 273.00 => Celsius reading
    Load_y(27300)
    lcall sub32
    mov FinalLM335+0, x+0
    mov FinalLM335+1, x+1
    mov FinalLM335+2, x+2
    mov FinalLM335+3, x+3

    ; Combine for thermocouple reading
    Load_y(0)
    mov x+0, StoreThermocouple+0
    mov x+1, StoreThermocouple+1
    mov x+2, StoreThermocouple+2
    mov x+3, StoreThermocouple+3
    mov a, SamplesPerDisplay+0
    mov y+0, a
    mov a, SamplesPerDisplay+1
    mov y+1, a
    lcall div32

    ; Add thermocouple to LM335 reading => final in x
    Load_y(0)
    mov y+0, FinalLM335+0
    mov y+1, FinalLM335+1
    mov y+2, FinalLM335+2
    mov y+3, FinalLM335+3
    lcall add32
    
    clr mf
	Load_y(17100)
	lcall x_gteq_y
	jnb mf, SkipSub
	Load_y(300)
	lcall sub32
SkipSub:

	clr mf
	Load_y(17500)
	lcall x_gteq_y
	jnb mf, SkipSub2
	Load_y(300)
	lcall sub32
	
SkipSub2:

	clr mf
	Load_y(18200)
	lcall x_gteq_y
	jnb mf, SkipSub3
	Load_y(450)
	lcall sub32
	
SkipSub3:

	mov FinalTemp+0, x+0
    mov FinalTemp+1, x+1
    mov FinalTemp+2, x+2
    mov FinalTemp+3, x+3
    ; --------------------------------------------------------
    ; Compare final temperature with soak/reflow setpoints
    ; --------------------------------------------------------
    clr mf
    Load_y(100)
    mov x+0, temp_soak
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall mul32
    mov y+0, FinalTemp+0
    mov y+1, FinalTemp+1
    mov y+2, FinalTemp+2
    mov y+3, FinalTemp+3
    lcall x_lteq_y ; mf = 1 if temp_soak<=FinalTemp
    mov c, mf
    mov temp_state1, c

    clr mf
    Load_y(100)
    mov x+0, temp_refl
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall mul32
    mov y+0, FinalTemp+0
    mov y+1, FinalTemp+1
    mov y+2, FinalTemp+2
    mov y+3, FinalTemp+3
    lcall x_lteq_y ; mf = 1 if temp_refl<=FinalTemp
    mov c, mf
    mov temp_state3, c

    ; Check error states
    mov x+0, FinalTemp+0
    mov x+1, FinalTemp+1
    mov x+2, FinalTemp+2
    mov x+3, FinalTemp+3

    clr mf
    Load_y(25000)
    lcall x_gteq_y ; mf = 1 if FinalTemp<=250
    mov c, mf
    mov err_tmp_150, c

    clr mf
    Load_y(5000)
    lcall x_gteq_y ; mf = 1 if FinalTemp>=50
    mov c, mf
    mov err_tmp, c

    clr mf
    Load_y(3000)
    lcall x_lteq_y ; mf = 1 if FinalTemp<=60
    mov c, mf
    mov temp_state5, c

	

    ; Convert FinalTemp => BCD => display
    lcall hex2bcd
    lcall SendBCD
    
   ; jnb display_temp EndForever
    lcall Display_formated_BCD

    mov StoreMeasurements+0, #0
    mov StoreMeasurements+1, #0
    mov StoreMeasurements+2, #0
    mov StoreMeasurements+3, #0

    mov StoreThermocouple+0, #0
    mov StoreThermocouple+1, #0
    mov StoreThermocouple+2, #0
    mov StoreThermocouple+3, #0

    mov FinalLM335+0, #0
    mov FinalLM335+1, #1
    mov FinalLM335+2, #2
    mov FinalLM335+3, #3

EndForever:
    ; Always read the push buttons each pass
    ;lcall LCD_PB
    ; Reset accumulators

    mov x+0, #0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    ljmp Forever

END
