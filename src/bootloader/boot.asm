; org directive tells the assembler where we expect our code to be loaded. In our case since
; we are using legacy bios booting mode we want it on location 0x7C00

; directive gives clue to assembler and is not translated to machine code
; a instruction is translated into machine code

org 0x7C00

; tell assembler to emit 16 bit code

bits 16


%define ENDL 0x0D, 0x0A

; 
; FAT12 header
;
jmp short start
nop

bdb_oem:	db 'MSWIN4.1' ; 8 bytes
bdb_bytes_per_sector:	dw 512
bdb_sectors_per_cluster: db 1
bdb_reserved_sectors: dw 1
bdb_fat_count: db 2
bdb_dir_entries_count: dw 0E0h
bdb_total_sectors: dw 2880 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type: db 0F0h ; F0 = 3.5" floppy disk
bdb_sectors_per_fat: dw 9 ; 9 sectors/fat
bdb_sectors_per_track: dw 18
bdb_heads: dw 2
bdb_hidden_sectors: dd 0
bdb_large_sector_count: dd 0

;
;	extended boot record
;
ebr_drive_number: db 0 ; 0x00 = floppy, 0x80 = hdd
				  db 0 ; reserved
ebr_signature:	db 29h
ebr_volume_id: db 12h, 34h, 56h, 78h ; serial number
ebr_volume_label: db 'UTOPIAN OS ' ; 11 bytes, padded with spaces
ebr_system_id:	db 'FAT12   ' ; 8 bytes

;
;
;

start:
	; setup data segments
	mov ax, 0 ; can't write to ds/es directly
	mov ds, ax
	mov es, ax

	; setup stack
	mov ss, ax
	mov sp, 0x7C00 ; stack grows downwards from where we are loaded in memory, making sure we dont override OS

	; some BIOSes might start us at 07C0:0000 instead of 0000:7C00
	; make sure we are in the expected location
	push es
	push word .after
	retf

.after:


	; read something from floppy disk
	; BIOS should set DL to drive number
	mov [ebr_drive_number], dl

	; show loading message
	mov si, msg_loading
	call puts

	; read drive parameters using BIOS routine Interrupt (sectors per track and head count)
	; instead of relying on data from formatted disk letting BIOS tell us
	push es
	move ah, 08h
	int 13h
	jc floppy_error
	pop es

	and cl, 0x3F ; remove top 2 bits
	xor ch, ch
	mov [bdb_sectors_per_track], cx ; sectors count

	inc dh
	mov [bdb_heads], dh ; head count

	; read FAT root directory
	; note: this section can be hardcoded
	mov ax, [bdb_sectors_per_fat] ; LBA of root directory = reserved + fats * fat_size
	mov bl, [bdb_fat_count]
	xor bh, bh
	mul bx ; ax = (fats * sectors_per_fat)
	add ax, [bdb_reserved_sectors] ; ax = LBA of root directory
	push ax

	; compute size of root directory = (32 * number of entries) / bytes per sector
	mov ax, [bdb_sectors_per_fat] 
	shl ax, 5 ; ax *= 32
	xor dx, dx ; dx = 0
	div word [bdb_bytes_per_sector] ; number of sectors we need to read

	test dx, dx ; if dx != 0, add 1
	jz .root_dir_after
	inc ax ; division remaining != 0, add 1
		   ; this means we have a sector only partially filled

.root_dir_after:

	; read root directory
	mov cl, al ; cl = number of sectors to read = size of root directory
	pop ax ; ax = LBA of root directory
	mov dl, [ebr_drive_number] ; dl = drive number
	mov bx, buffer ; ex:bx = buffer
	call disk_read


	; search for kernel.bin
	xor bx, bx
	mov di, buffer

.search_kernel:
	mov si, file_kernel_bin
	mov cx, 11 ; compare upto 11 characters
	push di
	repe cmpsb ; repe repeats while equal upto cx times and cx is decremented, cmpsb compares two bytes in memory one stored in ds:si and es:di
	pop di
	je .found_kernel

	; move to next directory entry
	add di, 32 ; 32 is size of directory entry
	inc bx
	cmp bx, [bdb_dir_entries_count]
	jl .search_kernel

	; kernel not found
	jmp kernel_not_found_error

.found_kernel:
	
	; di should have the address to the entry
	mov ax, [di + 26] ; first logical cluster field (offset 26)
	mov [kernel_cluster], ax

	; load FAT from disk into memory
	mov ax, [bdb_reserved_sectors]
	mov bx, buffer
	mov cl, [bdb_sectors_per_fat]
	mov dl, [ebr_drive_number]
	call disk_read

	; read kernel and process FAT chain
	mov bx, KERNEL_LOAD_SEGMENT
	mov es, bx
	mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:

	; Read next cluster
	mov ax, [kernel_cluster]

	; TODO: Change Hardcoded value
	add ax, 31 ; first cluster = start_sector + (kernel_cluster - 2 ) * sectors_per_cluster
			   ; start_sector = reserved + fats + root directory size = 1 + 18 + 134 = 33
	mov cl, 1
	mov dl, [ebr_drive_number]
	call disk_read

	add bx, [bdb_bytes_per_sector]
	
	; compute location of next cluster
	mov ax, [kernel_cluster]
	mov cx, 3
	mul cx
	mov cx, 2
	div cx ; ax = index of entry in fAT, dx = cluster mod 2

	mov si, buffer
	add si, ax
	mov ax, [ds:si] ; read entry from FAT Table at index ax

	or dx, dx

	jz .even

