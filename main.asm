;PWM and bit signal Controler
;8-ch PWM output, 16-ch bit (on/off) output @ 50Hz

;At 12MHz, 12T:
;1 cycle = 1 micro second
;00000-00500: PWM all high, read UART
;00500-02500: PWM to 0 according to input
;02500-20000: Process input data

;PWM Resulution: 1/250
;Refresh every 8us, 8us * 250times = 2000us = 2500us - 500us

;P0: 8-bit PWM output
;P1, P2: 16-bit ON/OFF output
;P3.0, P3.1 (UART): Not used
;P3.2 (INT0): Interupt, system clock @ 50Hz, use this for system sync
;P3.3: Not used
;P3.4 to P3.7: Data in
;P4.4-P4.5 (Pin29-30): Chip ID, config later on board by short (0-3)

;Input data format (5 bits every time, use 5 bit bus, GPIO):
;(P0.0L, P0.0H, P0.1L, P0.1H, ..., P0.7L, P0.7H, P1L, P1H, P2L, P2H)*4, CHECK 
;P1, P2: ON/OFF signal
;P0.x: Duty time (0-250)
;P3.4	P3.5	P3.6	P3.7
;Data.0	Data.1	Data.2	Data.3
;4 bits pre word, 20 words pre chip installed, one check word at the end
;If check fail, ignor this signal, remained last signal

;Notation: COM MA, ND  ;Comments (current step cycle, cycle remainds before step)

;=====================================================================

;STC89C52RC_90C special I/O
P4 EQU 0xE8				;Address for port P4

;Map
ORG 0x00
	JMP INI
ORG 0x03
	JMP PRE_READ

;Ini
INI:
	;Ini I/O ports
	MOV P3, #0xFF			;Turn on P3, prepare to read
	MOV P0, #0x00			;Turn off P0, P1, P2
	MOV P1, #0x00
	MOV P2, #0x00
	;Set chip ID
	MOV P4, #0xFF			;Prepare to read chip ID
	MOV A, P4			;Get chip ID
	ANL A, #0x70			;Select P4.4-4.6
	SWAP A				;A.4-.6 to A.0-.2
	MOV R7, A			;Save chip ID in R7
	;Get address of input data according to chip ID, base address = 128 + ID * 20 + 16, saved in R6
	MOV A, R7			;Set ID
	MOV B, #0x14			;Set 20
	MUL AB				;times
	MOV R0, A			;Get Id * 20
	ADD A, #0x80			;Add 128
	MOV R7, A			;Get base address, PWM at R7 to R7 + 15, On/OFF at R7 + 16 to R7 + 19
	;Enable interupt
	SETB IT0			;Set INT0 to edge trigger
	SETB EX0			;Enable INT0
	SETB EA				;Enable INT
	JMP $				;Wait for UART interupt

;Interupted by INT, prepare to read data then
PRE_READ:
	MOV P0, #0xFF			;PWM beginning, all high (x,500)
	MOV R0, #0x80			;Pointer for input data, saved in RAM (2,500)
	CLR A				;Prepare XOR check (1,498)

;Read data (exclude the check word) for 4 * 20 = 80 frames, save in RAM address 0x80 - 0xCF (6 * 80 = 480,497)
READ:
	MOV @R0, P3			;Read and save data of a frame [1010xxxx], lower 4 bits is garbage (2,6)
	XRL A, @R0			;XOR input data (1,4)
	INC R0				;Pointer++ (1,3)
	CJNE R0, #0xD0, READ		;All input readed, 0x80 + 4 * 20 = 0xD0, if not, go to read (2,2)

;Read end, check input by XOR. If verify, 1010 XOR 1010 = 0000; otherwise > 0
AFTER_READ:
	ANL A, #0xF0			;Select higher 4 bits only (1,17)
	XRL A, P3			;XOR check word, if verify, A should be 0x00(1,16)
	ANL A, #0xF0			;Select higher 4 bits only (1,15)
	MOV R2, A			;Save verify result in R2 (1,14)

;Output ON/OFF signal and prepare to read from X-RAM (for PWM signal), the data is from last successfully input
PRE_OUTPUT:
	MOV R0, #0xFC			;Set pointer of output data, saved in X-RAM ini value 252 (1,13)
	MOVX A, @R0			;Read from X-RAM for P2 (2,12)
	MOV P2, A			;Set P2 (1,10)
	DEC R0				;Pointer-- (1,9)
	MOVX A, @R0			;Read from X-RAM for P1 (2,8)
	MOV P1, A			;Set P1 (1,6)
	DEC R0				;Pointer-- (1,5)
	NOP				;Wait for 8 cycles (4,4)
	NOP
	NOP
	NOP
	;May add more NOP if need, due to clock missmatch between MCU system and external devices
	
;Send output data (PWM signal) from X-RAM to output IO (8 cycle pre time, 250 times)
OUTPUT:
	MOVX A, @R0			;Read from X-RAM (2,8)
	MOV P0, A			;Send data to output IO (1,6)
	NOP				;Wait for 3 cycles (3,5)
	NOP
	NOP
	DJNZ R0, OUTPUT			;Pointer--, if not 0, redo this step, until finish all 250 data (2,2)
	
