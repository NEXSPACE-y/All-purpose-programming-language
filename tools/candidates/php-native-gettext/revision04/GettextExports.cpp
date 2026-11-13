ZEND_API void zend_argument_value_error(uint32_t number,const char *message_format,...) {
    hit("zend_argument_value_error");if(!tls.error.empty())return;
    va_list arguments;va_start(arguments,message_format);std::string message=format(message_format,arguments);va_end(arguments);
    std::string name;
    if(tls.current&&tls.current->func&&number>0&&number<=tls.current->func->common.num_args){
        auto *info=tls.current->func->internal_function.arg_info;if(info&&info[number-1].name)name=info[number-1].name;
    }
    error("ValueError",callable()+"(): Argument #"+std::to_string(number)+(name.empty()?"":" ($"+name+")")+" "+message);
}
ZEND_API void zend_argument_must_not_be_empty_error(uint32_t number) {
    hit("zend_argument_must_not_be_empty_error");zend_argument_value_error(number,"must not be empty");
}
CWD_API char *virtual_getcwd(char *buffer,size_t size) {
    hit("virtual_getcwd");if(!tls.active||tls.cwd_bytes.empty()){errno=ENOENT;return nullptr;}
    size_t length=tls.cwd_bytes.size();
    if(!buffer){buffer=static_cast<char*>(allocate(length+1,true));if(!buffer){errno=ENOMEM;return nullptr;}}
    else if(size<=length){errno=ERANGE;return nullptr;}
    std::memcpy(buffer,tls.cwd_bytes.data(),length);buffer[length]=0;return buffer;
}
CWD_API char *virtual_realpath(const char *path,char *resolved) {
    hit("virtual_realpath");if(!path||!resolved){errno=EINVAL;return nullptr;}
    std::wstring canonical;std::string bytes;if(!cwd_resolve(path,std::strlen(path),canonical,bytes))return nullptr;
    std::memcpy(resolved,bytes.data(),bytes.size());resolved[bytes.size()]=0;return resolved;
}
int all_php_virtual_cwd_set(const unsigned char *path,size_t length) {
    clear_error();if(!callback_owner_valid())return -1;
    if(!tls.active||!path){error("Error","Virtual directory requires an active request and a path");return -1;}
    std::wstring canonical;std::string bytes;
    if(!cwd_resolve(reinterpret_cast<const char*>(path),length,canonical,bytes)){error("Error","Virtual directory resolution failed, errno "+std::to_string(errno));return -1;}
    DWORD attributes=GetFileAttributesW(canonical.c_str());
    if(attributes==INVALID_FILE_ATTRIBUTES){
        const DWORD failure=GetLastError();errno=cwd_win32_errno(failure);
        error("Error","Virtual directory attribute query failed, errno "+std::to_string(errno));return -1;
    }
    if(!(attributes&FILE_ATTRIBUTE_DIRECTORY)){errno=ENOTDIR;error("Error","Virtual directory is not a directory");return -1;}
    tls.cwd_wide=std::move(canonical);tls.cwd_bytes=std::move(bytes);
    if(tls.cwd_wide.size()>1&&tls.cwd_wide[1]==L':'){wchar_t drive=tls.cwd_wide[0];if(drive>=L'a'&&drive<=L'z')drive-=32;tls.drive_cwds[drive]=tls.cwd_wide;}
    return 0;
}
const char *all_php_virtual_cwd_get(size_t *length) {
    if(length)*length=0;if(!callback_owner_valid()||!tls.active)return nullptr;
    if(length)*length=tls.cwd_bytes.size();return tls.cwd_bytes.data();
}
