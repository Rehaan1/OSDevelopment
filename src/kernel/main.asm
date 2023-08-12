; org directive tells the assembler where we expect our code to be loaded
org 0x0

; tell assembler to emit 16 bit code
bits 16


%define ENDL 0x0D, 0x0A

start:
	; print message
	mov si, msg_hello
	call puts

.halt:	
	; hlt stops cpu from executing and can be resumed by an interrupt
	cli
	hlt

;
; Prints a string to the screen
; Params:
; 	- ds:si points to string
;
puts:

	; save registers we will modify
	push si
	push ax
	push bx

.loop:
	; loadsb, loadsw, loadsd: these instructions load a byte/word/doubleword from ds:si into
	; al/ax/eax, then increment si by the number of bytes loaded
	
	lodsb	; loads next character in al
	or al, al	; verify if next character is null
	jz .done ; jz : jumps to destination if zero flag is set

	mov ah, 0x0E
	mov bh, 0
	int 0x10 ; triggers a software interrupt

	jmp .loop
	
.done:
	pop bx
	pop ax
	pop si
	ret


msg_hello: db 'Hello World From UTOPIAN Kernel!', ENDL, 0
