// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <algorithm>
#include <cstdint>
#include <istream>
#include <stdexcept>
#include <string>
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#endif
namespace cie {
// Plain values only. Credentials never enter files, command lines or diagnostics.
struct NetworkConfig {
 int mode=0, port=0; // 0 direct, 1 HTTP proxy, 2 HTTPS proxy
 std::string host, user, password;
 static std::string bounded(const char* p,size_t maximum) {
  if(!p)return {};size_t n=0;while(n<=maximum&&p[n])++n;
  if(n>maximum)throw std::invalid_argument("network_config_invalid");
  std::string s(p,n);for(unsigned char c:s)if(c<32||c==127)throw std::invalid_argument("network_config_invalid");return s;
 }
 static bool validHost(const std::string& h) {
  if(h.empty()||h.size()>253)return false;
  if(h.front()=='['&&h.back()==']'){unsigned char bytes[16];auto address=h.substr(1,h.size()-2);return address.find('%')==std::string::npos&&inet_pton(AF_INET6,address.c_str(),bytes)==1;}
  if(h.front()=='.'||h.back()=='.'||h.find("..")!=std::string::npos)return false;
  size_t start=0;while(start<h.size()){auto end=h.find('.',start);if(end==std::string::npos)end=h.size();if(end-start>63||h[start]=='-'||h[end-1]=='-')return false;start=end+1;}
  return std::all_of(h.begin(),h.end(),[](unsigned char c){return(c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='.'||c=='-';});
 }
 static NetworkConfig from(int mode,const char* host,int port,const char* user,const char* password) {
  NetworkConfig n;n.mode=mode;n.port=port;n.host=bounded(host,253);n.user=bounded(user,256);n.password=bounded(password,1024);
  if(mode<0||mode>2||(mode==0&&(!n.host.empty()||port||!n.user.empty()||!n.password.empty()))||
    (mode!=0&&(!validHost(n.host)||port<1||port>65535))||n.user.find(':')!=std::string::npos||(!n.password.empty()&&n.user.empty()))throw std::invalid_argument("network_config_invalid");
  return n;
 }
 std::string endpoint()const{return mode==0?"":std::string(mode==2?"https://":"http://")+host;}
 std::string credentials()const{return user.empty()?"":user+":"+password;}
 std::string wire()const{return "CIE-NETWORK-1\n"+std::to_string(mode)+"\n"+host+"\n"+std::to_string(port)+"\n"+user+"\n"+password+"\n";}
 static NetworkConfig read(std::istream& input){
  std::string fields[6];size_t total=0;
  for(auto& field:fields){char c;bool ended=false;while(input.get(c)){if(++total>4096)throw std::invalid_argument("network_config_invalid");if(c=='\n'){ended=true;break;}field+=c;}if(!ended)throw std::invalid_argument("network_config_invalid");}
  if(fields[0]!="CIE-NETWORK-1"||input.peek()!=std::char_traits<char>::eof())throw std::invalid_argument("network_config_invalid");
  auto number=[](const std::string& s){if(s.empty()||s.size()>5||!std::all_of(s.begin(),s.end(),[](char c){return c>='0'&&c<='9';}))throw std::invalid_argument("network_config_invalid");return std::stoi(s);};
  return from(number(fields[1]),fields[2].c_str(),number(fields[3]),fields[4].c_str(),fields[5].c_str());
 }
 ~NetworkConfig(){for(auto* s:{&user,&password}){volatile char* p=s->empty()?nullptr:&(*s)[0];for(size_t i=0;i<s->size();i++)p[i]=0;}}
};
}
