#!/bin/bash

# --- Configuración inicial ---
LOG_DIR="/home/leonardo/conexiones/logs"
TMP_PASS_FILE="/tmp/.sshpass_$$.tmp"
MAX_ATTEMPTS=3 # Número máximo de intentos

# --- Configuración de la base de datos ---
DB_NAME="ssh_conexiones"
DB_USER="leonardo" # Usuario de MariaDB que creaste
DB_PASS="sisma802" # Contraseña de MariaDB

# --- Crear estructura de directorios ---
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

# --- Funciones principales ---

init_log() {
    local server_name=$1
    CURRENT_DATE=$(date "+%Y-%m-%d")
    LOG_FILE="$LOG_DIR/${server_name}_${CURRENT_DATE}.log"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
}

log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    rm -f "$TMP_PASS_FILE"
    log "=== Sesión finalizada ==="
    exit 0
}

validate_ip() {
    [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && return 0
    log "Error: IP $1 no válida"
    return 1
}

# --- NUEVA FUNCIÓN: Verificar y crear la base de datos y las tablas ---
check_and_create_db() {
    # Verificar conexión a MariaDB y crear la base de datos si no existe
    mariadb -u"$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo "Error: No se puede conectar a MariaDB. Verifique las credenciales."
        exit 1
    fi
    
    # Crear la tabla 'credenciales' si no existe
    mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
    CREATE TABLE IF NOT EXISTS credenciales (
        id INT AUTO_INCREMENT PRIMARY KEY,
        alias_equipo VARCHAR(255) NOT NULL,
        ip_servidor VARCHAR(15) NOT NULL,
        usuario VARCHAR(255) NOT NULL,
        contrasena_ofuscada TEXT NOT NULL,
        UNIQUE(alias_equipo, usuario)
    );" 2>/dev/null

    # Crear la tabla 'registros_conexion' si no existe
    mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
    CREATE TABLE IF NOT EXISTS registros_conexion (
        id INT AUTO_INCREMENT PRIMARY KEY,
        credencial_id INT NOT NULL,
        fecha_conexion DATETIME NOT NULL,
        FOREIGN KEY (credencial_id) REFERENCES credenciales(id) ON DELETE CASCADE
    );" 2>/dev/null
}

# ----------------- Funciones MODIFICADAS para usar la base de datos -----------------

get_server_cred() {
    local server_name=$1
    local user=$2
    mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT id, ip_servidor, contrasena_ofuscada FROM credenciales WHERE alias_equipo = '$server_name' AND usuario = '$user';" 2>/dev/null
}

get_last_user() {
    local server_name=$1
    mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT c.usuario FROM registros_conexion rc JOIN credenciales c ON rc.credencial_id = c.id WHERE c.alias_equipo = '$server_name' ORDER BY rc.fecha_conexion DESC LIMIT 1;" 2>/dev/null
}

get_ip_by_server_name() {
    local server_name=$1
    mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT ip_servidor FROM credenciales WHERE alias_equipo = '$server_name' LIMIT 1;" 2>/dev/null
}

save_credentials() {
    local name=$1 ip=$2 user=$3 pass=$4
    local cred_id
    
    enc_pass=$(echo "$pass" | openssl enc -aes-256-cbc -pbkdf2 -a -salt -pass pass:$(hostname) 2>/dev/null)
    
    existing_cred=$(mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT id FROM credenciales WHERE alias_equipo = '$name' AND usuario = '$user';" 2>/dev/null)
    
    if [ -n "$existing_cred" ]; then
        mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "UPDATE credenciales SET ip_servidor = '$ip', contrasena_ofuscada = '$enc_pass' WHERE id = '$existing_cred';" 2>/dev/null
        cred_id="$existing_cred"
        log "Credenciales actualizadas en la base de datos para $user@$name ($ip)"
    else
        mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO credenciales (alias_equipo, ip_servidor, usuario, contrasena_ofuscada) VALUES ('$name', '$ip', '$user', '$enc_pass');" 2>/dev/null
        cred_id=$(mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT id FROM credenciales WHERE alias_equipo = '$name' AND usuario = '$user';")
        log "Nueva credencial registrada en la base de datos para $user@$name ($ip)"
    fi
    
    if [ -n "$cred_id" ]; then
        mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO registros_conexion (credencial_id, fecha_conexion) VALUES ('$cred_id', NOW());" 2>/dev/null
    fi
}

connect_ssh() {
    local ip=$1 user=$2 pass=$3 do_log=$4
    echo "$pass" > "$TMP_PASS_FILE"
    chmod 600 "$TMP_PASS_FILE"
    
    local ssh_command="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o ServerAliveInterval=60 ${user}@${ip}"

    if [[ "$do_log" == "s" ]]; then
        local session_log_file="$LOG_DIR/${server_name}_session_$(date +%Y%m%d_%H%M%S).log"
        log "Conectando a $user@$ip... Sesión grabada en $session_log_file"
        sshpass -f "$TMP_PASS_FILE" script -q -c "$ssh_command" "$session_log_file"
    else
        log "Conectando a $user@$ip..."
        sshpass -f "$TMP_PASS_FILE" $ssh_command
    fi
    
    return $?
}

# ----------------- Lógica principal del script -----------------
trap cleanup EXIT INT TERM

# PASO CLAVE: Llamar a la función que crea la base de datos y las tablas
check_and_create_db

read -p "Nombre del servidor: " server_name
init_log "$server_name"
log "=== Inicio de sesión ==="

server_ip=$(get_ip_by_server_name "$server_name")

if [ -n "$server_ip" ]; then
    log "Servidor conocido: $server_name ($server_ip)"
    
    last_user=$(get_last_user "$server_name")
    read -p "¿Con qué usuario desea conectarse? [$last_user]: " new_user
    user=${new_user:-$last_user}
    ip=$server_ip

    for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
        cred_info=$(get_server_cred "$server_name" "$user")
        
        pass=""
        if [ -n "$cred_info" ]; then
            cred_id=$(echo "$cred_info" | awk '{print $1}')
            enc_pass=$(echo "$cred_info" | awk '{print $3}')
            
            pass=$(echo "$enc_pass" | openssl enc -aes-256-cbc -pbkdf2 -a -d -salt -pass pass:$(hostname) 2>/dev/null)
        fi
        
        if [ -n "$pass" ] && [ $i -eq 1 ]; then
            log "Intento $i de $MAX_ATTEMPTS: Usando contraseña guardada para $user"
        else
            log "Intento $i de $MAX_ATTEMPTS: Ingrese la contraseña manualmente para $user@$ip"
            read -s -p "Contraseña SSH: " pass
            echo ""
        fi
        
        read -p "¿Desea guardar la sesión en un log? (s/n): " save_session
        
        if connect_ssh "$ip" "$user" "$pass" "$save_session"; then
            log "Conexión exitosa a $server_name con usuario $user"
            if [ -z "$cred_info" ] || [ -z "$pass" ] || [ $i -gt 1 ]; then
                save_credentials "$server_name" "$ip" "$user" "$pass"
            fi
            cleanup
        fi
        log "Fallo al conectar (Intento $i)"
    done
    
    log "Número máximo de intentos ($MAX_ATTEMPTS) alcanzado. Fallo al conectar a $server_name"
    
else # Nuevo servidor
    log "Nuevo servidor detectado"
    while true; do
        read -p "IP del servidor: " ip
        validate_ip "$ip" && break
    done
    read -p "Usuario SSH: " user
    read -s -p "Contraseña SSH: " pass
    echo ""
    
    read -p "¿Desea guardar la sesión en un log? (s/n): " save_session
    
    if connect_ssh "$ip" "$user" "$pass" "$save_session"; then
        log "Conexión exitosa a $server_name"
        save_credentials "$server_name" "$ip" "$user" "$pass"
        cleanup
    else
        log "Fallo al conectar a $server_name"
    fi
fi

cleanup
