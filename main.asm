;PWM and bit signal Controler
;8-ch PWM output, 16-ch bit (on/off) output @ 50Hz

;At 12MHz, 12T:
;1 cycle = 1 micro second
;00000-00500: PWM all high, Set ON/OFF
;00500-02500: PWM to 0 according to input
;02500-20000: Receive input UART and process

;PWM Resulution: 1/250
;Refresh every 8us (8 cycles), 8us * 250times = 2000us = 2500us - 500us

;P0: 8-bit PWM output
;P1, P2: 16-bit ON/OFF output
;P3.0, P3.1: UART (Using Mode2, Baud 187500)
;P3.2 (INT0): Interupt, use this for system sync. Not used yet, depends on further performance
;P3.3 Reserved
;P3.7-P3.4: Chip ID

;Input data format:
;ID, PWM7, PWM6, PWM5, PWM5, PWM4, PWM3, PWM2, PWM1, PWM0, P2, P1, CHECK
;When ID: BIT = 1; otherwise 0

;When output PWM, the MCU read time map in XRAM
;There is two time map buuffer, XRAM 0x00-- and XRAM 0x01--

;=====================================================================


;Memory map - Byte
	;Cjip ID
	CHIPID		EQU	0x30
	;Port data (where to svae varified UART data)
	PWM7		EQU	0x47
	PWM6		EQU	0x46
	PWM5		EQU	0x45
	PWM4		EQU	0x44
	PWM3		EQU	0x43
	PWM2		EQU	0x42
	PWM1		EQU	0x41
	PWM0		EQU	0x40
	B2		EQU	0x3F
	B1		EQU	0x3E
	;UART buffer (where to save unverified UART data)
	PWM7_T		EQU	0x57
	PWM6_T		EQU	0x56
	PWM5_T		EQU	0x55
	PWM4_T		EQU	0x54
	PWM3_T		EQU	0x53
	PWM2_T		EQU	0x52
	PWM1_T		EQU	0x51
	PWM0_T		EQU	0x50
	B2_T		EQU	0x4F
	B1_T		EQU	0x4E	
	CHECK		EQU	0x4D
	;Working data (used to draw time map)
	PWM_W		EQU	0x20
	PWM_WC		EQU	0x31
	PWM0_W		EQU	0x58
	PWM1_W		EQU	0x59
	PWM2_W		EQU	0x5A
	PWM3_W		EQU	0x5B
	PWM4_W		EQU	0x5C
	PWM5_W		EQU	0x5D
	PWM6_W		EQU	0x5E
	PWM7_W		EQU	0x5F
;Memory map - Bit
	;Draw map working area
	W0		EQU	0x00
	W1		EQU	0x01
	W2		EQU	0x02
	W3		EQU	0x03
	W4		EQU	0x04
	W5		EQU	0x05
	W6		EQU	0x06
	W7		EQU	0x07
	;The UART data should be recieve, otherwise it is for others (ignor)
	UART_RECIEVE	EQU	0x08

	
;Interrupt vector map
ORG	0x00
	JMP	INI
ORG	0x0023
	JMP	UART


;Boot setup
INI:
	;Ini I/O ports
	MOV	P3, #0xFF			;Turn on P3, prepare to read
	MOV	P0, #0x00			;Turn off P0, P1, P2
	MOV	P1, #0x00
	MOV	P2, #0x00
	;Set chip ID
	MOV	A, P3
	SWAP	A
	ANL	A, #0x0F
	MOV	CHIPID, A
	;Setup SFR
	MOV	SP, #0x7F
	MOV	DPTR, #0x0000
	;Set custom memory
	CLR	UART_RECIEVE
	;Setup UART and interrupt
	SETB	ES				;Enable UART interrupt
	SETB	SM0				;UART Mode2
	SETB	REN				;Enable receive data
	SETB	EA				;Enable global interrupt
	CLR	RI				;Clear RI for receive
	JMP	$				;Wait for timer interrupt


