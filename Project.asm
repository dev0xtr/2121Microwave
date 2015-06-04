; 2121 Project
; Fraser and Andrew
; Microwave Simulator


.include "m2560def.inc"

; Does LCD commands
.macro do_lcd_command
    push LCD
    clr LCD
    ldi LCD, @0
    rcall lcd_command
    rcall lcd_wait
    pop LCD
.endmacro

; Outputs a register to the LCD
.macro do_lcd_data
    push LCD
    clr LCD
    mov LCD, @0
    rcall lcd_data
    rcall lcd_wait
    pop LCD
.endmacro

; Loads a spesific letter into the LCD Display
.macro load_lcd_letter
	push LCD
	clr LCD
	ldi LCD, @0
	rcall lcd_data
	rcall lcd_wait
	pop LCD
.endmacro

; Defining things, initally from Calculator
.def row = r24          	 ; current row number
.def col = r17          	 ; current column number
.def rmask = r18        	 ; mask for current row during scan
.def cmask = r19             ; mask for current column during scan
.def temp1 = r20			 ; Temp1
.def temp2 = r21			 ; Temp2
.def mul10 = r22			 ; Do we still use it?
.def DoorState = r23		 ; Used for storing the door state
.def LCD = r16				 ; Used for the LCD shockingly
.def bottomNumber = r25		 ; Used for number input
.def powerlevel= r31		 ; Used to store the Power Level

; It is possible this will need to be a different register
.def mode = r26
; The various modes, the value of the register denoting the mode
.equ Entry = 0
.equ Power = 1
.equ Running = 2
.equ Paused = 3
.equ Open = 4
.equ Finished = 5
.equ Opened = 1
.equ Closed = 0

.equ PORTLDIR = 0xF0    	 ; PD7-4: output, PD3-0, input
.equ INITCOLMASK = 0xEF  	 ; scan from the rightmost column,
.equ INITROWMASK = 0x01      ; scan from the top row
.equ ROWMASK = 0x0F     	 ; for obtaining input from Port D
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

; Sets the LCD
.macro lcd_set
    sbi PORTA, @0
.endmacro

; Clears the LCD
.macro lcd_clr
    cbi PORTA, @0
.endmacro

; Real code begins here

RESET:

    ; There will need to be something here for determining the mode

    ; Clear things so there are no leftovers
    clr bottomNumber
	clr doorState
    clr temp1
    clr temp2
	ldi mode, Entry			; Assumes Entry Mode when we reset
	ldi DoorState, Closed
	ser powerLevel			; Sets every bit in the powerlevel so it will be on full power initially

    ; Set up mul10 to actually have 10 in it
    ldi mul10, 10

	;Initialise the Stack
    ldi temp1, low(RAMEND)
    out SPL, temp1
    ldi temp1, high(RAMEND)
    out SPH, temp1

	;Setting up the LCD
    ser LCD
    out DDRF, LCD
    out DDRA, LCD
    clr LCD
    out PORTF, LCD
    out PORTA, LCD

    ;Initial LCD display
    do_lcd_command 0b00111000 ; 2x5x7
    rcall sleep_5ms
    do_lcd_command 0b00111000 ; 2x5x7
    rcall sleep_1ms
    do_lcd_command 0b00111000 ; 2x5x7
    do_lcd_command 0b00111000 ; 2x5x7
    do_lcd_command 0b00001000 ; display off?
    do_lcd_command 0b00000001 ; clear display
    do_lcd_command 0b00000110 ; increment, no display shift
    do_lcd_command 0b00001110 ; Cursor on, bar, no blink

    ldi temp1, PORTLDIR       ; PA7:4/PA3:0, out/in
    sts DDRL, temp1
    ser temp1     			  ; PORTC and PORTG are output
    out DDRC, temp1
	out DDRG, temp1
	out PORTC, mode
	;Print the initial Display
	rcall printEntry


