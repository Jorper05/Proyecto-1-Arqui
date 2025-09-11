 section .data
	filename db "config.ini", 0
	buffer_size equ 256
	newline db 0xA
	err_msg db "Error al abrir el archivo", 0xA
	err_len equ $ - err_msg
	reset_color db 0x1b, "[0m", 0
	; se cargan los valores desde config.ini

 section .bss
	;datos dinamicos
	buffer resb 1024
	inventario resb 1024
	config resb 256
	buffer resb beuffer_size

 section .text
	global _start

 _start:
	;abre el archivo
	mov rax, 2
	mov rdi, filename
	mov rsi, 0
	syscall
	cmp rax, 0
	jl error_open
	mov r12, rax

	;leer el archivo
	mov rax, 0
	mov rdi, 12
	mov rsi, buffer
	mov rdx, buffer_size
	syscall

	;cerrar el archivo
	mov rax, 3
	mov rdi, r12
	syscall

error_ open:
	mov rax, 1
	mov rdi, 1
	mov rsi, err_msg
	mov rdx, err_len
	syscall
	mov rax, 60
	mov rdi, 1
	syscall
