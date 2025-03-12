; 76E003 ADC test program: Reads channel 7 on P1.1, pin 14

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

CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))

ORG 0x0000
	ljmp main

;                     1234567890123456    <- This helps determine the location of the counter
test_message:     db '', 0
value_message:    db '', 0
cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5

BSEG
mf: dbit 1

$NOLIST
$include(math32.inc)
$LIST

Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
	; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
	mov R1, #200
    mov R0, #104
    djnz R0, $   ; 4 cycles->4*60.285ns*104=25us
    djnz R1, $-4 ; 25us*200=5.0ms
	
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1
	
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer
	
	; Initialize the pin used by the ADC (P1.1) as input.
	orl	P1M1, #0b00000010
	anl	P1M2, #0b11111101
	
	; Initialize and start the ADC:
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x07 ; Select channel 7
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b10000000 ; P1.1 is analog input
	orl ADCCON1, #0x01 ; Enable ADC
	
	ret

InitSerialPort:
	; Configure all the pins for biderectional I/O
	mov	P3M1,#0x00
	mov	P3M2,#0x00
	mov	P1M1,#0x00
	mov	P1M2,#0x00
	mov	P0M1,#0x00
	mov	P0M2,#0x00
	
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #200
    mov R0, #104
    djnz R0, $   ; 4 cycles->4*60.285ns*104=25us
    djnz R1, $-4 ; 25us*200=5.0ms

    ; Now we can proceed with the configuration of the serial port
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD
	setb TR1
    ret
    
wait_1ms:
	clr	TR0 ; Stop timer 0
	clr	TF0 ; Clear overflow flag
	mov	TH0, #high(TIMER0_RELOAD_1MS)
	mov	TL0,#low(TIMER0_RELOAD_1MS)
	setb TR0
	jnb	TF0, $ ; Wait for overflow
	ret 
	
; Wait the number of miliseconds in R2
waitms:
	lcall wait_1ms
	djnz R2, waitms
	ret

; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD:
	Set_Cursor(2,6)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	Set_Cursor(2, 10)
	;Display_char(#'=')
	ret

; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret
    
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret

Hello_World:
    DB  'gay gay gay!', '\r', '\n', 0
   
main:
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
    
    ;initial messages in LCD
	Set_Cursor(1, 1)
    Send_Constant_String(#test_message)
	Set_Cursor(2, 1)
    Send_Constant_String(#value_message)



Forever:
	clr ADCF
	setb ADCS
	jnb ADCF, $
    
    ;Read the ADC result and store in [R1, R0]
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, ADCRL
    mov R0, A
    ;Convert to voltage
	mov x+0, R0
	mov x+1, R1
	mov x+2, #0
	mov x+3, #0
	Load_y(50300) ; VCC voltage measured
	lcall mul32
	Load_y(4095) ; 2^12-1
	lcall div32
		
	Load_y(27315)
	lcall sub32
	 
	Load_y(100)
	lcall mul32
	
	;Convert to BCD and display
	lcall hex2bcd
	
	lcall Display_formated_BCD
	
	
	
	mov A, bcd+2      ; Get second BCD byte (Fractional part)
    swap A            ; Upper nibble
    anl A, #0x0F      ; Mask out lower nibble
    add A, #0x30      ; Convert to ASCII
    lcall putchar     ; Send third digit (6)

    mov A, bcd+2      ; Get second BCD byte again
    anl A, #0x0F      ; Lower nibble
    add A, #0x30      ; Convert to ASCII
    lcall putchar     ; Send fourth digit (8)

	mov A, #'.'
	lcall putchar
	
	mov A, bcd+1      ; Get second BCD byte (Fractional part)
    swap A            ; Upper nibble
    anl A, #0x0F      ; Mask out lower nibble
    add A, #0x30      ; Convert to ASCII
    lcall putchar     ; Send third digit (6)

    mov A, bcd+1      ; Get second BCD byte again
    anl A, #0x0F      ; Lower nibble
    add A, #0x30      ; Convert to ASCII
    lcall putchar     ; Send fourth digit (8)


    mov A, bcd+0      ; Get second BCD byte (Fractional part)
    swap A            ; Upper nibble
    anl A, #0x0F      ; Mask out lower nibble
    add A, #0x30      ; Convert to ASCII
    lcall putchar     ; Send third digit (6)

    mov A, bcd+0      ; Get second BCD byte again
    anl A, #0x0F      ; Lower nibble
    add A, #0x30      ; Convert to ASCII
    lcall putchar     ; Send fourth digit (8)

    mov A, #'\r'      ; Send carriage return
    lcall putchar

    mov A, #'\n'      ; Send newline
    lcall putchar
	
	;Wait 500 ms between conversions
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	
	;cpl P1.7 ; Blinking LED...

	ljmp Forever
	
	

	

	
END
	