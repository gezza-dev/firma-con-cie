# Adattamento della finestra desktop

La finestra usa le dimensioni preferite quando entrano nell'area utile del
monitor. Su monitor piccoli o quando cambiano risoluzione, DPI o disposizione,
dimensioni e posizione vengono adattate mantenendo accessibili i contenuti.
I caratteri conservano la scala fornita dal sistema/Flutter e il contenuto
lungo può scorrere. Questo comportamento riguarda il runner della GUI;
middleware, abbinamento, firma, PIN e accesso ai siti non vengono modificati.

## macOS

Il contenuto preferito resta 1080×760 **punti AppKit**. Il runner rimuove il
vincolo minimo/massimo fisso e abilita ridimensionamento e zoom, conservando
`.fullScreenNone`: non richiede il passaggio a schermo intero. La cornice
completa viene limitata a `NSScreen.visibleFrame`, con margine di 12 punti.
Dock, barra dei menu e cornice sono quindi considerati; non si moltiplica
per `backingScaleFactor` e non si modificano preferenze del sistema.

Le notifiche di cambio schermo, proprietà del backing, configurazione degli
schermi e fine del ridimensionamento aggiornano i vincoli. I minimi di contenuto
640×400 si riducono quando l'area è più piccola. Una finestra già più piccola
mantiene la dimensione; posizione e dimensioni sono limitate anche per monitor
con origini negative. La guardia di rientro evita ricorsioni durante `setFrame`.
Gli observer vengono rimossi alla distruzione della finestra.

Il calcolo usa il modulo Clang `CieWindowGeometry`, in `native/desktop`,
importato da Swift tramite `SWIFT_INCLUDE_PATHS` nel file comune AppInfo.xcconfig
del target Runner (Debug/Profile/Release). Lo script di build macOS copia
l'intero albero sorgente e conserva questo modulo. Serve Xcode/AppKit per
compilare e verificare l'integrazione Swift effettiva.

