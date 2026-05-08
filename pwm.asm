LIST P=18F452
    #include <p18f452.inc>

    ; Configuration bits for MPASMX
    CONFIG OSC = HS        ; High-Speed Crystal Oscillator
    CONFIG WDT = OFF       ; Watchdog Timer disabled
    CONFIG LVP = OFF       ; Low-Voltage Programming disabled


    ; Variable Declarations
    CBLOCK 0x20
        Duty_L             ; Lower byte of 10-bit Duty Cycle
        Duty_H             ; Upper byte of 10-bit Duty Cycle
        Delay1             ; Delay counter 1
        Delay2             ; Delay counter 2
        Delay3             ; Delay counter 3
    ENDC

    ORG 0x0000
    goto Main

    ORG 0x0020
Main:
    ; --- INITIALIZATION ---
    
    ; Set RC2 as output for PWM
    bcf     TRISC, 2

    ; Set PORTB as inputs for buttons
    movlw   0xFF
    movwf   TRISB
    bcf     INTCON2, RBPU   ; Enable PORTB internal pull-ups (Active Low)

    ; Configure Timer2 for 50kHz PWM
    movlw   d'79'           ; PR2 = 79
    movwf   PR2

    ; Configure CCP1 Module for PWM
    movlw   b'00001100'     ; CCP1M3:CCP1M0 = 1100 (PWM mode)
    movwf   CCP1CON

    ; Turn on Timer2 with Prescaler = 1
    movlw   b'00000100'     ; TMR2ON = 1, T2CKPS = 00
    movwf   T2CON

    ; Initialize Duty Cycle to 50% (160 counts out of 320)
    movlw   LOW d'160'
    movwf   Duty_L
    movlw   HIGH d'160'
    movwf   Duty_H

    call    Update_PWM

    ; --- MAIN LOOP ---
Loop:
    btfss   PORTB, 0        ; Skip next instruction if RB0 is HIGH (not pressed)
    call    Increase_Duty
    
    btfss   PORTB, 1        ; Skip next instruction if RB1 is HIGH (not pressed)
    call    Decrease_Duty

    ; ~100ms delay to control continuous scrolling speed when button is held
    call    Delay_100ms     
    goto    Loop


    ; --- SUBROUTINES ---

Increase_Duty:
    ; Add 6 to the 16-bit Duty variable
    movlw   d'6'
    addwf   Duty_L, F
    movlw   0
    addwfc  Duty_H, F

    ; Cap maximum value at 320 (0x0140)
    movlw   d'1'
    cpfsgt  Duty_H          ; Skip if Duty_H > 1
    bra     Check_Low_Inc
    bra     Cap_Max         ; Duty_H >= 2, Cap it
    
Check_Low_Inc:
    cpfslt  Duty_H          ; Skip if Duty_H < 1
    bra     Check_Low_Byte_Max
    bra     End_Inc         ; Duty_H == 0, we are safe
    
Check_Low_Byte_Max:
    movlw   d'64'           ; 0x40. 320 = 256 + 64 (0x0140)
    cpfsgt  Duty_L          ; Skip if Duty_L > 64
    bra     End_Inc         ; Duty is valid
    
Cap_Max:
    movlw   LOW d'320'
    movwf   Duty_L
    movlw   HIGH d'320'
    movwf   Duty_H
    
End_Inc:
    call    Update_PWM
    return


Decrease_Duty:
    ; Subtract 6 from the 16-bit Duty variable
    movlw   d'6'
    subwf   Duty_L, F
    movlw   0
    subwfb  Duty_H, F

    ; Check for underflow (If bit 7 of Duty_H goes high, it rolled over below 0)
    btfss   Duty_H, 7
    bra     End_Dec
    
Cap_Min:
    clrf    Duty_L
    clrf    Duty_H
    
End_Dec:
    call    Update_PWM
    return


Update_PWM:
    ; CCPR1L receives the top 8 bits (Duty >> 2)
    ; CCP1CON<5:4> receives the bottom 2 bits (Duty & 0x03)

    ; Load Duty values into Math registers
    movf    Duty_H, W
    movwf   PRODH
    movf    Duty_L, W
    movwf   PRODL

    ; Shift Right 16-bit variable by 2 
    bcf     STATUS, C
    rrcf    PRODH, F
    rrcf    PRODL, F
    bcf     STATUS, C
    rrcf    PRODH, F
    rrcf    PRODL, F

    ; Write upper 8 bits to CCPR1L
    movf    PRODL, W
    movwf   CCPR1L

    ; Extract lower 2 bits of original Duty_L
    movf    Duty_L, W
    andlw   b'00000011'     ; Mask out everything except bits 0 and 1
    
    ; Shift left by 4 to align with CCP1CON<5:4>
    rlncf   WREG, W
    rlncf   WREG, W
    rlncf   WREG, W
    rlncf   WREG, W
    movwf   PRODL           ; Temporarily store shifted bits
    
    ; Merge with existing CCP1CON settings
    movf    CCP1CON, W
    andlw   b'11001111'     ; Clear bits 5:4 in W
    iorwf   PRODL, W        ; OR in the new bits
    movwf   CCP1CON         ; Update CCP1 module
    
    return


Delay_100ms:
    ; Assuming 16MHz Clock (4MHz instruction cycle, 0.25us per cycle)
    ; 100ms = 400,000 instruction cycles
    movlw   d'5'
    movwf   Delay3
D3_Loop:
    movlw   d'200'
    movwf   Delay2
D2_Loop:
    movlw   d'132'
    movwf   Delay1
D1_Loop:
    decfsz  Delay1, F       ; 1 cycle if no skip, 2 if skip
    bra     D1_Loop         ; 2 cycles
    
    decfsz  Delay2, F
    bra     D2_Loop
    
    decfsz  Delay3, F
    bra     D3_Loop
    return

    END