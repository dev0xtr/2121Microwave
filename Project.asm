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
.def row = r24           ; current row number
.def col = r17           ; current column number
.def rmask = r18         ; mask for current row during scan
.def cmask = r19         ; mask for current column during scan
.def temp1 = r20
.def temp2 = r21
.def mul10 = r22
.def accumulator = r23
.def LCD = r16
.def bottomNumber = r25

; It is possible this will need to be a different register
.def mode = r26
;The various modes, the value of the register denoting the mode
.equ Entry = 0
.equ Power = 1
.equ Running = 2
.equ Paused = 3
.equ Open = 4
.equ Finished = 5                         

.equ PORTLDIR = 0xF0     ; PD7-4: output, PD3-0, input
.equ INITCOLMASK = 0xEF  ; scan from the rightmost column,
.equ INITROWMASK = 0x01  ; scan from the top row
.equ ROWMASK = 0x0F      ; for obtaining input from Port D
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

    ;There will need to be something here for determining the mode

    ; Clear things so there are no leftovers
    clr bottomNumber
	clr accumulator
    clr temp1
    clr temp2

    ; Set up mul10 to actually have 10 in it
    ldi mul10, 10

    ldi temp1, low(RAMEND)     ; initialize the stack
    out SPL, temp1
    ldi temp1, high(RAMEND)
    out SPH, temp1

    ser LCD
    out DDRF, LCD
    out DDRA, LCD
    clr LCD
    out PORTF, LCD
    out PORTA, LCD

    ;Initial setup of the LCD
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

    ldi temp1, PORTLDIR     ; PA7:4/PA3:0, out/in
    sts DDRL, temp1
    ser temp1     ; PORTC is output
    out DDRC, temp1
    ;out PORTC, temp1

	;out PortC, mode
	cpi mode, Power
	jmp main
	rcall printAccumulator

;Okay, so when taking in input we scan though the rows and columns
;Several things like the accumulator jump back to here
main:
    ldi cmask, INITCOLMASK     ; initial column mask
    clr col     ; initial column
    clr row

colloop:
    cpi col, 4
    breq main     ; If all keys are scanned, repeat.
    sts PORTL, cmask     ; Otherwise, scan a column.
    ldi temp1, 0xFF     ; Slow down the scan operation.

;Preliminary debouncing
delay:
    dec temp1
    brne delay
    lds temp1, PINL     ; Read PORTL
    andi temp1, ROWMASK     ; Get the keypad output value
    cpi temp1, 0xF     ; Check if any row is low
    breq nextcol
    ; If yes, find which row is low
    ldi rmask, INITROWMASK     ; Initialize for row check
    clr row ;

rowloop:
    cpi row, 4          ;While row is less than or equal to 4
    breq nextcol        ;  Row is over, next column
    mov temp2, temp1    ;Move bit to temp
    and temp2, rmask    ;Check un-masked bit
    breq convert        ;If bit is clear, the key is pressed
    inc row             ;   else move to the next row
    lsl rmask           ;Leftshift the row mask
    jmp rowloop         ;End while loop

nextcol:                ; if row scan is over
    lsl cmask           ;leftshift the column mask
    sbr cmask, 1        ;sbr the cmask with one
    inc col             ;increase column value
    jmp colloop         ;go to the next column

;For converting the bits we got into a number or letter
convert:
    rcall sleep_100ms   ;Wait a moment
    rcall sleep_100ms   ;Still wait
    cpi col, 3          ;If the pressed key is in col.3
    breq letters        ; goto letters
                        ;else
    cpi row, 3          ; If the key is in row3,
    breq symbols        ;   we have a symbol or 0
    mov temp1, row      ; else we have a number in 1-9
    lsl temp1           ;Left shift the temp
    add temp1, row      ;Add temp to row
    add temp1, col      ; temp1 = row*3 + col
    subi temp1, -1      ;Add one to temp1

    jmp accumulate      ;Jump to the accumulator
                        ;Will need to change

;Parse letters
letters:
    cpi row, 0          ;If row is 0
    breq addA           ;  Letter is A
    cpi row, 1          ;If row is 1
    breq B      		;  Letter is B
    cpi row, 2          ;If row is 2
    breq MulC           ;  Letter is C
    cpi row, 3          ;If row is 3
    breq DivD           ;  Letter is D
    jmp main            ;Return to Main

