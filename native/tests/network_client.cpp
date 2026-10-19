// SPDX-License-Identifier: BSD-3-Clause
// Loopback harness client; not part of the app's user-facing network API.
#include "NetworkConfig.h"
#include "HttpClient.h"
#include <iostream>
int main(int argc,char** argv){
 try{
  if(argc!=4)return 2;
  auto n=cie::NetworkConfig::read(std::cin);cie::HttpOptions options;
  options.proxy=n.endpoint();options.proxyPort=n.port;options.proxyCredentials=n.credentials();
  options.publicAddressesOnly=std::string(argv[2])=="1";options.head=std::string(argv[3])=="1";
  options.budget=std::make_shared<cie::HttpBudget>();options.budget->deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  auto r=cie::httpRequest(argv[1],{},nullptr,options,1024);
  std::cout<<"{\"transportCode\":"<<r.error<<",\"httpStatus\":"<<r.status<<",\"bytes\":"<<r.body.size()<<"}\n";
  std::cout.write(reinterpret_cast<const char*>(r.body.data()),r.body.size());return 0;
 }catch(...){return 2;}
}
