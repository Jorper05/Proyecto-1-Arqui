; visualizador.asm
; Compilar: nasm -f elf64 -o visualizador.o visualizador.asm
; Enlazar: ld -o visualizador visualizador.o

section .data
    ; --- Nombres de archivos ---
    inventario_file db "inventario.txt", 0
    config_file     db "config.ini", 0
    
    ; --- Mensajes de error ---
    error_open      db "Error: No se pudo abrir el archivo", 0xa, 0
    error_open_len  equ $ - error_open
    
    error_read      db "Error: No se pudo leer el archivo", 0xa, 0
    error_read_len  equ $ - error_read
    
    error_config    db "Error: Formato de config.ini inválido", 0xa, 0
    error_config_len equ $ - error_config
    
    ; --- Códigos ANSI por defecto ---
    default_char    db 0xe2, 0x96, 0xa0  ; Carácter Unicode ■ (bloque sólido)
    default_char_len equ 3
    
    default_bar_color  db "92"           ; Verde brillante por defecto
    default_bg_color   db "40"           ; Fondo negro por defecto
    
    ; --- Variables para configuración ---
    bar_char        times 4 db 0         ; Carácter para las barras
    bar_char_len    db 0                 ; Longitud del carácter
    bar_color       times 3 db 0         ; Código color barras
    bg_color        times 3 db 0         ; Código color fondo
    
    ; --- Buffer para lectura de archivos ---
    buffer          times 1024 db 0
    buffer_len      equ $ - buffer
    
    ; --- Estructura para items del inventario ---
    ; Cada item: nombre (32 bytes) : cantidad (4 bytes)
    struc inventario_item
        .name:      resb 32
        .quantity:  resd 1
    endstruc
    
    ; --- Array para almacenar items ---
    items           times 10 * inventario_item_size db 0
    item_count      dd 0
    
    ; --- Códigos ANSI ---
    ansi_esc        db 0x1b, "["         ; Secuencia de escape ANSI
    ansi_esc_len    equ $ - ansi_esc
    
    ansi_m          db "m"               ; Final de secuencia ANSI
    ansi_reset      db 0x1b, "[0m"       ; Resetear colores
    ansi_reset_len  equ $ - ansi_reset
    
    colon           db ": "              ; Separador
    colon_len       equ $ - colon
    
    space           db " "               ; Espacio
    newline         db 0xa               ; Nueva línea

section .bss
    fd_inventario   resd 1               ; File descriptor inventario
    fd_config       resd 1               ; File descriptor configuración
    temp_num        resb 12              ; Buffer para conversión numérica

section .text
    global _start

; PROGRAMA PRINCIPAL
_start:
    ; Paso 1: Leer y procesar config.ini
    call leer_configuracion
    
    ; Paso 2: Leer y procesar inventario.txt
    call leer_inventario
    
    ; Paso 3: Ordenar los datos alfabéticamente
    call ordenar_inventario
    
    ; Paso 4: Dibujar el gráfico de barras
    call dibujar_grafico
    
    ; Salir del programa
    mov rax, 60             ; sys_exit
    mov rdi, 0              ; código de salida 0
    syscall

; LEER CONFIGURACIÓN

leer_configuracion:
    ; Abrir archivo config.ini
    mov rax, 2              ; sys_open
    mov rdi, config_file
    mov rsi, 0              ; O_RDONLY
    mov rdx, 0
    syscall
    
    cmp rax, 0
    jl .error_open
    mov [fd_config], rax
    
    ; Leer contenido del archivo
    mov rax, 0              ; sys_read
    mov rdi, [fd_config]
    mov rsi, buffer
    mov rdx, buffer_len
    syscall
    
    cmp rax, 0
    jl .error_read
    
    ; Procesar configuración
    mov rsi, buffer         ; Puntero al buffer
    mov rcx, rax            ; Longitud leída
    
.procesar_linea:
    ; Buscar 'caracter_barra:'
    mov rdi, .caracter_barra_str
    mov rdx, .caracter_barra_len
    call buscar_substring
    test rax, rax
    jz .procesar_color_barra
    
    ; Extraer carácter de barra
    add rsi, .caracter_barra_len
    mov rdi, bar_char
    call extraer_valor
    mov [bar_char_len], al
    jmp .siguiente_linea

.procesar_color_barra:
    ; Buscar 'color_barra:'
    mov rdi, .color_barra_str
    mov rdx, .color_barra_len
    call buscar_substring
    test rax, rax
    jz .procesar_color_fondo
    
    ; Extraer color de barra
    add rsi, .color_barra_len
    mov rdi, bar_color
    call extraer_valor_num
    jmp .siguiente_linea

.procesar_color_fondo:
    ; Buscar 'color_fondo:'
    mov rdi, .color_fondo_str
    mov rdx, .color_fondo_len
    call buscar_substring
    test rax, rax
    jz .siguiente_linea
    
    ; Extraer color de fondo
    add rsi, .color_fondo_len
    mov rdi, bg_color
    call extraer_valor_num

