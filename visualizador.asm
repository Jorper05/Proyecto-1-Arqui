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
    default_char    db 0xE2, 0x96, 0x88, 0  ; █ (carácter de bloque completo)
    default_bar_color db "92", 0
    default_bg_color  db "40", 0
    
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
    items           times 10 * item_size db 0
    item_count      dd 0
    
    ; Códigos ANSI
    ansi_esc        db 0x1B, "["
    ansi_m          db "m", 0
    ansi_reset      db 0x1B, "[0m", 0
    colon           db ": ", 0
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
    push r12
    push r13
    
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
    mov rcx, 4
    rep movsb
    mov dword [bar_char_len], 3
    
    mov rsi, default_bar_color
    mov rdi, bar_color
    mov rcx, 3
    rep movsb
    
    mov rsi, default_bg_color
    mov rdi, bg_color
    mov rcx, 3
    rep movsb
    
    ; Procesar configuración
    mov r12, buffer
    add r12, rax
    mov byte [r12], 0  ; Null-terminate
    
    ; Buscar caracter_barra
    mov rsi, buffer
    mov rdi, .str_caracter
    call buscar_substring
    test rax, rax
    jz .check_color_barra
    
    add rax, .str_caracter_len
    mov rsi, rax
    mov rdi, bar_char
    call extraer_valor
    call strlen
    mov [bar_char_len], eax
    
.check_color_barra:
    mov rsi, buffer
    mov rdi, .str_color_barra
    call buscar_substring
    test rax, rax
    jz .check_color_fondo
    
    add rax, .str_color_barra_len
    mov rsi, rax
    mov rdi, bar_color
    call extraer_valor_num
    
.check_color_fondo:
    mov rsi, buffer
    mov rdi, .str_color_fondo
    call buscar_substring
    test rax, rax
    jz .close_file
    
    add rax, .str_color_fondo_len
    mov rsi, rax
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
    pop r13
    pop r12
    pop rbp
    ret

.str_caracter      db "caracter_barra:", 0
.str_caracter_len  equ $ - .str_caracter - 1
.str_color_barra   db "color_barra:", 0
.str_color_barra_len equ $ - .str_color_barra - 1
.str_color_fondo   db "color_fondo:", 0
.str_color_fondo_len equ $ - .str_color_fondo - 1

; Leer inventario desde inventario.txt
leer_inventario:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    
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
    mov r12, buffer
    mov r13, rax
    mov r14, items
    xor rbx, rbx
    
.process_line:
    cmp r13, 0
    jle .close_file
    
    ; Saltar espacios y newlines
    mov al, [r12]
    cmp al, 10
    je .next_char
    cmp al, 13
    je .next_char
    cmp al, ' '
    je .next_char
    cmp al, 0
    je .close_file
    
    ; Copiar nombre
    mov rdi, r14
    add rdi, item.name
    xor rcx, rcx
    
.copy_name:
    mov al, [r12]
    cmp al, ':'
    je .found_colon
    cmp al, 10
    je .invalid_line
    cmp al, 0
    je .close_file
    cmp rcx, 31
    jge .next_char_name
    
    mov [rdi], al
    inc rdi
    inc rcx
    
.next_char_name:
    inc r12
    dec r13
    jnz .copy_name
    jmp .close_file
    
.found_colon:
    mov byte [rdi], 0
    inc r12
    dec r13
    jz .close_file
    
    ; Convertir número
    xor rax, rax
    xor rcx, rcx
    
.convert_number:
    mov cl, [r12]
    cmp cl, 10
    je .save_quantity
    cmp cl, 13
    je .save_quantity
    cmp cl, 0
    je .save_quantity
    cmp cl, '0'
    jb .invalid_line
    cmp cl, '9'
    ja .invalid_line
    
    sub cl, '0'
    imul rax, 10
    add rax, rcx
    inc r12
    dec r13
    jnz .convert_number
    
.save_quantity:
    mov [r14 + item.quantity], eax
    inc dword [item_count]
    add r14, item_size
    inc rbx
    cmp rbx, 10
    jge .close_file
    jmp .next_line
    
.invalid_line:
    ; Saltar hasta el siguiente newline
    mov al, [r12]
    cmp al, 10
    je .next_line
    cmp al, 0
    je .close_file
    inc r12
    dec r13
    jnz .invalid_line
    
.next_line:
    ; Saltar hasta el siguiente newline o fin
    cmp r13, 0
    jle .close_file
    mov al, [r12]
    cmp al, 10
    je .next_char
    cmp al, 0
    je .close_file
    inc r12
    dec r13
    jmp .next_line
    
.next_char:
    inc r12
    dec r13
    jmp .process_line
    
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
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; Ordenar inventario alfabéticamente (Bubble Sort)
ordenar_inventario:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15
    
    mov ecx, [item_count]
    cmp ecx, 1
    jle .exit
    
    dec ecx
    mov r12, items
    
.outer_loop:
    mov r13, r12
    mov r14d, ecx
    
.inner_loop:
    mov rsi, r13
    mov rdi, r13
    add rdi, item_size
    
    ; Comparar nombres
    lea rax, [rsi + item.name]
    lea rbx, [rdi + item.name]
    call comparar_strings
    jle .no_swap
    
    ; Intercambiar items
    call intercambiar_items
    
.no_swap:
    add r13, item_size
    dec r14d
    jnz .inner_loop
    
    add r12, item_size
    loop .outer_loop
    
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; Dibujar gráfico de barras
dibujar_grafico:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    
    mov r12, items
    mov r13d, [item_count]
    test r13d, r13d
    jz .exit
    