; Okay, so when taking in input we scan though the rows and columns
; Several things like the accumulator jump back to here
; The buttons mostly jump back to here as well
main:
                              ; Make sure we have the right thing printed


NormalMain:
    ldi cmask, INITCOLMASK     	; initial column mask
    clr col     			    ; Clear the column
    clr row						; Clear the row
	 ser r16						; Fill r16 to measure the PB_'s
	 in r16, PIND				; Read in the Push Buttons
	 cpi mode, Open				; If mode == Open
	 breq openMode				; Jump into the Open Mode
    out PORTC, powerlevel		; Display Power Level
	 sbrc r16, 1					; Skip next line if PB1 is pressed
	 jmp colloop					; Jump to the column loop
	 push mode					; Else, Push mode onto the stack
	 ldi mode, Open				; Mode = Open
	 rjmp printDoorOpen			; Jump to print the open door dialogue

; When the Door is open
openMode:
	out PORTG, Powerlevel
	sbrc r16, 0					; Unless PB0 has been pressed
	jmp main					; Jump Back to main
								; Else, close the door
doorclosed:
	pop mode					; Pop the previous mode off the stack
	out PORTG, col
	cpi mode, Entry
    breq mainEntry
    cpi mode, Running
    breq mainRunning
    cpi mode, Finished
    breq mainFinished
    cpi mode, Paused
    breq mainPaused
    cpi mode, Power
    breq mainPower
MainEntry:
	jmp PrintEntry
	jmp NormalMain
MainRunning:
	jmp PrintRunning
	jmp NormalMain
MainFinished:
	jmp PrintEntry
	ldi mode, Entry
	jmp NormalMain
MainPaused:
	jmp PrintPaused
	jmp NormalMain
MainPower:
	jmp PrintPower
	jmp NormalMain

	jmp main					; Jump back to the main

colloop:
    cpi col, 4
    breq main     				; If all keys are scanned, repeat.
    sts PORTL, cmask    	    ; Otherwise, scan a column.
    ldi temp1, 0xFF     		; Slow down the scan operation.

;Preliminary debouncing
delay:
    dec temp1
    brne delay
    lds temp1, PINL     		; Read PORTL
    andi temp1, ROWMASK   	    ; Get the keypad output value
    cpi temp1, 0xF     			; Check if any row is low
    breq nextcol
   	; If yes, find which row is low
    ldi rmask, INITROWMASK     ; Initialize for row check
    clr row

;Checks the rows one by one
rowloop:
    cpi row, 4         			 ; While row is less than or equal to 4
    breq nextcol       			 ; Row is over, next column
    mov temp2, temp1    		 ; Move bit to temp
    and temp2, rmask    		 ; Check un-masked bit
    breq convert        		 ; If bit is clear, the key is pressed
    inc row             		 ;   else move to the next row
    lsl rmask          			 ;Leftshift the row mask
    jmp rowloop         		 ;End while loop

nextcol:               			 ; If row scan is over
    lsl cmask           		 ; Leftshift the column mask
    sbr cmask, 1        		 ; Sets second bit in the cmask
    inc col            			 ; Increase column value
    jmp colloop         		 ; Go to the next column

;For converting the bits we got into a number or letter
convert:
    rcall sleep_100ms   		 ;Wait a moment
    rcall sleep_100ms   		 ;Still wait

    cpi col, 3          		 ; If the pressed key is in col.3
    breq letters       			 ; Goto letters
                        		 ; Else
    cpi row, 3          		 ; If the key is in row3,
    breq jumpToSymbols        	 ; We have a symbol or 0
	cpi mode, power				 ; If mode = Power
	breq powerParse				 ; Jump to the power mode parser
    mov temp1, row      		 ; Else we have a number in 1-9
    lsl temp1           		 ; Left shift the temp
    add temp1, row      		 ; Add temp to row
    add temp1, col      		 ; Temp1 = row*3 + col
    subi temp1, -1      		 ; Add one to temp1

    jmp accumulate      		 ; Jump to the accumulator
                        		 ; Will likely need to change


