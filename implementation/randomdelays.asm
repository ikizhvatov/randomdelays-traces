;
; Implementation of several AES rounds with random delays.
; Random delays generation methods are:
; - no delays (ND)
; - plain uniform delays (PU)
; - Benoit-Tunstall table method (BT)
; - floating mean (FM)
; - improved floating mean (IFM)
;
; AES-128 implementation based on the code of B. Poettering [http://point-at-infinity.org/avraes/]
; 
; Started 2008-10-14 by Ilya Kizhvatov, University of Luxembourg


.include "m16def.inc"  ; declarations specific to ATmega16 (change to required if necessary)


; ****************************************************************************
; Predefinitions and macros

; AES state and other register predefinitions
.def ST11=r0
.def ST21=r1
.def ST31=r2
.def ST41=r3
.def ST12=r4
.def ST22=r5
.def ST32=r6
.def ST42=r7
.def ST13=r8
.def ST23=r9
.def ST33=r10
.def ST43=r11
.def ST14=r12
.def ST24=r13
.def ST34=r14
.def ST44=r15
.def H1=r16
.def H2=r17
.def H3=r18
.def TRIGHIGH=r19
.def TRIGLOW=r20
.def COUNTER=r21
.def MEAN=r22
.def MASK=r23
.def RND=r24

; precompute USART baud rate in a clever way (taken from http://www.mikrocontroller.net/articles/AVR-Tutorial:_UART)
.equ F_CPU = 3686400    ; target clock frequency in Hz (change to the actual one if necessary!!)
.equ BAUD  = 115200     ; selected baud rate (at 4MHz and at 8MHz, 38400 gives low error)
.equ UBRR_VAL   = ((F_CPU + BAUD * 8) / (BAUD * 16) - 1) ; clever rounding
.equ BAUD_REAL  = (F_CPU / (16 * (UBRR_VAL + 1)))        ; real baud rate
.equ BAUD_ERROR = ((BAUD_REAL * 1000) / BAUD - 1000)     ; error, promille
.if ((BAUD_ERROR > 10) || (BAUD_ERROR < -10))            ; allow no more than +/-10 promille error
  .error "Systematic baud rate error exceeds 1 percent and is therefore too high!"
.endif

; number of bytes in the RNG-simulating pool; depends on how many calls to
;  the pool it will be during the single execution
.equ RNDPOOLSIZE = 101

; random delay generation macros; calls procedures corresponding to the
;  selected method
#define METHOD_N

#if defined (METHOD_ND)
  .macro RandomDelay
  .endmacro
  .macro InitRandomDelays
  .endmacro
  .macro FlipRandomDelay
  .endmacro
#elif defined (METHOD_PU)
  .macro RandomDelay
    rcall randomdelay_pu
  .endmacro
  .macro InitRandomDelays
  .endmacro
  .macro FlipRandomDelay
  .endmacro
#elif defined (METHOD_BT)
  .macro RandomDelay
    rcall randomdelay_bt
  .endmacro
  .macro InitRandomDelays
  .endmacro
  .macro FlipRandomDelay
  .endmacro
#elif defined (METHOD_FM)
  .macro RandomDelay
    rcall randomdelay_fm
  .endmacro
  .macro InitRandomDelays
    rcall init_fm
  .endmacro
  .macro FlipRandomDelay
    rcall flip_fm
  .endmacro
#elif defined (METHOD_IFM)
  .macro RandomDelay
    rcall randomdelay_ifm
  .endmacro
  .macro InitRandomDelays
    rcall init_ifm
  .endmacro
  .macro FlipRandomDelay
    rcall flip_ifm
  .endmacro
#else
  #warning "No random delay generation method specified, assuming ND!"
  .macro RandomDelay
  .endmacro
  .macro InitRandomDelays
  .endmacro
  .macro FlipRandomDelay
  .endmacro
#endif



; ****************************************************************************
; SRAM space reservation
.DSEG
expkey:   .byte 16*11 ; expanded key
dummykey: .byte 16    ; dummy round key
rndpool:  .byte RNDPOOLSIZE ; pool for random numbers for RNG simulation
.org 0x0200
bttablesram: .byte 256 ; table for the Benoit-Tunstall method


; ****************************************************************************
; Executable code
.CSEG

  cli ; disable the interrupts (just in case)
  
  ; *******************************
  ; initialize stack pointer
  ldi  H1, HIGH(RAMEND)
  ldi  H2, LOW(RAMEND)
  out  SPH, H1
  out  SPL, H2

  ; *******************************
  ; setup the USART
  ; set baud rate
  ldi  H1, HIGH(UBRR_VAL)
  ldi  H2, LOW(UBRR_VAL)
  out  UBRRH, H1
  out  UBRRL, H2
  ; set frame format to 8-N-1, activate RX and TX
  ldi  H1, (1 << URSEL) | (3 << UCSZ0)
  ldi  H2, (1 << RXEN) | (1 << TXEN)
  out  UCSRC, H1
  out  UCSRB, H2

  ; ********************************
  ; prepare the trigger stuff
  ldi  TRIGLOW,0x00        ; value to set bit 0 of PORTB (PORTB0) low
  ldi  TRIGHIGH,0x01       ; value to set PORTB0 high
  out  DDRB, TRIGHIGH      ; configure PORTB0 for output
  out  PORTB, TRIGHIGH     ; raise the trigger (we're using 'idle high')

  ; ********************************
  ; preload the Benoit-Tunstall table into SRAM
  ldi  ZH, HIGH(bttable << 1)
  ldi  ZL, LOW(bttable << 1)
  ldi  YH, HIGH(bttablesram)
  ldi  YL, LOW(bttablesram)
  ldi  COUNTER, HIGH(bttablesram) + 1 ; store the threshold value for ending the loading loop
load_bttable:
  lpm  H1, Z+
  st   Y+, H1
  cpse YH, COUNTER  ; exit loop when all 256 bytes are loaded
  rjmp load_bttable

  ; ********************************
  ; prepare the expanded AES key in SRAM
  ldi ZH, high(key<<1)  ; load key into ST11-ST44
  ldi ZL, low(key<<1)
  lpm ST11, Z+
  lpm ST21, Z+
  lpm ST31, Z+
  lpm ST41, Z+
  lpm ST12, Z+
  lpm ST22, Z+
  lpm ST32, Z+
  lpm ST42, Z+
  lpm ST13, Z+
  lpm ST23, Z+
  lpm ST33, Z+
  lpm ST43, Z+
  lpm ST14, Z+
  lpm ST24, Z+
  lpm ST34, Z+
  lpm ST44, Z+
  ldi YH, high(expkey)  ; expand key to the memory
  ldi YL, low(expkey)	; locations $60..$60+(16*11-1)
  rcall key_expand


; ****************************************************************************
; the main program cycle
mainloop:

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ; load random pool with fresh random numbers
  ldi XH, high(rndpool)
  ldi XL, low(rndpool)
  ldi COUNTER, RNDPOOLSIZE ; counter
usart_read_rnd:
  sbis  UCSRA,RXC      ; wait until reception is completed
  rjmp  usart_read_rnd
  in    H1, UDR
  st    X+, H1
  dec   COUNTER
  brne  usart_read_rnd
  ldi XH, high(rndpool) ; reset X to random pool start - it is a dedicated
  ldi XL, low(rndpool)  ;  register to be used solely for pool access

  ; obtain 16-byte plaintext from USART and load it to state registers
usart_read_11:         ; 1st column
  sbis  UCSRA,RXC      ; wait until reception is completed
  rjmp  usart_read_11
  in    ST11, UDR
usart_read_21:
  sbis  UCSRA,RXC
  rjmp  usart_read_21
  in    ST21, UDR
usart_read_31:
  sbis  UCSRA,RXC
  rjmp  usart_read_31
  in    ST31, UDR
usart_read_41:
  sbis  UCSRA,RXC
  rjmp  usart_read_41
  in    ST41, UDR

usart_read_12:         ; 2nd column
  sbis  UCSRA,RXC
  rjmp  usart_read_12
  in    ST12, UDR
usart_read_22:
  sbis  UCSRA,RXC
  rjmp  usart_read_22
  in    ST22, UDR
usart_read_32:
  sbis  UCSRA,RXC
  rjmp  usart_read_32
  in    ST32, UDR
usart_read_42:
  sbis  UCSRA,RXC
  rjmp  usart_read_42
  in    ST42, UDR

usart_read_13:         ; 3rd column
  sbis  UCSRA,RXC
  rjmp  usart_read_13
  in    ST13, UDR
usart_read_23:
  sbis  UCSRA,RXC
  rjmp  usart_read_23
  in    ST23, UDR
usart_read_33:
  sbis  UCSRA,RXC
  rjmp  usart_read_33
  in    ST33, UDR
usart_read_43:
  sbis  UCSRA,RXC
  rjmp  usart_read_43
  in    ST43, UDR

usart_read_14:         ; last column
  sbis  UCSRA,RXC
  rjmp  usart_read_14
  in    ST14, UDR
usart_read_24:
  sbis  UCSRA,RXC
  rjmp  usart_read_24
  in    ST24, UDR
usart_read_34:
  sbis  UCSRA,RXC
  rjmp  usart_read_34
  in    ST34, UDR
usart_read_44:
  sbis  UCSRA,RXC
  rjmp  usart_read_44
  in    ST44, UDR

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ; produce the per-execution 'floating mean'
  InitRandomDelays

  ; *** perform encryption **********************
  push ST11 ; save the original state, clear
  clr ST11  ; state registers
  push ST12
  clr ST12  ; (16 * 3 = 48 cycles)
  push ST13
  clr ST13
  push ST14
  clr ST14
  push ST21
  clr ST21
  push ST22
  clr ST22
  push ST23
  clr ST23
  push ST24
  clr ST24
  push ST31
  clr ST31
  push ST32
  clr ST32
  push ST33
  clr ST33
  push ST34
  clr ST34
  push ST41
  clr ST41
  push ST42
  clr ST42
  push ST43
  clr ST43
  push ST44
  clr ST44

  out   PORTB, TRIGLOW  ; fire the trigger

      ldi YH, high(dummykey)
      ldi YL, low(dummykey)
      rcall encryptround ; dummy round
      ldi YH, high(dummykey)
      ldi YL, low(dummykey)
      rcall encryptround ; dummy round
      ldi YH, high(dummykey)
      ldi YL, low(dummykey)
      rcall encryptround ; dummy round

      pop ST44 ; load the original state and the
      pop ST43 ; actual key
      pop ST42 ; (16 * 2 + 2 = 34 cycles)
      pop ST41
      pop ST34
      pop ST33
      pop ST32
      pop ST31
      pop ST24
      pop ST23
      pop ST22
      pop ST21
      pop ST14
      pop ST13
      pop ST12
      pop ST11

      ldi YH, high(expkey)  ; initialize YH:YL to
      ldi YL, low(expkey)   ;  expanded key and call
      ;out   PORTB, TRIGHIGH
      rcall encryptround    ; encryption round
      ;out   PORTB, TRIGLOW
      rcall encryptround
      ;FlipRandomDelay
      rcall encryptround
      rcall encryptround

      push ST11 ; again, save the actual state and clear
      clr ST11  ; state registers
      push ST12 ; (50 cycles)
      clr ST12
      push ST13
      clr ST13
      push ST14
      clr ST14
      push ST21
      clr ST21
      push ST22
      clr ST22
      push ST23
      clr ST23
      push ST24
      clr ST24
      push ST31
      clr ST31
      push ST32
      clr ST32
      push ST33
      clr ST33
      push ST34
      clr ST34
      push ST41
      clr ST41
      push ST42
      clr ST42
      push ST43
      clr ST43
      push ST44
      clr ST44

      ldi YH, high(dummykey)
      ldi YL, low(dummykey)
      rcall encryptround ; dummy round
      ldi YH, high(dummykey)
      ldi YL, low(dummykey)
      rcall encryptround ; dummy round
      ldi YH, high(dummykey)
      ldi YL, low(dummykey)
      rcall encryptround ; dummy round

  out   PORTB, TRIGHIGH  ; pull up the trigger

  pop ST44 ; load the original state
  pop ST43 ; (32 cycles)
  pop ST42
  pop ST41
  pop ST34
  pop ST33
  pop ST32
  pop ST31
  pop ST24
  pop ST23
  pop ST22
  pop ST21
  pop ST14
  pop ST13
  pop ST12
  pop ST11

  ; *********************************************

  ; send a sync byte via USART
usart_write_sync:
  sbis  UCSRA,UDRE
  rjmp  usart_write_sync
  out   UDR, TRIGHIGH

/*
  ; return the ciphertext via USART
usart_write_11:         ; 1st column
  sbis  UCSRA,UDRE      ; wait until UDR is ready for the next byte
  rjmp  usart_write_11
  out   UDR, ST11
usart_write_21:
  sbis  UCSRA,UDRE
  rjmp  usart_write_21
  out   UDR, ST21
usart_write_31:
  sbis  UCSRA,UDRE
  rjmp  usart_write_31
  out   UDR, ST31
usart_write_41:
  sbis  UCSRA,UDRE
  rjmp  usart_write_41
  out   UDR, ST41

usart_write_12:         ; 2nd column
  sbis  UCSRA,UDRE
  rjmp  usart_write_12
  out   UDR, ST12
usart_write_22:
  sbis  UCSRA,UDRE
  rjmp  usart_write_22
  out   UDR, ST22
usart_write_32:
  sbis  UCSRA,UDRE
  rjmp  usart_write_32
  out   UDR, ST32
usart_write_42:
  sbis  UCSRA,UDRE
  rjmp  usart_write_42
  out   UDR, ST42

usart_write_13:
  sbis  UCSRA,UDRE      ; 3rd column
  rjmp  usart_write_13
  out   UDR, ST13
usart_write_23:
  sbis  UCSRA,UDRE
  rjmp  usart_write_23
  out   UDR, ST23
usart_write_33:
  sbis  UCSRA,UDRE
  rjmp  usart_write_33
  out   UDR, ST33
usart_write_43:
  sbis  UCSRA,UDRE
  rjmp  usart_write_43
  out   UDR, ST43

usart_write_14:         ; last column
  sbis  UCSRA,UDRE    
  rjmp  usart_write_14
  out   UDR, ST14
usart_write_24:
  sbis  UCSRA,UDRE
  rjmp  usart_write_24
  out   UDR, ST24
usart_write_34:
  sbis  UCSRA,UDRE
  rjmp  usart_write_34
  out   UDR, ST34
usart_write_44:
  sbis  UCSRA,UDRE
  rjmp  usart_write_44
  out   UDR, ST44
*/

  rjmp mainloop


;;; ***************************************************************************
;;; The AES-128 secret key
key:
;.db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
;.db $01,$23,$45,$67,$89,$ab,$cd,$ef,$fe,$dc,$ba,$98,$76,$54,$32,$10
.db $2b,$7e,$15,$16,$28,$ae,$d2,$a6,$ab,$f7,$15,$88,$09,$cf,$4f,$3c


;;; ***************************************************************************
;;; 
;;; KEY_EXPAND
;;; The following routine implements the Rijndael key expansion algorithm. The 
;;; caller supplies the 128 bit key in the registers ST11-ST44 and a pointer 
;;; in the YH:YL register pair. The key is expanded to the memory 
;;; positions [Y : Y+16*11-1]. Note: the key expansion is necessary for both
;;; encryption and decryption.
;;; 
;;; Parameters:
;;;     ST11-ST44:  the 128 bit key
;;;     YH:YL:      pointer to ram location
;;; Touched registers:
;;;     ST11-ST44,H1-H3,ZH,ZL,YH,YL

key_expand:
	ldi H1, 1
	ldi H2, $1b
	ldi ZH, high(sbox<<1)
	rjmp keyexp1
keyexp0:mov ZL, ST24
	lpm H3, Z
	eor ST11, H3
	eor ST11, H1
	mov ZL, ST34
	lpm H3, Z
	eor ST21, H3
	mov ZL, ST44
	lpm H3, Z
	eor ST31, H3
	mov ZL, ST14
	lpm H3, Z
	eor ST41, H3
	eor ST12, ST11
	eor ST22, ST21
	eor ST32, ST31
	eor ST42, ST41
	eor ST13, ST12
	eor ST23, ST22
	eor ST33, ST32
	eor ST43, ST42
	eor ST14, ST13
	eor ST24, ST23
	eor ST34, ST33
	eor ST44, ST43
	lsl H1
	brcc keyexp1
	eor H1, H2
keyexp1:st Y+, ST11
	st Y+, ST21
	st Y+, ST31
	st Y+, ST41
	st Y+, ST12
	st Y+, ST22
	st Y+, ST32
	st Y+, ST42
	st Y+, ST13
	st Y+, ST23
	st Y+, ST33
	st Y+, ST43
	st Y+, ST14
	st Y+, ST24
	st Y+, ST34
	st Y+, ST44
	cpi H1, $6c
	brne keyexp0
	ret


;;; ***************************************************************************
;;;
;;; ENCRYPTROUND
;;;
;;; 1 round only, with random delays incorporated; 128 bit plaintext block
;;; supplied in ST11-ST44, expanded key given in YH:YL. The resulting 128 bit
;;; ciphertext block is stored in ST11-ST44.
;;;
;;; Parameters:
;;;     YH:YL:	pointer to expanded key
;;;     ST11-ST44:  128 bit plaintext block
;;; Touched registers:
;;;     ST11-ST44,H1,H2,H3,ZH,ZL,YH,YL
;;; Clock cycles:	Variable

encryptround:

    RandomDelay

    ld H1, Y+     ; AddRoundKey
	eor ST11, H1
	ld H1, Y+
	eor ST21, H1
	ld H1, Y+
	eor ST31, H1
	ld H1, Y+
	eor ST41, H1
	ld H1, Y+
	eor ST12, H1
	ld H1, Y+
	eor ST22, H1
	ld H1, Y+
	eor ST32, H1
	ld H1, Y+
	eor ST42, H1
	ld H1, Y+
	eor ST13, H1
	ld H1, Y+
	eor ST23, H1
	ld H1, Y+
	eor ST33, H1
	ld H1, Y+
	eor ST43, H1
	ld H1, Y+
	eor ST14, H1
	ld H1, Y+
	eor ST24, H1
	ld H1, Y+
	eor ST34, H1
	ld H1, Y+
	eor ST44, H1

    RandomDelay

	ldi ZH, high(sbox<<1)   ; SubBytes + ShiftRows
	mov ZL, ST11
	lpm ST11, Z
	mov ZL, ST12
	lpm ST12, Z
	mov ZL, ST13
	lpm ST13, Z
	mov ZL, ST14
	lpm ST14, Z

    RandomDelay

	mov H1, ST21
	mov ZL, ST22
	lpm ST21, Z
	mov ZL, ST23
	lpm ST22, Z
	mov ZL, ST24
	lpm ST23, Z
	mov ZL, H1
	lpm ST24, Z

    RandomDelay

	mov H1, ST31
	mov ZL, ST33
	lpm ST31, Z
	mov ZL, H1
	lpm ST33, Z
	mov H1, ST32
	mov ZL, ST34
	lpm ST32, Z
	mov ZL, H1
	lpm ST34, Z

    RandomDelay

	mov H1, ST44
	mov ZL, ST43
	lpm ST44, Z
	mov ZL, ST42
	lpm ST43, Z
	mov ZL, ST41
	lpm ST42, Z
	mov ZL, H1
	lpm ST41, Z

    RandomDelay

	ldi ZH, high(xtime<<1)   ; MixColumns
	mov H1, ST11             ; 1st column
	eor H1, ST21
	eor H1, ST31
	eor H1, ST41
	mov H2, ST11
	mov H3, ST11
	eor H3, ST21
	mov ZL, H3
	lpm H3, Z
	eor ST11, H3
	eor ST11, H1
	mov H3, ST21
	eor H3, ST31
	mov ZL, H3
	lpm H3, Z
	eor ST21, H3
	eor ST21, H1
	mov H3, ST31
	eor H3, ST41
	mov ZL, H3
	lpm H3, Z
	eor ST31, H3
	eor ST31, H1
	mov H3, ST41
	eor H3, H2
	mov ZL, H3
	lpm H3, Z
	eor ST41, H3
	eor ST41, H1

    RandomDelay
	
    ldi ZH, high(xtime<<1)
	mov H1, ST12                ; 2nd column
	eor H1, ST22
	eor H1, ST32
	eor H1, ST42
	mov H2, ST12
	mov H3, ST12
	eor H3, ST22
	mov ZL, H3
	lpm H3, Z
	eor ST12, H3
	eor ST12, H1
	mov H3, ST22
	eor H3, ST32
	mov ZL, H3
	lpm H3, Z
	eor ST22, H3
	eor ST22, H1
	mov H3, ST32
	eor H3, ST42
	mov ZL, H3
	lpm H3, Z
	eor ST32, H3
	eor ST32, H1
	mov H3, ST42
	eor H3, H2
	mov ZL, H3
	lpm H3, Z
	eor ST42, H3
	eor ST42, H1

    RandomDelay
	
    ldi ZH, high(xtime<<1)
	mov H1, ST13               ; 3rd column
	eor H1, ST23
	eor H1, ST33
	eor H1, ST43
	mov H2, ST13
	mov H3, ST13
	eor H3, ST23
	mov ZL, H3
	lpm H3, Z
	eor ST13, H3
	eor ST13, H1
	mov H3, ST23
	eor H3, ST33
	mov ZL, H3
	lpm H3, Z
	eor ST23, H3
	eor ST23, H1
	mov H3, ST33
	eor H3, ST43
	mov ZL, H3
	lpm H3, Z
	eor ST33, H3
	eor ST33, H1
	mov H3, ST43
	eor H3, H2
	mov ZL, H3
	lpm H3, Z
	eor ST43, H3
	eor ST43, H1

    RandomDelay
	
    ldi ZH, high(xtime<<1)
	mov H1, ST14                ; 4th column
	eor H1, ST24
	eor H1, ST34
	eor H1, ST44
	mov H2, ST14
	mov H3, ST14
	eor H3, ST24
	mov ZL, H3
	lpm H3, Z
	eor ST14, H3
	eor ST14, H1
	mov H3, ST24
	eor H3, ST34
	mov ZL, H3
	lpm H3, Z
	eor ST24, H3
	eor ST24, H1
	mov H3, ST34
	eor H3, ST44
	mov ZL, H3
	lpm H3, Z
	eor ST34, H3
	eor ST34, H1
	mov H3, ST44
	eor H3, H2
	mov ZL, H3
	lpm H3, Z
	eor ST44, H3
	eor ST44, H1

    RandomDelay

	ret


;;; ***************************************************************************
;;; *** Plain uniform delays
;;; ***************************************************************************
;;; 
;;; RANDOMDELAY_PU
;;; This routine produces delay by dummy cycling for a random number of rounds
;;;  The method is plain uniform.
;;;
;;; Parameters:
;;;     MASK should contain the mask for truncating the delay (i.e. parameter b)
;;; Touched registers:
;;;     RND, X

randomdelay_pu:
    ld    RND, X+       ; put a random number into RNG register
    and   RND, MASK     ; truncate the random value
    tst   RND           ; balancing between 'zero' and 'non-zero' cases
    breq  zero_pu       ; 2 cycles if branch, 1 otherwise
    nop                 
    nop
dummyloop_pu:
    dec   RND		    ; 1 cycle
    brne  dummyloop_pu  ; 2 cycles if branch, 1 otherwise
zero_pu:
    ret

;;; ***************************************************************************
;;; 
;;; INIT_PU
;;; This routine initializes the stuff required for the floating mean method
;;;  in H4 register
;;;
;;; Parameters:
;;;     X is the exlusive pointer-counter for this routine
;;; Touched registers:
;;;     X, RND, MASK, MEAN
init_pu:
  ldi MASK, 0x0f ; set up mask for future use
  ret


;;; ***************************************************************************
;;; *** Floating mean
;;; ***************************************************************************
;;; 
;;; RANDOMDELAY_FM
;;; This routine produces delay by dummy cycling for a random number of rounds
;;;  The method is 'Floating mean'
;;;
;;; Parameters:
;;;     MASK should contain the mask for truncating the delay (i.e. parameter b)
;;; Touched registers:
;;;     RND, X

randomdelay_fm:
    ld    RND, X+       ; put a random number into RNG register
    and   RND, MASK     ; truncate the random value
    add   RND, MEAN     ; add 'floating mean'
    tst   RND           ; balancing between 'zero' and 'non-zero' cases
    breq  zero_fm       ; 2 cycles if branch, 1 otherwise
    nop
    nop
dummyloop_fm:
    dec   RND		    ; 1 cycle
    brne  dummyloop_fm  ; 2 cycles if branch, 1 otherwise
zero_fm:
    ret


;;; ***************************************************************************
;;; 
;;; INIT_FM
;;; This routine initializes the stuff required for the floating mean method
;;;
;;; Parameters:
;;;     X is the exlusive pointer-counter for this routine
;;; Touched registers:
;;;     X, RND, MASK, MEAN
init_fm:
  ld  RND, X+
  mov MEAN, RND
  ldi MASK, 0x0f
  and MEAN, MASK
  ldi MASK, 0x03 ; set up mask for future use in the floating mean
  ret

;;; ***************************************************************************
;;; 
;;; FLIP_FM
;;; 'Flips' the floating mean. To be called in the middle of the execution
flip_fm:
  ldi COUNTER, 0x0f
  sub COUNTER, MEAN
  mov MEAN, COUNTER
  ret


;;; ***************************************************************************
;;; *** Improved floating mean
;;; ***************************************************************************
;;; 
;;; RANDOMDELAY_IFM
;;; This routine produces delay by dummy cycling for a random number of rounds
;;;  The method is 'Improved floating mean'
;;;
;;; Parameters:
;;;     MASK should contain the mask for truncating the delay (i.e. parameter b)
;;; Touched registers:
;;;     RND, X

randomdelay_ifm:
    ld    RND, X+       ; put a random number into RNG register
    and   RND, MASK     ; truncate the random value, including the 'extension'
    add   RND, MEAN     ; add 'floating mean'
    lsr   RND           ; 'squeeze' the delay value with rounding (the number
    lsr   RND           ;  of LSR instructions is equal to parameter k
    lsr   RND
    tst   RND           ; balancing between 'zero' and 'non-zero' cases
    breq  zero_ifm       ;  2 cycles if branch (zero), 1 otherwise (nonzero)
    nop
    nop
dummyloop_ifm:
    dec   RND		     ; 1 cycle
    brne  dummyloop_ifm  ; 2 cycles if branch, 1 otherwise
zero_ifm:
    ret


;;; ***************************************************************************
;;; 
;;; INIT_IFM
;;; This routine initializes the stuff required for the improved floating mean
;;;  method
;;;
;;; Parameters:
;;;     X is the exlusive pointer-counter for this routine
;;; Touched registers:
;;;     X, RND, MASK, MEAN
init_ifm:
  ld  RND, X+
  mov MEAN, RND
  ldi MASK, 0x7f ; the mask for truncating the mean (k=3)
  and MEAN, MASK
  ldi MASK, 0x1f ; set up mask for future use in the floating mean (k=3)
  ret

;;; ***************************************************************************
;;; 
;;; FLIP_IFM
;;; 'Flips' the floating mean. To be called in the middle of the execution
;;;
;;; Touched registers:
;;;    COUNTER is used a s a temporary helper register here
flip_ifm:
  ldi COUNTER, 0x7f ; the same as the mask for truncating the mean (k=3)
  sub COUNTER, MEAN
  mov MEAN, COUNTER
  ret


;;; ***************************************************************************
;;; *** Benoit-Tunstall
;;; ***************************************************************************
;;; 
;;; RANDOMDELAY_BT
;;; This routine produces delay by dummy cycling for a random number of rounds
;;;  The method is 'Benoit-Tunstall'
;;;
;;; Parameters:
;;;     MASK should contain the mask for truncating the delay (i.e. parameter b)
;;; Touched registers:
;;;     RND, X

randomdelay_bt:
    ld   RND, X+       ; put a random number into RNG register
    ldi  ZH, high(bttablesram)
    mov  ZL, RND
    ld   RND, Z        ; lookup dealy value in the table modelling i.c.d.f.
    tst  RND           ; balancing between 'zero' and 'non-zero' cases
    breq zero_bt       ; 2 cycles if branch, 1 otherwise
    nop                 
    nop
dummyloop_bt:
    dec   RND		    ; 1 cycle
    brne  dummyloop_bt  ; 2 cycles if branch, 1 otherwise
zero_bt:
    ret
    

;;; ***************************************************************************
;;; RNG simulation
;;; ***************************************************************************
;;; 
;;; RANDOMBYTE
;;; This routine returns the next random byte from the preloaded pool in SRAM
;;;  in H4 register
;;;
;;; Parameters:
;;;     X is the exlusive pointer-counter for this routine
;;; Touched registers:
;;;     X, RND

;randombyte:
;    ld  RND, X+
;    ret



;;; ***************************************************************************
;;; 
;;; S-BOX and "xtime" tables
;;; Rijndael consists of a non-linear step in its rounds (called "sbox step"), 
;;; here implemented with two hard-coded lookup tables (the sbox itself and its
;;; inverse for decryption). To provide an implementation secure against power 
;;; analysis attacks, the polynomial multiplication in the MixColumns operation 
;;; is done via an auxiliary lookup table called xtime. See [1] for details.
;;;
;;; The three tables have to be aligned to a flash position with its lower 
;;; address byte equal to $00. In assembler syntax: low(sbox<<1) == 0.
;;; To ensure the proper alignment of the sboxes, the assembler directive
;;; .ORG is used (below the sboxes are defined to begin at $800). Note, that 
;;; any other address can be used as well, as long as the lower byte is equal 
;;; to $00.
;;;
;;; The order of the sboxes is totally arbitrary. They even do not have to be
;;; allocated in adjacent memory areas.
	
.CSEG
.ORG $800

sbox:   ; common AES S-Box
.db $63,$7c,$77,$7b,$f2,$6b,$6f,$c5,$30,$01,$67,$2b,$fe,$d7,$ab,$76 
.db $ca,$82,$c9,$7d,$fa,$59,$47,$f0,$ad,$d4,$a2,$af,$9c,$a4,$72,$c0 
.db $b7,$fd,$93,$26,$36,$3f,$f7,$cc,$34,$a5,$e5,$f1,$71,$d8,$31,$15 
.db $04,$c7,$23,$c3,$18,$96,$05,$9a,$07,$12,$80,$e2,$eb,$27,$b2,$75 
.db $09,$83,$2c,$1a,$1b,$6e,$5a,$a0,$52,$3b,$d6,$b3,$29,$e3,$2f,$84 
.db $53,$d1,$00,$ed,$20,$fc,$b1,$5b,$6a,$cb,$be,$39,$4a,$4c,$58,$cf 
.db $d0,$ef,$aa,$fb,$43,$4d,$33,$85,$45,$f9,$02,$7f,$50,$3c,$9f,$a8 
.db $51,$a3,$40,$8f,$92,$9d,$38,$f5,$bc,$b6,$da,$21,$10,$ff,$f3,$d2 
.db $cd,$0c,$13,$ec,$5f,$97,$44,$17,$c4,$a7,$7e,$3d,$64,$5d,$19,$73 
.db $60,$81,$4f,$dc,$22,$2a,$90,$88,$46,$ee,$b8,$14,$de,$5e,$0b,$db 
.db $e0,$32,$3a,$0a,$49,$06,$24,$5c,$c2,$d3,$ac,$62,$91,$95,$e4,$79 
.db $e7,$c8,$37,$6d,$8d,$d5,$4e,$a9,$6c,$56,$f4,$ea,$65,$7a,$ae,$08 
.db $ba,$78,$25,$2e,$1c,$a6,$b4,$c6,$e8,$dd,$74,$1f,$4b,$bd,$8b,$8a 
.db $70,$3e,$b5,$66,$48,$03,$f6,$0e,$61,$35,$57,$b9,$86,$c1,$1d,$9e 
.db $e1,$f8,$98,$11,$69,$d9,$8e,$94,$9b,$1e,$87,$e9,$ce,$55,$28,$df 
.db $8c,$a1,$89,$0d,$bf,$e6,$42,$68,$41,$99,$2d,$0f,$b0,$54,$bb,$16 

xtime:
.db $00,$02,$04,$06,$08,$0a,$0c,$0e,$10,$12,$14,$16,$18,$1a,$1c,$1e
.db $20,$22,$24,$26,$28,$2a,$2c,$2e,$30,$32,$34,$36,$38,$3a,$3c,$3e
.db $40,$42,$44,$46,$48,$4a,$4c,$4e,$50,$52,$54,$56,$58,$5a,$5c,$5e
.db $60,$62,$64,$66,$68,$6a,$6c,$6e,$70,$72,$74,$76,$78,$7a,$7c,$7e
.db $80,$82,$84,$86,$88,$8a,$8c,$8e,$90,$92,$94,$96,$98,$9a,$9c,$9e
.db $a0,$a2,$a4,$a6,$a8,$aa,$ac,$ae,$b0,$b2,$b4,$b6,$b8,$ba,$bc,$be
.db $c0,$c2,$c4,$c6,$c8,$ca,$cc,$ce,$d0,$d2,$d4,$d6,$d8,$da,$dc,$de
.db $e0,$e2,$e4,$e6,$e8,$ea,$ec,$ee,$f0,$f2,$f4,$f6,$f8,$fa,$fc,$fe
.db $1b,$19,$1f,$1d,$13,$11,$17,$15,$0b,$09,$0f,$0d,$03,$01,$07,$05
.db $3b,$39,$3f,$3d,$33,$31,$37,$35,$2b,$29,$2f,$2d,$23,$21,$27,$25
.db $5b,$59,$5f,$5d,$53,$51,$57,$55,$4b,$49,$4f,$4d,$43,$41,$47,$45
.db $7b,$79,$7f,$7d,$73,$71,$77,$75,$6b,$69,$6f,$6d,$63,$61,$67,$65
.db $9b,$99,$9f,$9d,$93,$91,$97,$95,$8b,$89,$8f,$8d,$83,$81,$87,$85
.db $bb,$b9,$bf,$bd,$b3,$b1,$b7,$b5,$ab,$a9,$af,$ad,$a3,$a1,$a7,$a5
.db $db,$d9,$df,$dd,$d3,$d1,$d7,$d5,$cb,$c9,$cf,$cd,$c3,$c1,$c7,$c5
.db $fb,$f9,$ff,$fd,$f3,$f1,$f7,$f5,$eb,$e9,$ef,$ed,$e3,$e1,$e7,$e5


;;; ***************************************************************************
;;; 
;;; Lookup table for the Banoit-Tunstall methood of random delay generation

bttable:
.db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
.db $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01
.db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
.db $01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
.db $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03
.db $03,$03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04
.db $04,$04,$05,$05,$05,$05,$05,$05,$05,$06,$06,$06,$06,$06,$06,$07
.db $07,$07,$07,$08,$08,$08,$09,$09,$09,$0a,$0a,$0a,$0b,$0b,$0b,$0c
.db $0c,$0c,$0c,$0d,$0d,$0d,$0d,$0d,$0e,$0e,$0e,$0e,$0e,$0e,$0f,$0f
.db $0f,$0f,$0f,$0f,$0f,$0f,$0f,$10,$10,$10,$10,$10,$10,$10,$10,$10
.db $10,$10,$10,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
.db $11,$11,$11,$11,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
.db $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13
.db $13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13
.db $13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13
