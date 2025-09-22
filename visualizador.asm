; Compilar: nasm -f elf64 visualizador.asm -o visualizador.o
; Enlazar: ld visualizador.o -o visualizador
; Ejecutar: ./visualizador

section .data
    config_file     db "config.ini",0       ; Nombre archivo configuración
    inventario_file db "inventario.txt",0   ; Nombre archivo inventario
    newline         db 10                   ; Salto de línea (LF)

section .bss
    buffer      resb 257    ; Buffer genérico para lectura de archivos (256 + terminador)
    bytes_read  resq 1      ; Bytes leídos de un archivo
    caracter_barra resb 8   ; Símbolo de la barra (puede ser multibyte)
    color_barra resb 4      ; Código ANSI para color de texto
    color_fondo resb 4      ; Código ANSI para color de fondo

    ; Buffers para almacenar líneas del inventario (texto antes del número)
    linea1 resb 32
    linea2 resb 32
    linea3 resb 32
    linea4 resb 32

    ; Variables para las cantidades numéricas
    num1 resq 1
    num2 resq 1
    num3 resq 1
    num4 resq 1

    num_str resb 32         ; Buffer temporal para convertir números a string (si fuera necesario)

    ; Buffers para almacenar barras graficadas (con colores)
    barra1 resb 256
    barra2 resb 256
    barra3 resb 256
    barra4 resb 256

    ; Buffers para almacenar concatenaciones (linea + barra)
    out1 resb 512
    out2 resb 512
    out3 resb 512
    out4 resb 512

    ; Arreglo de punteros dinámicos a out1..out4
    outs resq 4

    ; Buffer único para concatenar las líneas ordenadas
    out_sorted resb 2048

section .text
global _start

_start:
    ; Inicializamos el arreglo outs con direcciones de out1..out4
    lea rax, [rel out1]
    mov [outs+0*8], rax
    lea rax, [rel out2]
    mov [outs+1*8], rax
    lea rax, [rel out3]
    mov [outs+2*8], rax
    lea rax, [rel out4]
    mov [outs+3*8], rax

    ; =================================================
    ; 1. Abrir config.ini (syscall open -> rax=2)
    ; =================================================
    mov rax, 2
    lea rdi, [rel config_file]   ; filename
    xor rsi, rsi                 ; flags = 0 (solo lectura)
    syscall
    mov r12, rax                 ; guardar descriptor en r12
    cmp rax, 0
    js err_open_config           ; error -> salir

    ; =================================================
    ; 2. Leer config.ini en buffer
    ; =================================================
    lea rsi, [rel buffer]        ; destino
    mov rdx, 256                 ; tamaño
    mov rax, 0                   ; syscall read
    mov rdi, r12                 ; fd
    syscall
    mov [bytes_read], rax
    cmp rax, 0
    js err_read                  ; error -> salir

    ; Añadir terminador al final
    mov rbx, [bytes_read]
    cmp rbx, 256
    jbe .cfg_ok
    mov rbx, 256
.cfg_ok:
    lea rcx, [rel buffer]
    add rcx, rbx
    mov byte [rcx], 0

    ; =================================================
    ; 3. Parsear config.ini
    ; =================================================
    lea rsi, [rel buffer]    ; puntero al inicio del buffer
    xor r8, r8               ; contador de parámetros (0=caracter, 1=color_barra, 2=color_fondo)

parse_config:
    lodsb
    cmp al, 0
    je fin_config            ; fin del archivo

    cmp al, ':'
    jne parse_config

    cmp r8, 0
    je save_caracter
    cmp r8, 1
    je save_color_barra
    cmp r8, 2
    je save_color_fondo
    jmp parse_config

; Guardar caracter_barra
save_caracter:
    xor r9, r9
.copy_char:
    lodsb
    cmp al, 10
    je .done
    mov [caracter_barra + r9], al
    inc r9
    jmp .copy_char
.done:
    mov byte [caracter_barra + r9], 0
    inc r8
    jmp parse_config

; Guardar color_barra
save_color_barra:
    lodsb
    mov [color_barra], al
    lodsb
    mov [color_barra+1], al
    mov byte [color_barra+2], 0
    inc r8
    jmp next_line

; Guardar color_fondo
save_color_fondo:
    lodsb
    mov [color_fondo], al
    lodsb
    mov [color_fondo+1], al
    mov byte [color_fondo+2], 0
    inc r8
    jmp next_line

; Saltar al final de línea
next_line:
.skip:
    lodsb
    cmp al, 10
    jne .skip
    jmp parse_config

