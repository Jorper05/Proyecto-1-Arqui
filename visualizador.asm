; Compilar: nasm -f elf64 visualizador.asm -o visualizador.o
; Enlazar: ld visualizador.o -o visualizador
; Ejecutar: ./visualizador

; Sección de datos definidos
section .data
    archivo_config      db "config.ini",0       ; Archivo de parámetros
    archivo_inventario  db "inventario.txt",0   ; Archivo de datos
    salto_linea         db 10                   ; Carácter nueva línea

; Sección de reserva de memoria
section .bss
    memoria_temp    resb 257    ; Almacenamiento temporal para lecturas
    bytes_leidos    resq 1      ; Contador de bytes leídos
    simbolo_barra   resb 8      ; Símbolo utilizado para las barras
    color_texto     resb 4      ; Código color del texto (ANSI)
    color_base      resb 4      ; Código color de fondo (ANSI)

    ; Espacios para nombres de productos
    producto1 resb 32
    producto2 resb 32
    producto3 resb 32
    producto4 resb 32

    ; Almacenamiento para valores numéricos
    valor1 resq 1
    valor2 resq 1
    valor3 resq 1
    valor4 resq 1

    cadena_numero resb 32       ; Conversión temporal números→texto

    ; Buffers para las barras generadas
    grafica1 resb 256
    grafica2 resb 256
    grafica3 resb 256
    grafica4 resb 256

    ; Buffers para combinaciones (producto + barra)
    resultado1 resb 512
    resultado2 resb 512
    resultado3 resb 512
    resultado4 resb 512

    ; Array de referencias a resultados
    referencias resq 4

    ; Buffer unificado para salida final
    salida_ordenada resb 2048

; Código principal
section .text
global _start

_start:
    ; Configurar array de referencias
    lea rax, [rel resultado1]
    mov [referencias+0*8], rax
    lea rax, [rel resultado2]
    mov [referencias+1*8], rax
    lea rax, [rel resultado3]
    mov [referencias+2*8], rax
    lea rax, [rel resultado4]
    mov [referencias+3*8], rax

    ; Acceder a archivo de configuración
     mov rax, 2
    lea rdi, [rel archivo_config]   ; nombre archivo
    xor rsi, rsi                    ; modo lectura
    syscall
    mov r12, rax                    ; preservar descriptor
    cmp rax, 0
    js error_config                 ; fallo apertura

    ; Cargar contenido de configuración

    lea rsi, [rel memoria_temp]     ; destino
    mov rdx, 256                    ; capacidad
    mov rax, 0                      ; lectura
    mov rdi, r12                    ; descriptor
    syscall
    mov [bytes_leidos], rax
    cmp rax, 0
    js error_lectura                ; fallo lectura

    ; Establecer terminador de cadena
    mov rbx, [bytes_leidos]
    cmp rbx, 256
    jbe .config_ok
    mov rbx, 256
.config_ok:
    lea rcx, [rel memoria_temp]
    add rcx, rbx
    mov byte [rcx], 0


     ; 3. Interpretar parámetros de configuración
    ; =================================================
    lea rsi, [rel memoria_temp]     ; inicio buffer
    xor r8, r8                      ; índice parámetro

analizar_config:
    lodsb
    cmp al, 0
    je fin_analisis                 ; final archivo

    cmp al, ':'
    jne analizar_config

    cmp r8, 0
    je guardar_simbolo
    cmp r8, 1
    je guardar_color_texto
    cmp r8, 2
    je guardar_color_base
    jmp analizar_config

; Preservar símbolo de barra
guardar_simbolo:
    xor r9, r9
.copiar_simbolo:
    lodsb
    cmp al, 10
    je .completado
    mov [simbolo_barra + r9], al
    inc r9
    jmp .copiar_simbolo
.completado:
    mov byte [simbolo_barra + r9], 0
    inc r8
    jmp analizar_config

; Preservar color del texto
guardar_color_texto:
    lodsb
    mov [color_texto], al
    lodsb
    mov [color_texto+1], al
    mov byte [color_texto+2], 0
    inc r8
    jmp siguiente_linea

; Preservar color de fondo
guardar_color_base:
    lodsb
    mov [color_base], al
    lodsb
    mov [color_base+1], al
    mov byte [color_base+2], 0
    inc r8
    jmp siguiente_linea