;Parse Symbols
symbols:
    cpi col, 0          ;If column is 0
    breq star           ;  Letter is *
    cpi col, 1          ;If column is 1
    breq zero           ;  Letter is 0
    cpi col, 2          ;If column is 2
    breq hash           ;  Letter is #
    jmp convert_end     ;End conversion

;For processing the *
star:
    ;ldi temp1, '*'     ; Set to star
	cpi mode, Running
	;Second timer + 60
    cpi mode, Entry
    ldi mode, Running
    jmp RESET

; As far as I can tell this ones okay
zero:
    ldi temp1, 0
    jmp accumulate

;End the conversion
convert_end:
    subi temp1, 48      ; temp1 is current 49, the ASCII value for 1
    out PORTC, temp1    ; Write value to PORTC (LCDs)
                        ; These instead need to display the power level
    jmp main            ; Restart main loop

;Left over from the calculator
accumulate:
	// temp1 has the current number we're adding to the overall sum
   ldi mul10, 10               ;Make sure mul10 has 10 in it
   mul bottomNumber, mul10     ;Multiply the bottom by 10
   mov bottomNumber, r0        ;Move bottom into r0
   add bottomNumber, temp1     ;Add the bottom number and 10

	subi temp1, -'0'            ;Add the ascii value of 0 (convert)
	;do_lcd_data temp1           ;Output the lcd data of temp1
	subi temp1, '0'             ;Subtract the ascii value of 0 (revert)
	jmp main                    ;Return to the main function

addA:
   cpi mode, Entry                 ; If mode == entry
   ldi mode, Power	               ;change mode to power level
   cpi mode, Power
   jmp printPower
                               ;This will have to be changed to be set mode to 0
   jmp sleep_100ms             ;Sleep (temporary line to check output was working)
   jmp reset                   ;Return to the start

;The hash does different things according to the mode
hash:
    cpi mode, 1
    ldi mode, 0
    ;If mode == entry
    ; time = 0
    ;If mode == finished
    ; mode = entry
    ;If mode == running
    ; pause
    jmp reset                  ;Return to start

;B doesn't appear to actually do anything
b:
   jmp reset


MulC:
	;If mode == running
   ;  second timer +30s
   ;Update time display
;	jmp                         ;Where?

DivD:
	;If mode == running
   ;  second timer -30s
   ;Update time display
  ; jmp                         ;Where?


print:
   cpi mode, Power
   jmp main
   do_lcd_command 0b00000001     ; clear display
   rcall printAccumulator        ;We will need a print time display
   jmp main

	;rcall printBottom            ;No longer needed

;We're going to need a "thousands" in here
printBottom:
    push r18
    push r19
    push r20
    push r21
    push r22
    push r23

    clr r18
    clr r19
    clr r20
    clr r21
    clr r22

    mov r21, bottomNumber
	 rcall hundreds

printAccumulator:

    push r18
    push r19
    push r20
    push r21
    push r22
    push r23

    clr r18
    clr r19
    clr r20
    clr r21
    clr r22

	 clr bottomNumber
    mov r21, accumulator

hundreds:
    cpi r21, 100
    brlo tens
    subi r21, 100
    inc r22 // counter of 100s
    jmp hundreds

tens:

    cpi r21, 10
    brlo ones
    subi r21, 10
    inc r20 // counter of 10s
    jmp tens

ones:
    out PORTC, r20 // should print 100s
    // r21 is now the number of tens

endLoop:

   //r22, r20, r21 100s 10s 1s

    subi r22, -'0'
    do_lcd_data r22 // hundreds

    load_lcd_letter ':'         ;Break up time display with :

    subi r20, -'0'
    do_lcd_data r20 // tens

    subi r21, -'0'
    do_lcd_data r21 // ones

    ;In here we will need some kind of tab so we can display the turntable
    ;call display turntable function

    do_lcd_command 0b11000000    ; new line

    ;These will no longer be needed (I think...)
    pop r23
    pop r22
    pop r21
    pop r20
    pop r19
    pop r18
    ret


    ;
    ; Send a command to the LCD (r16)
    ;

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

printPower:
	;FOR DEBUGGING ONLY
	 out PORTC, mode
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

	;jump to scanner

	ret

PrintRunning:
   ;Activate magnatron
   ;Turntable needs to turn 3x per minute
   ret

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