.siguiente_linea:
    ; Avanzar a siguiente línea
    mov al, [rsi]
    test al, al
    jz .cerrar_archivo
    cmp al, 0xa
    jne .avanzar
    inc rsi
    jmp .procesar_linea

.avanzar:
    inc rsi
    jmp .siguiente_linea

.cerrar_archivo:
    ; Cerrar archivo de configuración
    mov rax, 3              ; sys_close
    mov rdi, [fd_config]
    syscall
    ret

.error_open:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_open
    mov rdx, error_open_len
    syscall
    jmp _exit_error

.error_read:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_read
    mov rdx, error_read_len
    syscall
    jmp _exit_error

.caracter_barra_str db "caracter_barra:"
.caracter_barra_len equ $ - .caracter_barra_str

.color_barra_str db "color_barra:"
.color_barra_len equ $ - .color_barra_str

.color_fondo_str db "color_fondo:"
.color_fondo_len equ $ - .color_fondo_str

; LEER INVENTARIO
leer_inventario:
    ; Abrir archivo inventario.txt
    mov rax, 2              ; sys_open
    mov rdi, inventario_file
    mov rsi, 0              ; O_RDONLY
    mov rdx, 0
    syscall
    
    cmp rax, 0
    jl .error_open
    mov [fd_inventario], rax
    
    ; Leer contenido del archivo
    mov rax, 0              ; sys_read
    mov rdi, [fd_inventario]
    mov rsi, buffer
    mov rdx, buffer_len
    syscall
    
    cmp rax, 0
    jl .error_read
    
    ; Procesar líneas del inventario
    mov rsi, buffer
    mov rdi, items
    mov rcx, rax

.procesar_linea:
    ; Saltar espacios y newlines
    cmp byte [rsi], 0xa
    je .avanzar
    cmp byte [rsi], ' '
    je .avanzar
    cmp byte [rsi], 0
    je .fin_procesamiento
    
    ; Copiar nombre del item
    mov rdx, rdi
    add rdx, inventario_item.name
    
.copiar_nombre:
    mov al, [rsi]
    cmp al, ':'
    je .encontrar_cantidad
    cmp al, 0xa
    je .encontrar_cantidad
    cmp al, 0
    je .encontrar_cantidad
    
    mov [rdx], al
    inc rsi
    inc rdx
    jmp .copiar_nombre

.encontrar_cantidad:
    ; Buscar ':' y extraer cantidad
    cmp byte [rsi], ':'
    jne .avanzar
    inc rsi
    
    ; Convertir número
    xor rax, rax
    xor rbx, rbx
    
.convertir_numero:
    mov bl, [rsi]
    cmp bl, 0xa
    je .guardar_cantidad
    cmp bl, 0
    je .guardar_cantidad
    cmp bl, '0'
    jb .avanzar
    cmp bl, '9'
    ja .avanzar
    
    sub bl, '0'
    imul rax, 10
    add rax, rbx
    inc rsi
    jmp .convertir_numero

.guardar_cantidad:
    mov [rdi + inventario_item.quantity], eax
    inc dword [item_count]
    add rdi, inventario_item_size

.avanzar:
    inc rsi
    dec rcx
    jnz .procesar_linea

.fin_procesamiento:
    ; Cerrar archivo de inventario
    mov rax, 3              ; sys_close
    mov rdi, [fd_inventario]
    syscall
    ret

.error_open:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_open
    mov rdx, error_open_len
    syscall
    jmp _exit_error

.error_read:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_read
    mov rdx, error_read_len
    syscall
    jmp _exit_error

    ; ORDENAR INVENTARIO (Bubble Sort)
; =============================================================================
ordenar_inventario:
    mov ecx, [item_count]
    dec ecx
    jle .fin_ordenamiento
    
.outer_loop:
    mov rsi, items
    mov rdi, items
    add rdi, inventario_item_size
    mov edx, [item_count]
    dec edx
    
.inner_loop:
    ; Comparar nombres
    mov rax, rsi
    add rax, inventario_item.name
    mov rbx, rdi
    add rbx, inventario_item.name
    
    call comparar_strings
    jbe .no_intercambiar
    
    ; Intercambiar items
    call intercambiar_items

.no_intercambiar:
    add rsi, inventario_item_size
    add rdi, inventario_item_size
    dec edx
    jnz .inner_loop
    
    dec ecx
    jnz .outer_loop

.fin_ordenamiento:
    ret


; DIBUJAR GRÁFICO

dibujar_grafico:
    mov rsi, items
    mov ecx, [item_count]
    
