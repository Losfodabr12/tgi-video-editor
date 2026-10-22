// Built against exactly the bundled whisper.cpp/ggml headers and libraries.
#include "ggml-backend.h"
#include <iostream>
#include <iomanip>
#include <string>

int main() {
    ggml_backend_load_all();
    std::cout << "[";
    int gpu_index = 0;
    bool first = true;
    for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
        auto dev = ggml_backend_dev_get(i);
        ggml_backend_dev_props props{};
        ggml_backend_dev_get_props(dev, &props);
        if (props.type != GGML_BACKEND_DEVICE_TYPE_GPU &&
            props.type != GGML_BACKEND_DEVICE_TYPE_IGPU) continue;
        const int index = gpu_index++;
        if (std::string(props.name).find("Vulkan") != 0) continue;
        if (!first) std::cout << ",";
        first = false;
        // std::quoted escapes device descriptions (driver-provided strings).
        std::cout << "{\"index\":" << index
                  << ",\"id\":" << std::quoted(props.device_id ? props.device_id : props.description)
                  << ",\"name\":" << std::quoted(props.description)
                  << ",\"engine\":" << std::quoted(props.name)
                  << ",\"discrete\":" << (props.type == GGML_BACKEND_DEVICE_TYPE_GPU ? "true" : "false")
                  << ",\"free\":" << props.memory_free
                  << ",\"total\":" << props.memory_total << "}";
    }
    std::cout << "]\n";
}
