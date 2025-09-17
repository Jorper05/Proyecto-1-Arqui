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

    ; Procesar inventario
    mov rsi, buffer_inv
    mov rdi, nombres
    mov rbx, cantidades
    call parse_inventario

    ; Ordenar inventario
    call sort_inventory

    ; Dibujar gráfico
    call draw_graph

    ; Salir
    mov rax, 60
    xor rdi, rdi
    syscall

error:
    mov rax, 1
    mov rdi, 1
    mov rsi, err_msg
    mov rdx, err_len
    syscall
    mov rax, 60
    mov rdi, 1
error_format:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg_format
    mov rdx, msg_format_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall
    syscall

; Funciones para buscar claves
find_key_char_barra:
    mov rdi, key_char_barra
    call find_value
    ret

find_key_color_barra:
    mov rdi, key_color_barra
    call find_value
    ret

find_key_color_fondo:
    mov rdi, key_color_fondo
    call find_value
    ret

find_value:
.next_char:
    mov al, [rsi]
    cmp al, 0
    je .not_found
    mov rbx, rsi
    mov rcx, rdi
.compare:
    mov al, [rbx]
    mov dl, [rcx]
    cmp dl, 0
    je .found
    cmp al, dl
    jne .next
    inc rbx
    inc rcx
    jmp .compare
.next:
    inc rsi
    jmp .next_char
.found:
    add rsi, 14
    ret
.not_found:
    ret

copy_value:
    mov rcx, 0
.copy_loop:
    mov al, [rsi + rcx]
    cmp al, 0xA
    je .done
    mov [rdi + rcx], al
    inc rcx
    cmp rcx, 4
    je .done
    jmp .copy_loop
.done:
    ret

parse_inventario:
    mov rcx, 0
.next_line:
    mov rdx, 0
.read_name:
    mov al, [rsi]
    cmp al, ':'
    jne error_format
    cmp al, ':'
    je .read_quantity
    cmp al, 0
    je .done
    cmp al, 0xA
    je .next_line
mov r10, rcx
imul r10, 32
add r10, rdx
mov [rdi + r10], al
    inc rdx
    inc rsi
    jmp .read_name

.read_quantity:
    inc rsi
    mov rdx, 0
    cmp al, '0'
    jl error_format
    cmp al, '9'
    jg error_format
.read_digits:
    mov al, [rsi]
    cmp al, 0xA
    je .store_next
    cmp al, 0
    je .done
mov r11, rcx
imul r11, 8
add r11, rdx
mov [rbx + r11], al
    inc rdx
    inc rsi
    jmp .read_digits

.store_next:
    inc rsi
    inc rcx
    cmp rcx, 4
    je .done
    jmp .next_line
.done:
    ret

sort_inventory:
    mov rcx, 4
.outer_loop:
    mov rsi, 0
.inner_loop:
    mov rdi, nombres
    mov rbx, cantidades

    mov r8, rsi
    imul r8, 32
    add rdi, r8

    mov r9, rsi
    inc r9
    imul r9, 32
    mov rdx, nombres
    add rdx, r9

    mov r8, 0

.compare_chars:
    mov al, [rdi + r8]
    mov bl, [rdx + r8]
    cmp al, bl
    je .next_char
    jb .no_swap
    jmp .do_swap
.next_char:
    inc r8
    cmp r8, 32
    jne .compare_chars
    jmp .no_swap

.do_swap:
    mov r8, 0
.swap_loop:
    mov al, [rdi + r8]
    mov bl, [rdx + r8]
    mov [rdi + r8], bl
    mov [rdx + r8], al
    inc r8
    cmp r8, 32
    jne .swap_loop

    mov rdi, cantidades
    mov rdx, cantidades
    mov r8, rsi
    imul r8, 8
    add rdi, r8
    mov r9, rsi
    inc r9
    imul r9, 8
    add rdx, r9

    mov r8, 0
.swap_qty:
    mov al, [rdi + r8]
    mov bl, [rdx + r8]
    mov [rdi + r8], bl
    mov [rdx + r8], al
    inc r8
    cmp r8, 8
    jne .swap_qty

.no_swap:
    inc rsi
    cmp rsi, 3
    jl .inner_loop
    loop .outer_loop
    ret