.dibujar_item:
    test ecx, ecx
    jz .fin_dibujo
    
    ; Imprimir nombre del item
    push rsi
    push rcx
    
    mov rax, 1              ; sys_write
    mov rdi, 1
    lea rsi, [rsi + inventario_item.name]
    call strlen
    mov rdx, rax
    syscall
    
    ; Imprimir ": "
    mov rax, 1
    mov rdi, 1
    mov rsi, colon
    mov rdx, colon_len
    syscall
    
    ; Aplicar colores ANSI
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_esc
    mov rdx, ansi_esc_len
    syscall
    
    ; Color de fondo
    mov rax, 1
    mov rdi, 1
    mov rsi, bg_color
    call strlen
    mov rdx, rax
    syscall
    
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_m
    mov rdx, 1
    syscall
    
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_esc
    mov rdx, ansi_esc_len
    syscall
    
    ; Color de barra
    mov rax, 1
    mov rdi, 1
    mov rsi, bar_color
    call strlen
    mov rdx, rax
    syscall
    
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_m
    mov rdx, 1
    syscall
    
    ; Dibujar barras según cantidad
    pop rcx
    pop rsi
    push rsi
    push rcx
    
    mov eax, [rsi + inventario_item.quantity]
    mov rdi, bar_char
    movzx rdx, byte [bar_char_len]
    
.dibujar_barras:
    test eax, eax
    jz .fin_barras
    
    push rax
    mov rax, 1
    mov rsi, rdi
    syscall
    pop rax
    dec eax
    jmp .dibujar_barras

.fin_barras:
    ; Resetear colores
    mov rax, 1
    mov rdi, 1
    mov rsi, ansi_reset
    mov rdx, ansi_reset_len
    syscall
    
    ; Imprimir espacio y cantidad numérica
    mov rax, 1
    mov rdi, 1
    mov rsi, space
    mov rdx, 1
    syscall
    
    ; Convertir cantidad a string
    pop rcx
    pop rsi
    push rsi
    push rcx
    
    mov eax, [rsi + inventario_item.quantity]
    mov rdi, temp_num
    call int_to_string
    
    mov rdx, rax            ; longitud del número
    mov rax, 1
    mov rdi, 1
    mov rsi, temp_num
    syscall
    
    ; Nueva línea
    mov rax, 1
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1
    syscall
    
    pop rcx
    pop rsi
    add rsi, inventario_item_size
    dec ecx
    jmp .dibujar_item

.fin_dibujo:
    ret

; FUNCIONES AUXILIARES

; Buscar substring en buffer
buscar_substring:
    push rsi
    push rdi
    push rcx
    push rdx
    
    mov r8, rdi             ; substring a buscar
    mov r9, rdx             ; longitud del substring
    
.buscar_loop:
    mov rdi, r8
    mov rdx, r9
    mov r10, rsi
    
.comparar:
    mov al, [rdi]
    mov bl, [r10]
    cmp al, bl
    jne .no_coincide
    
    inc rdi
    inc r10
    dec rdx
    jnz .comparar
    
    ; Coincidencia encontrada
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    mov rax, 1
    ret

.no_coincide:
    inc rsi
    dec rcx
    jnz .buscar_loop
    
    ; No encontrado
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    xor rax, rax
    ret

;;copy_value:
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
mov r10, rdi
imul r11, rcx, 32
add r10, r11
add r10, rdx
mov [r10], al
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
mov r10, rbx
imul r11, rcx, 8
add r10, r11
add r10, rdx
mov [r10], al
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
mov r10, rdi
add r10, r8
mov al, [r10]
mov r11, rdx
add r11, r8
mov bl, [r11]
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
mov r10, rdi
add r10, r8
mov al, [r10]
mov r11, rdx
add r11, r8
mov bl, [r11]
mov [r10], bl
mov [r11], al
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
mov r10, rdi
add r10, r8
mov al, [r10]
mov r11, rdx
add r11, r8
mov bl, [r11]
mov [r10], bl
mov [r11], al
    inc r8
    cmp r8, 8
    jne .swap_qty

.no_swap:
    inc rsi
    cmp rsi, 3
    jl .inner_loop
dec rcx
jnz .outer_loop
    ret

draw_graph:
    mov rcx, 0
.next_item:
    cmp rcx, 4
    je .done

    mov rsi, nombres
    mov rdi, 1
    mov rax, 1
    mov rbx, rcx
    imul rbx, 32
    add rsi, rbx
    mov rdx, 32
    syscall

    mov rsi, sep
    mov rdx, sep_len
    syscall

    mov rsi, ansi_prefix
    mov rdx, ansi_prefix_len
    syscall

    mov rsi, color_bg
    mov rdx, 2
    syscall

    mov rsi, sep_color
    mov rdx, 1
    syscall

    mov rsi, color_bar
    mov rdx, 2
    syscall

    mov rsi, ansi_suffix
    mov rdx, ansi_suffix_len
    syscall

    mov rbx, cantidades
    mov r8, rcx
    imul r8, 8
    add rbx, r8
    call draw_bar

    mov rsi, reset_color
    mov rdx, reset_color_len
    syscall

    mov rsi, cantidades
    mov rbx, rcx
    imul rbx, 8
    add rsi, rbx
    mov rdx, 8
    syscall

    mov rsi, newline
    mov rdx, 1
    syscall

    inc rcx
    jmp .next_item
.done:
    ret

draw_bar:
    mov al, [rbx]
    sub al, '0'
    mov cl, al
.loop_bar:
    cmp cl, 0
    je .done_bar
    mov rsi, char_bar
    mov rdx, 1
    mov rdi, 1
    mov rax, 1
    syscall
    dec cl
    jmp .loop_bar
.done_bar:
    ret
