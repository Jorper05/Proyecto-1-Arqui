; visualizador.asm
; Programa en ensamblador x64 puro para Linux
; Visualizador de datos con ordenamiento

section .data
    ; Archivos
    inventario_file db "inventario.txt", 0
    config_file     db "config.ini", 0
    
    ; Mensajes de error
    error_open      db "Error: No se pudo abrir el archivo", 10, 0
    error_read      db "Error: No se pudo leer el archivo", 10, 0
    error_config    db "Error: Formato de config.ini inválido", 10, 0
    
    ; Códigos ANSI por defecto
    default_char    db 0xE2, 0x96, 0x88, 0  ; █
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
    
    ; Array de items - usar tamaño explícito en lugar de item_size
    items           times 10 * (32 + 4) db 0
    item_count      dd 0
    
    ; Códigos ANSI
    ansi_esc        db 0x1B, "[", 0
    ansi_m          db "m", 0
    ansi_reset      db 0x1B, "[0m", 0
    colon           db ": ", 0
    space           db " ", 0
    newline         db 10, 0

    ; 🔹 Buffer dinámico para secuencias ANSI
    ansi_code       times 16 db 0

section .bss
    fd_inventario   resq 1
    fd_config       resq 1
    temp_num        resb 12

section .text
    global _start

%define ITEM_SIZE 36

; ================== MAIN ==================
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

; ================== DIBUJAR GRAFICO ==================
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
    
    ; 🔹 Aplicar color de fondo
    mov rsi, bg_color
    call build_ansi
    mov rsi, ansi_code
    call print_string
    
    ; 🔹 Aplicar color de barra
    mov rsi, bar_color
    call build_ansi
    mov rsi, ansi_code
    call print_string
    
    ; Dibujar barras
    mov ecx, [r12 + item.quantity]
    test ecx, ecx
    jz .no_bars
    
    mov r14, rcx
.draw_bars:
    mov rsi, bar_char
    call print_string
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
    add r12, ITEM_SIZE
    dec r13d
    jnz .draw_item
    
.exit:
    pop r14
    pop r13
    pop r12
    pop rbp
    ret

; ================== FUNCIONES AUXILIARES ==================

; ... (todas tus funciones auxiliares actuales: leer_configuracion, leer_inventario,
; ordenar_inventario, strcmp, strcpy, strlen, etc. SE MANTIENEN IGUAL) ...

; 🔹 Nueva función: construir ANSI completo
; Entrada: rsi = puntero al valor ("40" o "92")
; Salida: ansi_code = "\x1B[" + valor + "m"
build_ansi:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi

    mov rdi, ansi_code

    ; Copiar "\x1B["
    mov byte [rdi], 0x1B
    inc rdi
    mov byte [rdi], '['
    inc rdi

.copy_val:
    mov al, [rsi]
    cmp al, 0
    je .copy_m
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .copy_val

.copy_m:
    ; Agregar 'm' y terminador
    mov byte [rdi], 'm'
    inc rdi
    mov byte [rdi], 0

    pop rsi
    pop rdi
    pop rbp
    ret

; ================== SALIDA ERROR ==================
_exit_error:
    mov rax, 60
    mov rdi, 1
    syscall