; Avanzar a siguiente línea
siguiente_linea:
.omitir:
    lodsb
    cmp al, 10
    jne .omitir
    jmp analizar_config

fin_analisis:

    ; 4. Abrir inventario.txt

    mov rax, 2
    lea rdi, [rel archivo_inventario]
    xor rsi, rsi
    syscall
    mov r13, rax
    cmp rax, 0
    js error_inventario

    ; 5. Leer inventario.txt en buffer

    lea rsi, [rel memoria_temp]
    mov rdx, 256
    mov rax, 0
    mov rdi, r13
    syscall
    mov rbx, rax
    cmp rax, 0
    js error_lectura

    ; Terminador de cadena
    cmp rbx, 256
    jbe .inventario_ok
    mov rbx, 256
.inventario_ok:
    lea rcx, [rel memoria_temp]
    add rcx, rbx
    mov byte [rcx], 0


    ; 6. Inicializar contadores numéricos

    mov qword [valor1], 0
    mov qword [valor2], 0
    mov qword [valor3], 0
    mov qword [valor4], 0

    ; 7. Copiar líneas y extraer números

    lea rsi, [rel memoria_temp]
    lea rdi, [rel producto1]
    mov rcx, 4
    xor r8, r8      ; índice de línea

procesar_lineas:
    push rcx
    xor r9, r9      ; acumulador numérico
    mov r10b, 0     ; indicador post-delimitador

procesar_caracter:
    lodsb
    cmp al, 10
    je near fin_procesamiento

    cmp al, ':'
    jne near no_es_delimitador
    mov r10b, 1
    stosb
    jmp near procesar_caracter

no_es_delimitador:
    cmp r10b, 1
    jne near copiar_nombre
    ; procesar dígitos numéricos
    stosb
    movzx rax, al
    sub rax, '0'
    imul r9, r9, 10
    add r9, rax
    jmp near procesar_caracter

copiar_nombre:
    stosb
    jmp near procesar_caracter

fin_procesamiento:
    mov al, 0
    stosb

    ; Almacenar valor según línea actual
    cmp r8, 0
    je near almacenar_valor1
    cmp r8, 1
    je near almacenar_valor2
    cmp r8, 2
    je near almacenar_valor3
    cmp r8, 3
    je near almacenar_valor4

almacenar_valor1: mov [valor1], r9
    jmp near avanzar_linea
almacenar_valor2: mov [valor2], r9
    jmp near avanzar_linea
almacenar_valor3: mov [valor3], r9
    jmp near avanzar_linea
almacenar_valor4: mov [valor4], r9

avanzar_linea:
    inc r8
    cmp r8, 1
    je near establecer_producto2
    cmp r8, 2
    je near establecer_producto3
    cmp r8, 3
    je near establecer_producto4
    jmp near continuar_proceso

establecer_producto2: lea rdi, [rel producto2]
    jmp near continuar_proceso
establecer_producto3: lea rdi, [rel producto3]
    jmp near continuar_proceso
establecer_producto4: lea rdi, [rel producto4]

continuar_proceso:
    pop rcx
    dec rcx
    jnz near procesar_lineas

    ; 8. Construir barras (con códigos ANSI de color)

   lea rsi, [rel valor1]
    lea rdi, [rel grafica1]
    call generar_grafica

    lea rsi, [rel valor2]
    lea rdi, [rel grafica2]
    call generar_grafica

    lea rsi, [rel valor3]
    lea rdi, [rel grafica3]
    call generar_grafica

    lea rsi, [rel valor4]
    lea rdi, [rel grafica4]
    call generar_grafica


    ; 9. Concatenar línea + barra 

    lea rsi, [rel producto1]
    lea rdx, [rel grafica1]
    lea rdi, [rel resultado1]
    call combinar_cadenas

    lea rsi, [rel producto2]
    lea rdx, [rel grafica2]
    lea rdi, [rel resultado2]
    call combinar_cadenas

    lea rsi, [rel producto3]
    lea rdx, [rel grafica3]
    lea rdi, [rel resultado3]
    call combinar_cadenas

    lea rsi, [rel producto4]
    lea rdx, [rel grafica4]
    lea rdi, [rel resultado4]
    call combinar_cadenas


    ; 10. Ordenar alfabéticamente outs[]

    mov rcx, 4
bucle_externo:
    mov rbx, 0
