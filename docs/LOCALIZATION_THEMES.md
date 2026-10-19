# Lingue, tema e nome del prodotto

L'interfaccia condivisa usa **Segui il sistema** come lingua predefinita. La lingua primaria del sistema è risolta in italiano se `it`, in inglese se `en`, indeterminata o diversa da queste due. In **Impostazioni → Generali → Lingua dell'applicazione** si può scegliere Segui il sistema, Italiano o English. Una scelta esplicita Italiano/English è conservata ai successivi avvii. La selezione è salvata nel file delle impostazioni, si applica senza riavviare l'interfaccia e resta separata dalle credenziali e dagli abbinamenti della carta. Le impostazioni precedenti, prive del campo `language`, restano compatibili e seguono il sistema.

## Cataloghi

- `lib/l10n/app_it.json`: testi italiani e chiavi dei messaggi.
- `lib/l10n/app_en.json`: traduzioni inglesi, con le stesse chiavi e gli stessi parametri `{p0}`, `{p1}`, ecc.
- `python3 scripts/generate_l10n.py`: verifica i cataloghi e rigenera `catalog.g.dart`.
- `lib/app_localizations.dart`: delegate Flutter e scelta della lingua. I parametri personali (titolare, carta, percorsi e contenuti dei documenti) restano invariati. Le informazioni legali originali non vengono tradotte.

La guida inclusa, gli avvisi, gli esiti e i dettagli di verifica usano gli stessi cataloghi. Il testo bilingue impresso nella firma PDF è parte del documento e non dipende dalla lingua dell'interfaccia.

Le schede di Impostazioni sono, in ordine: **Generali**, **Proxy**, **Log**. Generali si apre per prima.

## Menu e dialoghi

Il menu macOS conserva soltanto **CIE ID → Informazioni su CIE ID / Esci da CIE ID**, tradotte in inglese quando selezionato. Su macOS le risorse `it.lproj`/`en.lproj` e il canale `cie.id/application` localizzano i menu nativi secondo la preferenza dell'applicazione. La preferenza Cocoa viene impostata soltanto nel dominio dell'app: non modifica la lingua del Mac. Alcuni elementi delle finestre native gestite dal sistema possono usare una lingua già caricata fino al successivo avvio. I nomi dei filtri documento sono selezionati esplicitamente dall'app.

Su Windows e Linux i controlli condivisi e i menu contestuali Flutter seguono la lingua selezionata; i dialoghi nativi del sistema operativo possono mantenere la lingua del sistema. Occorre completare il collaudo dei runner sui rispettivi sistemi.

## Tema

Nella scheda Generali è disponibile **Tema dell’applicazione**: **Segui il sistema** (predefinito), **Chiaro**, **Scuro**. La selezione è salvata nel campo opzionale `theme` e applicata subito, senza coinvolgere il lettore. Cambi di lingua e salvataggi di rete/log preservano il tema. Su macOS anche la barra nativa e i dialoghi seguono la scelta dell'app, senza modificare le impostazioni del Mac.

Con Segui il sistema, `ThemeMode.system` segue automaticamente l'impostazione chiara/scura del sistema, anche quando cambia durante l'esecuzione. `lib/app_theme.dart` conserva il tema chiaro esistente e deriva i colori scuri dal medesimo colore principale. Errori e stati usano colori compatibili con il tema. Le pagine PDF e la firma grafica mantengono i colori del documento.

## Eseguibili

Il prodotto è `CIE-ID.app` su macOS, `CIE-ID.exe` su Windows e `CIE-ID` su Linux. Il nome visibile resta **CIE ID**. Identificativi dei bundle, estensione CryptoTokenKit e spazi dei nomi degli archivi protetti rimangono invariati, così la rinomina non invalida gli abbinamenti.

## Verifica

`test/localization_theme_test.dart` controlla la parità dei cataloghi, i parametri, tutte le destinazioni in inglese, la persistenza della selezione, i cambiamenti di luminosità del sistema e l'allineamento della Home con il bordo visibile dell'immagine. Le prove non inviano PIN o PUK e non modificano la carta.

## Firma grafica e passaggi

Le nuove anteprime iniziano dalla prima pagina. Dopo aver determinato la dimensione effettiva del segno, il riquadro viene posizionato in basso a destra con 36 punti PDF di margine destro e inferiore (circa 12,7 mm); sulle pagine molto piccole il margine è limitato al 10% della dimensione corrispondente. Una posizione già personalizzata viene conservata quando si riapre la stessa anteprima. I separatori della procedura guidata sono triangoli pieni rivolti a destra, centrati verticalmente.

## Orario nel segno grafico

Anteprima e SDK PDF mostrano data e ora locali del computer con lo scostamento UTC effettivo al momento della firma, compresa l’ora legale: per esempio UTC, UTC+1, UTC+2, UTC-5, UTC+5:30 e UTC+5:45. La lingua dell’interfaccia non determina il fuso. Il motore nativo acquisisce un unico istante per testo visibile e metadati PDF, includendo lo stesso scostamento nei metadati. Le marche temporali, le date dei certificati e i riferimenti della validazione continuano a essere trattati come istanti assoluti.

Le prove native coprono i cambi d’ora in Europa/Roma, offset negativi e frazionari e il cambio di anno. Le fixture PDF sono firmate con chiavi sintetiche e controllate crittograficamente, senza CIE o PIN.
