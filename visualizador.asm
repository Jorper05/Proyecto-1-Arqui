; visualizador.asm
; Programa en ensamblador x64 puro para Linux
; Visualizador de datos con ordenamiento
; Compilar: nasm -f elf64 visualizador.asm -o visualizador.o
; Enlazar: ld visualizador.o -o visualizador

section .data
    ; Archivos
    inventario_file db "inventario.txt", 0
    config_file     db "config.ini", 0
    
    ; Mensajes de error
    error_open      db "Error: No se pudo abrir el archivo", 10, 0
    error_read      db "Error: No se pudo leer el archivo", 10, 0
    error_config    db "Error: Formato de config.ini inválido", 10, 0
    
    ; Códigos ANSI por defecto
    default_char    db 0xE2, 0x96, 0xA0  ; ■
    default_bar_color db "92", 0
    default_bg_color  db "40", 0
    
    ; Variables de configuración
    bar_char        times 4 db 0
    bar_char_len    db 0
    bar_color       times 3 db 0
    bg_color        times 3 db 0
    
    ; Buffer para lectura
    buffer          times 1024 db 0
    
    ; Estructura de inventario
    struc item
        .name:      resb 32
        .quantity:  resd 1
    endstruc
    
    ; Array de items
    items           times 10 * item_size db 0
    item_count      dd 0
    
    ; Códigos ANSI
    ansi_esc        db 0x1B, "["
    ansi_m          db "m", 0
    ansi_reset      db 0x1B, "[0m", 0
    colon           db ":", 0
    space           db " ", 0
    newline         db 10, 0

section .bss
    fd_inventario   resq 1
    fd_config       resq 1
    temp_num        resb 12

section .text
    global _start

_start:
    ; Alinear stack
    and rsp, -16
    
    ; Leer configuración
    call leer_configuracion
    test rax, rax
    jnz _exit_error
    
    ; Leer inventario
    call leer_inventario
    test rax, rax
    jnz _exit_error
    
    ; Ordenar items
    call ordenar_inventario
    
    ; Dibujar gráfico
    call dibujar_grafico
    
    ; Salir
    mov rax, 60
    xor rdi, rdi
    syscall

; Leer configuración desde config.ini
leer_configuracion:
    push rbp
    mov rbp, rsp
    
    ; Abrir archivo
    mov rax, 2
    mov rdi, config_file
    xor rsi, rsi
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .error
    mov [fd_config], rax
    
    ; Leer contenido
    mov rax, 0
    mov rdi, [fd_config]
    mov rsi, buffer
    mov rdx, 1024
    syscall
    cmp rax, 0
    jl .error
    
    ; Valores por defecto
    mov rsi, default_char
    mov rdi, bar_char
    mov rcx, 3
    rep movsb
    mov byte [bar_char_len], 3
    
    mov rsi, default_bar_color
    mov rdi, bar_color
    mov rcx, 3
    rep movsb
    
    mov rsi, default_bg_color
    mov rdi, bg_color
    mov rcx, 3
    rep movsb
    
    ; Procesar configuración
    mov rsi, buffer
    mov rcx, rax
    
    ; Buscar caracter_barra
    mov rdi, .str_caracter
    mov rdx, .len_caracter
    call buscar_substring
    test rax, rax
    jz .check_color_barra
    
    add rsi, rax
    mov rdi, bar_char
    call extraer_valor
    mov [bar_char_len], al
    
.check_color_barra:
    mov rsi, buffer
    mov rdi, .str_color_barra
    mov rdx, .len_color_barra
    call buscar_substring
    test rax, rax
    jz .check_color_fondo
    
    add rsi, rax
    mov rdi, bar_color
    call extraer_valor_num
    
.check_color_fondo:
    mov rsi, buffer
    mov rdi, .str_color_fondo
    mov rdx, .len_color_fondo
    call buscar_substring
    test rax, rax
    jz .close_file
    
    add rsi, rax
    mov rdi, bg_color
    call extraer_valor_num
    
.close_file:
    mov rax, 3
    mov rdi, [fd_config]
    syscall
    
    xor rax, rax
    jmp .exit
    
.error:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_open
    call print_string
    mov rax, 1
    
.exit:
    pop rbp
    ret

.str_caracter      db "caracter_barra:", 0
.len_caracter      equ $ - .str_caracter - 1
.str_color_barra   db "color_barra:", 0
.len_color_barra   equ $ - .str_color_barra - 1
.str_color_fondo   db "color_fondo:", 0
.len_color_fondo   equ $ - .str_color_fondo - 1

; Leer inventario desde inventario.txt
leer_inventario:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    ; Abrir archivo
    mov rax, 2
    mov rdi, inventario_file
    xor rsi, rsi
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .error
    mov [fd_inventario], rax
    
    ; Leer contenido
    mov rax, 0
    mov rdi, [fd_inventario]
    mov rsi, buffer
    mov rdx, 1024
    syscall
    cmp rax, 0
    jl .error
    
    ; Procesar líneas
    mov rsi, buffer
    mov rdi, items
    mov r12, rax
    xor r13, r13
    
.process_line:
    cmp byte [rsi], 0
    je .close_file
    cmp byte [rsi], 10
    je .next_line
    
    ; Copiar nombre
    mov rcx, rdi
    add rcx, item.name
    xor rdx, rdx
    
.copy_name:
    mov al, [rsi]
    cmp al, ':'
    je .found_colon
    cmp al, 10
    je .found_colon
    cmp al, 0
    je .found_colon
    cmp rdx, 31
    jge .next_char
    
    mov [rcx], al
    inc rcx
    inc rdx
    
.next_char:
    inc rsi
    dec r12
    jnz .copy_name
    
.found_colon:
    mov byte [rcx], 0
    cmp byte [rsi], ':'
    jne .next_line
    inc rsi
    dec r12
    
    ; Convertir número
    xor rax, rax
    xor rbx, rbx
    
.convert_number:
    mov bl, [rsi]
    cmp bl, 10
    je .save_quantity
    cmp bl, 0
    je .save_quantity
    cmp bl, '0'
    jb .next_line
    cmp bl, '9'
    ja .next_line
    
    sub bl, '0'
    imul rax, 10
    add rax, rbx
    inc rsi
    dec r12
    jnz .convert_number
    
.save_quantity:
    mov [rdi + item.quantity], eax
    inc dword [item_count]
    add rdi, item_size
    inc r13
    cmp r13, 10
    jge .close_file
    
.next_line:
    cmp byte [rsi], 0
    je .close_file
    cmp byte [rsi], 10
    jne .skip_char
    inc rsi
    dec r12
    jnz .process_line
    jmp .close_file
    
.skip_char:
    inc rsi
    dec r12
    jnz .process_line
    
.close_file:
    mov rax, 3
    mov rdi, [fd_inventario]
    syscall
    xor rax, rax
    jmp .exit
    
.error:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_open
    call print_string
    mov rax, 1
    
.exit:
    pop r13
    pop r12
    pop rbp
    ret

; Ordenar inventario alfabéticamente (Bubble Sort)
ordenar_inventario:
   