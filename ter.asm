.include "m2560def.inc"

main:
    ;ser r16
    out DDRC, r16
    
    clr r16
    out DDRD, r16
    com r16
    out PORTD, r16
loop:
    in r16, PIND
    out PORTC, r16
    rjmp loop
