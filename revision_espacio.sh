#!/bin/bash

# --- Configuración ---
NUM_FILES_A_MOSTRAR=20     # Número de archivos más pesados a mostrar
EXTENSION_COMPRIMIDO=".tar.gz" # Extensión para los archivos comprimidos.
RUTA_LOG="/tmp"          # Directorio base donde se guardará el archivo de log.
PREFIJO_LOG="revision_espacio_" # Prefijo para el nombre del archivo de log.

# Extensiones de archivos a EXCLUIR de la búsqueda (archivos ya comprimidos o similares)
# Puedes añadir más si lo necesitas, separados por espacios
EXTENSIONES_A_EXCLUIR=("gz" "tgz" "tar.gz" "zip" "rar" "7z" "bz2" "tbz2" "xz" "txz" "iso" "img")

# --- Variables Globales de Estado ---
# Se usará para controlar si el log ya se ha iniciado
LOG_YA_GENERADO=false
ARCHIVO_LOG_ACTUAL="" # Se inicializará cuando sea necesario

# --- Funciones ---

# Función para limpiar la pantalla y mostrar un encabezado
limpiar_y_encabezado() {
    clear
    echo "============================================================"
    echo "  Herramienta Interactiva de Gestión de Archivos Pesados   "
    echo "============================================================"
    echo ""
}

# Función para registrar mensajes en el log
registrar_mensaje() {
    local MENSAJE="$1"

    # Si el log aún no ha sido generado, hacerlo ahora
    if ! $LOG_YA_GENERADO; then
        ARCHIVO_LOG_ACTUAL="${RUTA_LOG}/${PREFIJO_LOG}$(date '+%Y%m%d_%H%M%S').log"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Script iniciado. Log de esta sesión: $ARCHIVO_LOG_ACTUAL" | sudo tee -a "$ARCHIVO_LOG_ACTUAL" > /dev/null
        LOG_YA_GENERADO=true
    fi
    
    # Escribir el mensaje actual
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $MENSAJE" | sudo tee -a "$ARCHIVO_LOG_ACTUAL" > /dev/null
}

# Función para validar la integridad de un archivo tar.gz
validar_targz() {
    local ARCHIVO="$1"
    
    # Validar integridad de gzip (descomprime temporalmente en memoria)
    if gzip -t "$ARCHIVO" 2>/dev/null; then
        # Validar integridad de tar (lista el contenido sin extraer)
        if tar -tf "$ARCHIVO" >/dev/null 2>&1; then
            return 0 # 0 significa éxito (válido)
        else
            return 1 # 1 significa fallo (tar corrupto)
        fi
    else
        return 1 # 1 significa fallo (gzip corrupto)
    fi
}


