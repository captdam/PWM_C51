;UART - PWM Motor controler
;8-ch PWM output, 16-ch bit (on/off) output @ 50Hz

;At 12MHz, 12T:
;1 cycle = 1 micro second
;00000-00500: PWM all high, read UART
;00500-02500: PWM to 0 according to input
;02500-20000: Process input data

;PWM Resulution: 1/250
;Refresh every 8us, 8us * 250times = 2000us = 2500us - 500us

;UART data format:
;P1 P2 P0.0(0-249) P0.1 P0.2 ... P0.7 (10 bytes)

;Notation: COM MA, ND  ;Comments (current step cycle, cycle remainds before step)

;=====================================================================

;Ini
INI:
	NOP
	JMP $			;Wait for UART interupt

;Interupted by UART, read data then
READ:
	MOV P0, #0xFF		;PWM beginning, all high (x,500)

;Prepare to read from X-RAM, the data is from last time
PRE_OUTPUT:
	MOV R0, #0xFA		;R0: Pointer of output data, ini value 250 (1,1)
	
;Send output data (PWM signal) from X-RAM to output IO (8 cycle pre time, 250 times)
OUTPUT:
	MOVX A, @R0		;Read from X-RAM (2,8)
	MOV P0, A		;Send data to output IO (1,6)
	NOP			;Wait for 2 cycle (3,5)
	NOP
	NOP
	DJNZ R0, OUTPUT	;Pointer--, if not 0, redo this step, until finish all 250 data (2,2)
	
;Process input data
PROCESS:
	NOP
	RETI			;Return, wait for next UART interupt

;End
END