;Process input data (about 17500, but may vary due to the clock is decided by external source, less cycle is better)
PROCESS:
	MOV P0, #0x00			;Close all PWM output

;Check input data
PROCESS_CHECK:
	CJNE R2, #0x00, READ_NG		;Verify result is not 0x00, verify fail, go to READ_NG
	JMP PROCESS_P12			;Otherwise, go to READ_OK
	READ_NG:
	RETI				;Do nothing, output data remainds same as last successfully process

;Process P1 and P2: merge 4-bit input data and save result in X-RAM (0xFB and 0xFC)
PROCESS_P12:
	MOV A, R7			;Pointer fot input data in RAM (ini: base address)
	ADD A, #0x13			;Add 16, which is address of P2High
	;P2
	MOV R1, A			;Pointer for input data of P2High in RAM
	MOV A, @R1			;Get P2High
	MOV R5, A			;Send to R5, prepare for the function
	DEC R1				;Pointer for input data of P2Low
	MOV A, @R1			;Get P2Low
	ACALL FUNC_BITTRANS		;Process data, merge
	MOV R0, #0xFC			;Set pointer for output data in X-RAM (for P2, it is 0xFC, 252)
	MOVX @R0, A			;Save data in X-RAM
	;P1
	DEC R1				;Pointer for input data of P1High
	MOV A, @R1			;Get P1High
	MOV R5, A			;Send to R5, prepare for the function
	DEC R1				;Pointer for input data of P1Low
	MOV A, @R1			;Get P1Low
	ACALL FUNC_BITTRANS		;Process data, merge
	MOV R0, #0xFB			;Set pointer for output data in X-RAM (for P1, it is 0xFB, 251)
	MOVX @R0, A			;Save data in X-RAM

;Process P0, merged input data for P0 and save in RAM slot 0x70 to 0x77, 0x70 for P0.0
PROCESS_MERGEPWM:
	MOV R0, #0x77			;Pointer for merged input data of P0.7
	PROCESS_READ:
	  DEC R1			;Get P0.xHigh
	  MOV A, @R1
	  MOV R5, A			;Send to R5, prepare for the function
	  DEC R1			;Get P0.xLow
	  MOV A, @R1
	  ACALL FUNC_BITTRANS		;Process data, merge
	  MOV @R0, A			;Save data in RAM
	  DEC R0				;Pointer of merged input data --
	  CJNE R0, #0x6F, PROCESS_READ	;Last one 0x70 (P0), decrease then it should be 0x6F
	
;Process P0, draw map of PWM output, saved in X-RAM slot 0x0001 to 0x00FA, fetch 0x00FA for first step
PROCESS_MAPPWM:
	MOV R0, #0xFA			;Pointer for output data in X-RAM (ini: 250)
	MOV R2, #0xFF			;Ini status of PWM, all high
	;Loop for 250 times to draw the map
	  PWM_OUT:
	  MOV R1, #0x78			;Set/reset pointer of channel data (last + 1)
	  CLR A				;Reset ACC
	  ;Loop for 8 times to process 8 channels
	    PWM_IN:
	    RL A			;Get bit of this chennel
	    DEC R1			;Set pointer to this channe
	    MOV R3, A			;Save A in R3
	    MOV A, @R1			;Get time of this channel in ACC
	    DEC A			;Time of current channel -1
	    MOV @R1, A			;Save the time (compare with last outer loop, time value = time value - 1)
	    JNZ	PWM_ON			;If time reachs 0, set to xxxxxxx0, otherwise xxxxxxx1
	    JMP PWM_DONE
	    PWM_ON:
	    INC R3			;Set to xxxxxxx1, without this step, it will be xxxxxxx0
	    PWM_DONE:
	    MOV A, R3			;Get A from R3 back
	    CJNE R2, #0x70, PWM_IN	;All 8 channels process end (for current time), if not, go to PWM_IN
	  ANL A, R1			;AND with R1 (current PWM), so if any channel reaches 0, turn off that channel
	  MOV R1, A			;Save current PWM status in R1
	  MOVX @R0, A			;Save the value in X-RAM (time map)
	  DJNZ R0, PWM_OUT		;Point to next X-RAM address. If all 250 X-RAM processed, next; otherwise go to PWM_OUT
	
;End of process
PROCESS_END:
	RETI				;Return, wait for next interupt

;Because the input data is 4 bits (higher half, 1010xxxx) * 2 words, use this function to merge them into 8 bits * 1 word
;Input: R5 for higher bits, A for lower bits; Output: A
FUNC_BITTRANS:
	ANL A, #0xF0			;Clean garbage bits of lower bits
	SWAP A				;Send to lower half
	XCH A, R5			;Save in R5 and get higher bits
	ANL A, #0xF0			;Clean garbage bits
	ADD A, R5			;Combine lower higher bits
	RET				;End, return

;End
END
