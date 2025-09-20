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

    debug_start     db "Iniciando programa...", 0xa, 0
    debug_start_len equ $ - debug_start
    
    debug_config_ok db "Configuración leída OK", 0xa, 0
    debug_config_ok_len equ $ - debug_config_ok
    
    debug_inv_ok    db "Inventario leído OK", 0xa, 0
    debug_inv_ok_len equ $ - debug_inv_ok
    
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
    
    colon           db ":"              ; Separador
    colon_len       equ $ - colon
    
    space           db " "               ; Espacio
    newline         db 0xa               ; Nueva línea

section .bss
    fd_inventario   resd 1               ; File descriptor inventario
    fd_config       resd 1               ; File descriptor configuración
    temp_num        resb 12              ; Buffer para conversión numérica

section .text
    global _start

; PROGRAMA PRINCIPAL - CON STACK ALINEADO
_start:
    
    ; Alinear stack a 16-bytes para evitar segmentation fault
    and rsp, -16

    ; Mensaje de inicio para debug
    mov rax, 1
    mov rdi, 1
    mov rsi, debug_msg
    mov rdx, debug_msg_len
    syscall

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
    push rbp
    mov rbp, rsp
    sub rsp, 32

    ; Abrir archivo config.ini
    mov rax, 2              ; sys_open
    mov rdi, config_file
    mov rsi, 0              ; O_RDONLY
    mov rdx, 0
    syscall
    
    ; Verificar error
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
    
    ; Inicializar valores por defecto
    mov rsi, default_char
    mov rdi, bar_char
    mov rcx, default_char_len
    rep movsb
    mov byte [bar_char_len], default_char_len
    
    mov rsi, default_bar_color
    mov rdi, bar_color
    mov rcx, 2
    rep movsb
    mov byte [bar_color + 2], 0
    
    mov rsi, default_bg_color
    mov rdi, bg_color
    mov rcx, 2
    rep movsb
    mov byte [bg_color + 2], 0


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
    dec rcx
    jmp .siguiente_linea

.cerrar_archivo:
    ; Cerrar archivo de configuración
    mov rax, 3              ; sys_close
    mov rdi, [fd_config]
    syscall
    
    ; Debug: configuración OK
    mov rax, 1
    mov rdi, 1
    mov rsi, debug_config_ok
    mov rdx, debug_config_ok_len
    syscall
    
    mov rsp, rbp
    pop rbp
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
    push rbp
    mov rbp, rsp
    sub rsp, 32             ; Reservar espacio en stack    

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

    ; Verificar límite de items
    mov eax, [item_count]
    cmp eax, 10
    jge .fin_procesamiento
    
    ; Copiar nombre del item
    mov rdx, rdi
    add rdx, inventario_item.name
    mov r8, 0               ; contador de caracteres
    
.copiar_nombre:
    mov al, [rsi]
    cmp al, ':'
    je .encontrar_cantidad
    cmp al, 0xa
    je .encontrar_cantidad
    cmp al, 0
    je .encontrar_cantidad

    ; Verificar límite de nombre
    cmp r8, 31
    jge .avanzar
    
    mov [rdx], al
    inc rsi
    inc rdx
    inc r8
    jmp .copiar_nombre

.encontrar_cantidad:
    ; Asegurar que el nombre termina en null
    mov byte [rdx], 0

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
    ; Debug: inventario OK
    mov rax, 1
    mov rdi, 1
    mov rsi, debug_inv_ok
    mov rdx, debug_inv_ok_len
    syscall
    
    mov rsp, rbp
    pop rbp
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

ordenar_inventario:
    push rbp
    mov rbp, rsp

    mov ecx, [item_count]
    cmp ecx, 1
    dec ecx
    jle .fin_ordenamiento
    dec ecx
    
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
    pop rbp
    ret


; DIBUJAR GRÁFICO

dibujar_grafico:
    push rbp
    mov rbp, rsp

    mov rsi, items
    mov ecx, [item_count]
    test ecx, ecx
    jz .fin_dibujo
    
.dibujar_item:
    ; Verificar que tenemos un item válido
    cmp byte [rsi + inventario_item.name], 0
    je .siguiente_item
    
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
    test eax, eax
    jz .fin_barras

    mov rdi, bar_char
    movzx rdx, byte [bar_char_len]
    
.dibujar_barras:
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
    pop rbp    
    ret

; FUNCIONES AUXILIARES

; Buscar substring en buffer
buscar_substring:
    push rbp
    mov rbp, rsp    

    push rsi
    push rdi
    push rcx
    push rdx
    
    mov r8, rdi             ; substring a buscar
    mov r9, rdx             ; longitud del substring

    pop rbp
    ret
    