; Stepping stone function - Used because brge doesn't jump very far
jumpToSymbols:
	jmp symbols


; Parser spesifically for the Power Mode numbers
powerParse:
	cpi row, 1					 ; If its not in the first row its not relevant
	brge notNum					 ; Jump to notNum
	cpi col, 0					 ; If its in Column 0
	breq one					 ; Jump to one
	cpi col, 1					 ; If its in Column 1
	breq two					 ; Jump to two
	cpi col, 2					 ; If its in Column 2
	breq three					 ; Jump to 3
	jmp main					 ; Else, return to main
; Deals with one
one:
	ser powerlevel				 ; Set every bit in power level
	jmp powerParseEnd			 ; Jump to the end
; Deals with two
two:
	ldi powerlevel, 15			 ; Load half the bits in the power level register
	jmp powerParseEnd			 ; Jump to the end
; Deals with three
three:
	ldi powerlevel, 3			 ; Load a quarter of the bits
	jmp powerParseEnd			 ; Jump to the end
; Deals with things not relevent
notNum:
	jmp main					 ; Return to the main

; End of the power parse
PowerParseEnd:
	ldi mode, Entry				 ; Return to entry mode
	out PortC, powerlevel		 ; Output the power level
	rcall PrintEntry			 ; Print the entry screen
	jmp main					 ; Return to the main

;Parse letters
letters:
    cpi row, 0         			 ; If row is 0
    breq JumpA           		 ;  Letter is A
    cpi row, 1          		 ; If row is 1
    breq JumpB      			 ;  Letter is B
    cpi row, 2          		 ; If row is 2
    breq JumpC           		 ;  Letter is C
    cpi row, 3          		 ; If row is 3
    breq JumpD           		 ;  Letter is D
    jmp main            		 ; Else return to Main

; Useful because breq doesn't jump very far
JumpA:
	jmp a
JumpB:
	jmp b
JumpC:
	jmp c
JumpD:
	jmp d


; Parse Symbols
symbols:
    cpi col, 0          		 ; If column is 0
    breq star           		 ;  Letter is *
    cpi col, 1          		 ;If column is 1
    breq zero           		 ;  Letter is 0
    cpi col, 2          		 ;If column is 2
    breq hash           		 ;  Letter is #
    jmp convert_end     		 ;End conversion


; Processing the star
star:
	cpi mode, Running			 ; If running
	breq StarRunning			 ; Go to StarRunning
    cpi mode, Entry				 ; If entry
    breq StarEntry				 ; Go to StarEntry
	cpi mode, Paused			 ; If paused
	breq StarPaused				 ; Go to StarPaused
	jmp main					 ; Else go to main

StarEntry:
	ldi mode, Running			 ; Load running
	rcall printRunning			 ; Print running screen
	jmp main					 ; Go to main
StarRunning:
	;+60s
	jmp main
StarPaused:
	ldi mode, Running			 ; Load running
	rcall printRunning			 ; Print running screen
	jmp main					 ; Go to main


; Special because its located in the symbols row
zero:
    ldi temp1, 0				 ; Load 0 into temp1
    jmp accumulate				 ; Jump to accumulate


; End the conversion
convert_end:
    subi temp1, 48      		 ; temp1 is current 49, the ASCII value for 1
    jmp main            	 	 ; Restart main loop


; Left over from the calculator
; Yet to be adapted to the time thing
accumulate:
	// temp1 has the current number we're adding to the overall sum
   ldi mul10, 10               	;Make sure mul10 has 10 in it
   mul bottomNumber, mul10     	;Multiply the bottom by 10
   mov bottomNumber, r0         ;Move bottom into r0
   add bottomNumber, temp1     	;Add the bottom number and 10

	subi temp1, -'0'            ;Add the ascii value of 0 (convert)
	subi temp1, '0'             ;Subtract the ascii value of 0 (revert)

; Stepping stone function
JumptoMain:
	jmp main                    ;Return to the main function


