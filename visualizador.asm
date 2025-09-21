; visualizador.asm
; Programa en ensamblador x64 puro para Linux
; Compilar: nasm -f elf64 visualizador.asm -o visualizador.o
; Enlazar: ld visualizador.o -o visualizador

section .data
    inventario_file db "inventario.txt", 0
    config_file     db "config.ini", 0
    
    error_open      db "Error: No se pudo abrir el archivo", 10
    error_read      db "Error: No se pudo leer el archivo", 10
    
    default_char    db 0xE2, 0x96, 0xA0, 0  ; ■
    default_bar_color db "92", 0
    default_bg_color  db "40", 0
    
    bar_char        times 4 db 0
    bar_char_len    db 0
    bar_color       times 3 db 0
    bg_color        times 3 db 0
    
    buffer          times 1024 db 0
    
    struc item
        .name:      resb 32
        .quantity:  resd 1
    endstruc
    
    items           times 10 * item_size db 0
    item_count      dd 0
    
    ansi_esc        db 0x1B, "["
    ansi_m          db "m"
    ansi_reset      db 0x1B, "[0m"
    colon_str       db ": "
    space_str       db " "
    newline_str     db 10

section .bss
    fd_inventario   resd 1
    fd_config       resd 1
    temp_num        resb 12

section .text
    global _start

_start:
    and rsp, -16
    
    call leer_configuracion
    call leer_inventario
    call ordenar_inventario
    call dibujar_grafico
    
    mov rax, 60
    xor rdi, rdi
    syscall

leer_configuracion:
    push rbp
    mov rbp, rsp
    
    ; Abrir config.ini
    mov rax, 2
    mov rdi, config_file
    xor rsi, rsi
    syscall
    test rax, rax
    jl .error
    mov [fd_config], eax
    
    ; Leer archivo
    mov eax, 0
    mov edi, [fd_config]
    mov rsi, buffer
    mov rdx, 1024
    syscall
    test rax, rax
    jl .error
    
    ; Valores por defecto
    mov rsi, default_char
    mov rdi, bar_char
    mov rcx, 4
    rep movsb
    mov byte [bar_char_len], 3
    
    mov rsi, default_bar_color
    mov rdi, bar_color
    call copiar_string
    
    mov rsi, default_bg_color
    mov rdi, bg_color
    call copiar_string
    
    ; Cerrar archivo
    mov eax, 3
    mov edi, [fd_config]
    syscall
    
    xor rax, rax
    jmp .exit
    
.error:
    mov rsi, error_open
    call imprimir_string
    mov rax, 1
    
.exit:
    pop rbp
    ret

leer_inventario:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    ; Abrir inventario.txt
    mov rax, 2
    mov rdi, inventario_file
    xor rsi, rsi
    syscall
    test rax, rax
    jl .error
    mov [fd_inventario], eax
    
    ; Leer archivo
    mov eax, 0
    mov edi, [fd_inventario]
    mov rsi, buffer
    mov rdx, 1024
    syscall
    test rax, rax
    jl .error
    
    ; Procesar contenido
    mov rsi, buffer
    mov rdi, items
    mov r12, rax
    xor r13, r13
    
.procesar_linea:
    test r12, r12
    jz .cerrar_archivo
    
    ; Saltar espacios y newlines
    mov al, [rsi]
    cmp al, 10
    je .siguiente
    cmp al, ' '
    je .siguiente
    cmp al, 0
    je .cerrar_archivo
    
    ; Verificar límite
    cmp r13, 10
    jge .cerrar_archivo
    
    ; Copiar nombre
    mov rcx, rdi
    add rcx, item.name
    xor rdx, rdx
    
.copiar_nombre:
    mov al, [rsi]
    cmp al, ':'
    je .encontrar_cantidad
    cmp al, 10
    je .encontrar_cantidad
    cmp al, 0
    je .encontrar_cantidad
    cmp rdx, 31
    jge .siguiente_caracter
    
    mov [rcx], al
    inc rcx
    inc rdx
    
.siguiente_caracter:
    inc rsi
    dec r12
    jnz .copiar_nombre
    
.encontrar_cantidad:
    mov byte [rcx], 0
    cmp byte [rsi], ':'
    jne .siguiente
    inc rsi
    dec r12
    
    ; Convertir número
    xor rax, rax
    xor rbx, rbx
    
.convertir_numero:
    test r12, r12
    jz .guardar_cantidad
    mov bl, [rsi]
    cmp bl, 10
    je .guardar_cantidad
    cmp bl, 0
    je .guardar_cantidad
    cmp bl, '0'
    jb .siguiente
    cmp bl, '9'
    ja .siguiente
    
    sub bl, '0'
    imul rax, 10
    add rax, rbx
    inc rsi
    dec r12
    jmp .convertir_numero
    
.guardar_cantidad:
    mov [rdi + item.quantity], eax
    inc dword [item_count]
    add rdi, item_size
    inc r13
    
.siguiente:
    test r12, r12
    jz .cerrar_archivo
    cmp byte [rsi], 10
    jne .avanzar
    inc rsi
    dec r12
    jmp .procesar_linea
    
.avanzar:
    inc rsi
    dec r12
    jmp .procesar_linea
    
