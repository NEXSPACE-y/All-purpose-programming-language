// Test-only translation unit. Production cores do not export this setter.
#include "generated02/callback/src/Runtime.cpp"
extern "C" __declspec(dllexport) int all_info_v2_contract_set_error(const unsigned char *bytes,size_t length) {
    if(length&&!bytes){error("Error","Invalid synthetic contract pointer");return -1;}
    std::string message;if(length)message.assign(reinterpret_cast<const char*>(bytes),length);
    error("TypeError",message);return 0;
}
