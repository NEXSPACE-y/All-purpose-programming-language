// ALL implementation of the Windows UTF-8 virtual-directory boundary.
// Each request snapshots host cwd once. Resolution never changes process cwd.
bool cwd_from_utf8(const char *data,size_t length,std::wstring &result) {
    if(length>INT_MAX||std::memchr(data,0,length)){errno=EINVAL;return false;}
    if(!length){result.clear();return true;}
    int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,data,static_cast<int>(length),nullptr,0);
    if(!count){errno=EILSEQ;return false;}result.resize(count);
    return MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,data,static_cast<int>(length),&result[0],count)==count;
}
bool cwd_to_utf8(const std::wstring &value,std::string &result) {
    if(value.size()>INT_MAX){errno=ENAMETOOLONG;return false;}
    if(value.empty()){result.clear();return true;}
    int count=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);
    if(!count){errno=EILSEQ;return false;}result.resize(count);
    return WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),&result[0],count,nullptr,nullptr)==count;
}
int cwd_win32_errno(DWORD code) {
    switch(code){case ERROR_FILE_NOT_FOUND:case ERROR_PATH_NOT_FOUND:case ERROR_INVALID_DRIVE:return ENOENT;
    case ERROR_ACCESS_DENIED:case ERROR_SHARING_VIOLATION:return EACCES;
    case ERROR_FILENAME_EXCED_RANGE:case ERROR_BUFFER_OVERFLOW:return ENAMETOOLONG;
    case ERROR_DIRECTORY:return ENOTDIR;default:return EINVAL;}
}
std::wstring cwd_root(const std::wstring &path) {
    if(path.size()>1&&path[1]==L':')return path.substr(0,2)+L"\\";
    if(path.size()>1&&path[0]==L'\\'&&path[1]==L'\\'){
        size_t server=path.find(L'\\',2);if(server!=std::wstring::npos){size_t share=path.find(L'\\',server+1);return share==std::wstring::npos?path+L"\\":path.substr(0,share+1);}
    }return L"";
}
bool cwd_request_initialize() {
    tls.cwd_wide.clear();tls.cwd_bytes.clear();tls.drive_cwds.clear();
    DWORD needed=GetCurrentDirectoryW(0,nullptr);if(!needed){errno=cwd_win32_errno(GetLastError());return false;}
    std::vector<wchar_t> current(needed);DWORD size=GetCurrentDirectoryW(needed,current.data());
    if(!size||size>=needed){errno=EINVAL;return false;}tls.cwd_wide.assign(current.data(),size);
    if(!cwd_to_utf8(tls.cwd_wide,tls.cwd_bytes)||tls.cwd_bytes.size()>=MAXPATHLEN)return false;
    for(wchar_t drive=L'A';drive<=L'Z';++drive){
        std::wstring name=L"=";name+=drive;name+=L":";DWORD count=GetEnvironmentVariableW(name.c_str(),nullptr,0);
        if(count){std::vector<wchar_t> value(count);DWORD actual=GetEnvironmentVariableW(name.c_str(),value.data(),count);if(actual&&actual<count)tls.drive_cwds[drive]=std::wstring(value.data(),actual);}
    }
    if(tls.cwd_wide.size()>1&&tls.cwd_wide[1]==L':'){
        wchar_t drive=tls.cwd_wide[0];if(drive>=L'a'&&drive<=L'z')drive-=32;tls.drive_cwds[drive]=tls.cwd_wide;
    }return true;
}
void cwd_request_clear(){tls.cwd_wide.clear();tls.cwd_bytes.clear();tls.drive_cwds.clear();}
bool cwd_resolve(const char *input,size_t length,std::wstring &canonical,std::string &bytes) {
    if(!tls.active||tls.cwd_wide.empty()){errno=ENOENT;return false;}
    if(length>=MAXPATHLEN){errno=ENAMETOOLONG;return false;}
    std::wstring path;if(!cwd_from_utf8(input,length,path))return false;
    std::replace(path.begin(),path.end(),L'/',L'\\');
    if(path.empty())path=tls.cwd_wide;
    else if(path.size()>1&&path[1]==L':'){
        if(path.size()==2||path[2]!=L'\\'){
            wchar_t drive=path[0];if(drive>=L'a'&&drive<=L'z')drive-=32;
            auto found=tls.drive_cwds.find(drive);std::wstring base=found==tls.drive_cwds.end()?std::wstring(1,drive)+L":\\":found->second;
            path=base+(base.back()==L'\\'?L"":L"\\")+path.substr(2);
        }
    }else if(path.size()>1&&path[0]==L'\\'&&path[1]==L'\\'){}
    else if(path[0]==L'\\')path=cwd_root(tls.cwd_wide)+path.substr(1);
    else path=tls.cwd_wide+(tls.cwd_wide.back()==L'\\'?L"":L"\\")+path;
    // Input is now absolute; GetFullPathName cannot consult changing process cwd.
    DWORD needed=GetFullPathNameW(path.c_str(),0,nullptr,nullptr);
    if(!needed){errno=cwd_win32_errno(GetLastError());return false;}
    std::vector<wchar_t> full(needed);DWORD size=GetFullPathNameW(path.c_str(),needed,full.data(),nullptr);
    if(!size||size>=needed){errno=ENAMETOOLONG;return false;}
    HANDLE file=CreateFileW(full.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,nullptr);
    if(file==INVALID_HANDLE_VALUE){errno=cwd_win32_errno(GetLastError());return false;}
    DWORD final_needed=GetFinalPathNameByHandleW(file,nullptr,0,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    if(!final_needed){DWORD last=GetLastError();CloseHandle(file);errno=cwd_win32_errno(last);return false;}
    std::vector<wchar_t> resolved(final_needed+1);DWORD final_size=GetFinalPathNameByHandleW(file,resolved.data(),static_cast<DWORD>(resolved.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    DWORD last=GetLastError();CloseHandle(file);
    if(!final_size||final_size>=resolved.size()){errno=cwd_win32_errno(last);return false;}
    canonical.assign(resolved.data(),final_size);
    if(canonical.compare(0,8,L"\\\\?\\UNC\\")==0)canonical=L"\\\\"+canonical.substr(8);
    else if(canonical.compare(0,4,L"\\\\?\\")==0)canonical.erase(0,4);
    if(!cwd_to_utf8(canonical,bytes))return false;
    if(bytes.size()>=MAXPATHLEN){errno=ENAMETOOLONG;return false;}return true;
}