.draw_item:
    cmp byte [r12 + item.name], 0
    je .next_item
    
    ; Nombre
    lea rsi, [r12 + item.name]
    call print_string
    
    ; Separador
    mov rsi, colon
    call print_string
    
    ; Aplicar color de fondo
    mov rsi, ansi_esc
    call print_string
    mov rsi, bg_color
    call print_string
    mov rsi, ansi_m
    call print_string
    
    ; Aplicar color de barra
    mov rsi, ansi_esc
    call print_string
    mov rsi, bar_color
    call print_string
    mov rsi, ansi_m
    call print_string
    
    ; Dibujar barras
    mov ecx, [r12 + item.quantity]
    test ecx, ecx
    jz .no_bars
    
    mov r14, rcx
.draw_bars:
    mov rsi, bar_char
    mov edx, [bar_char_len]
    call print_string_len
    dec r14
    jnz .draw_bars
    
.no_bars:
    ; Resetear color
    mov rsi, ansi_reset
    call print_string
    
    ; Espacio y cantidad
    mov rsi, space
    call print_string
    
    mov eax, [r12 + item.quantity]
    mov rdi, temp_num
    call int_to_string
    mov rsi, temp_num
    call print_string
    
    ; Nueva línea
    mov rsi, newline
    call print_string
    
.next_item:
    add r12, item_size
    dec r13d
    jnz .draw_item
    
.exit:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ===== FUNCIONES AUXILIARES =====

; Buscar substring
buscar_substring:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    
    mov r12, rdi    ; substring a buscar
    mov r13, rsi    ; buffer donde buscar
    xor r14, r14    ; posición actual
    
    ; Calcular longitud del substring
    mov rdi, r12
    call strlen
    mov rcx, rax    ; longitud del substring
    
.search_loop:
    mov al, [r13 + r14]
    test al, al
    jz .not_found
    
    ; Comparar desde esta posición
    mov rdi, r12
    lea rsi, [r13 + r14]
    push rcx
    call strncmp
    pop rcx
    test rax, rax
    jz .found
    
    inc r14
    jmp .search_loop
    
.found:
    mov rax, r14    ; devolver posición
    jmp .exit
    
.not_found:
    xor rax, rax
    
.exit:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; Comparar n caracteres
strncmp:
    push rbp
    mov rbp, rsp
    xor rax, rax
    
.compare:
    dec rcx
    js .equal
    mov al, [rdi]
    mov dl, [rsi]
    cmp al, dl
    jne .different
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .compare
    
.different:
    sub al, dl
    movsx rax, al
    jmp .exit
    
.equal:
    xor rax, rax
    
.exit:
    pop rbp
    ret

; Extraer valor (texto)
extraer_valor:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    mov r12, rsi    ; posición inicial
    mov r13, rdi    ; buffer destino
    xor rcx, rcx
    
.loop:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, 10
    je .done
    cmp al, 13
    je .done
    cmp al, ' '
    je .skip
    cmp al, ';'
    je .done
    
    mov [r13], al
    inc r13
    inc rcx
    
.skip:
    inc r12
    jmp .loop
    
.done:
    mov byte [r13], 0
    mov rax, rcx    ; longitud extraída
    pop r13
    pop r12
    pop rbp
    ret

; Extraer valor numérico
extraer_valor_num:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    mov r12, rsi
    mov r13, rdi
    xor rcx, rcx
    
.loop:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, 10
    je .done
    cmp al, 13
    je .done
    cmp al, '0'
    jb .skip
    cmp al, '9'
    ja .skip
    
    mov [r13], al
    inc r13
    inc rcx
    
.skip:
    inc r12
    jmp .loop
    
.done:
    mov byte [r13], 0
    mov rax, rcx
    pop r13
    pop r12
    pop rbp
    ret

; Comparar strings
comparar_strings:
    push rbp
    mov rbp, rsp
    
.compare:
    mov al, [rax]
    mov dl, [rbx]
    cmp al, dl
    jne .different
    test al, al
    jz .equal
    inc rax
    inc rbx
    jmp .compare
    
.different:
    sub al, dl
    movsx rax, al
    jmp .exit
    
.equal:
    xor rax, rax
    
.exit:
    pop rbp
    ret

; Intercambiar items
intercambiar_items:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    
    mov r12, rsi
    mov r13, rdi
    mov r14, item_size
    
.swap_loop:
    mov al, [r12]
    mov dl, [r13]
    mov [r12], dl
    mov [r13], al
    inc r12
    inc r13
    dec r14
    jnz .swap_loop
    
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; Convertir int to string
int_to_string:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    
    mov rbx, rdi
    mov r12, 10
    xor rcx, rcx
    
    test rax, rax
    jnz .convert
    
    ; Caso cero
    mov byte [rbx], '0'
    mov byte [rbx + 1], 0
    mov rax, 1
    jmp .exit
    
.convert:
    xor rdx, rdx
    div r12
    add dl, '0'
    push rdx
    inc rcx
    test rax, rax
    jnz .convert
    
    mov rax, rcx
    
.pop_digits:
    pop rdx
    mov [rbx], dl
    inc rbx
    loop .pop_digits
    
    mov byte [rbx], 0
    
.exit:
    pop r12
    pop rbx
    pop rbp
    ret

; Imprimir string
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

; Imprimir string con longitud específica
print_string_len:
    push rbp
    mov rbp, rsp
    mov rax, 1
    mov rdi, 1
    syscall
    pop rbp
    ret

; Longitud de string
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

; Salida con error
_exit_error:
    mov rax, 60
    mov rdi, 1
    syscall