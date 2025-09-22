; Compilar: nasm -f elf64 visualizador.asm -o visualizador.o
; Enlazar: ld visualizador.o -o visualizador
; Ejecutar: ./visualizador

section .data
    ; Archivos
    inventario_file db "inventario.txt", 0
    config_file     db "config.ini", 0
    
    ; Mensajes de error
    error_open      db "Error: No se pudo abrir el archivo", 10, 0
    error_read      db "Error: No se pudo leer el archivo", 10, 0
    error_config    db "Error: Formato de config.ini inválido", 10, 0
    
    ; Códigos ANSI por defecto - SIMPLIFICADO
    default_char    db "#", 0              ; Carácter simple ASCII
    default_bar_color db "92", 0           ; Verde
    default_bg_color  db "40", 0           ; Negro
    
    ; Variables de configuración
    bar_char        times 4 db 0
    bar_char_len    dd 0
    bar_color       times 8 db 0
    bg_color        times 8 db 0
    
    ; Buffer para lectura
    buffer          times 1024 db 0
    
    ; Estructura de inventario
    struc item
        .name:      resb 32
        .quantity:  resd 1
    endstruc
    
    ; Array de items
    items           times 10 * 36 db 0
    item_count      dd 0
    
    ; Códigos ANSI
    ansi_esc        db 0x1B, 0         ; ESC character
    ansi_open       db "[", 0          ; ANSI open bracket
    ansi_m          db "m", 0          ; ANSI end
    ansi_reset      db 0x1B, "[0m", 0  ; ANSI reset code
    
    ; Textos para imprimir
    dos_puntos      db ": ", 0
    espacio         db " ", 0
    nueva_linea     db 10, 0

section .bss
    fd_inventario   resq 1
    fd_config       resq 1
    temp_num        resb 12
    char_buffer     resb 1

section .text
    global _start

%define ITEM_SIZE 36

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

; ========================================
; CONFIGURACIÓN
; ========================================

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
    mov rcx, 1
    rep movsb
    mov byte [bar_char_len], 1
    
    mov rsi, default_bar_color
    mov rdi, bar_color
    call copiar_string
    
    mov rsi, default_bg_color
    mov rdi, bg_color
    call copiar_string
    
    ; Procesar configuración
    mov rsi, buffer
    
    ; Buscar caracter_barra
    mov rdi, .str_caracter
    mov rdx, .len_caracter
    call buscar_substring
    test rax, rax
    jz .check_color_barra
    
    add rsi, rax
    mov rdi, bar_char
    call extraer_valor_simple
    call strlen
    mov [bar_char_len], eax
    
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

; ========================================
; INVENTARIO
; ========================================

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
    cmp r12, 0
    jle .close_file
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
    jmp .close_file
    
.found_colon:
    mov byte [rcx], 0
    cmp byte [rsi], ':'
    jne .next_line
    inc rsi
    dec r12
    jz .close_file
    
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
    add rdi, ITEM_SIZE
    inc r13
    cmp r13, 10
    jge .close_file
    
.next_line:
    cmp r12, 0
    jle .close_file
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

; ========================================
; ORDENAMIENTO
; ========================================

ordenar_inventario:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    
    mov ecx, [item_count]
    cmp ecx, 1
    jle .exit
    
    dec ecx
    mov r12, items
    
.outer_loop:
    xor r11, r11
    xor r10, r10
    
.inner_loop:
    cmp r10, rcx
    jge .check_swap
    
    mov rax, r10
    imul rax, ITEM_SIZE
    lea rsi, [r12 + rax]
    
    mov rbx, r10
    inc rbx
    imul rbx, ITEM_SIZE
    lea rdi, [r12 + rbx]
    
    mov rax, rsi
    add rax, item.name
    mov rbx, rdi
    add rbx, item.name
    
    call comparar_strings
    jle .no_swap
    
    call intercambiar_items
    mov r11, 1
    
.no_swap:
    inc r10
    jmp .inner_loop
    
.check_swap:
    test r11, r11
    jz .exit
    dec ecx
    jnz .outer_loop
    
.exit:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ========================================
; GRÁFICO - VERSIÓN SIMPLIFICADA
; ========================================

dibujar_grafico:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    mov r12, items
    mov r13d, [item_count]
    test r13d, r13d
    jz .exit
    
.draw_item:
    cmp byte [r12 + item.name], 0
    je .next_item
    
    ; Nombre
    mov rsi, r12
    add rsi, item.name
    call print_string
    
    ; ": "
    mov rsi, dos_puntos
    call print_string
    
    ; Aplicar color de fondo
    call aplicar_color_fondo
    
    ; Aplicar color de barra
    call aplicar_color_barra
    
    ; Barras
    mov ecx, [r12 + item.quantity]
    test ecx, ecx
    jz .no_bars
    
.bar_loop:
    push rcx
    mov rsi, bar_char
    call print_string
    pop rcx
    loop .bar_loop
    
