; org directive tells the assembler where we expect our code to be loaded. In our case since
; we are using legacy bios booting mode we want it on location 0x7C00

; directive gives clue to assembler and is not translated to machine code
; a instruction is translated into machine code

org 0x7C00

; tell assembler to emit 16 bit code

bits 16


%define ENDL 0x0D, 0x0A

start:
	jmp main


;
; Prints a string to the screen
; Params:
; 	- ds:si points to string
;
puts:

	; save registers we will modify
	push si
	push ax

.loop:
	; loadsb, loadsw, loadsd: these instructions load a byte/word/doubleword from ds:si into
	; al/ax/eax, then increment si by the number of bytes loaded
	
	lodsb	; loads next character in al
	or al, al	; verify if next character is null
	jz .done ; jz : jumps to destination if zero flag is set

	mov ah, 0x0e
	mov bh, 0
	int 0x10 ; triggers a software interrupt

	jmp .loop
	
.done:
	pop ax
	pop si
	ret

main:

	; setup data segments
	mov ax, 0 ; can't write to ds/es directly
	mov ds, ax
	mov es, ax

	; setup stack
	mov ss, ax
	mov sp, 0x7C00 ; stack grows downwards from where we are loaded in memory, making sure we dont override OS


	; print message
	mov si, msg_hello
	call puts
	
	; hlt stops cpu from executing and can be resumed by an interrupt
	hlt

.halt:
	; jmp jumps to given location
	jmp .halt


msg_hello: db 'Hello World!', ENDL, 0

; bios expects that last two bytes of the first sector is AA55
; we are putting it in standard floppy disk

; db directive writes given bytes to the assembled binary file
; times directive used to repeate given instructions or data
; dollar sign which is equal to the memory offset of the current line
; double dollar sign which is equal to the memory offset of the beginning of the current section

; dolar - dollar dollar gives the size of the program so far in bytes

times 510-($-$$) db 0
dw 0AA55h
