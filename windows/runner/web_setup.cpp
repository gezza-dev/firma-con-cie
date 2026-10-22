// SPDX-License-Identifier: BSD-3-Clause
#include "web_setup.h"
#include <objbase.h>
#include <thread>
#include <filesystem>
#include "../../native/platform/windows/web/setup_policy.h"
namespace {
std::wstring wide(const std::string& s){auto n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),nullptr,0);if(n<=0)return {};std::wstring out(n,0);MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),out.data(),n);return out;}
DWORD checkSetup(const std::wstring& reader,bool package=false){
 wchar_t path[32768];auto n=GetModuleFileNameW(nullptr,path,32768);if(!n||n>=32768)return 6;
 auto directory=std::filesystem::path(path).parent_path()/L"web-component";
 auto helper=directory/L"CIE-Web-Setup.exe";
 if(GetFileAttributesW(helper.c_str())==INVALID_FILE_ATTRIBUTES)return 6;
 auto arguments=package?std::wstring(L" --status-package"):L" --check "+cie_setup::quote(reader);auto command=cie_setup::quote(helper.wstring())+arguments;
 STARTUPINFOW start{};start.cb=sizeof(start);start.dwFlags=STARTF_USESHOWWINDOW;start.wShowWindow=SW_HIDE;PROCESS_INFORMATION child{};
 if(!CreateProcessW(helper.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,directory.c_str(),&start,&child))return 6;
 CloseHandle(child.hThread);DWORD code=6;
 if(WaitForSingleObject(child.hProcess,30000)==WAIT_OBJECT_0)GetExitCodeProcess(child.hProcess,&code);
 else {TerminateProcess(child.hProcess,6);WaitForSingleObject(child.hProcess,5000);}
 CloseHandle(child.hProcess);return code;
}
}
WebSetupChannel::WebSetupChannel(flutter::BinaryMessenger* messenger,HWND){
 channel_=std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger,"cie.id/windows-web-setup",&flutter::StandardMethodCodec::GetInstance());
 channel_->SetMethodCallHandler([this](const auto& call,auto reply){
  if(call.method_name()=="checkPackage"){
   if(package_job_&&package_job_->code==STILL_ACTIVE){reply->Success(flutter::EncodableValue(true));return;}
   auto job=package_job_=std::make_shared<Job>();
   std::thread([job]{DWORD result=7;try{result=checkSetup(L"",true);}catch(...){result=7;}job->code=result;}).detach();
   reply->Success(flutter::EncodableValue(true));return;
  }
  if(call.method_name()=="packageStatus"){
   DWORD code=package_job_?package_job_->code.load():ERROR_INVALID_STATE;
   reply->Success(flutter::EncodableValue(flutter::EncodableMap{{flutter::EncodableValue("pending"),flutter::EncodableValue(code==STILL_ACTIVE)},{flutter::EncodableValue("nativeCode"),flutter::EncodableValue(static_cast<int64_t>(code))}}));return;
  }
  if(call.method_name()=="check"){
   if(job_&&job_->code==STILL_ACTIVE){reply->Error("setup_busy");return;}
   const auto* args=std::get_if<flutter::EncodableMap>(call.arguments());const std::string* value=nullptr;
   if(args){auto it=args->find(flutter::EncodableValue("reader"));if(it!=args->end())value=std::get_if<std::string>(&it->second);}
   auto reader=value&&value->size()<=16384?wide(*value):L"";if(!cie_setup::validReader(reader)){reply->Error("setup_reader_required");return;}
   auto job=job_=std::make_shared<Job>();
   std::thread([job,reader]{HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);DWORD result=7;try{result=checkSetup(reader);}catch(...){result=7;}job->code=result;if(SUCCEEDED(initialized))CoUninitialize();}).detach();
   reply->Success(flutter::EncodableValue(true));return;
  }
  if(call.method_name()=="status"){
   DWORD code=job_?job_->code.load():ERROR_INVALID_STATE;
   reply->Success(flutter::EncodableValue(flutter::EncodableMap{{flutter::EncodableValue("pending"),flutter::EncodableValue(code==STILL_ACTIVE)},{flutter::EncodableValue("nativeCode"),flutter::EncodableValue(static_cast<int64_t>(code))},{flutter::EncodableValue("ok"),flutter::EncodableValue(code==0)}}));return;
  }
  reply->NotImplemented();
 });
}