;Draw time map for the PWM (This requires 5306 cycles)
DRAW_MAP_INI:
	;Ini
	MOV	R7, PWM7			;First put value in working temp
	MOV	R6, PWM6
	MOV	R5, PWM5
	MOV	R4, PWM4
	MOV	R3, PWM3
	MOV	R2, PWM2
	MOV	R1, PWM1
	MOV	R0, PWM0
	INC	R7
	INC	R6
	INC	R5
	INC	R4
	INC	R3
	INC	R2
	INC	R1
	INC	R0
	MOV	PWM_W, #0xFF
	MOV	DPL, #0xFB			;250 + 1

;Draw map in loop
DRAW_MAP_LOOP7:
	DJNZ	R7, DRAW_MAP_LOOP6		;If working temp is 0, write 0 to that bit
	CLR	W7
DRAW_MAP_LOOP6:
	DJNZ	R6, DRAW_MAP_LOOP5
	CLR	W6
DRAW_MAP_LOOP5:
	DJNZ	R5, DRAW_MAP_LOOP4
	CLR	W5
DRAW_MAP_LOOP4:
	DJNZ	R4, DRAW_MAP_LOOP3
	CLR	W4
DRAW_MAP_LOOP3:
	DJNZ	R3, DRAW_MAP_LOOP2
	CLR	W3
DRAW_MAP_LOOP2:
	DJNZ	R2, DRAW_MAP_LOOP1
	CLR	W2
DRAW_MAP_LOOP1:
	DJNZ	R1, DRAW_MAP_LOOP0
	CLR	W1
DRAW_MAP_LOOP0:
	DJNZ	R0, DRAW_MAP_LOOPX
	CLR	W0
DRAW_MAP_LOOPX:
	MOV	A, PWM_W			;Put the value in XRAM
	MOVX	@DPTR, A
	DJNZ	DPL, DRAW_MAP_LOOP7		;Lopp this for 252 times until DPTR hits 0
	XRL	DPH, #0x01			;Save the timemap buffer
	
	
;Output
OUTPUT:
	CLR	EA				;This is time critical, disablr the interrupt
	MOV	P0, #0xFF
	

;UART interrupt
UART:
	JBC	RI, UART_GET			;Receive interrupt
	JBC	TI, UART_END			;Send interrupt
	RETI					;This should never happen, write this just in case

;UART received command
UART_GET:
	JB	RB8, UART_GET_ID		;RB8 = 1, this is ID frame
	JB	UART_RECIEVE, UART_GET_CHECKSUM	;UART_RECIEVE = 1, this is my data
	RETI

;Process Data
UART_GET_DATA:
	MOV	A, #CHECK			;Get buffer RAM pointer, save in R0
	ADD	A, R7
	MOV	R0, A
	MOV	@R0, SBUF			;Read date from UART to RAM
	MOV	A, @R0				;Calculate checksum
	XRL	CHECK, A
	RETI					;Not my data, do nothing

;UART receive data process
UART_GET_CHECKSUM:
	DJNZ	R7, UART_GET_DATA		;UART counter -1, if not zero, go receiver data
	CLR	UART_RECIEVE			;Clear UART_RECIEVE flag
	MOV	A, SBUF
	XRL	A, CHECK			;If checksum matched, A will be 0
	JNZ	UART_END			;Do nothing, if A != 0 (not matched)
	CLR	REN				;Temp disable UART receiver interrupt
	MOV	B1, B1_T			;Transfer data from temp to perm
	MOV	B2, B2_T
	MOV	PWM7, PWM7_T
	MOV	PWM6, PWM6_T
	MOV	PWM5, PWM5_T
	MOV	PWM4, PWM4_T
	MOV	PWM3, PWM3_T
	MOV	PWM2, PWM2_T
	MOV	PWM1, PWM1_T
	MOV	PWM0, PWM0_T
	MOV	P0, B1
	SETB	REN
	RETI

;Process ID word, check ID
UART_GET_ID:
	MOV	A, SBUF
	XRL	A, CHIPID			;If ID matched, A will be 0
	JNZ	UART_END			;Do nothing, if A != 0 (not matched)
	SETB	UART_RECIEVE			;Set UART_RECIEVE flag, setup UART counter and checksum
	MOV	R7, #(PWM7_T - CHECK + 0x01)
	MOV	CHECK, #0x00
	RETI

UART_END:
	RETI


	
	
;End
END
