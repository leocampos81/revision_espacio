#include <iostream>
#include <fstream>
#include <string>
#include <cstdio>
#include <stdexcept>
#include <cstdlib>
#include <vector>
#include <unistd.h>

// Función para ejecutar un comando y capturar su salida
std::string exec(const char* cmd) {
    char buffer[128];
    std::string result = "";
    FILE* pipe = popen(cmd, "r");
    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }
    try {
        while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
            result += buffer;
        }
    } catch (...) {
        pclose(pipe);
        throw;
    }
    pclose(pipe);
    return result;
}

// Función para determinar el gestor de paquetes
std::string get_package_manager() {
    if (system("command -v apt-get >/dev/null 2>&1") == 0) {
        return "apt-get";
    }
    if (system("command -v dnf >/dev/null 2>&1") == 0) {
        return "dnf";
    }
    if (system("command -v pacman >/dev/null 2>&1") == 0) {
        return "pacman";
    }
    return ""; // Si no se encuentra ninguno
}

// Función para instalar un paquete
bool install_package(const std::string& package, const std::string& pkg_manager) {
    std::string install_command;
    if (pkg_manager == "apt-get") {
        install_command = "sudo apt-get update && sudo apt-get install -y " + package;
    } else if (pkg_manager == "dnf") {
        install_command = "sudo dnf install -y " + package;
    } else if (pkg_manager == "pacman") {
        install_command = "sudo pacman -S --noconfirm " + package;
    } else {
        std::cerr << "Error: Gestor de paquetes no soportado." << std::endl;
        return false;
    }
    
    std::cout << "Instalando el paquete '" << package << "'..." << std::endl;
    return system(install_command.c_str()) == 0;
}

// Función que chequea e instala las dependencias
void check_and_install_dependencies() {
    std::string pkg_manager = get_package_manager();
    if (pkg_manager.empty()) {
        std::cerr << "Error: No se encontró un gestor de paquetes soportado (apt, dnf, pacman)." << std::endl;
        return;
    }

    std::vector<std::pair<std::string, std::string>> commands = {
        {"dmidecode", "dmidecode"},
        {"lspci", "pciutils"},
        {"lsb_release", "lsb-release"},
        {"lshw", "lshw"},
        {"acpi", "acpi"},
        {"upower", "upower"}
    };

    std::cout << "Comprobando e instalando dependencias con '" << pkg_manager << "'..." << std::endl;
    
    for (const auto& cmd_pair : commands) {
        std::string command_to_check = "command -v " + cmd_pair.first + " >/dev/null 2>&1";
        if (system(command_to_check.c_str()) != 0) {
            if (!install_package(cmd_pair.second, pkg_manager)) {
                std::cerr << "Error: No se pudo instalar el paquete '" << cmd_pair.second << "'. Por favor, instálelo manualmente." << std::endl;
            }
        }
    }
    std::cout << "Todas las dependencias están listas." << std::endl;
}

int main(int argc, char* argv[]) {
    // Verificación de permisos
    if (getuid() != 0) {
        std::cerr << "Error: Este script debe ser ejecutado con permisos de superusuario (sudo)." << std::endl;
        std::cerr << "Por favor, ejecute: sudo " << argv[0] << " [nombre_archivo]" << std::endl;
        return 1;
    }

    check_and_install_dependencies();

    std::string outputFileName;
    if (argc > 1) {
        outputFileName = argv[1];
    } else {
        const char* homeDir = getenv("HOME");
        if (homeDir) {
            outputFileName = std::string(homeDir) + "/info_notebook.txt";
        } else {
            outputFileName = "info_notebook.txt";
        }
    }

    std::ofstream outputFile(outputFileName);
    if (!outputFile.is_open()) {
        std::cerr << "Error: No se pudo abrir el archivo " << outputFileName << ". Verifique los permisos del directorio." << std::endl;
        return 1;
    }

    std::cout << "\nRecopilando información del notebook..." << std::endl;
    std::cout << "Se guardará en: " << outputFileName << std::endl;

    outputFile << "=======================================\n";
    outputFile << "   INFORMACIÓN DEL NOTEBOOK (LINUX)      \n";
    outputFile << "=======================================\n\n";

    // --- 1. Información del Sistema Operativo ---
    outputFile << "--- Información del Sistema Operativo ---\n";
    try {
        outputFile << exec("lsb_release -a");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info del SO: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 2. Información del Sistema/Modelo ---
    outputFile << "--- Modelo/Fabricante ---\n";
    try {
        outputFile << "Fabricante: " << exec("dmidecode -s system-manufacturer");
        outputFile << "Producto: " << exec("dmidecode -s system-product-name");
        outputFile << "Versión: " << exec("dmidecode -s system-version");
        outputFile << "Placa Base: " << exec("dmidecode -s baseboard-manufacturer");
        outputFile << "Modelo de Placa Base: " << exec("dmidecode -s baseboard-product-name");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de dmidecode: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 3. Información de CPU ---
    outputFile << "--- Información de CPU ---\n";
    try {
        outputFile << exec("lscpu");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de CPU: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 4. Información de Memoria (RAM) ---
    outputFile << "--- Información de Memoria (RAM) ---\n";
    try {
        outputFile << exec("free -h");
        outputFile << "Detalles de módulos RAM:\n";
        outputFile << exec("dmidecode -t memory | grep -E 'Size:|Speed:|Type:|Locator:'");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de Memoria: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 5. Información de Discos y Espacio ---
    outputFile << "--- Información de Discos y Espacio ---\n";
    try {
        outputFile << exec("lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,SERIAL");
        outputFile << "\nUso del sistema de archivos:\n";
        outputFile << exec("df -h");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de Discos: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 6. Información de Tarjeta Gráfica (GPU) ---
    outputFile << "--- Información de Tarjeta Gráfica ---\n";
    try {
        outputFile << exec("lspci -k | grep -EA3 'VGA|3D|Display'");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de GPU: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 7. Información de Red ---
    outputFile << "--- Información de Red ---\n";
    try {
        outputFile << exec("lshw -class network");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de Red: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 8. Información de la Batería (si aplica) ---
    outputFile << "--- Información de Batería ---\n";
    try {
        outputFile << exec("acpi -i");
        outputFile << exec("upower -d | grep -E 'state|time to empty|percentage'");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de Batería: " << e.what() << "\n";
    }
    outputFile << "\n";

    outputFile.close();
    std::cout << "\nInformación recopilada y guardada en " << outputFileName << std::endl;

    return 0;
}
