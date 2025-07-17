#include <iostream> // Para entrada/salida estándar (cout)
#include <fstream>  // Para manejo de archivos (ofstream)
#include <string>   // Para manejar cadenas de texto
#include <cstdio>   // Para popen y pclose

// Función para ejecutar un comando y capturar su salida
std::string exec(const char* cmd) {
    char buffer[128];
    std::string result = "";
    // popen abre un pipe para leer la salida del comando
    FILE* pipe = popen(cmd, "r");
    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }
    try {
        // Lee la salida del comando línea por línea
        while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
            result += buffer;
        }
    } catch (...) {
        pclose(pipe); // Asegura que el pipe se cierre incluso si hay un error
        throw;
    }
    pclose(pipe); // Cierra el pipe
    return result;
}

int main() {
    std::ofstream outputFile("info_notebook.txt"); // Abre el archivo para escritura
    if (!outputFile.is_open()) {
        std::cerr << "Error: No se pudo abrir el archivo info_notebook.txt" << std::endl;
        return 1; // Retorna un código de error
    }

    std::cout << "Recopilando información del notebook..." << std::endl;

    outputFile << "=======================================\n";
    outputFile << "  INFORMACIÓN DEL NOTEBOOK (UBUNTU)    \n";
    outputFile << "=======================================\n\n";

    // --- 1. Información del Sistema/Modelo ---
    outputFile << "--- Modelo/Fabricante ---\n";
    try {
        outputFile << "Fabricante: " << exec("sudo dmidecode -s system-manufacturer");
        outputFile << "Producto: " << exec("sudo dmidecode -s system-product-name");
        outputFile << "Versión: " << exec("sudo dmidecode -s system-version");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de dmidecode: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 2. Información de CPU ---
    outputFile << "--- Información de CPU ---\n";
    try {
        outputFile << exec("lscpu");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de CPU: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 3. Información de Memoria (RAM) ---
    outputFile << "--- Información de Memoria (RAM) ---\n";
    try {
        outputFile << exec("free -h");
        // Para detalles de módulos (requiere dmidecode y permisos):
        outputFile << "Detalles de módulos RAM (requiere sudo para dmidecode):\n";
        outputFile << exec("sudo dmidecode -t memory | grep -E 'Size:|Speed:|Type:|Locator:'");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de Memoria: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 4. Información de Discos ---
    outputFile << "--- Información de Discos ---\n";
    try {
        outputFile << exec("lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,SERIAL");
        // Para info más detallada de particiones (requiere sudo):
        outputFile << "\nDetalles de Particiones (requiere sudo para fdisk):\n";
        outputFile << exec("sudo fdisk -l");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de Discos: " << e.what() << "\n";
    }
    outputFile << "\n";

    // --- 5. Información de Tarjeta Gráfica (GPU) ---
    outputFile << "--- Información de Tarjeta Gráfica ---\n";
    try {
        outputFile << exec("lspci -k | grep -EA3 'VGA|3D|Display'");
    } catch (const std::exception& e) {
        outputFile << "Error al obtener info de GPU: " << e.what() << "\n";
    }
    outputFile << "\n";

    outputFile.close(); // Cierra el archivo
    std::cout << "Información recopilada y guardada en info_notebook.txt" << std::endl;

    return 0; // Retorna éxito
}
