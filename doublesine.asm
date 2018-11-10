//--------------------------------------------------------------------------------------------------
// plasma params...

.const templatex_len = _templatex - templatex
.const templatey_len = _templatey - templatey
.const templateend_len = _templateend - templateend

.const colortable = $1400 // $1400 - $14ff
.const bitmap = $2000
.const speedstart = $4000
.const screen = $400
.const sine64 = $1500
.const sine128 = $1700
.const countlo = $02
.const counthi = $03
.const posx = $04
.const posy = $05
.const scrlo = $06
.const scrhi = $07
.const count = $08 // count during execution
.const yval  = $09 // value for the Y row


//--------------------------------------------------------------------------------------------------
.pc = $0801 "basic"
:BasicUpstart(begin)

.pc = sine64 "sine64"
.for (var i=0; i<$200; i++)
	.by 32 + 32 * sin(i/[$100/2/PI])
.pc = sine128 "sine128"
.for (var i=0; i<$200; i++)
	.by 64 + 64 * sin(i/[$100/2/PI])

* = $1000 "Main program"
begin:
	sei

	// Disable Kernal
	lda #$35 //Bank out kernal and basic
	sta $01  //$e000-$ffff

	// Setup VIC bank
	lda $dd00
	ora #$03  // VIC bank to 0000$-3fff$
	sta $dd00

	// Setup video mode
	lda #$38 // 25 col, bitmap, screen on
	sta $d011

	lda #$18 // Bitmap 2000, screen ram 400-7ff
	sta $d018

	// Fill the bitmap
	jsr fillbitmap

	// Build color table
	jsr colorgen

	// Generate speed code
	jsr speedgen

	// Initialize raster interrupt
	lda #$ef    // Disable CIA1 interrupts
	sta $dc0d
	lda $dc0d   // Ack pending iterrupts

	lda #$01		// Initialize the interrupt enable registers
	sta $d01a		// Enable the raster inturrupt
	sta $d019
	lda #$00		// Disable timer in cia1
	sta $dc0e

	lda #100			// Interrupt at line 40
	sta $d012 

	lda #<irq_40 // Initialize the interrupt vector
	sta $fffe
	lda #>irq_40
	sta $ffff

	cli

// Main loop
main_loop: 
	jmp *

rts
//--------------------------------------------------------------------------------------------------
// Interrupt routine
irq_40:
	lda #$01
	sta $d020
	
	lda $d019		  // Ack interrupt
	sta $d019

	inx
	jsr speedstart

	lda #$00
	sta $d020

	rti

//--------------------------------------------------------------------------------------------------
// Speed code generator
colorgen:
	ldx #$00
!loop:
	txa 
	clc
	asl
	asl
	asl
	asl
	bcc !over+
	eor #$ff
!over:
	lsr	
	lsr	
	lsr	
	lsr	
	lsr	
	tay
	lda colors, y
	sta colortable, x
	inx
	bne !loop-
	rts

//--------------------------------------------------------------------------------------------------
// Speed code generator
speedgen:
	lda #01
	sta $d020

	ldx #$00
	ldy #$00
	stx countlo
	stx counthi
	stx count
!loop:
	// store counters
	stx posx
	sty posy
	
	jsr applyxtemplate

	// Keep the count pointer
	lda countlo
	clc
	adc #$01		// + 1
	sta countlo
	lda counthi
	adc #$00    // + carry
	sta counthi
	
	// Main loop
	ldx posx

	inx
	txa // X postion
	cmp #40 // 0-39 characters
	bne !loop-
	ldx #00

	// store X and bring back Y
	stx posx // extra store :|
	ldy posy
	
	// Apply Y template
	jsr applyytemplate

	// Main loop
	ldx posx
	ldy posy

	iny 
	tya // Y postion
	cmp #24 // 0-24 rows * 3 because 3 steps per line
	bne !loop-
	
	// End of speed code
	lda destx			// Copy the correct pointer into the self modifying code
	sta destend
	lda destx+1
	sta destend+1

	ldx #$00									// Loop to put end code in place
!:	
	lda templateend, x				// load code from filled out template
	sta destend: speedstart,x // store the speedcode here (self modifying)
	inx
	cpx #templateend_len
	bne !-
	
	lda #00
	sta $d020
	
	rts // done

//--------------------------------------------------------------------------------------------------
// Apply X template
applyxtemplate:
	// Set sine0 address 
	lda posx			// x position to 
	asl 
	asl
	clc
	adc #<sine128
	sta sine0
	//lda #>sine128  // does not change, here for completeness
	//sta sine0+1

	// Set screenpos address
	lda countlo
	sta screenpos
	lda counthi
	clc
	adc #$04     // $0400 screen address
	sta screenpos+1	

	// store the code in memory
	ldx #$00	
!:
	lda templatex, x // load code from filled out template
	sta destx: speedstart,x // store the speedcode here (self modifying)
	inx
	cpx #templatex_len
	bne !-

	lda destx						// self modify the destination
	clc
	adc #templatex_len
	sta destx
	lda destx+1
	adc #$00						// add carry
	sta destx+1 

	rts

//--------------------------------------------------------------------------------------------------
// Apply Y template
applyytemplate:
	// Copy the current pointer
	lda destx
	sta desty
	lda destx+1
	sta desty+1

	// Modify the template
	tya
	asl
	sta siney0  // every block + 2

	ldx #$00	
!:
	// Y update code
	lda templatey, x // load code from filled out template
	sta desty: speedstart,x // store the speedcode here (self modifying)
	inx
	cpx #templatey_len
	bne !-

	// Save the current pointer + Y template len
	lda destx						// self modify the destinationX (the lead counter)
	clc
	adc #templatey_len
	sta destx
	lda destx+1
	adc #$00						// add carry
	sta destx+1 
	
	rts

//--------------------------------------------------------------------------------------------------
// fill bitmap...
fillbitmap:
	ldx #0
	ldy #$1f
	lda #%01010101
	!:	sta bitmap,x
	eor #%11111111
	inx
	bne !-
	inc !- +2
	dey
	bpl !-

	rts

//--------------------------------------------------------------------------------------------------
// The template for every X mutation
// X holds the time offset
// Y holds the y offset
// A is the result that gets translated and put onto the screen
templatex:
	lda sine0: sine64, x
	adc yval
	tay
	lda colortable, y
	sta screenpos: screen
_templatex:


//--------------------------------------------------------------------------------------------------
// The template for every Y mutation
templatey:
	lda siney0: sine128, x
	sta yval	
_templatey:

//--------------------------------------------------------------------------------------------------
// The template for every Y mutation
templateend:
rts
_templateend:



// Data
colors:		.byte $a7,$aa,$8a,$2a,$b8,$95,$b5,$c5,$55,$5f,$cd,$5d,$37,$dd,$d1,$11