Riferimenti: [area visibile NSScreen](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe),
[cambio schermo della finestra](https://developer.apple.com/documentation/appkit/nswindow/didchangescreennotification).

## Windows

Il runner PerMonitorV2 conserva 1280×720 come preferenza logica iniziale.
Questa preferenza viene convertita **una volta** ai DPI del monitor e limitata
al rettangolo fisico `MONITORINFO.rcWork`, che esclude la taskbar. Se la
dimensione richiesta non entra, la prima visualizzazione richiede la normale
massimizzazione Windows. Sono riabilitati bordo ridimensionabile, pulsante e
comando di massimizzazione.

`WM_DPICHANGED` fornisce un rettangolo già scalato per i nuovi DPI: il runner
lo limita all'area utile senza scalarlo nuovamente. Flutter e i plugin ricevono
comunque il messaggio; la gestione nativa della geometria viene eseguita anche
se un plugin restituisce un risultato. `WM_DISPLAYCHANGE`, `SPI_SETWORKAREA`
e `WM_EXITSIZEMOVE` ricontrollano le finestre normali. Le finestre minimizzate
sono lasciate al sistema e quelle massimizzate mantengono la gestione nativa.

`WM_GETMINMAXINFO` limita il minimo di contenuto 640×400 allo spazio disponibile,
con decorazioni DPI-aware (`AdjustWindowRectExForDpi` se presente). I valori
di massimizzazione/bordi forniti da Windows vengono conservati. Le coordinate
firmate dei monitor sono mantenute, senza spostare tutto sul monitor primario.

Riferimenti: [MONITORINFO](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-monitorinfo),
[WM_DPICHANGED](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged),
[WM_GETMINMAXINFO](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-getminmaxinfo).

## Linux

Resta il runner GTK dedicato: area utile già in coordinate logiche, dimensione
preferita 1280×720 e richiesta di massimizzazione se necessario. Il collaudo
manuale dell'adattamento GNOME con il `.deb` `0.1.0~test20261020.2` è stato
confermato dall'utente. [Pacchetto e dettagli Linux](LINUX_PACKAGE.md).
Le modifiche macOS/Windows non richiedono un nuovo `.deb`.

## Test eseguiti su Linux e limiti

Il rettangolo viene limitato da `native/desktop/window_geometry.h`: header C
senza dipendenze dalla GUI, usato direttamente da entrambi i runner. È testato
come C e C++: monitor negativi/frazionari, area utile ridotta, finestre piccole,
conversione iniziale DPI 96/120/144/168/192, rettangoli suggeriti già scalati,
idempotenza e dati non validi. Un terzo controllo Clang verifica l'importazione
del modulo. Questo controllo non compila né esegue Swift/AppKit.

```sh
cmake -S native/desktop/tests -B .build/desktop-window-tests -G Ninja
cmake --build .build/desktop-window-tests --parallel 2
ctest --test-dir .build/desktop-window-tests --output-on-failure
flutter analyze
flutter test
```

Risultati del 20 ottobre 2026: tre gruppi CTest superati; 212 test Flutter
superati, tre test facoltativi di runtime saltati, analisi senza problemi.
I 18 scenari `test/desktop_window_layout_test.dart` attraversano tutte le
pagine nelle varianti Linux/macOS/Windows, da 640×400, con caratteri fino al
200% e display fino al 200%, senza cambiare ulteriormente la scala del testo.

Anche `win32_window.cpp` è stato compilato in un oggetto Windows x64 COFF
con Clang, header MinGW e header C ufficiali Flutter, scaricati solo in
`.build/desktop-window-cross`. Il controllo usa gli header Flutter upstream
per verificare l'API C; non sostituisce una build dell'app con l'SDK Windows
fissato dal progetto. Nessun pacchetto di compilazione è stato installato
sull'host, nessun binario Windows eseguito e nessuna app avviata.

Al termine delle prove Linux restavano da eseguire build complete macOS/Windows, verifica Swift/AppKit e
collaudo visivo su entrambe le piattaforme: avvio su schermi piccoli,
minimizza/ripristina, zoom/massimizzazione, monitor con DPI diversi, rimozione
monitor e cambi di Dock/taskbar. Questi test non richiedono una CIE.
Nessuna nuova prova sulla CIE o modifica a browser/permessi è inclusa.

## Collaudo Windows e crescita della finestra (21 ottobre)

La build Windows x64 è stata completata con Flutter 3.47.7. `DesktopPageBody`
ricalcola larghezza e altezza utile a ogni variazione del viewport, senza il
precedente limite di larghezza delle pagine. Anche l'anteprima della firma cresce
con la finestra e mantiene i pulsanti nel footer fisso. L'area di caricamento
documenti sfrutta lo spazio verticale aggiuntivo.

Nel runner, `WM_SIZE` viene gestito anche se un plugin intercetta il messaggio.
Il ridimensionamento della finestra figlia usa `SetWindowPos` senza aggiornamento
sincrono; le richieste rientranti sono accorpate e applicate dopo il callback
corrente. All'uscita dal trascinamento viene richiesto un fotogramma finale.
Il test Win32 esercita il runner reale con una finestra figlia sintetica che
genera messaggi annidati: 926 controlli, inclusi 300 cicli di ridimensionamento.

Sul PC collaudato il renderer predefinito Impeller continuava a mostrare una
fascia nera e fotogrammi bloccati, mentre input e navigazione restavano attivi.
La selezione esplicita di Skia nel runner ha risolto il problema nella prova
manuale: allargamento, restringimento e nuovo allargamento trascinando il bordo,
seguiti dall'apertura di Verifica Firma. L'utente ha confermato l'esito positivo.
Il confronto riguarda questa configurazione; prima di riattivare Impeller con
un nuovo motore occorre ripetere il collaudo.

Analisi Flutter senza problemi; 215 test Flutter superati e tre facoltativi
saltati. Su MSVC passano due gruppi di test geometrici e 42 controlli dell'host.
I nuovi test Flutter verificano la crescita e il restringimento della stessa
finestra e la permanenza dei pulsanti visibili durante lo scorrimento.
Le prove macOS/AppKit, KDE e i casi Windows con più monitor/DPI restano pendenti.