.odd:
	shr ax, 4
	jmp .next_cluster_after

.even:
	and ax, 0x0FFF

.next_cluster_after:
	cmp ax, 0x0FF8  ; check end of chain
	jae .read_finish

	mov [kernel_cluster], ax
	jmp .load_kernel_loop

.read_finish:
	
	; jump to our kernel
	mov dl, [ebr_drive_number] ; boot device in dl

	; set segment registers
	mov ax, KERNEL_LOAD_OFFSET

	mov ds, ax
	mov es, ax

	jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET


	; if jump fails
	jmp wait_key_and_reboot



	; hlt stops cpu from executing and can be resumed by an interrupt
	
	cli ; disable interrupts
	hlt

;
; Error Handlers
;

floppy_error:
	mov si, msg_read_failed
	call puts
	jmp wait_key_and_reboot

kernel_not_found_error:
	mov si, msg_kernel_not_found
	call puts
	jmp wait_key_and_reboot

wait_key_and_reboot:
	mov ah, 0
	int 16h		; wait for keypress
	jmp 0FFFFh:0 ; jump to beginning of BIOS, should reboot

.halt:
	cli			; disable interrupts, this way we cant get out of halt state
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

	mov ah, 0x0e
	mov bh, 0
	int 0x10 ; triggers a software interrupt

	jmp .loop
	
.done:
	pop bx
	pop ax
	pop si
	ret


;
; Disk Routines
;

;
; Converts an LBA address to a CHS address
; Parameters:
; 	- ax: LBA address
; Returns:
;   - cx [bits 0-5]: sector number
; 	- cs [bits 6-15]: cylinder
;	- dh: head

lba_to_chs:

	push ax
	push dx

	xor dx, dx	; dx = 0
	div word [bdb_sectors_per_track] ; ax = LBA / SectorsPerTrack
									 ; dx = LBA % SectorsPerTrack
	inc dx							 ; dx = (LBA % SectorsPerTrack + 1) = sector
	mov cx, dx						 ; cx = sector

	xor dx, dx	; dx = 0
	div word [bdb_heads]			 ; ax = (LBA / SectorsPerTrack) / Heads = cylinder
									 ; dx = (LBA / SectorsPerTrack) % Heads = head
	mov dh, dl					 ; dh = head
	mov ch, al						 ; ch = cylinder (lower 8 bits)
	shl ah, 6  						 
	or cl, ah						 ; put upper 2 bits of cylinder in CL

	pop ax
	mov dl, al						 ; restor dl
	pop ax
	ret

;
; Reads Sectors from a Disk
; Parameters:
; 	- ax: LBA address
;   - cl: number of sectors to read (upto 128)
;   - dl: drive number
;   - es:bx: memory address where to store read data
disk_read:
	
	push ax			; save registers we will modify
	push bx
	push cx
	push dx
	push di
	
	push cx			; temporarilu save cl (number of sectors to read)
	call lba_to_chs ; compute chs
	pop ax			; al = number of sectors to read
	
	mov ah, 02h
	mov di, 3		; retry count

.retry:
	pusha			; save all registers, we dont know what bios modifies
	stc				; set carry flag
	int 13h			; carry flag cleared = success
	jnc .done

	;read failed
	popa
	call disk_reset

	dec di
	test di, di
	jnz .retry

.fail:
	; after all attempts
	jmp floppy_error

.done:
	popa

	pop di			; restore registers
	pop dx
	pop cx
	pop bx
	pop ax
	
	ret

;
; Resets disk controllers
; Parameters:
;	dl: drive number
;
disk_reset:
	pusha
	mov ah, 0
	stc
	int 13h
	jc floppy_error
	popa
	ret

msg_loading: db 'Loading UTOPIAN Operating System....', ENDL, 0
msg_read_failed: db 'Read From Disk Failed!', ENDL, 0
msg_kernel_not_found: db 'KERNEL.BIN : UTOPIAN Kernel Not Found!', ENDL, 0
file_kernel_bin: db 'KERNEL  BIN'
kernel_cluster: dw 0

KERNEL_LOAD_SEGMENT	equ 0x2000
KERNEL_LOAD_OFFSET	equ 0

; bios expects that last two bytes of the first sector is AA55
; we are putting it in standard floppy disk

; db directive writes given bytes to the assembled binary file
; times directive used to repeate given instructions or data
; dollar sign which is equal to the memory offset of the current line
; double dollar sign which is equal to the memory offset of the beginning of the current section

; dolar - dollar dollar gives the size of the program so far in bytes

times 510-($-$$) db 0
dw 0AA55h

buffer:
