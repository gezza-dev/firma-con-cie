# Adattamento della finestra desktop

La finestra usa le dimensioni preferite quando entrano nell'area utile del
monitor. Su monitor piccoli o quando cambiano risoluzione, DPI o disposizione,
dimensioni e posizione vengono adattate mantenendo accessibili i contenuti.
I caratteri conservano la scala fornita dal sistema/Flutter e il contenuto
lungo può scorrere. Questo comportamento riguarda il runner della GUI;
middleware, abbinamento, firma, PIN e accesso ai siti non vengono modificati.

## Posizione iniziale al centro dell'area utile

All'avvio la cornice completa viene adattata e centrata nell'area utile del
monitor, escludendo gli spazi riservati dal sistema. La centratura si applica
solo alla prima apertura: spostamenti e ridimensionamenti successivi restano
liberi, mentre i cambi di monitor continuano soltanto a limitare eventuali
parti fuori schermo. Su schermi piccoli resta la massimizzazione già prevista.

Su Windows la creazione iniziale usa `MONITORINFO.rcWork` del monitor primario,
nei pixel fisici dei suoi DPI; il posizionamento avviene prima della prima
visualizzazione. Su macOS `NSScreen.visibleFrame` include Dock e barra dei menu:
il runner centra matematicamente la cornice già adattata, in punti AppKit,
con il margine esistente di 12 punti. Non usa più `NSWindow.center()`, la cui
posizione verticale non coincide necessariamente con il centro geometrico.

Su Linux viene impostato `GTK_WIN_POS_CENTER` prima di mostrare la finestra.
GTK 3 calcola la posizione iniziale con `gdk_monitor_get_workarea`, includendo
i pannelli esposti dal desktop. Non viene usato `GTK_WIN_POS_CENTER_ALWAYS`.
Il gestore delle finestre mantiene l'autorità finale sul posizionamento; in
particolare su Wayland l'app non può imporre coordinate globali. La richiesta
di centratura resta quindi soggetta alla politica del compositor.

Riferimenti: [centratura iniziale GTK 3](https://github.com/GNOME/gtk/blob/gtk-3-24/gtk/gtkwindow.c),
[politica di posizionamento GTK](https://docs.gtk.org/gtk3/method.Window.move.html).

La politica condivisa `cie_window_center_rect` viene esercitata come C e C++
con barre su lati diversi, origini negative e frazionarie, DPI 96–192 e aree
troppo piccole. Il test dell'host Win32 verifica anche la posizione iniziale
reale rispetto a `rcWork` e che i successivi 300 cicli di ridimensionamento
non causino ricentrature. La compilazione e la verifica dei runner macOS/Linux
richiedono i rispettivi sistemi; i soli test geometrici non le sostituiscono.

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

La barra del titolo appartiene al runner nativo, non al widget tree Flutter.
Su macOS il runner disegna già il titolo al centro; su Windows il titolo
standard era allineato a sinistra. Il runner Win32 ora estende il solo spazio
della didascalia nel client e disegna il testo al centro dell'intera finestra,
con margini simmetrici per icona e pulsanti. Font e metriche vengono letti
dal sistema ai DPI correnti. Testo e icona sono centrati verticalmente in tutta
l'altezza visibile della barra: la fascia superiore ridimensionabile non viene
sottratta dal rettangolo di disegno, evitando uno spostamento verso il basso
nella finestra normale rispetto a quella massimizzata.
Il nome nativo della finestra non viene svuotato:
resta disponibile per taskbar, Alt+Tab e strumenti di accessibilità.

Riduci, Ingrandisci/Ripristina e Chiudi mantengono i comandi nativi di Windows;
normalmente la loro area nel buffer resta trasparente e i simboli sono disegnati
da DWM. `DwmDefWindowProc` riceve sempre i messaggi prima del correttivo per la
cornice massimizzata. Trascinamento, doppio clic, menu di sistema e bordi
mantengono i normali messaggi Win32. Flutter riceve soltanto il rettangolo
sottostante alla barra.
Per `WM_NCHITTEST` i rettangoli di Riduci, Ingrandisci/Ripristina e Chiudi,
letti con `WM_GETTITLEBARINFOEX`, hanno precedenza sulle aree di trascinamento.
Questo evita che DWM, dopo la massimizzazione della cornice estesa, riconosca
i clic sui pulsanti come trascinamento del titolo. Un test dedicato verifica
cinque punti di ciascun pulsante in finestra normale, massimizzata e dopo
minimizzazione/ripristino, per due cicli, usando il runner e DWM effettivi.

Il passaggio del mouse viene seguito tramite `WM_NCMOUSEMOVE` e
`WM_NCMOUSELEAVE`, inoltrati al runner anche quando un plugin restituisce un
risultato. Poiché DWM può omettere l’hover sulla cornice estesa massimizzata,
il solo pulsante sotto il mouse riceve un overlay con sfondo grigio per
Riduci/Ingrandisci/Ripristina e rosso per Chiudi, con simbolo scalato ai DPI.
L’overlay usa i rettangoli di accessibilità di Windows e viene rimosso all’uscita
del mouse, alla disattivazione o al cambio dimensioni. I colori seguono il tema
chiaro/scuro della cornice; in contrasto elevato resta la barra standard.
Il test nativo verifica anche l’invalidazione dell’hover all’ingresso e
all’uscita da ogni pulsante: 150 controlli complessivi. La prova visiva del
27 ottobre 2026 verifica hover e rimozione dell’evidenziazione nelle finestre
normale e massimizzata, oltre ai comandi Ingrandisci, Ripristina, Riduci e Chiudi.

Il buffer della didascalia è separato dalla superficie Flutter e conserva Skia.
Le modifiche di tema/font/DPI invalidano la didascalia; la cornice DWM viene
aggiornata solo quando cambiano i relativi valori. Con contrasto elevato o
composizione DWM indisponibile viene mantenuta la barra standard di sistema.

Riferimento: [cornici personalizzate con DWM](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe).

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

## Collaudo della centratura e della barra del titolo (22 ottobre)

Build Windows x64 Release completata con Flutter 3.47.7 e renderer Skia.
Verificati avvio centrato, spostamento libero e nuovo avvio centrato, titolo
centrato orizzontalmente e verticalmente, finestra normale/massimizzata,
trascinamento del titolo, doppio clic, menu Alt+Spazio e ridimensionamento
da tastiera. L'apertura di Verifica Firma dopo le prove resta responsiva.

La regressione dei tre pulsanti a finestra massimizzata è stata riprodotta
nel test del runner: Windows restituiva `HTCAPTION` sui centri dei pulsanti.
Dopo la correzione passano 114 controlli, con cinque punti per pulsante e
due cicli normale → massimizzata → minimizzata/ripristinata. L'utente ha
confermato con il mouse Ripristina, Ingrandisci, Riduci, riapertura dalla
taskbar e Chiudi; app e observer terminano dopo la chiusura. I test separati
del ridimensionamento mantengono 300 cicli di crescita/restringimento con
messaggi annidati. Passano anche i due gruppi geometrici C e C++ con MSVC.

Per ripetere i test nativi da Developer PowerShell x64, dopo aver generato
il runner con `flutter build windows --release --no-pub`:

```powershell
cmake -S native/desktop/tests -B .build/desktop-window-tests -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build .build/desktop-window-tests
ctest --test-dir .build/desktop-window-tests --output-on-failure
cmake -S windows/runner/tests -B .build/win32-runner-tests -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build .build/win32-runner-tests
ctest --test-dir .build/win32-runner-tests --output-on-failure
```

Il test DWM usa una finestra di prova in background e non accede alla CIE.
Gli installer locali 1.0.0 includono le correzioni; i confronti dei payload
confermano middleware, componente web, dipendenze e licenze invariati.
La verifica visiva di questa attività usa il tema scuro del sistema e il
monitor corrente: contrasto elevato, Windows 10, Snap e più monitor con DPI
diversi non sono stati collaudati manualmente. I sorgenti macOS/Linux per la
centratura iniziale richiedono ancora build e collaudo sui rispettivi sistemi.
