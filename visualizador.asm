; visualizador.asm
; Programa en ensamblador x64 puro para Linux
; Compilar: nasm -f elf64 visualizador.asm -o visualizador.o
; Enlazar: ld visualizador.o -o visualizador

section .data
    ; Archivos
    inventario_file db "inventario.txt", 0
    config_file     db "config.ini", 0
    
    ; Mensajes de error
    error_open      db "Error: No se pudo abrir el archivo", 10, 0
    error_read      db "Error: No se pudo leer el archivo", 10, 0
    
    ; Códigos ANSI por defecto
    default_char    db 0xE2, 0x96, 0xA0, 0  ; ■
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
    colon_str       db ": ", 0
    space_str       db " ", 0
    newline_str     db 10, 0

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
    
    ; Leer inventario
    call leer_inventario
    
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
    call copy_string
    
    mov rsi, default_bg_color
    mov rdi, bg_color
    call copy_string
    
    ; Cerrar archivo
    mov rax, 3
    mov rdi, [fd_config]
    syscall
    
    xor rax, rax
    jmp .exit
    
.error:
    mov rsi, error_open
    call print_string
    mov rax, 1
    
.exit:
    pop rbp
    ret

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
    cmp r12, 0
    jle .save_quantity
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
    jmp .convert_number
    
.save_quantity:
    mov [rdi + item.quantity], eax
    inc dword [item_count]
    add rdi, item_size
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
    jmp .process_line
    
.skip_char:
    inc rsi
    dec r12
    jmp .process_line
    
.close_file:
    mov rax, 3
    mov rdi, [fd_inventario]
    syscall
    xor rax, rax
    jmp .exit
    
.error:
    mov rsi, error_open
    call print_string
    mov rax, 1
    
.exit:
    pop r13
    pop r12
    pop rbp
    ret

; Ordenar inventario alfabéticamente
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
    mov r13, r12
    mov r14d, [item_count]
    dec r14d
    
.inner_loop:
    mov rsi, r13
    mov rdi, r13
    add rdi, item_size
    
    mov rax, rsi
    add rax, item.name
    mov rbx, rdi
    add rbx, item.name
    
    call comparar_strings
    jle .no_swap
    
    call intercambiar_items
    
.no_swap:
    mov r13, rdi
    dec r14d
    jnz .inner_loop
    
    dec ecx
    jnz .outer_loop
    
.exit:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; Dibujar gráfico de barras - CORREGIDO
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
    
    ; Separador
    mov rsi, colon_str
    call print_string
    
    ; Secuencia ANSI: ESC[<bg_color>mESC[<bar_color>m
    mov rax, 1
    mov rdi, 1
    
    ; ESC[
    mov rsi, ansi_esc
    mov rdx, 2
    syscall
    
    ; Color de fondo
    mov rsi, bg_color
    call strlen
    mov rdx, rax
    syscall
    
    ; m
    mov rsi, ansi_m
    mov rdx, 1
    syscall
    
    ; ESC[
    mov rsi, ansi_esc
    mov rdx, 2
    syscall
    
    ; Color de barra
    mov rsi, bar_color
    call strlen
    mov rdx, rax
    syscall
    
    ; m
    mov rsi, ansi_m
    mov rdx, 1
    syscall
    
    ; Barras
    mov ecx, [r12 + item.quantity]
    test ecx, ecx
    jz .no_bars
    
.draw_bars:
    push rcx
    mov rax, 1
    mov rdi, 1
    mov rsi, bar_char
    movzx rdx, byte [bar_char_len]
    syscall
    pop rcx
    dec ecx
    jnz .draw_bars
    
.no_bars:
    ; Reset color
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_reset
    mov rdx, 4
    syscall
    
    ; Espacio y cantidad
    mov rsi, space_str
    call print_string
    
    ; Convertir cantidad a string
    mov eax, [r12 + item.quantity]
    mov rdi, temp_num
    call int_to_string
    mov rsi, temp_num
    call print_string
    
    ; Nueva línea
    mov rsi, newline_str
    call print_string
    
.next_item:
    add r12, item_size
    dec r13d
    jnz .draw_item
    
.exit:
    pop r13
    pop r12
    pop rbp
    ret

; ===== FUNCIONES AUXILIARES =====

; Copiar string
copy_string:
    push rbp
    mov rbp, rsp
.copy_loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rsi
    inc rdi
    jmp .copy_loop
.done:
    pop rbp
    ret

; Comparar strings
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

; Intercambiar items
intercambiar_items:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    mov r12, rsi
    mov r13, rdi
    mov rcx, item_size
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

; Convertir int to string
int_to_string:
    push rbp
    mov rbp, rsp
    push rbx
    mov rbx, rdi
    test eax, eax
    jnz .convert
    mov byte [rbx], '0'
    mov byte [rbx + 1], 0
    mov eax, 1
    jmp .exit
.convert:
    mov edi, 10
    xor ecx, ecx
.convert_loop:
    xor edx, edx
    div edi
    add dl, '0'
    push rdx
    inc ecx
    test eax, eax
    jnz .convert_loop
    mov eax, ecx
.pop_digits:
    pop rdx
    mov [rbx], dl
    inc rbx
    loop .pop_digits
    mov byte [rbx], 0
.exit:
    pop rbx
    pop rbp
    ret

; Imprimir string - CORREGIDA
print_string:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    push rdx
    
    mov rdi, rsi
    call strlen
    test rax, rax
    jz .done
    
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    pop rdx
    pop rdi
    pop rsi
    syscall
    jmp .exit
    
.done:
    pop rdx
    pop rdi
    pop rsi
.exit:
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