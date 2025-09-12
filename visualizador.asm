; visualizador.asm
; Compilar: nasm -f elf64 -o visualizador.o visualizador.asm
; Enlazar: ld -o visualizador visualizador.o

section .data
    filename_cfg db "config.ini", 0
    filename_inv db "inventario.txt", 0

    key_char_barra db "caracter_barra:", 0
    key_color_barra db "color_barra:", 0
    key_color_fondo db "color_fondo:", 0

    sep db ": ", 0
    sep_len equ $ - sep

    ansi_prefix db 0x1b, "["
    ansi_prefix_len equ $ - ansi_prefix
    sep_color db ";"
    ansi_suffix db "m"
    ansi_suffix_len equ $ - ansi_suffix

    reset_color db 0x1b, "[0m"
    reset_color_len equ $ - reset_color

    newline db 0xA

    err_msg db "Error al abrir archivo", 0xA
    err_len equ $ - err_msg
msg_format db "Error: formato inválido en inventario.txt", 0xA
msg_format_len equ $ - msg_format

section .bss
    buffer_cfg resb 256
    buffer_inv resb 512

    char_bar resb 4
    color_bar resb 4
    color_bg resb 4

    nombres resb 128        ; 4 frutas x 32 bytes
    cantidades resb 32      ; 4 cantidades x 8 bytes

section .text
    global _start

_start:
    ; Leer config.ini
    mov rax, 2
    mov rdi, filename_cfg
    mov rsi, 0
    syscall
    cmp rax, 0
    jl error
    mov r12, rax

    mov rax, 0
    mov rdi, r12
    mov rsi, buffer_cfg
    mov rdx, 256
    syscall

    mov rax, 3
    mov rdi, r12
    syscall

    ; Procesar config.ini
    mov rsi, buffer_cfg
    call find_key_char_barra
    mov rdi, char_bar
    call copy_value

    mov rsi, buffer_cfg
    call find_key_color_barra
    mov rdi, color_bar
    call copy_value

    mov rsi, buffer_cfg
    call find_key_color_fondo
    mov rdi, color_bg
    call copy_value

    ; Leer inventario.txt
    mov rax, 2
    mov rdi, filename_inv
    mov rsi, 0
    syscall
    cmp rax, 0
    jl error
    mov r12, rax

    mov rax, 0
    mov rdi, r12
    mov rsi, buffer_inv
    mov rdx, 512
    syscall

    mov rax, 3
    mov rdi, r12
    syscall

   
