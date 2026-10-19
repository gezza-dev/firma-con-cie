# Cofirma, guida e preferenze condivise

Questa integrazione riguarda il prototipo Flutter, separato da CIE ID Universal.
Il codice Dart e il motore C/C++ sono condivisi tra macOS e Windows. Nessuna
prova reale di Cambio PIN o Sblocco Carta è autorizzata da questo collaudo.

## Cofirma P7M

Nella pagina Firma, un input `.p7m` seleziona **Aggiungi una firma**. Il formato CAdES
ordinario resta disponibile per documenti non ancora incapsulati: la scelta
esplicita evita di annidare per errore un P7M dentro un altro P7M. La destinazione
proposta termina con `.p7m` e deve essere nuova.

Il ponte e l'adattatore controllano il contenitore prima dell'autenticazione.
Sono ammessi CMS SignedData con contenuto incorporato di tipo id-data, almeno
una firma e meno di 64 firmatari, fino a 256 MiB. Sono supportati DER/BER, PEM
CMS/PKCS7 e Base64. Firme detached, contenuto vuoto, dati residui, contenitori
malformati o firme crittograficamente non verificabili vengono rifiutati. Il
controllo preliminare richiede anche che le firme siano verificabili dall’SDK
condiviso; algoritmi o identificatori non gestiti sono rifiutati prima del PIN.
Il controllo è locale: non stabilisce fiducia, validità temporale o
revoca dei certificati e non esegue richieste di rete.

L'SDK firma il contenuto originale e aggiunge un SignerInfo allo stesso CMS.
Conserva gli altri SignerInfo, inclusi gli attributi non firmati, i certificati,
le CRL incorporate e il contenuto. I SET vengono serializzati secondo DER;
non si promette identità dell'intero file o dell'ordine dei firmatari. Prima
pubblicazione, il ponte verifica tutte le firme e controlla che contenuto e
firme precedenti siano conservati. Un errore elimina il temporaneo, senza
sovrascrivere l'originale né ripetere il PIN. Lo stesso firmatario può produrre
un SignerInfo identico nello stesso istante: se non risulta una firma aggiuntiva
il risultato viene rifiutato. Le marche di archivio e gli esiti storici/LTA
richiedono una nuova valutazione sul risultato; la cofirma non li rinnova.

La prova nativa usa tre identità sintetiche effimere: due firme iniziali con
SHA-384/SHA-256, un attributo non firmato e una CRL incorporata, poi una nuova
firma CAdES generata dallo stesso SDK con un firmatario in memoria. Verifica
integrità di tutte le firme, conservazione dei dati, supporto PEM/Base64 e
rifiuto prima del firmatario per input insufficienti. Non usa una carta reale.
Il verificatore legacy è esteso a RSA/SHA-384 e RSA/SHA-512, necessari per
verificare tutte le firme dei campioni misti; algoritmi, lunghezze e attributi
firmati sono controllati prima di attribuire integrità valida.

## Guida inclusa e collegamenti

La pagina **Guida** contiene otto sezioni: lettore/CIE, firma, grafica PDF,
cofirma, verifica/estrazione, PIN/PUK, dati locali e aiuto. Il testo è incluso
nel programma e non richiede Internet. I collegamenti HTTPS elencati sono
fissi e vengono aperti nel browser predefinito tramite url_launcher; errori di
apertura mostrano il collegamento da copiare. Il link ufficiale è
https://www.cartaidentita.interno.gov.it/info-utili/software-cie-2/ .
I link al repository e all'ultima release si riferiscono esplicitamente
all'app macOS di riferimento, non a una release Windows del prototipo.
Informazioni e licenze include gli avvisi Flutter/Dart e i testi principali
del middleware, SDK e prototipo; gli avvisi completi delle dipendenze e DSS/JVM
restano inclusi nel runtime di test.

## Preferenze della firma

La sezione **Preferenze firma** della pagina **Impostazioni** salva il formato proposto per i nuovi documenti
(PAdES/CAdES) e un'immagine proposta nelle nuove anteprime PDF. Nessuna grafica
viene applicata a una firma senza la conferma dell'anteprima. Cambiare le
preferenze non altera il documento attuale o un'anteprima già preparata.

L'archivio è privato del prototipo, sotto la cartella Application Support fornita
da path_provider, nella sottocartella `signature-preferences`. Su macOS/Linux
questa sottocartella ha permessi 0700; Windows usa l'area applicativa dell'utente.
`preferences.json` ha schema 1 e solo `format` e `image`; l'immagine è copiata e
normalizzata in PNG con nome generato dall'app. Non si conservano riferimenti
al percorso originale scelto, PIN, PUK o documenti. Le nuove immagini per CIE sono associate localmente alla carta in un archivio distinto; vedere [SIGNING_UX3.md](SIGNING_UX3.md).
Non viene eseguita sincronizzazione in rete.

I percorsi sono normalizzati tramite URI su entrambi i sistemi, compresi
separatori misti e caratteri Unicode. I salvataggi usano un temporaneo e rinomina; file corrotti o percorsi immagine
esterni vengono rifiutati e la UI permette il ripristino. L'immagine è limitata
a 10 MiB, 8192 pixel per lato e 16 megapixel. La rimozione e il ripristino
eliminano solo la copia gestita dal prototipo. Il file scelto dall'utente rimane
intatto. Le preferenze della firma restano separate dalla configurazione di rete e diagnostica, ora disponibili nella stessa pagina Impostazioni; vedere [impostazioni condivise](SETTINGS_DIAGNOSTICS_PROXY.md). L’abbinamento CIE resta un’integrazione successiva.