fin_config:

    ; =================================================
    ; 4. Abrir inventario.txt
    ; =================================================
    mov rax, 2
    lea rdi, [rel inventario_file]
    xor rsi, rsi
    syscall
    mov r13, rax
    cmp rax, 0
    js err_open_inv

    ; =================================================
    ; 5. Leer inventario.txt en buffer
    ; =================================================
    lea rsi, [rel buffer]
    mov rdx, 256
    mov rax, 0
    mov rdi, r13
    syscall
    mov rbx, rax
    cmp rax, 0
    js err_read

    ; terminador
    cmp rbx, 256
    jbe .inv_ok
    mov rbx, 256
.inv_ok:
    lea rcx, [rel buffer]
    add rcx, rbx
    mov byte [rcx], 0

    ; =================================================
    ; 6. Inicializar contadores numéricos
    ; =================================================
    mov qword [num1], 0
    mov qword [num2], 0
    mov qword [num3], 0
    mov qword [num4], 0

    ; =================================================
    ; 7. Copiar líneas y extraer números
    ; =================================================
    lea rsi, [rel buffer]
    lea rdi, [rel linea1]
    mov rcx, 4
    xor r8, r8      ; contador de línea

copiar_lineas:
    push rcx
    xor r9, r9      ; acumulador numérico
    mov r10b, 0     ; flag: después de ':'

copiar_char:
    lodsb
    cmp al, 10
    je near fin_linea

    cmp al, ':'
    jne near no_dos_puntos
    mov r10b, 1
    stosb
    jmp near copiar_char

no_dos_puntos:
    cmp r10b, 1
    jne near copiar_texto
    ; acumulamos número
    stosb
    movzx rax, al
    sub rax, '0'
    imul r9, r9, 10
    add r9, rax
    jmp near copiar_char

copiar_texto:
    stosb
    jmp near copiar_char

fin_linea:
    mov al, 0
    stosb

    ; guardar número en variable correspondiente
    cmp r8, 0
    je near save_num1
    cmp r8, 1
    je near save_num2
    cmp r8, 2
    je near save_num3
    cmp r8, 3
    je near save_num4

save_num1: mov [num1], r9  ; línea 1 -> num1
    jmp near siguiente_linea
save_num2: mov [num2], r9  ; línea 2 -> num2
    jmp near siguiente_linea
save_num3: mov [num3], r9  ; línea 3 -> num3
    jmp near siguiente_linea
save_num4: mov [num4], r9  ; línea 4 -> num4

siguiente_linea:
    inc r8
    cmp r8, 1
    je near set_linea2
    cmp r8, 2
    je near set_linea3
    cmp r8, 3
    je near set_linea4
    jmp near despues_set

set_linea2: lea rdi, [rel linea2]  ; siguiente destino
    jmp near despues_set
set_linea3: lea rdi, [rel linea3]
    jmp near despues_set
set_linea4: lea rdi, [rel linea4]
    jmp near despues_set

despues_set:
    pop rcx
    dec rcx
    jnz near copiar_lineas

    ; =================================================
    ; 8. Construir barras (con códigos ANSI de color)
    ; =================================================
    lea rsi, [rel num1]
    lea rdi, [rel barra1]
    call build_bar

    lea rsi, [rel num2]
    lea rdi, [rel barra2]
    call build_bar

    lea rsi, [rel num3]
    lea rdi, [rel barra3]
    call build_bar

    lea rsi, [rel num4]
    lea rdi, [rel barra4]
    call build_bar

    ; =================================================
    ; 9. Concatenar línea + barra (ej: "manzanas:12 ####")
    ; =================================================
    lea rsi, [rel linea1]
    lea rdx, [rel barra1]
    lea rdi, [rel out1]
    call concat

    lea rsi, [rel linea2]
    lea rdx, [rel barra2]
    lea rdi, [rel out2]
    call concat

    lea rsi, [rel linea3]
    lea rdx, [rel barra3]
    lea rdi, [rel out3]
    call concat

    lea rsi, [rel linea4]
    lea rdx, [rel barra4]
    lea rdi, [rel out4]
    call concat

    ; =================================================
    ; 10. Ordenar alfabéticamente outs[]
    ; =================================================
    mov rcx, 4
outer_loop:
    mov rbx, 0
inner_loop:
    mov rdx, rcx
    dec rdx
    cmp rbx, rdx
    jge .next_outer

    mov rsi, [outs+rbx*8]
    mov rdi, [outs+(rbx+1)*8]
    call strcmp
    cmp rax, 0
    jle .no_swap

    ; intercambiar punteros
    mov r8, [outs+rbx*8]
    mov r9, [outs+(rbx+1)*8]
    mov [outs+rbx*8], r9
    mov [outs+(rbx+1)*8], r8

