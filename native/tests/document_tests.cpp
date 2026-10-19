// SPDX-License-Identifier: BSD-3-Clause
#include "cie_bridge.h"
#include "pdf_appearance.h"
#include "visible_output.h"
#include "card_number.h"
#include "Native/CardholderName.h"
#include "Native/SigningTime.h"
#include "PdfSignatureGenerator.h"
#include "disigonsdk.h"
#include <podofo/podofo.h>
#include <openssl/cms.h>
#include <openssl/x509.h>
#include <png.h>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <limits>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif
using PrepareAppearance=int (*)(const char*,const CiePdfAppearance*,CiePdfAppearance*);
static PrepareAppearance cie_document_prepare_appearance=nullptr;
namespace fs=std::filesystem;
static unsigned checks=0;
static void require(bool value,const char* message) {++checks;if(!value)throw std::runtime_error(message);}
static std::string call(char* p) {require(p,"Missing JSON");std::string s(p);cie_bridge_free(p);return s;}
static bool ok(const std::string& s){return s.find("\"ok\":true")!=std::string::npos;}
static std::vector<char> read(const fs::path& path) {std::ifstream f(path,std::ios::binary);return {std::istreambuf_iterator<char>(f),{}};}
static void write(const fs::path& path,const std::vector<char>& data){std::ofstream f(path,std::ios::binary);f.write(data.data(),data.size());require(f.good(),"Fixture write failed");}
int main(int argc,char**argv) {
    try {
        require(argc>=2,"Backend path required");
        const bool keep=argc>=3;
        fs::path folder=keep ? fs::u8path(argv[2]) : fs::temp_directory_path()/fs::u8path("cie-document-test-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
        fs::create_directories(folder);
        struct Cleanup{fs::path path;bool keep;~Cleanup(){if(!keep){std::error_code ec;fs::remove_all(path,ec);}}} cleanup{folder,keep};
        require(ok(call(cie_bridge_load(argv[1],""))),"Backend load failed");
#ifdef _WIN32
        auto module=LoadLibraryW(fs::u8path(argv[1]).wstring().c_str());
        cie_document_prepare_appearance=reinterpret_cast<PrepareAppearance>(GetProcAddress(module,"cie_document_prepare_appearance"));
#else
        auto module=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
        cie_document_prepare_appearance=reinterpret_cast<PrepareAppearance>(dlsym(module,"cie_document_prepare_appearance"));
#endif
        require(cie_document_prepare_appearance!=nullptr,"Missing appearance function");
        PoDoFo::PdfMemDocument document;
        for(int rotation:{0,90,180,270}) {
            auto& page=document.GetPages().CreatePage(PoDoFo::Rect(0,0,600,850));
            page.SetCropBox(PoDoFo::Rect(40,70,400,600));page.SetRotation(rotation);
        }
        PoDoFo::charbuff pdf;PoDoFo::BufferStreamDevice device(pdf);document.Save(device);
        fs::path source=folder/"source.pdf";write(source,{pdf.begin(),pdf.end()});
        auto visibleOutput=folder/"visibility-fixture.pdf";write(visibleOutput,{'P','D','F'});
#ifdef __APPLE__
        require(chflags(visibleOutput.c_str(),UF_HIDDEN|UF_NODUMP)==0,"Could not create hidden test inode");
#endif
        cie::makeOutputVisible(visibleOutput);
        require(read(visibleOutput)==std::vector<char>({'P','D','F'}),"Visibility changed output bytes");
#ifdef __APPLE__
        struct stat visibleStat{};require(stat(visibleOutput.c_str(),&visibleStat)==0&&!(visibleStat.st_flags&UF_HIDDEN)&&(visibleStat.st_flags&UF_NODUMP),"Visibility must clear hidden only");
#endif
        {
          cie::OutputStaging staging(folder,"pdf");
          require(staging.file.filename().u8string().front()!='.'&&staging.file.parent_path().filename().u8string().front()!='.',"Hidden staging name");
          write(staging.file,{'P','D','F'});
          auto final=folder/"published-visible.pdf";require(!staging.publish(final),"No-replace publish failed");
          require(!fs::exists(staging.file)&&read(final)==std::vector<char>({'P','D','F'}),"Published bytes/source lifetime incorrect");
          write(staging.file,{'N','E','W'});require(bool(staging.publish(final)),"Existing destination overwritten");
          require(read(final)==std::vector<char>({'P','D','F'}),"Existing PDF altered");
        }
        {
          auto final=folder/"replace-visible.pdf";write(final,{'O','L','D'});
          cie::OutputStaging staging(folder,"pdf");staging.prepareReplacement(final);
          write(staging.file,{'N','E','W'});
          write(final,{'E','D','I','T'});
          require(bool(staging.publish(final,true)),"Changed destination replaced");
          require(read(final)==std::vector<char>({'E','D','I','T'}),"Concurrent edit lost");
        }
        {
          auto final=folder/"replace-visible.pdf";
          cie::OutputStaging staging(folder,"pdf");staging.prepareReplacement(final);
          write(staging.file,{'N','E','W'});
          require(!staging.publish(final,true),"Explicit replacement failed");
          require(read(final)==std::vector<char>({'N','E','W'})&&!fs::exists(staging.file),"Replacement bytes wrong");
        }
        fs::path image=folder/"signature.png";png_image png{};png.version=PNG_IMAGE_VERSION;png.width=png.height=2;png.format=PNG_FORMAT_RGBA;
        unsigned char pixels[]={255,0,0,255,0,255,0,255,0,0,255,255,0,0,0,0};
        require(png_image_write_to_file(&png,image.u8string().c_str(),0,pixels,0,nullptr)==1,"PNG fixture failed");
        EVP_PKEY_CTX* kctx=EVP_PKEY_CTX_new_from_name(nullptr,"RSA",nullptr);EVP_PKEY* key=nullptr;
        require(kctx && EVP_PKEY_keygen_init(kctx)==1 && EVP_PKEY_CTX_set_rsa_keygen_bits(kctx,2048)==1 && EVP_PKEY_keygen(kctx,&key)==1,"Test key failed");EVP_PKEY_CTX_free(kctx);
        std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)> keyGuard(key,EVP_PKEY_free);
        std::unique_ptr<X509,decltype(&X509_free)> cert(X509_new(),X509_free);X509_set_version(cert.get(),2);ASN1_INTEGER_set(X509_get_serialNumber(cert.get()),17);
        X509_gmtime_adj(X509_getm_notBefore(cert.get()),-60);X509_gmtime_adj(X509_getm_notAfter(cert.get()),3600);X509_set_pubkey(cert.get(),key);
        X509_NAME_add_entry_by_txt(X509_get_subject_name(cert.get()),"CN",MBSTRING_ASC,reinterpret_cast<const unsigned char*>("Prototype document fixture"),-1,-1,0);
        X509_NAME_add_entry_by_txt(X509_get_subject_name(cert.get()),"givenName",MBSTRING_UTF8,reinterpret_cast<const unsigned char*>(u8"Léa Maria"),-1,-1,0);
        X509_NAME_add_entry_by_txt(X509_get_subject_name(cert.get()),"surname",MBSTRING_UTF8,reinterpret_cast<const unsigned char*>("D'Amico"),-1,-1,0);
        X509_NAME_add_entry_by_txt(X509_get_subject_name(cert.get()),"serialNumber",MBSTRING_ASC,reinterpret_cast<const unsigned char*>("IDCIT-CA00000AA"),-1,-1,0);
        X509_set_issuer_name(cert.get(),X509_get_subject_name(cert.get()));require(X509_sign(cert.get(),key,EVP_sha256())>0,"Test certificate failed");
        auto labelFor=[&](X509* certificate){int n=i2d_X509(certificate,nullptr);std::vector<unsigned char> bytes(n);auto* p=bytes.data();i2d_X509(certificate,&p);return cie::cardholderName(bytes.data(),bytes.size());};
        int certLength=i2d_X509(cert.get(),nullptr);std::vector<unsigned char> certDer(certLength);auto* certPos=certDer.data();i2d_X509(cert.get(),&certPos);
        const char digits[]="0123456789abcdef";std::string certHex;for(auto b:certDer){certHex+=digits[b>>4];certHex+=digits[b&15];}
        auto parsedName=call(cie_bridge_certificate_name(certHex.c_str()));require(ok(parsedName)&&parsedName.find(u8"Léa Maria D'Amico")!=std::string::npos,"Read-only public certificate name failed");
        require(parsedName.find("\"cardNumber\":\"CA00000AA\"")!=std::string::npos,"Printed number missing from public certificate metadata");
        auto numberFor=[&](X509* c){require(X509_sign(c,key,EVP_sha256())>0,"Number fixture signing failed");int n=i2d_X509(c,nullptr);std::vector<unsigned char> bytes(n);auto* p=bytes.data();i2d_X509(c,&p);return cie::certificateCardNumber(bytes.data(),bytes.size());};
        std::unique_ptr<X509,decltype(&X509_free)> numberCert(X509_dup(cert.get()),X509_free);
        require(numberFor(numberCert.get())=="CA00000AA","Printed card number differs from certificate");
        auto* numberSubject=X509_get_subject_name(numberCert.get());
        for(const auto* value:{"TINIT-AAAAAAAAAAAAAAAA","IDCIT-123456789012","IDCIT-CA00X00AA","IDCIT-ca00000aa","IDCIT-CA00000AAextra"}){
          int i=X509_NAME_get_index_by_NID(numberSubject,NID_serialNumber,-1);X509_NAME_ENTRY_free(X509_NAME_delete_entry(numberSubject,i));
          X509_NAME_add_entry_by_txt(numberSubject,"serialNumber",MBSTRING_ASC,reinterpret_cast<const unsigned char*>(value),-1,-1,0);
          require(numberFor(numberCert.get()).empty(),"Tax code, PAN or malformed number mislabelled as printed card number");
        }
        X509_NAME_add_entry_by_txt(numberSubject,"serialNumber",MBSTRING_ASC,reinterpret_cast<const unsigned char*>("IDCIT-CA00000AA"),-1,-1,0);
        require(numberFor(numberCert.get()).empty(),"Ambiguous card number accepted");
        require(cie::certificateCardNumber(nullptr,0).empty(),"Missing certificate gave card number");
        for(const auto* bad:{"", "f", "zz", "300100"})require(!ok(call(cie_bridge_certificate_name(bad))),"Malformed public certificate accepted");
        auto holder=labelFor(cert.get());require(holder==u8"Léa Maria D'Amico","Full card name order/UTF8 failed");
        std::unique_ptr<X509,decltype(&X509_free)> other(X509_dup(cert.get()),X509_free);
        auto* subject=X509_get_subject_name(other.get());int index=X509_NAME_get_index_by_NID(subject,NID_surname,-1);
        X509_NAME_ENTRY_free(X509_NAME_delete_entry(subject,index));
        X509_NAME_add_entry_by_txt(subject,"surname",MBSTRING_UTF8,reinterpret_cast<const unsigned char*>("Rossi"),-1,-1,0);
        require(X509_sign(other.get(),key,EVP_sha256())>0,"Changed fixture certificate");
        require(labelFor(other.get())==u8"Léa Maria Rossi","Label reused another certificate identity");
        X509_NAME_add_entry_by_txt(subject,"surname",MBSTRING_UTF8,reinterpret_cast<const unsigned char*>("Duplicate"),-1,-1,0);
        require(X509_sign(other.get(),key,EVP_sha256())>0,"Ambiguous fixture certificate");
        bool refused=false;try{labelFor(other.get());}catch(...){refused=true;}require(refused,"Duplicate surname accepted");
        while((index=X509_NAME_get_index_by_NID(subject,NID_surname,-1))>=0)X509_NAME_ENTRY_free(X509_NAME_delete_entry(subject,index));
        require(X509_sign(other.get(),key,EVP_sha256())>0,"Missing name fixture certificate");
        refused=false;try{labelFor(other.get());}catch(...){refused=true;}require(refused,"CN substituted for missing surname");
        refused=false;try{cie::cardholderName(nullptr,0);}catch(...){refused=true;}require(refused,"Missing certificate accepted");
        auto cms=[&](const char* bytes,size_t length,bool detached) {
            std::unique_ptr<BIO,decltype(&BIO_free)> bio(BIO_new_mem_buf(bytes,int(length)),BIO_free);
            std::unique_ptr<CMS_ContentInfo,decltype(&CMS_ContentInfo_free)> value(CMS_sign(cert.get(),key,nullptr,bio.get(),CMS_BINARY|(detached?CMS_DETACHED:0)),CMS_ContentInfo_free);
            require(bool(value),"CMS fixture failed");int size=i2d_CMS_ContentInfo(value.get(),nullptr);std::vector<char> out(size);auto* p=reinterpret_cast<unsigned char*>(out.data());require(i2d_CMS_ContentInfo(value.get(),&p)==size,"CMS encoding failed");return out;
        };
        // Real parsers, misleading extensions, attachedInput/detachedInput/corrupt CMS.
        auto preflight=[&](const fs::path& p){return call(cie_bridge_signing_info(p.u8string().c_str()));};
        auto documentInfo=preflight(source);
        require(ok(documentInfo)&&documentInfo.find("\"pdfSupported\":true")!=std::string::npos,"Real PDF not recognized");
        auto disguisedInput=folder/"document.txt";write(disguisedInput,read(source));
        require(preflight(disguisedInput).find("\"pdfSupported\":true")!=std::string::npos,"PDF eligibility depends on filename");
        auto invalidInput=folder/"not-a-pdf.pdf";write(invalidInput,{'n','o'});
        require(preflight(invalidInput).find("\"pdfSupported\":false")!=std::string::npos,"Suffix accepted as PDF");
        auto attachedInput=folder/"attachedInput.p7m";write(attachedInput,cms("content",7,false));
        require(preflight(attachedInput).find("\"cosignSupported\":true")!=std::string::npos,"Valid attachedInput CMS refused");
        auto detachedInput=folder/"detachedInput.p7m";write(detachedInput,cms("content",7,true));
        require(preflight(detachedInput).find("\"cosignSupported\":false")!=std::string::npos,"Detached CMS allowed for co-signing");
        auto corrupt=read(attachedInput);corrupt.back()^=1;write(attachedInput,corrupt);
        require(preflight(attachedInput).find("\"cosignSupported\":false")!=std::string::npos,"Corrupted signature allowed for co-signing");
        require(!ok(preflight(folder/"missing.pdf")),"Missing input accepted");
        for(int page=0;page<4;page++) {
            auto info=call(cie_bridge_pdf_info(source.u8string().c_str(),page));require(ok(info)&&info.find("\"pageCount\":4")!=std::string::npos,"PDF metadata failed");
            auto imagePath=image.u8string();CiePdfAppearance a{sizeof(a),page,.13,.27,.31,.12,imagePath.c_str()},raw{};
            require(cie_document_prepare_appearance(source.u8string().c_str(),&a,&raw)==0,"PDF appearance preflight failed");
            auto expected=a;
            require(std::abs(raw.left-expected.left)<1e-8 && std::abs(raw.top-expected.top)<1e-8,"Displayed rectangle changed during preflight");
            PdfSignatureGenerator generator;require(generator.Load(pdf.data(),pdf.size())==0,"SDK PDF loading failed");
            generator.InitSignature(page,float(raw.left),float(raw.top+raw.height),float(raw.width),float(raw.height),"Prototype",nullptr,"Fixture",nullptr,nullptr,nullptr,"Visible","ETSI.CAdES.detached",page%2?imagePath.c_str():nullptr,holder.c_str(),nullptr,nullptr);
            UUCByteArray bytes;generator.GetBufferForSignature(bytes);auto signedBytes=cms(reinterpret_cast<const char*>(bytes.getContent()),bytes.getLength(),true);generator.SetSignature(signedBytes.data(),signedBytes.size());UUCByteArray result;generator.GetSignedPdf(result);
            auto output=folder/("visible-"+std::to_string(page*90)+".pdf");write(output,{reinterpret_cast<const char*>(result.getContent()),reinterpret_cast<const char*>(result.getContent())+result.getLength()});
            PoDoFo::PdfMemDocument reopened;reopened.LoadFromBuffer(PoDoFo::bufferview(reinterpret_cast<const char*>(result.getContent()),result.getLength()));
            auto& signedPage=reopened.GetPages().GetPageAt(page);
            auto rect=PoDoFo::Rect::FromCorners(signedPage.GetAnnotations().GetAnnotAt(0).GetRectRaw());
            const double cx=40,cy=70,cw=400,ch=600;
            double x,y,w,h;
            switch(page) {
              case 0:x=cx+a.left*cw;y=cy+(1-a.top-a.height)*ch;w=a.width*cw;h=a.height*ch;break;
              case 1:x=cx+a.top*cw;y=cy+a.left*ch;w=a.height*cw;h=a.width*ch;break;
              case 2:x=cx+(1-a.left-a.width)*cw;y=cy+a.top*ch;w=a.width*cw;h=a.height*ch;break;
              default:x=cx+(1-a.top-a.height)*cw;y=cy+(1-a.left-a.width)*ch;w=a.height*cw;h=a.width*ch;break;
            }
            require(std::abs(rect.X-x)<.01 && std::abs(rect.Y-y)<.01,"Raw PDF signature placement failed");
            require(std::abs(rect.Width-w)<.01 && std::abs(rect.Height-h)<.01,"Raw PDF signature dimensions failed");
            auto* appearanceObject=signedPage.GetAnnotations().GetAnnotAt(0).GetAppearanceStream();
            std::unique_ptr<PoDoFo::PdfXObjectForm> form;
            require(appearanceObject&&PoDoFo::PdfXObject::TryCreateFromObject(*appearanceObject,form),"Missing rendered appearance form");
            auto& flattened=reopened.GetPages().CreatePage(PoDoFo::Rect(0,0,600,850));
            PoDoFo::PdfPainter painter;painter.SetCanvas(flattened);painter.DrawXObject(*form,10,10);painter.FinishDrawing();
            std::vector<PoDoFo::PdfTextEntry> entries;flattened.ExtractTextTo(entries,PoDoFo::PdfTextExtractParams{});
            std::string appearanceText;for(auto& entry:entries)appearanceText+=entry.Text;
            std::string drawing;
            for(auto* object:reopened.GetObjects())if(object->HasStream()){
                PoDoFo::charbuff contents;object->GetStream()->CopyTo(contents);
                drawing.append(contents.begin(),contents.end());
            }
            require(drawing.find(" d")!=std::string::npos && drawing.find(" re")!=std::string::npos,"Dashed signature border missing");
            require(appearanceText.find("Firmato digitalmente da/Signed by:")!=std::string::npos&&appearanceText.find("In Data/On Date:")!=std::string::npos,"Bilingual appearance captions missing");
            require(appearanceText.find(holder)!=std::string::npos,"Rendered label differs from certificate name/surname");
            require(appearanceText.find(" UTC")!=std::string::npos,"Rendered signing date missing");
            auto signatureDate=signedPage.GetAnnotations().GetAnnotAt(0).GetObject().GetDictionary().FindKey("V")->GetDictionary().FindKey("M")->GetString().GetString();
            require(signatureDate.size()>=16,"PDF signature date missing");
            const auto parsedDate=PoDoFo::PdfDate::Parse(signatureDate);
            require(parsedDate.GetMinutesFromUtc().has_value(),"PDF signature date has no UTC offset");
            const auto zoneLabel=cie::utcOffsetLabel(int(parsedDate.GetMinutesFromUtc()->count()));
            const auto expectedDate=std::string(signatureDate.substr(8,2))+"/"+std::string(signatureDate.substr(6,2))+"/"+std::string(signatureDate.substr(2,4))+" "+std::string(signatureDate.substr(10,2))+":"+std::string(signatureDate.substr(12,2))+":"+std::string(signatureDate.substr(14,2))+" "+zoneLabel;
            require(appearanceText.find(expectedDate)!=std::string::npos,"Visible date differs from signature metadata");
            auto verification=call(cie_bridge_verify(output.u8string().c_str()));require(ok(verification)&&verification.find("\"signatureValid\":true")!=std::string::npos,"Visible PDF signature invalid");
        }
        CiePdfAppearance textOnly{sizeof(textOnly),0,.1,.1,.3,.1,CIE_PDF_CARDHOLDER_NAME},textRaw{};
        require(cie_document_prepare_appearance(source.u8string().c_str(),&textOnly,&textRaw)==0,"Cardholder text-only mode rejected");
        textOnly.imagePath="cie:unknown-mode";
        require(cie_document_prepare_appearance(source.u8string().c_str(),&textOnly,&textRaw)!=0,"Unknown appearance mode accepted");
        require(!ok(call(cie_bridge_pdf_info(source.u8string().c_str(),4))),"Out-of-range PDF page accepted");
        auto imagePath=image.u8string();CiePdfAppearance invalid{sizeof(invalid),0,0,0,.3,.1,imagePath.c_str()},raw{};
        invalid.width=std::numeric_limits<double>::quiet_NaN();require(cie_document_prepare_appearance(source.u8string().c_str(),&invalid,&raw)!=0,"NaN accepted");
        invalid.width=.3;invalid.left=.9;require(cie_document_prepare_appearance(source.u8string().c_str(),&invalid,&raw)!=0,"Out-of-page rectangle accepted");
        auto badImage=folder/"invalid.png";write(badImage,{'b','a','d'});auto badImagePath=badImage.u8string();
        invalid.left=.1;invalid.imagePath=badImagePath.c_str();require(cie_document_prepare_appearance(source.u8string().c_str(),&invalid,&raw)!=0,"Malformed PNG accepted");
        auto attached=folder/"document.pdf.p7m";write(attached,cms(pdf.data(),pdf.size(),false));auto extracted=folder/"extracted.pdf";
        auto extraction=call(cie_bridge_extract(attached.u8string().c_str(),extracted.u8string().c_str()));require(ok(extraction)&&extraction.find("\"integrityChecked\":false")!=std::string::npos,"CMS extraction failed");require(read(extracted)==std::vector<char>(pdf.begin(),pdf.end()),"Extracted bytes differ");
        auto before=read(extracted);require(!ok(call(cie_bridge_extract(attached.u8string().c_str(),extracted.u8string().c_str()))),"Existing extraction overwritten");require(read(extracted)==before,"Existing output changed");
        auto detached=folder/"detached.p7m";write(detached,cms(pdf.data(),pdf.size(),true));auto rejected=folder/"rejected.pdf";
        require(!ok(call(cie_bridge_extract(detached.u8string().c_str(),rejected.u8string().c_str())))&&!fs::exists(rejected),"Detached CMS extracted");
        auto bad=folder/"malformed.p7m";write(bad,{'b','a','d'});require(!ok(call(cie_bridge_extract(bad.u8string().c_str(),rejected.u8string().c_str())))&&!fs::exists(rejected),"Malformed CMS extracted");
        for(const auto& p:fs::directory_iterator(folder))require(p.path().filename().u8string().find(".cie-extract-")!=0,"Extraction temporary file leaked");
        std::cout<<"DOCUMENT_FEATURE_CHECKS="<<checks<<"\nPDF rotations/CropBox, visible signatures, metadata, CMS extraction/detached rejection/no overwrite passed; no card accessed\n";
        return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