.no_bars:
    ; Reset color
    call reset_color
    
    ; Espacio y cantidad
    mov rsi, espacio
    call print_string
    
    mov eax, [r12 + item.quantity]
    call imprimir_numero
    
    ; Nueva línea
    mov rsi, nueva_linea
    call print_string
    
.next_item:
    add r12, ITEM_SIZE
    dec r13d
    jnz .draw_item
    
.exit:
    pop r13
    pop r12
    pop rbp
    ret

aplicar_color_fondo:
    push rax
    push rdi
    push rsi
    push rdx
    
    ; ESC[
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_esc
    mov rdx, 1
    syscall
    
    mov rax, 1
    mov rsi, ansi_open
    mov rdx, 1
    syscall
    
    ; Código de fondo
    mov rsi, bg_color
    call print_string
    
    ; m
    mov rax, 1
    mov rsi, ansi_m
    mov rdx, 1
    syscall
    
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

aplicar_color_barra:
    push rax
    push rdi
    push rsi
    push rdx
    
    ; ESC[
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_esc
    mov rdx, 1
    syscall
    
    mov rax, 1
    mov rsi, ansi_open
    mov rdx, 1
    syscall
    
    ; Código de barra
    mov rsi, bar_color
    call print_string
    
    ; m
    mov rax, 1
    mov rsi, ansi_m
    mov rdx, 1
    syscall
    
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

reset_color:
    push rax
    push rdi
    push rsi
    push rdx
    
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_reset
    mov rdx, 4
    syscall
    
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; ========================================
; FUNCIONES AUXILIARES
; ========================================

imprimir_numero:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    mov rdi, temp_num + 11
    mov byte [rdi], 0
    
    test eax, eax
    jnz .convert
    
    ; Caso cero
    mov byte [rdi - 1], '0'
    dec rdi
    jmp .print
    
.convert:
    mov ebx, 10
    xor ecx, ecx
    
.convert_loop:
    xor edx, edx
    div ebx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    inc ecx
    test eax, eax
    jnz .convert_loop
    
.print:
    mov rsi, rdi
    call print_string
    
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

buscar_substring:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    
    mov r12, rdi
    mov r13, rdx
    mov r14, rsi
    mov rcx, 1024
    
.search_loop:
    mov rdi, r12
    mov rsi, r14
    mov rdx, r13
    
.compare:
    mov al, [rdi]
    cmp al, [rsi]
    jne .no_match
    inc rdi
    inc rsi
    dec rdx
    jnz .compare
    
    mov rax, r13
    jmp .exit
    
.no_match:
    inc r14
    loop .search_loop
    xor rax, rax
    
.exit:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

extraer_valor_simple:
    push rbp
    mov rbp, rsp
    
.loop:
    mov al, [rsi]
    cmp al, 10
    je .done
    cmp al, 0
    je .done
    cmp al, ' '
    je .skip
    cmp al, 13
    je .skip
    
    mov [rdi], al
    inc rdi
    
.skip:
    inc rsi
    jmp .loop
    
.done:
    mov byte [rdi], 0
    pop rbp
    ret

extraer_valor_num:
    push rbp
    mov rbp, rsp
    
.loop:
    mov al, [rsi]
    cmp al, 10
    je .done
    cmp al, 0
    je .done
    cmp al, '0'
    jb .skip
    cmp al, '9'
    ja .skip
    
    mov [rdi], al
    inc rdi
    
.skip:
    inc rsi
    jmp .loop
    
.done:
    mov byte [rdi], 0
    pop rbp
    ret

comparar_strings:
    push rbp
    mov rbp, rsp
    
.compare:
    mov al, [rax]
    mov dl, [rbx]
    test al, al
    jz .check_second
    test dl, dl
    jz .greater
    cmp al, dl
    jne .difference
    inc rax
    inc rbx
    jmp .compare

.check_second:
    test dl, dl
    jz .equal
    jmp .less

.difference:
    cmp al, dl
    jl .less

.greater:
    mov eax, 1
    jmp .exit

.less:
    mov eax, -1
    jmp .exit

.equal:
    xor eax, eax

.exit:
    pop rbp
    ret

intercambiar_items:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    mov r12, rsi
    mov r13, rdi
    mov rcx, ITEM_SIZE
    
.swap_loop:
    mov al, [r12]
    mov dl, [r13]
    mov [r12], dl
    mov [r13], al
    inc r12
    inc r13
    loop .swap_loop
    
    pop r13
    pop r12
    pop rbp
    ret

copiar_string:
    push rbp
    mov rbp, rsp
    
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .loop
    
.done:
    mov byte [rdi], 0
    pop rbp
    ret

print_string:
    push rbp
    mov rbp, rsp
    push rsi
    
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    pop rsi
    syscall
    
    pop rbp
    ret

strlen:
    push rbp
    mov rbp, rsp
    xor rcx, rcx
    
.loop:
    cmp byte [rdi + rcx], 0
    je .done
    inc rcx
    jmp .loop
    
.done:
    mov rax, rcx
    pop rbp
    ret

_exit_error:
    mov rax, 60
    mov rdi, 1
    syscall