.no_swap:
    inc rbx
    jmp inner_loop

.next_outer:
    loop outer_loop

    ; =================================================
    ; 11. Concatenar líneas ordenadas en out_sorted
    ; =================================================
    lea rdi, [rel out_sorted]
    mov rcx, 4
    mov rbx, 0
concat_loop:
    mov rsi, [outs+rbx*8]
.copy_line:
    mov al, [rsi]
    cmp al, 0
    je .line_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .copy_line
.line_done:
    mov byte [rdi], 10   ; salto de línea entre entradas
    inc rdi
    inc rbx
    loop concat_loop
    mov byte [rdi], 0

    ; =================================================
    ; 12. Imprimir buffer final (única salida del programa)
    ; =================================================
    lea rsi, [rel out_sorted]
    call print_str

    ; =================================================
    ; 13. Cerrar archivos y salir
    ; =================================================
    mov rax, 3
    mov rdi, r12
    syscall

    mov rax, 3
    mov rdi, r13
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall

; ========================================
; FUNCIONES AUXILIARES
; ========================================

; ------------------------------------------------
; strcmp: compara dos strings terminados en 0
; salida: rax = diferencia (0 si iguales, >0 o <0)
; ------------------------------------------------
strcmp:
    xor rax, rax
.loop:
    mov al, [rsi]
    mov dl, [rdi]
    cmp al, 0
    je .end
    cmp dl, 0
    je .end
    cmp al, dl
    jne .end
    inc rsi
    inc rdi
    jmp .loop
.end:
    movzx rax, al
    movzx rdx, dl
    sub rax, rdx
    ret

; ------------------------------------------------
; print_str: imprime string terminado en 0 por stdout
; ------------------------------------------------
print_str:
    push rsi
    mov rax, rsi
.find_end:
    cmp byte [rax], 0
    je .len_ready
    inc rax
    jmp .find_end
.len_ready:
    sub rax, rsi
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    pop rsi
    syscall
    ret

; ------------------------------------------------
; build_bar: construye barra coloreada
; Entrada: rsi -> número, rdi -> destino
; Salida: buffer en formato: ESC[bg;fgm#####ESC[0m
; ------------------------------------------------
build_bar:
    ; código de color inicial
    mov byte [rdi], 27
    inc rdi
    mov byte [rdi], '['
    inc rdi
    mov al, [color_fondo]
    mov [rdi], al
    inc rdi
    mov al, [color_fondo+1]
    cmp al, 0
    je .skip_cf
    mov [rdi], al
    inc rdi
.skip_cf:
    mov byte [rdi], ';'
    inc rdi
    mov al, [color_barra]
    mov [rdi], al
    inc rdi
    mov al, [color_barra+1]
    cmp al, 0
    je .skip_cb
    mov [rdi], al
    inc rdi
.skip_cb:
    mov byte [rdi], 'm'
    inc rdi

    ; repetir caracter_barra
    mov rcx, [rsi]
.loop:
    cmp rcx, 0
    je .close
    lea r8, [rel caracter_barra]
.copy_utf8:
    mov al, [r8]
    cmp al, 0
    je .next
    mov [rdi], al
    inc rdi
    inc r8
    jmp .copy_utf8
.next:
    dec rcx
    jmp .loop

.close:
    ; reset de color
    mov byte [rdi], 27
    inc rdi
    mov byte [rdi], '['
    inc rdi
    mov byte [rdi], '0'
    inc rdi
    mov byte [rdi], 'm'
    inc rdi

    mov byte [rdi], 0
    ret

; ------------------------------------------------
; concat: une linea + espacio + barra en destino
; ------------------------------------------------
concat:
.copy_line:
    mov al, [rsi]
    cmp al, 0
    je .after_line
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .copy_line
.after_line:
    mov byte [rdi], ' '
    inc rdi
.copy_bar:
    mov al, [rdx]
    cmp al, 0
    je .done
    mov [rdi], al
    inc rdx
    inc rdi
    jmp .copy_bar
.done:
    mov byte [rdi], 0
    ret

; ================================================================
; MANEJO DE ERRORES
; ================================================================
err_open_config:   ; error al abrir config.ini
    mov rax, 60
    mov rdi, 1
    syscall

err_open_inv:      ; error al abrir inventario.txt
    mov rax, 60
    mov rdi, 2
    syscall

err_read:          ; error al leer archivo
    mov rax, 60
    mov rdi, 3
    syscall