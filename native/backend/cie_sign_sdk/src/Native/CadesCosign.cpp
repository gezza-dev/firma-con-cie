// SPDX-License-Identifier: BSD-3-Clause
#include "CadesCosign.h"
#include "SignedDocument.h"
#include <openssl/cms.h>
#include <openssl/objects.h>
#include <openssl/evp.h>
#include <string>
#include <algorithm>
#include <memory>
#include <stdexcept>
namespace cie::cades {
namespace {
void require(bool value){if(!value)throw std::runtime_error("P7M attached valido richiesto per la cofirma");}
using Cms=std::unique_ptr<CMS_ContentInfo,decltype(&CMS_ContentInfo_free)>;
Cms parse(const Bytes& data) {
 const unsigned char* p=data.data();Cms cms(d2i_CMS_ContentInfo(nullptr,&p,data.size()),CMS_ContentInfo_free);
 require(cms && p==data.data()+data.size() && OBJ_obj2nid(CMS_get0_type(cms.get()))==NID_pkcs7_signed && CMS_is_detached(cms.get())==0 && OBJ_obj2nid(CMS_get0_eContentType(cms.get()))==NID_pkcs7_data);
 auto n=sk_CMS_SignerInfo_num(CMS_get0_SignerInfos(cms.get()));require(n>0 && n<=64);
 return cms;
}
Bytes encode(CMS_ContentInfo* cms){int n=i2d_CMS_ContentInfo(cms,nullptr);require(n>0);Bytes out(n);auto* p=out.data();require(i2d_CMS_ContentInfo(cms,&p)==n);return out;}
struct Node{unsigned char tag;Bytes value;};
std::vector<Bytes> split(const Bytes& input){
 std::vector<Bytes> out;size_t p=0;
 while(p<input.size()){
  size_t start=p;unsigned tag=input[p++];require((tag&31)!=31 && p<input.size());size_t n=input[p++];
  if(n&128){size_t bytes=n&127;require(bytes>0 && bytes<=sizeof(size_t) && bytes<=input.size()-p);n=0;while(bytes--){require(n<=(size_t(-1)>>8));n=(n<<8)|input[p++];}}
  require(n<=input.size()-p);p+=n;out.emplace_back(input.begin()+start,input.begin()+p);require(out.size()<=256);
 }
 return out;
}
Node node(const Bytes& der){require(der.size()>=2);size_t p=1,n=der[p++];if(n&128){size_t bytes=n&127;require(bytes>0&&bytes<=sizeof(size_t)&&bytes<=der.size()-p);n=0;while(bytes--)n=(n<<8)|der[p++];}require(n==der.size()-p);return{der[0],Bytes(der.begin()+p,der.end())};}
Bytes wrap(unsigned char tag,const Bytes& body){Bytes out{tag};size_t n=body.size();if(n<128)out.push_back(n);else{Bytes len;while(n){len.insert(len.begin(),n&255);n>>=8;}out.push_back(128|len.size());out.insert(out.end(),len.begin(),len.end());}out.insert(out.end(),body.begin(),body.end());return out;}
Bytes join(const std::vector<Bytes>& fields){Bytes out;for(auto& f:fields)out.insert(out.end(),f.begin(),f.end());return out;}
std::vector<Bytes> fields(const Bytes& cms){auto outer=split(node(cms).value);require(outer.size()==2&&node(outer[1]).tag==0xa0);auto sd=node(node(outer[1]).value);require(sd.tag==0x30);auto f=split(sd.value);require(f.size()>=4&&f.size()<=6&&node(f.back()).tag==0x31);return f;}
Bytes united(unsigned char tag,const Bytes& a,const Bytes& b){auto values=split(node(a).value),more=split(node(b).value);values.insert(values.end(),more.begin(),more.end());std::sort(values.begin(),values.end());values.erase(std::unique(values.begin(),values.end()),values.end());return wrap(tag,join(values));}
Bytes optional(const std::vector<Bytes>& f,unsigned char tag){for(size_t i=3;i+1<f.size();i++)if(node(f[i]).tag==tag)return f[i];return wrap(tag,{});}
}
namespace {
Bytes decode(const void* data,size_t size){
 const auto* input=static_cast<const unsigned char*>(data);if(input[0]==0x30)return Bytes(input,input+size);
 std::string text(reinterpret_cast<const char*>(input),size);
 auto whitespace=[](char c){return c==' '||c=='\t'||c=='\r'||c=='\n';};
 const auto first=text.find_first_not_of(" \t\r\n"),last=text.find_last_not_of(" \t\r\n");require(first!=std::string::npos);text=text.substr(first,last-first+1);
 if(text.rfind("-----BEGIN ",0)==0){bool matched=false;for(auto name:{"CMS","PKCS7"}){auto head=std::string("-----BEGIN ")+name+"-----",tail=std::string("-----END ")+name+"-----";
  if(text.rfind(head,0)==0 && text.size()>=head.size()+tail.size() && text.substr(text.size()-tail.size())==tail){text=text.substr(head.size(),text.size()-head.size()-tail.size());matched=true;break;}}
  require(matched);
 }
 text.erase(std::remove_if(text.begin(),text.end(),whitespace),text.end());require(!text.empty()&&text.size()%4==0);
 const auto padding=text.back()=='='?(text[text.size()-2]=='='?2u:1u):0u;
 for(size_t i=0;i<text.size()-padding;i++){auto c=text[i];require((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='+'||c=='/');}
 Bytes output(text.size()/4*3);int n=EVP_DecodeBlock(output.data(),reinterpret_cast<const unsigned char*>(text.data()),text.size());require(n>=0&&static_cast<unsigned>(n)>=padding);output.resize(n-padding);return output;
}
}
Bytes canonical(const void* data,size_t size){
 require(data&&size>0&&size<=256*1024*1024);Bytes bytes=decode(data,size);auto cms=parse(bytes);
 std::unique_ptr<BIO,decltype(&BIO_free)> sink(BIO_new(BIO_s_null()),BIO_free);
 require(sink && CMS_verify(cms.get(),nullptr,nullptr,nullptr,sink.get(),CMS_BINARY|CMS_NO_SIGNER_CERT_VERIFY)==1);
 auto encoded=encode(cms.get());
 // A valid OpenSSL CMS may use an algorithm/identifier the legacy SDK cannot
 // report. Refuse it before card authentication instead of failing afterward.
 CSignedDocument legacy(encoded.data(),encoded.size());
 for(unsigned i=0;i<count(encoded);i++){const int status=legacy.verify(i,static_cast<REVOCATION_INFO*>(nullptr));require(status>=0 && (status&VERIFIED_SIGNATURE)!=0);}
 return encoded;
}
Bytes content(const Bytes& bytes){auto cms=parse(bytes);auto p=CMS_get0_content(cms.get());require(p&&*p&&ASN1_STRING_length(*p)>0);auto data=ASN1_STRING_get0_data(*p);return Bytes(data,data+ASN1_STRING_length(*p));}
unsigned count(const Bytes& bytes){auto cms=parse(bytes);return sk_CMS_SignerInfo_num(CMS_get0_SignerInfos(cms.get()));}
Bytes merge(const Bytes& original,const Bytes& fresh){
 require(content(original)==content(fresh));auto a=fields(original),b=fields(fresh);require(count(fresh)==1&&count(original)<64);
 auto version=node(a[0]).value,other=node(b[0]).value;require(version.size()==1&&other.size()==1);a[0]=wrap(2,{std::max(version[0],other[0])});
 std::vector<Bytes> out{a[0],united(0x31,a[1],b[1]),a[2]};
 auto certs=united(0xa0,optional(a,0xa0),optional(b,0xa0));if(!node(certs).value.empty())out.push_back(certs);
 auto crls=optional(a,0xa1);if(!node(crls).value.empty())out.push_back(crls);
 out.push_back(united(0x31,a.back(),b.back()));auto outer=split(node(original).value);
 auto result=wrap(0x30,join({outer[0],wrap(0xa0,wrap(0x30,join(out)))}));
 require(count(result)==count(original)+1 && preserves(original,result));return canonical(result.data(),result.size());
}
bool preserves(const Bytes& original,const Bytes& result){
 try{if(content(original)!=content(result)||count(result)!=count(original)+1)return false;auto a=fields(original),b=fields(result);
 if(a[2]!=b[2]||optional(a,0xa1)!=optional(b,0xa1))return false;
 for(auto tag:{0x31,0xa0}){auto old=split(node(tag==0x31?a.back():optional(a,tag)).value);auto now=split(node(tag==0x31?b.back():optional(b,tag)).value);for(auto& item:old)if(std::find(now.begin(),now.end(),item)==now.end())return false;}
 return true;}catch(...){return false;}
}
}
