 section .data
	newline db 0xA
	reset_color db 0x1b, "[0m", 0
	; se cargan los valores desde config.ini

 section .bss
	;datos dinamicos
	buffer resb 1024
	inventario resb 1024
	config resb 256

 section .text
	global _start

 _start:
	
