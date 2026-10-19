// SPDX-License-Identifier: BSD-3-Clause
#import <CryptoTokenKit/CryptoTokenKit.h>
#import <Security/Security.h>
#import <os/log.h>
#import <CommonCrypto/CommonDigest.h>
#include "cie_web.h"
#include "web_policy.h"
#include "web_sign_request.h"

static BOOL Fail(NSError **error,NSInteger code,NSString *message) {
 os_log_error(OS_LOG_DEFAULT,"CIE prototype token failed: code=%{public}ld reason=%{public}@",(long)code,message);
 if(error)*error=[NSError errorWithDomain:TKErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
 return NO;
}
@interface CIEWebContext:NSObject
@property(nonatomic,weak) TKSmartCard *card;
@property(nonatomic) CieWebSession *native;
@property(nonatomic,strong) NSUUID *ownerID;
@property(nonatomic) BOOL authenticated;
@end
@implementation CIEWebContext
- (void)dealloc { cie_web_close(_native); }
@end
// TKSmartCard owns the connection. Synchronous completion is bridged from its
// raw transport; requests contain secure-messaging APDUs and are sent once.
static int32_t Transmit(void *opaque,const uint8_t *request,uint32_t length,uint8_t *response,uint32_t *size) {
 CIEWebContext *ctx=(__bridge CIEWebContext *)opaque;TKSmartCard *card=ctx.card;
 if(!card||!card.valid)return CIE_WEB_TRANSPORT;
 __block NSData *reply=nil;__block NSError *failure=nil;
 dispatch_semaphore_t done=dispatch_semaphore_create(0);
 [card transmitRequest:[NSData dataWithBytes:request length:length] reply:^(NSData *data,NSError *error){reply=data;failure=error;dispatch_semaphore_signal(done);}];
 // Wait for completion, never return leaving an in-flight card operation.
 dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
 if(failure||!reply||reply.length>*size)return CIE_WEB_TRANSPORT;
 memcpy(response,reply.bytes,reply.length);*size=(uint32_t)reply.length;return 0;
}
// This App Group contains public DER only. Never read pairing/PIN storage.
static NSData *PublicCertificate(NSString *identifier) {
 NSString *group=[[NSBundle mainBundle]objectForInfoDictionaryKey:@"CIEWebPublicAppGroup"];
 if(!group.length)return nil;
 NSURL *root=[[NSFileManager defaultManager]containerURLForSecurityApplicationGroupIdentifier:group];
 if(!root)return nil;
 NSData *idData=[identifier dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];
 CC_SHA256(idData.bytes,(CC_LONG)idData.length,hash);NSMutableString *name=[NSMutableString string];
 for(unsigned i=0;i<sizeof(hash);++i)[name appendFormat:@"%02x",hash[i]];
 NSURL *file=[[root URLByAppendingPathComponent:@"public-certificates" isDirectory:YES]URLByAppendingPathComponent:[name stringByAppendingString:@".der"]];
 NSDictionary *attrs=[[NSFileManager defaultManager]attributesOfItemAtPath:file.path error:nil];
 if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]>8192)return nil;
 NSData *der=[NSData dataWithContentsOfURL:file];return der.length&&der.length<=8192?der:nil;
}
static CIEWebContext *Open(TKSmartCard *card,NSString *expected,NSError **error) {
 CIEWebContext *ctx=[CIEWebContext new];ctx.card=card;NSData *atr=card.slot.ATR.bytes;
 CieWebSession *native=nullptr;
 int32_t status=cie_web_open((const uint8_t *)atr.bytes,(uint32_t)atr.length,Transmit,(__bridge void *)ctx,expected.UTF8String,&native);ctx.native=native;
 if(status){Fail(error,TKErrorCodeCommunicationError,@"Impossibile inizializzare la CIE per l’accesso ai siti.");return nil;}
 return ctx;
}
@interface CIEPrototypeToken:TKSmartCardToken<TKTokenDelegate>
@property(nonatomic,copy) NSData *publicCertificate;
@end
@interface CIEPrototypeSession:TKSmartCardTokenSession<TKTokenSessionDelegate> {
 cie_web::SignRequest _request;
 cie_web::AuthenticatedSession _authentication;
}
@property(nonatomic,strong) NSUUID *contextID;
@property(nonatomic,strong) TKSmartCard *transportCard;
@property(nonatomic) BOOL transactionHeld;
@property(nonatomic) uint64_t transactionGeneration;
- (BOOL)beginCardTransaction:(TKSmartCard *)card error:(NSError **)error;
- (void)refreshTransactionDeadline;
- (CIEWebContext *)contextForCard:(TKSmartCard *)card error:(NSError **)error;
- (CIEWebContext *)authenticatedContextForCard:(TKSmartCard *)card error:(NSError **)error;
- (BOOL)computePendingSignature:(CIEWebContext *)ctx error:(NSError **)error;
- (void)invalidateAuthentication;
- (BOOL)authenticateAndSignOnCard:(TKSmartCard *)card pin:(char *)pin error:(NSError **)error;
@end
@interface CIEPrototypePIN:TKTokenSmartCardPINAuthOperation
@property(nonatomic,strong) TKSmartCard *transportCard;
@property(nonatomic,strong) CIEPrototypeSession *session;
@end
@implementation CIEPrototypePIN
- (BOOL)finishWithError:(NSError **)error {
 char pin[8]={};BOOL valid=self.PIN.length==8;
 for(NSUInteger i=0;valid&&i<8;++i){unichar c=[self.PIN characterAtIndex:i];if(c<'0'||c>'9')valid=NO;else pin[i]=(char)c;}
 self.PIN=nil;
 if(!valid){[self.session invalidateAuthentication];cie_web::wipe(pin,8);return Fail(error,TKErrorCodeBadParameter,@"Inserisci le otto cifre del PIN della CIE.");}
 BOOL success=[self.session authenticateAndSignOnCard:self.transportCard pin:pin error:error];
 cie_web::wipe(pin,8);return success;
}
@end
@implementation CIEPrototypeSession
- (instancetype)initWithToken:(TKToken *)token {if((self=[super initWithToken:token])){self.delegate=self;self.contextID=[NSUUID UUID];}return self;}
- (TKSmartCard *)activeCard:(NSError **)error {
 // A TKTokenSession owns one TKSmartCard connection. Reacquiring a different
 // object between PIN completion and signing can reset the sensitive context.
 if(self.transportCard){
  if(!self.transportCard.valid){Fail(error,TKErrorCodeTokenNotFound,@"La carta è stata rimossa. Nessun tentativo automatico eseguito.");return nil;}
  return self.transportCard;
 }
 TKSmartCard *card=nil;
 if(@available(macOS 26.0,*))card=[self getSmartCardWithError:error];
 else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  card=self.smartCard;
#pragma clang diagnostic pop
 }
 card.sensitive=YES;self.transportCard=card;return card;
}
- (CIEWebContext *)contextForCard:(TKSmartCard *)card error:(NSError **)error {
 // A card context is reusable only by this token authentication session.
 // Different clients/LAContexts must never inherit another session's PIN auth.
 if([card.context isKindOfClass:CIEWebContext.class]&&[((CIEWebContext*)card.context).ownerID isEqual:self.contextID])return card.context;
 CIEWebContext *ctx=Open(card,self.token.configuration.instanceID,error);
 NSData *der=((CIEPrototypeToken*)self.token).publicCertificate;
 if(ctx&&(!der.length||cie_web_set_certificate(ctx.native,(const uint8_t*)der.bytes,(uint32_t)der.length))){Fail(error,TKErrorCodeObjectNotFound,@"Configura nuovamente l’accesso ai siti nell’applicazione.");return nil;}
 if(ctx){ctx.ownerID=self.contextID;card.context=ctx;}return ctx;
}
- (void)dealloc {
 // AID is nil, so this explicit transaction belongs to the driver, not CTK.
 if(_transactionHeld)[_transportCard endSession];
}
- (BOOL)beginCardTransaction:(TKSmartCard *)card error:(NSError **)error {
 if(self.transactionHeld)return YES;
 __block BOOL started=NO;__block NSError *failure=nil;
 dispatch_semaphore_t done=dispatch_semaphore_create(0);
 [card beginSessionWithReply:^(BOOL success,NSError *inner){started=success;failure=inner;dispatch_semaphore_signal(done);}];
 dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
 if(!started){if(error)*error=failure;return NO;}
 self.transactionHeld=YES;return YES;
}
- (void)refreshTransactionDeadline {
 // Keep one sensitive transaction across Safari's related TLS requests. The
 // idle deadline prevents an OS authentication context from locking the reader
 // indefinitely. Timer and delegates share the same monitor; never end an APDU
 // transaction concurrently with a private operation. No PIN is captured here.
 uint64_t generation=++self.transactionGeneration;
 __weak CIEPrototypeSession *weakSelf=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
  CIEPrototypeSession *session=weakSelf;if(!session)return;
  @synchronized(session){
   if(session.transactionHeld&&session.transactionGeneration==generation){
    [session invalidateAuthentication];
    os_log(OS_LOG_DEFAULT,"CIE prototype: idle card transaction released; no PIN retry");
   }
  }
 });
}
- (void)invalidateAuthentication {
 _authentication.fail();_request.fail();
 ++self.transactionGeneration;
 if(self.transactionHeld){self.transactionHeld=NO;[self.transportCard endSession];}
 if([self.transportCard.context isKindOfClass:CIEWebContext.class]&&[((CIEWebContext*)self.transportCard.context).ownerID isEqual:self.contextID])self.transportCard.context=nil;
}
- (CIEWebContext *)authenticatedContextForCard:(TKSmartCard *)card error:(NSError **)error {
 CIEWebContext *ctx=[card.context isKindOfClass:CIEWebContext.class]?card.context:nil;
 BOOL owned=ctx&&ctx.authenticated&&[ctx.ownerID isEqual:self.contextID];
 if(!_authentication.reuse(card&&card.valid&&card==self.transportCard,owned)){
  [self invalidateAuthentication];
  Fail(error,TKErrorCodeAuthenticationFailed,@"La sessione della carta è cambiata. Riparti dall’accesso nel browser. Nessun nuovo tentativo PIN eseguito.");return nil;
 }
 return ctx;
}
- (BOOL)computePendingSignature:(CIEWebContext *)ctx error:(NSError **)error {
 uint8_t signature[256];uint32_t size=sizeof(signature);const auto& input=_request.input();
 int32_t status=cie_web_sign(ctx.native,input.data(),(uint32_t)input.size(),signature,&size);
 if(status){os_log_error(OS_LOG_DEFAULT,"CIE prototype: native signature result=%{public}d",status);return Fail(error,TKErrorCodeCommunicationError,@"La firma della richiesta non è riuscita. Nessun nuovo tentativo PIN eseguito.");}
 if(!_request.complete(signature,size))return Fail(error,TKErrorCodeCorruptedData,@"Risultato della richiesta non valido.");
 os_log(OS_LOG_DEFAULT,"CIE prototype: signature computed and verified in authenticated transaction");return YES;
}
- (BOOL)authenticateAndSignOnCard:(TKSmartCard *)card pin:(char *)pin error:(NSError **)error {
 @synchronized(self){
 if(!_authentication.beginAuthentication()||!_request.beginAuthentication()){
  [self invalidateAuthentication];return Fail(error,TKErrorCodeAuthenticationFailed,@"Nessun tentativo automatico consentito. Ripeti l’operazione dal browser.");
 }
 // Retain an explicit transaction between callbacks: ending the last
 // sensitive transaction otherwise resets this card before Safari's next TLS
 // request. Per-operation nested sessions below remain balanced.
 if(![self beginCardTransaction:card error:error]){[self invalidateAuthentication];return NO;}
 BOOL success=[card inSessionWithError:error executeBlock:^BOOL(NSError **inner){
  CIEWebContext *ctx=[self contextForCard:card error:inner];if(!ctx)return NO;
  int32_t status=cie_web_authenticate(ctx.native,pin,8);
  if(status){
   os_log_error(OS_LOG_DEFAULT,"CIE prototype: native authentication result=%{public}d",status);
   NSString *message=status==0x6983?@"PIN bloccato.":(status&0xfff0)==0x63c0?@"La carta ha rifiutato il PIN. Nessun tentativo automatico eseguito.":@"La sessione CIE non ha completato l’autenticazione o il controllo del certificato. Questo esito non identifica un PIN errato. Nessun tentativo automatico eseguito.";
   return Fail(inner,TKErrorCodeAuthenticationFailed,message);
  }
  if(!self->_authentication.completeAuthentication())return NO;
  ctx.authenticated=YES;
  os_log(OS_LOG_DEFAULT,"CIE prototype: native authentication and certificate validation completed");
  return [self computePendingSignature:ctx error:inner];
 }];
 if(!success)[self invalidateAuthentication];else [self refreshTransactionDeadline];return success;
 }
}
- (TKTokenAuthOperation *)tokenSession:(TKTokenSession *)session beginAuthForOperation:(TKTokenOperation)operation constraint:(TKTokenOperationConstraint)constraint error:(NSError **)error {
 @synchronized(self){
 if(operation!=TKTokenOperationSignData||![constraint isEqual:@"CIE-PIN8"]){Fail(error,TKErrorCodeNotImplemented,@"Operazione non supportata.");return nil;}
 if(_authentication.isFailed()){Fail(error,TKErrorCodeAuthenticationFailed,@"Sessione di autenticazione terminata. Nessun tentativo automatico eseguito.");return nil;}
 TKSmartCard *card=[self activeCard:error];if(!card){[self invalidateAuthentication];return nil;}
 if(_authentication.hasAttempted()){
  // Safari may ask for authorization again before providing the next digest.
  // A generic auth operation is valid only while this same card context lives.
  BOOL valid=[card inSessionWithError:error executeBlock:^BOOL(NSError **inner){return [self authenticatedContextForCard:card error:inner]!=nil;}];
  if(!valid){[self invalidateAuthentication];return nil;}
  [self refreshTransactionDeadline];
  os_log(OS_LOG_DEFAULT,"CIE prototype: existing card authentication accepted without PIN retry");
  return [TKTokenAuthOperation new];
 }
 if(!_request.pending()){[self invalidateAuthentication];Fail(error,TKErrorCodeAuthenticationFailed,@"Nessuna richiesta di firma pendente. Riparti dal browser.");return nil;}
 CIEPrototypePIN *auth=[CIEPrototypePIN new];auth.session=self;auth.transportCard=card;auth.APDUTemplate=nil;
 auth.PINFormat.minPINLength=8;auth.PINFormat.maxPINLength=8;auth.PINFormat.charset=TKSmartCardPINCharsetNumeric;return auth;
 }
}
- (BOOL)tokenSession:(TKTokenSession *)session supportsOperation:(TKTokenOperation)operation usingKey:(TKTokenObjectID)key algorithm:(TKTokenKeyAlgorithm *)algorithm {
 return operation==TKTokenOperationSignData&&[key isEqual:@"cie-auth-key"]&&
 [algorithm isAlgorithm:kSecKeyAlgorithmRSASignatureRaw]&&[algorithm supportsAlgorithm:kSecKeyAlgorithmRSASignatureDigestPKCS1v15Raw];
}
- (NSData *)tokenSession:(TKTokenSession *)session signData:(NSData *)data usingKey:(TKTokenObjectID)key algorithm:(TKTokenKeyAlgorithm *)algorithm error:(NSError **)error {
 @synchronized(self){
 if(![self tokenSession:session supportsOperation:TKTokenOperationSignData usingKey:key algorithm:algorithm]){Fail(error,TKErrorCodeNotImplemented,@"Algoritmo non supportato dalla CIE.");return nil;}
 // Security.framework supplies EMSA-PKCS1-v1_5. Strip canonical BT1 padding
 // only; IAS/card applies it itself. Never pass arbitrary raw RSA messages.
 const uint8_t *p=(const uint8_t *)data.bytes;NSUInteger n=data.length,i=2;
 if(n!=256||p[0]!=0||p[1]!=1){Fail(error,TKErrorCodeBadParameter,@"Blocco RSA non valido.");return nil;}
 while(i<n&&p[i]==0xff)++i;
 if(i<10||i>=n||p[i++]!=0||!cie_web::digestInfo(p+i,(uint32_t)(n-i))){Fail(error,TKErrorCodeBadParameter,@"Digest non supportato.");return nil;}
 if(_request.ready()){
  std::vector<uint8_t> signature;
  if(!self.transportCard.valid){[self invalidateAuthentication];Fail(error,TKErrorCodeTokenNotFound,@"La carta è stata rimossa. Nessun tentativo automatico eseguito.");return nil;}
  if(!_request.take(p+i,(uint32_t)(n-i),signature)){[self invalidateAuthentication];Fail(error,TKErrorCodeBadParameter,@"La richiesta di firma è cambiata. Nessun nuovo tentativo PIN eseguito.");return nil;}
  [self refreshTransactionDeadline];
  os_log(OS_LOG_DEFAULT,"CIE prototype: one-use signature delivered for original request");
  return [NSData dataWithBytes:signature.data() length:signature.size()];
 }
 if(_request.consumed()&&!_authentication.isFailed()){
  TKSmartCard *card=[self activeCard:error];if(!card){[self invalidateAuthentication];return nil;}
  __block NSData *result=nil;
  BOOL success=[card inSessionWithError:error executeBlock:^BOOL(NSError **inner){
   CIEWebContext *ctx=[self authenticatedContextForCard:card error:inner];if(!ctx)return NO;
   if(!self->_request.prepareNext(p+i,(uint32_t)(n-i))||!self->_request.beginAuthentication())return Fail(inner,TKErrorCodeBadParameter,@"Richiesta successiva non valida.");
   if(![self computePendingSignature:ctx error:inner])return NO;
   std::vector<uint8_t> signature;
   if(!self->_request.take(p+i,(uint32_t)(n-i),signature))return Fail(inner,TKErrorCodeCorruptedData,@"Risultato della richiesta successiva non valido.");
   result=[NSData dataWithBytes:signature.data() length:signature.size()];return YES;
  }];
  if(!success){[self invalidateAuthentication];return nil;}
  [self refreshTransactionDeadline];
  os_log(OS_LOG_DEFAULT,"CIE prototype: follow-up signature delivered without PIN retry");return result;
 }
 if(!_request.empty()||_authentication.hasAttempted()||_authentication.isFailed()){[self invalidateAuthentication];Fail(error,TKErrorCodeAuthenticationFailed,@"Sessione di autenticazione terminata. Nessun tentativo automatico eseguito.");return nil;}
 if(!_request.prepare(p+i,(uint32_t)(n-i))){Fail(error,TKErrorCodeBadParameter,@"Richiesta di firma non valida.");return nil;}
 Fail(error,TKErrorCodeAuthenticationNeeded,@"Autorizza l’accesso con il PIN della CIE.");return nil;
 }
}
@end
@implementation CIEPrototypeToken
- (TKTokenSession *)token:(TKToken *)token createSessionWithError:(NSError **)error {return [[CIEPrototypeSession alloc]initWithToken:self];}
@end
@interface CIEPrototypeTokenDriver:TKSmartCardTokenDriver<TKSmartCardTokenDriverDelegate>
- (TKSmartCardToken *)createTokenForCard:(TKSmartCard *)card expected:(NSString *)expected configuration:(TKTokenConfiguration *)configuration error:(NSError **)error;
@end
@implementation CIEPrototypeTokenDriver
- (instancetype)init {if((self=[super init]))self.delegate=self;return self;}
// Smart-card discovery belongs to TKSmartCardTokenDriver. Never enumerate
// slots synchronously from tokenForConfiguration: ctkd can be waiting for this
// callback while the slot endpoint is waiting for ctkd, causing an XPC cycle.
- (TKSmartCardToken *)tokenDriver:(TKSmartCardTokenDriver *)driver createTokenForSmartCard:(TKSmartCard *)card AID:(NSData *)AID error:(NSError **)error {
 return [self createTokenForCard:card expected:nil configuration:nil error:error];
}
- (TKSmartCardToken *)createTokenForCard:(TKSmartCard *)card expected:(NSString *)expected configuration:(TKTokenConfiguration *)configuration error:(NSError **)error {
 os_log(OS_LOG_DEFAULT,"CIE prototype: physical smart-card discovery started");
 __block NSData *der=nil;__block CIEPrototypeToken *token=nil;
 BOOL success=[card inSessionWithError:error executeBlock:^BOOL(NSError **inner){
  CIEWebContext *ctx=Open(card,expected,inner);if(!ctx)return NO;
  char id[64];uint32_t size=sizeof(id);if(cie_web_identifier(ctx.native,id,&size))return Fail(inner,TKErrorCodeCorruptedData,@"Identificativo CIE non valido.");
  NSString *identifier=[NSString stringWithUTF8String:id];
  token=[[CIEPrototypeToken alloc]initWithSmartCard:card AID:nil instanceID:identifier tokenDriver:self];token.delegate=token;
  der=PublicCertificate(identifier);
  token.publicCertificate=der;
  if(!der.length)return YES; // Register physical presence before host provisioning.
  if(cie_web_set_certificate(ctx.native,(const uint8_t*)der.bytes,(uint32_t)der.length))return Fail(inner,TKErrorCodeCorruptedData,@"Il certificato configurato non corrisponde alla CIE.");
  return YES;
 }];
 if(!success)return nil;
 if(!der.length){os_log(OS_LOG_DEFAULT,"CIE prototype: physical token awaits public certificate");return token;}
 SecCertificateRef certificate=SecCertificateCreateWithData(NULL,(__bridge CFDataRef)der);
 if(!certificate){Fail(error,TKErrorCodeCorruptedData,@"Certificato CIE non valido.");return nil;}
 TKTokenKeychainCertificate *cert=[[TKTokenKeychainCertificate alloc]initWithCertificate:certificate objectID:@"cie-auth-cert"];
 TKTokenKeychainKey *key=[[TKTokenKeychainKey alloc]initWithCertificate:certificate objectID:@"cie-auth-key"];
 CFRelease(certificate);key.canSign=YES;key.canDecrypt=NO;key.suitableForLogin=NO;key.label=@"CIE ID · Accesso ai siti";
 key.constraints=@{@(TKTokenOperationSignData):@"CIE-PIN8"};
 key.applicationTag=[token.configuration.instanceID dataUsingEncoding:NSUTF8StringEncoding];
 [token.keychainContents fillWithItems:@[cert,key]];os_log(OS_LOG_DEFAULT,"CIE prototype: physical certificate and key published");return token;
}
@end
