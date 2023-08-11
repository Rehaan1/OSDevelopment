; org directive tells the assembler where we expect our code to be loaded. In our case since
; we are using legacy bios booting mode we want it on location 0x7C00

; directive gives clue to assembler and is not translated to machine code
; a instruction is translated into machine code

org 0x7C00

; tell assembler to emit 16 bit code

bits 16

main:
	; hlt stops cpu from executing and can be resumed by an interrupt
	hlt

.halt:
	; jmp jumps to given location
	jmp .halt

; bios expects that last two bytes of the first sector is AA55
; we are putting it in standard floppy disk

; db directive writes given bytes to the assembled binary file
; times directive used to repeate given instructions or data
; dollar sign which is equal to the memory offset of the current line
; double dollar sign which is equal to the memory offset of the beginning of the current section

; dolar - dollar dollar gives the size of the program so far in bytes

times 510-($-$$) db 0
dw 0AA55h