A:
   cpi mode, Entry              ; If mode == entry
   breq Apower	               	;	Go to power mode
   cpi mode, Running			;If mode == running
   breq Arunning				;	Go to running

   jmp main						;Else button not used in this mode
Apower:
   ldi mode, Power				;Mode = power mode
   rcall printPower				;Print out mode
   jmp main                   	;Return to the start
Arunning:
   ;+30s					 	;Add 30s to time
   jmp main						;Return to the start


;The hash does different things according to the mode
hash:
    cpi mode, Power				; If mode = power
    breq HashPower				; 	Go to HashPower
    cpi mode, Entry				; If mode = entry
	breq HashEntry				; 	Go to HashEntry
	cpi mode, Finished			; If mode = finished
	breq HashFinished			; 	Go to HashFinished
	cpi mode, Running			; If mode = running
	breq HashRunning			; 	Go to hashRunning
	cpi mode, Paused			; If mode = paused
	breq HashPaused				; 	Go to HashPaused

    jmp main                  	; Else, return to start
HashRunning:
	ldi mode, Paused			; Load paused mode
	rcall printPaused			; Print Paused screen
	jmp main					; Return to main
HashPower:
	ldi mode, Entry				; Load entry mode
	rcall PrintEntry			; Print Entry screen
	jmp main					; Return to main
HashFinished:
	ldi mode, Entry				; Load entry mode
	rcall printEntry			; Print Entry screen
	jmp main					; Return to main
HashPaused:
	ldi mode, Entry				; Load entry mode
	rcall printEntry			; Print Entry screen
	jmp main					; Return to main
HashEntry:
	;Clear time
	jmp main					; Return to main


; B doesn't appear to actually do anything
; Temporary usage to move from running to finished
b:
	cpi mode, Running			; If mode = running
	breq tempB					; Jump to temp
   	jmp main					; Else just go to main
TempB:
	ldi mode, Finished			; Load finished
	rcall printFinished			; Print finished screen
	jmp main					; Jump to main


C:
	;If mode == running
    ;  second timer +30s
    ;Update time display
	;	jmp main                ;Where?


D:
	;If mode == running
   	;  second timer -30s
    ;Update time display
    ; jmp main                  ;Where?


print:
   cpi mode, Power
   breq powerPrint

   jmp main

powerprint:
   jmp PrintPower


;Stepping stone function
JumptojumptoPower:
	jmp PrintPower


;LCD functions
lcd_command:
    out PORTF, LCD
    rcall sleep_1ms
    lcd_set LCD_E
    rcall sleep_1ms
    lcd_clr LCD_E
    rcall sleep_1ms
    ret

lcd_data:
    out PORTF, LCD
    lcd_set LCD_RS
    rcall sleep_1ms
    lcd_set LCD_E
    rcall sleep_1ms
    lcd_clr LCD_E
    rcall sleep_1ms
    lcd_clr LCD_RS
    ret

lcd_wait:
    push LCD
    clr LCD
    out DDRF, LCD
    out PORTF, LCD
    lcd_set LCD_RW
    lcd_wait_loop:
    rcall sleep_1ms
    lcd_set LCD_E
    rcall sleep_1ms
    in LCD, PINF
    lcd_clr LCD_E
    sbrc LCD, 7
    rjmp lcd_wait_loop
    lcd_clr LCD_RW
    ser LCD
    out DDRF, LCD
    pop LCD
    ret

    .equ F_CPU = 16000000
    .equ DELAY_1MS = F_CPU / 4 / 1000 - 4

;Sleep functions
sleep_1ms:
    push r24
    push r25
    ldi r25, high(DELAY_1MS)
    ldi r24, low(DELAY_1MS)
delayloop_1ms:
    sbiw r25:r24, 1
    brne delayloop_1ms
    pop r25
    pop r24
    ret

sleep_5ms:
    rcall sleep_1ms
    rcall sleep_1ms
    rcall sleep_1ms
    rcall sleep_1ms
    rcall sleep_1ms
    ret