# Función principal para procesar un directorio
procesar_directorio() {
    limpiar_y_encabezado

    local DIRECTORIO_OBJETIVO

    # 1. Solicitar la ruta del directorio
    while true; do
        read -p "Por favor, ingresa la ruta completa de la carpeta a revisar (ej. /var/log/nginx): " DIRECTORIO_OBJETIVO
        
        DIRECTORIO_OBJETIVO="${DIRECTORIO_OBJETIVO%/}" # Eliminar barra final si existe

        if [ -d "$DIRECTORIO_OBJETIVO" ]; then
            echo ""
            echo "Revisando el directorio: $DIRECTORIO_OBJETIVO"
            echo "Esto puede tardar un momento si el directorio es muy grande..."
            break
        else
            echo "Error: El directorio '$DIRECTORIO_OBJETIVO' no existe o no es válido."
            echo "Por favor, inténtalo de nuevo."
            echo ""
        fi
    done

    echo "------------------------------------------------------------"
    echo "  Los $NUM_FILES_A_MOSTRAR archivos más pesados en '$DIRECTORIO_OBJETIVO' son: "
    echo "------------------------------------------------------------"
    echo "  (Ordenados por tamaño, descendente - Excluyendo archivos ya comprimidos)"

    # Construir la parte de exclusión para el comando find
    local EXCLUSION_FIND_PART=""
    for ext in "${EXTENSIONES_A_EXCLUIR[@]}"; do
        EXCLUSION_FIND_PART+=" -not -name \"*.$ext\""
    done

    declare -a LISTA_ARCHIVOS_CRUDA
    # Buscar archivos, aplicar exclusiones, obtener tamaño y fecha, ordenar por tamaño, tomar los N primeros
    mapfile -t LISTA_ARCHIVOS_CRUDA < <(eval sudo find \""$DIRECTORIO_OBJETIVO"\" -type f "$EXCLUSION_FIND_PART" -print0 | \
        xargs -0 du -h --time --time-style=+%d-%m-%Y\ %H:%M 2>/dev/null | \
        sort -rh | head -n "$NUM_FILES_A_MOSTRAR")

    if [ ${#LISTA_ARCHIVOS_CRUDA[@]} -eq 0 ]; then
        echo "No se encontraron archivos que cumplan los criterios en el directorio seleccionado."
        echo "============================================================"
        return # Salir de la función, volver al bucle principal
    fi

    declare -a ARCHIVOS_PARA_COMPRESION
    INDICE=1
    for info_archivo in "${LISTA_ARCHIVOS_CRUDA[@]}"; do
        # Extraer la ruta usando awk (desde el 4to campo hasta el final)
        RUTA_ARCHIVO=$(echo "$info_archivo" | awk '{path=""; for (i=4; i<=NF; i++) path=path (path=="" ? "" : " ") $i; print path}')
        
        # Mostrar la lista numerada
        TAMANO=$(echo "$info_archivo" | awk '{print $1}')
        FECHA_HORA=$(echo "$info_archivo" | awk '{print $2, $3}')
        
        printf "%-3s %-10s %-20s %s\n" "$INDICE." "$TAMANO" "$FECHA_HORA" "$RUTA_ARCHIVO"
        ARCHIVOS_PARA_COMPRESION[INDICE]="$RUTA_ARCHIVO" # Guardar la ruta completa para la compresión
        ((INDICE++))
    done
    echo "------------------------------------------------------------"
    echo ""

    # 2. Preguntar si el usuario desea comprimir archivos de la lista
    read -p "¿Deseas comprimir alguno de estos archivos? (s/N): " CONFIRMAR_COMPRIMIR
    echo ""

    if [[ "$CONFIRMAR_COMPRIMIR" =~ ^[Ss]$ ]]; then
        read -p "Ingresa los números de los archivos a comprimir, separados por espacios (ej. 1 3 5): " NUMEROS_ARCHIVOS_A_COMPRIMIR
        echo ""

        # Comprimir los archivos seleccionados
        for num in $NUMEROS_ARCHIVOS_A_COMPRIMIR; do
            ARCHIVO_A_COMPRIMIR="${ARCHIVOS_PARA_COMPRESION[num]}"
            
            if [ -n "$ARCHIVO_A_COMPRIMIR" ] && [ -f "$ARCHIVO_A_COMPRIMIR" ]; then
                NOMBRE_ARCHIVO=$(basename "$ARCHIVO_A_COMPRIMIR")
                NOMBRE_DIRECTORIO=$(dirname "$ARCHIVO_A_COMPRIMIR")
                ARCHIVO_COMPRIMIDO="${ARCHIVO_A_COMPRIMIR}${EXTENSION_COMPRIMIDO}"

                # Obtener tamaño ANTES de comprimir
                TAMANO_ANTES=$(sudo du -h "$ARCHIVO_A_COMPRIMIR" 2>/dev/null | awk '{print $1}')
                if [ -z "$TAMANO_ANTES" ]; then
                    TAMANO_ANTES="N/A"
                fi

                echo "Comprimiendo '$NOMBRE_ARCHIVO' en '$ARCHIVO_COMPRIMIDO'..."
                registrar_mensaje "[INICIO COMPRESION] $ARCHIVO_A_COMPRIMIR" # Este es el primer punto donde se puede generar el log
                
                # Comprimir usando tar y gzip, eliminar el original si tiene éxito
                sudo tar -czf "$ARCHIVO_COMPRIMIDO" -C "$NOMBRE_DIRECTORIO" "$NOMBRE_ARCHIVO" --remove-files
                
                if [ $? -eq 0 ]; then
                    # Obtener tamaño DESPUES de comprimir
                    TAMANO_DESPUES=$(sudo du -h "$ARCHIVO_COMPRIMIDO" 2>/dev/null | awk '{print $1}')
                    if [ -z "$TAMANO_DESPUES" ]; then
                        TAMANO_DESPUES="N/A"
                    fi # <--- ¡Aquí estaba la 'C' que causaba el error! Ahora es 'fi'
                    
                    echo "¡Listo! '$NOMBRE_ARCHIVO' ha sido comprimido y el original borrado."
                    
                    # Validación del archivo comprimido
                    if validar_targz "$ARCHIVO_COMPRIMIDO"; then
                        echo "  -> Validación del archivo comprimido OK."
                        registrar_mensaje "[COMPRIMIDO] $ARCHIVO_A_COMPRIMIR [antes] $TAMANO_ANTES -- [despues] $(basename "$ARCHIVO_COMPRIMIDO") $TAMANO_DESPUES [VALIDADO: OK]"
                    else
                        echo "  -> ¡Advertencia! El archivo comprimido podría estar corrupto."
                        registrar_mensaje "[COMPRIMIDO] $ARCHIVO_A_COMPRIMIR [antes] $TAMANO_ANTES -- [despues] $(basename "$ARCHIVO_COMPRIMIDO") $TAMANO_DESPUES [VALIDADO: POSIBLE CORRUPCION]"
                    fi

                else
                    echo "Error: No se pudo comprimir '$NOMBRE_ARCHIVO'."
                    registrar_mensaje "[ERROR COMPRESION] $ARCHIVO_A_COMPRIMIR - No se pudo comprimir."
                fi
            else
                echo "Advertencia: El número '$num' no corresponde a un archivo válido o el archivo no existe."
                registrar_mensaje "[ADVERTENCIA] El número '$num' no corresponde a un archivo válido o el archivo '$ARCHIVO_A_COMPRIMIR' no existe."
            fi
            echo "" # Espacio entre cada compresión
        done
    else
        echo "No se seleccionaron archivos para comprimir."
        echo ""
    fi
    echo "============================================================"
    echo "  Análisis y Compresión completados para este directorio.   "
    echo "============================================================"
    echo ""
}

# --- Bucle Principal del Script ---

# El archivo de log se genera la primera vez que registrar_mensaje es llamado.
# No se llama registrar_mensaje aquí para evitar un log si no hay actividad.

while true; do
    procesar_directorio # Ejecutar el proceso completo
    
    # Preguntar si el usuario quiere consultar otro directorio
    read -p "¿Deseas consultar otro directorio? (s/N): " OTRA_CARPETA_CONFIRMAR
    echo ""

    if [[ ! "$OTRA_CARPETA_CONFIRMAR" =~ ^[Ss]$ ]]; then
        echo "Saliendo del script. ¡Hasta la próxima!"
        # Registrar mensaje de finalización solo si el log fue generado
        if $LOG_YA_GENERADO; then
            registrar_mensaje "Script finalizado."
        fi
        break # Salir del bucle principal y terminar el script
    fi
done

# Mostrar la ruta del log solo si el log fue generado
if $LOG_YA_GENERADO; then
    echo "Se generó un archivo log de respaldo de esta solicitud en: $ARCHIVO_LOG_ACTUAL"
fi
exit 0