bucle_interno:
    mov rdx, rcx
    dec rdx
    cmp rbx, rdx
    jge .siguiente_externo

    mov rsi, [referencias+rbx*8]
    mov rdi, [referencias+(rbx+1)*8]
    call comparar_cadenas
    cmp rax, 0
    jle .sin_intercambio

    ; Intercambiar referencias
    mov r8, [referencias+rbx*8]
    mov r9, [referencias+(rbx+1)*8]
    mov [referencias+rbx*8], r9
    mov [referencias+(rbx+1)*8], r8

.sin_intercambio:
    inc rbx
    jmp bucle_interno

.siguiente_externo:
    loop bucle_externo

    ; 11. Concatenar líneas ordenadas en out_sorted

     lea rdi, [rel salida_ordenada]
    mov rcx, 4
    mov rbx, 0
bucle_union:
    mov rsi, [referencias+rbx*8]
.copiar_contenido:
    mov al, [rsi]
    cmp al, 0
    je .linea_completada
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .copiar_contenido
.linea_completada:
    mov byte [rdi], 10   ; inserción salto de línea
    inc rdi
    inc rbx
    loop bucle_union
    mov byte [rdi], 0


    ; Imprimir buffer final 
    
    lea rsi, [rel salida_ordenada]
    call mostrar_texto


    ; salir
    
     mov rax, 3
    mov rdi, r12
    syscall

    mov rax, 3
    mov rdi, r13
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall


; FUNCIONES AUXILIARES

comparar_cadenas: ; comparar_cadenas: evalúa orden alfabético
    xor rax, rax
.ciclo:
    mov al, [rsi]
    mov dl, [rdi]
    cmp al, 0
    je .final
    cmp dl, 0
    je .final
    cmp al, dl
    jne .final
    inc rsi
    inc rdi
    jmp .ciclo
.final:
    movzx rax, al
    movzx rdx, dl
    sub rax, rdx
    ret

mostrar_texto: ; mostrar_texto: presenta cadena por salida estándar
    push rsi
    mov rax, rsi
.determinar_longitud:
    cmp byte [rax], 0
    je .longitud_obtenida
    inc rax
    jmp .determinar_longitud
.longitud_obtenida:
    sub rax, rsi
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    pop rsi
    syscall
    ret

generar_grafica:; generar_grafica: crea barra visual con colores
    ; Secuencia inicial de color
    mov byte [rdi], 27
    inc rdi
    mov byte [rdi], '['
    inc rdi
    mov al, [color_base]
    mov [rdi], al
    inc rdi
    mov al, [color_base+1]
    cmp al, 0
    je .omitir_base
    mov [rdi], al
    inc rdi
.omitir_base:
    mov byte [rdi], ';'
    inc rdi
    mov al, [color_texto]
    mov [rdi], al
    inc rdi
    mov al, [color_texto+1]
    cmp al, 0
    je .omitir_texto
    mov [rdi], al
    inc rdi
.omitir_texto:
    mov byte [rdi], 'm'
    inc rdi

    ; Repetir símbolo según valor
    mov rcx, [rsi]
.ciclo_grafica:
    cmp rcx, 0
    je .cerrar_grafica
    lea r8, [rel simbolo_barra]
.copiar_simbolo:
    mov al, [r8]
    cmp al, 0
    je .siguiente_repeticion
    mov [rdi], al
    inc rdi
    inc r8
    jmp .copiar_simbolo
.siguiente_repeticion:
    dec rcx
    jmp .ciclo_grafica

.cerrar_grafica:
    ; Restablecer atributos visuales
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

concat: ; une linea + espacio + barra en destino
combinar_cadenas:
.copiar_nombre:
    mov al, [rsi]
    cmp al, 0
    je .post_nombre
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .copiar_nombre
.post_nombre:
    mov byte [rdi], ' '
    inc rdi
.copiar_grafica:
    mov al, [rdx]
    cmp al, 0
    je .combinacion_completada
    mov [rdi], al
    inc rdx
    inc rdi
    jmp .copiar_grafica
.combinacion_completada:
    mov byte [rdi], 0
    ret

; MANEJO DE ERRORES

error_config:      ; fallo apertura configuración
    mov rax, 60
    mov rdi, 1
    syscall

error_inventario:  ; fallo apertura inventario
    mov rax, 60
    mov rdi, 2
    syscall

error_lectura:     ; fallo lectura archivo
    mov rax, 60
    mov rdi, 3
    syscall