sleep_100ms:
    push r19
    clr r19

loop:
    inc r19
    rcall sleep_5ms
    cpi r19, 20
    brlt loop

    pop r19
    ret


; Printing functions
printPower:

	;In here we need to put something to change it to the power mode
	;heh, power mode sounds exciting

	do_lcd_command 0b00000001 ; clear display
	load_lcd_letter 'S'
	load_lcd_letter 'E'
	load_lcd_letter 'L'
	load_lcd_letter 'E'
	load_lcd_letter 'C'
	load_lcd_letter 'T'
	load_lcd_letter ' '
	load_lcd_letter 'P'
	load_lcd_letter 'O'
	load_lcd_letter 'W'
	load_lcd_letter 'E'
	load_lcd_letter 'R'

    do_lcd_command 0b11000000    ;New line because it doesn't all fit on one

    load_lcd_letter 'L'
	load_lcd_letter 'E'
	load_lcd_letter 'V'
	load_lcd_letter 'E'
	load_lcd_letter 'L'
	load_lcd_letter ':'
	load_lcd_letter ' '
	load_lcd_letter '1'
	load_lcd_letter ','
	load_lcd_letter '2'
	load_lcd_letter ','
	load_lcd_letter '3'
	load_lcd_letter ' '
	load_lcd_letter ' '
	load_lcd_letter ' '
	sbrs DoorState, 0
	load_lcd_letter 'C'
	sbrc DoorState, 0
	load_lcd_letter 'O'
	jmp main

PrintRunning:

	do_lcd_command 0b00000001 ; clear display
	load_lcd_letter 'R'
	load_lcd_letter 'u'
	load_lcd_letter 'n'
	load_lcd_letter 'n'
	load_lcd_letter 'i'
	load_lcd_letter 'n'
	load_lcd_letter 'g'
	load_lcd_letter ' '
	load_lcd_letter 'm'
	load_lcd_letter 'o'
	load_lcd_letter 'd'
	load_lcd_letter 'e'

	ret
   ;Activate magnatron
   ;Turntable needs to turn 3x per minute

PrintFinished:

	do_lcd_command 0b00000001 ; clear display
	load_lcd_letter 'D'
	load_lcd_letter 'o'
	load_lcd_letter 'n'
	load_lcd_letter 'e'

   	do_lcd_command 0b11000000    ;New line because it doesn't all fit on one

    load_lcd_letter 'R'
	load_lcd_letter 'e'
	load_lcd_letter 'm'
	load_lcd_letter 'o'
	load_lcd_letter 'v'
	load_lcd_letter 'e'
	load_lcd_letter ' '
	load_lcd_letter 'f'
	load_lcd_letter 'o'
	load_lcd_letter 'o'
	load_lcd_letter 'd'

	ret

PrintEntry:
	do_lcd_command 0b00000001 ; clear display
	load_lcd_letter '0'
	load_lcd_letter '0'
	load_lcd_letter ':'
	load_lcd_letter '0'
	load_lcd_letter '0'

	jmp main

PrintPaused:
	do_lcd_command 0b00000001 ; clear display
	load_lcd_letter 'P'
	load_lcd_letter 'a'
	load_lcd_letter 'u'
	load_lcd_letter 's'
	load_lcd_letter 'e'
	load_lcd_letter 'd'
	load_lcd_letter ' '
	load_lcd_letter 'm'
	load_lcd_letter 'o'
	load_lcd_letter 'd'
	load_lcd_letter 'e'

	ret

PrintDoorOpen:
	do_lcd_command 0b00000001 ; clear display
	load_lcd_letter 'D'
	load_lcd_letter 'o'
	load_lcd_letter 'o'
	load_lcd_letter 'r'
	load_lcd_letter ' '
	load_lcd_letter 'o'
	load_lcd_letter 'p'
	load_lcd_letter 'e'
	load_lcd_letter 'n'

	jmp main
