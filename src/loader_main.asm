
; Copyright (c) 2019, k4m1 <k4m1@protonmail.com>
; All rights reserved. See /LICENSE for full license agreement.
;
; This code is responsible of loading the kernel from boot device, and
; then relocating it to 0x10000.
;

%include "src/consoles.asm"
%include "src/bioscall.asm"

loader_main:
	push	bp
	mov	bp, sp

	; We start by finding the kernel header with basic
	; disk read, then proceed with extended disk-read.
	call	load_kern_hdr
	call	parse_kern_hdr
	call	load_kernel

	; Jump to kernel entry after header
	mov	edi, 0x10000
	add	di, word [kern_offset]
	add	edi, 4
	add	edi, 4
	jmp	edi

; Counter for remaining kernel sectors
kern_sectors_left:
	dd	0x00000000

; Offset to beginning of kernel header
kern_offset:
	dw	0x0000

; address where we store our kernel
current_target_addr:
	dd	0x10000

; =================================================================== ;
; Function to handle actual kernel load process.                      ;
; =================================================================== ;

load_kernel:
	push	bp
	mov	bp, sp

.load_kernel_start:
	cmp	dword [kern_sectors_left], 0x28
	jle	.final_iteration

	; Load 0x28 sectors from disk
	mov	word [DAP.sector_count], 0x28
	jmp	.do_read

.final_iteration:
	mov	ax, word [kern_sectors_left]
	mov	word [DAP.sector_count], ax

.do_read:
	mov	dword [DAP.transfer_buffer], 0x2000
	mov	dl, byte [boot_device]
	mov	al, 0x42
	mov	si, DAP
	call	do_bios_call_13h
	jc	.fail

	mov	si, .msg_loaded_chunk
	call	write_serial

	; relocate sectors to 0x10000 onwards
	mov	ecx, (0x28 * 512)

	.relocation_loop_start:
		mov	edx, dword [current_target_addr]
		mov	ebx, 0x2000
	.relocation_loop:
		mov	al, byte [ebx]
		mov	byte [edx], al
		inc	edx
		inc	ebx
		loop	.relocation_loop

	; adjust target address
	inc	edx
	mov	dword [current_target_addr], edx

	; adjust remaining sector count
	mov	ax, word [DAP.sector_count]
	sub	dword [kern_sectors_left], eax
	cmp	dword [kern_sectors_left], 0
	jne	.load_kernel_start

	; we're done reading the kernel !
	mov	sp, bp
	pop	bp
	ret

.fail:
	mov	esi, .msg_kern_load_failed
	call	panic
.msg_kern_load_failed:
	db "KERNEL LOAD FAILED", 0x0A, 0x0D, 0
.msg_loaded_chunk:
	db "Loaded ~ 20Kb chunk of kernel.", 0x0A, 0x0D, 0

; =================================================================== ;
; Function to get kernel header.                                      ;
; We'll load kernel header to static address 0x2000                   ;
; =================================================================== ;
load_kern_hdr:
	push	bp
	mov	bp, sp

	mov	bx, 0x2000
	mov	ch, 0x00
	mov	cl, SECTOR_CNT
	add	cl, 4
	xor	dh, dh
	mov	dl, byte [boot_device]

	.read_start:
		mov	di, 5
	.read:
		mov	ah, 0x02
		mov	al, 1
		call	do_bios_call_13h
		jnc	.read_done
		dec	di
		test	di, di
		jnz	.read
		mov	si, .msg_disk_read_fail
		call	panic
	.read_done:
		mov	sp, bp
		pop	bp
		ret
	.msg_disk_read_fail:
		db	"DISK READ FAILED", 0x0

; =================================================================== ;
; Function to parse kernel header & populate DAP accordingly. See     ;
; section below.                                                      ;
; =================================================================== ;
parse_kern_hdr:
	mov	si, 0x2000
	.loop:
		cmp	dword [si], 'nyan'
		jne	.invalid_hdr

	sub	si, 0x2000
	mov	word [kern_offset], si
	add	si, 0x2000
	push	si
	mov	si, .msg_kernel_found
	call	write_serial
	pop	si

	add	si, 4
	mov	eax, dword [si]
	mov	dword [kern_sectors_left], eax
	ret

.invalid_hdr:
	inc	si
	cmp	si, 0x2512
	jl	.loop
.fail:
	mov	si, .msg_invalid_hdr
	call	panic

.msg_invalid_hdr:
	db	"INVALID KERNEL HEADER, CORRUPTED DISK?", 0x0
.msg_kernel_found:
	db	"Found kernel from sector "
	db	(0x30 + SECTOR_CNT + 4)
	db	0x0A, 0x0D, 0

; =================================================================== ;
; Disk address packet format:                                         ;
;                                                                     ;
; Offset | Size | Desc                                                ;
;      0 |    1 | Packet size                                         ;
;      1 |    1 | Zero                                                ;
;      2 |    2 | Sectors to read/write                               ;
;      4 |    4 | transfer-buffer 0xffff:0xffff                       ;
;      8 |    4 | lower 32-bits of 48-bit starting LBA                ;
;     12 |    4 | upper 32-bits of 48-bit starting LBAs               ;
; =================================================================== ;

DAP:
	.size:
		db	0x10
	.zero:
		db	0x00
	.sector_count:
		dw	0x0000
	.transfer_buffer:
		dd	0x00000000
	.lower_lba:
		dd	0x00000000
	.higher_lba:
		dd	0x00000000

sectors equ SECTOR_CNT * 512 + 512
times sectors db 0xff