.cerrar_archivo:
    mov eax, 3
    mov edi, [fd_inventario]
    syscall
    xor rax, rax
    jmp .exit
    
.error:
    mov rsi, error_open
    call imprimir_string
    mov rax, 1
    
.exit:
    pop r13
    pop r12
    pop rbp
    ret

ordenar_inventario:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    mov ecx, [item_count]
    cmp ecx, 1
    jle .exit
    
    dec ecx
    mov r12, items
    
.bucle_externo:
    mov r13, r12
    mov edx, [item_count]
    dec edx
    
.bucle_interno:
    mov rsi, r13
    mov rdi, r13
    add rdi, item_size
    
    mov rax, rsi
    add rax, item.name
    mov rbx, rdi
    add rbx, item.name
    
    call comparar_strings
    jle .no_intercambiar
    
    call intercambiar_items
    
.no_intercambiar:
    mov r13, rdi
    dec edx
    jnz .bucle_interno
    
    dec ecx
    jnz .bucle_externo
    
.exit:
    pop r13
    pop r12
    pop rbp
    ret

dibujar_grafico:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    
    mov r12, items
    mov r13d, [item_count]
    test r13d, r13d
    jz .exit
    
.dibujar_item:
    cmp byte [r12 + item.name], 0
    je .siguiente_item
    
    ; Nombre
    mov rsi, r12
    add rsi, item.name
    call imprimir_string
    
    ; Separador
    mov rsi, colon_str
    mov rdx, 2
    call imprimir_buffer
    
    ; Color de fondo
    mov rsi, ansi_esc
    mov rdx, 2
    call imprimir_buffer
    
    mov rsi, bg_color
    call imprimir_string
    
    mov rsi, ansi_m
    mov rdx, 1
    call imprimir_buffer
    
    ; Color de barra
    mov rsi, ansi_esc
    mov rdx, 2
    call imprimir_buffer
    
    mov rsi, bar_color
    call imprimir_string
    
    mov rsi, ansi_m
    mov rdx, 1
    call imprimir_buffer
    
    ; Barras
    mov ecx, [r12 + item.quantity]
    test ecx, ecx
    jz .fin_barras
    
.dibujar_barras:
    push rcx
    mov rsi, bar_char
    movzx rdx, byte [bar_char_len]
    call imprimir_buffer
    pop rcx
    loop .dibujar_barras
    
.fin_barras:
    ; Reset color
    mov rsi, ansi_reset
    mov rdx, 4
    call imprimir_buffer
    
    ; Espacio
    mov rsi, space_str
    mov rdx, 1
    call imprimir_buffer
    
    ; Cantidad
    mov eax, [r12 + item.quantity]
    mov rdi, temp_num
    call int_a_string
    mov rsi, temp_num
    call imprimir_string
    
    ; Nueva línea
    mov rsi, newline_str
    mov rdx, 1
    call imprimir_buffer
    
.siguiente_item:
    add r12, item_size
    dec r13d
    jnz .dibujar_item
    
.exit:
    pop r13
    pop r12
    pop rbp
    ret

; ===== FUNCIONES AUXILIARES =====

copiar_string:
.copiar:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .hecho
    inc rsi
    inc rdi
    jmp .copiar
.hecho:
    ret

comparar_strings:
.comparar:
    mov al, [rax]
    mov dl, [rbx]
    test al, al
    jz .verificar_segundo
    test dl, dl
    jz .mayor
    cmp al, dl
    jne .diferencia
    inc rax
    inc rbx
    jmp .comparar

.verificar_segundo:
    test dl, dl
    jz .igual
    jmp .menor

.diferencia:
    cmp al, dl
    jl .menor

.mayor:
    mov eax, 1
    ret

.menor:
    mov eax, -1
    ret

.igual:
    xor eax, eax
    ret

intercambiar_items:
    push rcx
    mov rcx, item_size
.intercambiar:
    mov al, [rsi]
    mov dl, [rdi]
    mov [rsi], dl
    mov [rdi], al
    inc rsi
    inc rdi
    loop .intercambiar
    pop rcx
    ret

int_a_string:
    push rbx
    mov rbx, rdi
    test eax, eax
    jnz .convertir
    
    mov byte [rbx], '0'
    mov byte [rbx + 1], 0
    mov eax, 1
    jmp .salir
    
.convertir:
    mov edi, 10
    xor ecx, ecx
    
.bucle_convertir:
    xor edx, edx
    div edi
    add dl, '0'
    push rdx
    inc ecx
    test eax, eax
    jnz .bucle_convertir
    
    mov eax, ecx
    
.extraer_digitos:
    pop rdx
    mov [rbx], dl
    inc rbx
    loop .extraer_digitos
    
    mov byte [rbx], 0
    
.salir:
    pop rbx
    ret

imprimir_string:
    call strlen
    mov rdx, rax
    jmp imprimir_buffer

imprimir_buffer:
    mov rax, 1
    mov rdi, 1
    syscall
    ret

strlen:
    xor rcx, rcx
.bucle:
    cmp byte [rsi + rcx], 0
    je .hecho
    inc rcx
    jmp .bucle
.hecho:
    mov rax, rcx
    ret