.buscar_loop:
    push rbp
    mov rbp, rsp

    mov rdi, r8
    mov rdx, r9
    mov r10, rsi

    pop rbp
    ret
    
.comparar:
    push rbp
    mov rbp, rsp    

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

    pop rbp
    ret
.no_coincide:
    push rbp
    mov rbp, rsp

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
    
    pop rbp
    ret

; Extraer valor de configuración (texto)
extraer_valor:
    push rbp
    mov rbp, rsp
    
    xor rax, rax

    pop rbp
    ret
    
.extraer_loop:
    push rbp
    mov rbp, rsp
    
    mov al, [rsi]
    cmp al, 0xa
    je .fin_extraccion
    cmp al, 0
    je .fin_extraccion
    cmp al, ' '
    je .saltar_espacio
    
    mov [rdi], al
    inc rdi
    inc rax

    pop rbp
    ret

.saltar_espacio:
    push rbp
    mov rbp, rsp

    inc rsi
    jmp .extraer_loop

    pop rbp
    ret

.fin_extraccion:
    push rbp
    mov rbp, rsp

    mov byte [rdi], 0
    ret

    pop rbp
    ret
; Extraer valor numérico de configuración
extraer_valor_num:
    push rbp
    mov rbp, rsp

    xor rax, rax

    pop rbp
    ret
    
.extraer_loop:
    push rbp
    mov rbp, rsp
    mov al, [rsi]
    cmp al, 0xa
    je .fin_extraccion
    cmp al, 0
    je .fin_extraccion
    cmp al, '0'
    jb .saltar
    cmp al, '9'
    ja .saltar
    
    mov [rdi], al
    inc rdi
    pop rbp
    ret

.saltar:
    push rbp
    mov rbp, rsp
    inc rsi
    jmp .extraer_loop
    pop rbp
    ret

.fin_extraccion:
    push rbp
    mov rbp, rsp
    mov byte [rdi], 0
    ret
    pop rbp
    ret

; Comparar dos strings
comparar_strings:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    pop rbp
    ret
    
.comparar_loop:
    push rbp
    mov rbp, rsp
    mov al, [rax]
    mov bl, [rbx]
    test al, al
    jz .fin_comparacion
    test bl, bl
    jz .fin_comparacion
    cmp al, bl
    jne .fin_comparacion
    inc rax
    inc rbx
    jmp .comparar_loop
    pop rbp
    ret

.fin_comparacion:
    push rbp
    mov rbp, rsp
    sub al, bl
    pop rdi
    pop rsi
    ret
    pop rbp
    ret

; Intercambiar dos items del inventario
intercambiar_items:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    push rcx
    
    mov rcx, inventario_item_size
    mov r8, rsi
    mov r9, rdi
    pop rbp
    ret
    
.intercambiar_loop:
    push rbp
    mov rbp, rsp
    mov al, [r8]
    mov bl, [r9]
    mov [r8], bl
    mov [r9], al
    inc r8
    inc r9
    dec rcx
    jnz .intercambiar_loop
    
    pop rcx
    pop rdi
    pop rsi
    ret
    pop rbp
    ret

; Calcular longitud de string
strlen:
    push rbp
    mov rbp, rsp
    push rsi
    xor rcx, rcx
    pop rbp
    ret
.calcular_longitud:
    push rbp
    mov rbp, rsp
    cmp byte [rsi + rcx], 0
    je .fin_calculo
    inc rcx
    jmp .calcular_longitud
    pop rbp
    ret

.fin_calculo:
    push rbp
    mov rbp, rsp
    mov rax, rcx
    pop rsi
    ret
    pop rbp
    ret

; Convertir entero a string
int_to_string:
    push rbp
    mov rbp, rsp
    push rbx
    push rdx
    push rdi
    
    mov rbx, 10
    xor rcx, rcx
    test rax, rax
    jnz .convertir_digitos
    
    ; Caso especial: número 0
    mov byte [rdi], '0'
    mov rax, 1
    jmp .fin_conversion
    pop rbp
    ret
.convertir_digitos:
    push rbp
    mov rbp, rsp
    xor rdx, rdx
    div rbx
    add dl, '0'
    push rdx
    inc rcx
    test rax, rax
    jnz .convertir_digitos
    pop rbp
    ret

.pop_digitos:
    push rbp
    mov rbp, rsp
    pop rax
    mov [rdi], al
    inc rdi
    dec rcx
    jnz .pop_digitos
    pop rbp
    ret

.fin_conversion:
    push rbp
    mov rbp, rsp
    mov byte [rdi], 0
    mov rax, rdi
    pop rdi
    sub rax, rdi
    pop rdx
    pop rbx
    ret
    pop rbp
    ret

; Salida con error
_exit_error:
    mov rax, 60
    mov rdi, 1
    syscall
