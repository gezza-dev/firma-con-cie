// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'native_bridge.dart';
import 'signature_image.dart';

// PDF points: a 36-point inset is about 12.7 mm on a normal page.
const defaultSignatureInsetPoints = 36.0;
Offset defaultSignaturePosition(Size page, Size normalizedSignature) {
  final rightInset = (defaultSignatureInsetPoints / page.width).clamp(0.0, .1);
  final bottomInset = (defaultSignatureInsetPoints / page.height).clamp(
    0.0,
    .1,
  );
  return Offset(
    (1 - normalizedSignature.width - rightInset).clamp(
      0.0,
      1 - normalizedSignature.width,
    ),
    (1 - normalizedSignature.height - bottomInset).clamp(
      0.0,
      1 - normalizedSignature.height,
    ),
  );
}

class PreparedPdfSignature {
  const PreparedPdfSignature(this.directory, this.pdfPath, this.appearance);
  final Directory directory;
  final String pdfPath;
  final PdfAppearance appearance;
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

Future<PreparedPdfSignature?> configurePdfAppearance(
  BuildContext context,
  CieService service,
  String source, {
  String? defaultImagePath,
  String? cardholderName,
  PdfAppearance? initialAppearance,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'cie-pdf-appearance-',
  );
  PdfDocument? document;
  var retained = false;
  try {
    final original = File(source);
    if (!await original.exists() ||
        await original.length() > 256 * 1024 * 1024) {
      throw const FormatException(
        'PDF non leggibile o troppo grande (massimo 256 MiB).',
      );
    }
    final copy = await original.copy('${directory.path}/documento.pdf');
    final info = await service.pdfInfo(copy.path, 0);
    if (info['ok'] != true) {
      throw FormatException(
        info['message'] as String? ?? 'PDF non supportato.',
      );
    }
    final initialImage = File('${directory.path}/originale.png');
    final imagePath = initialAppearance?.imagePath ?? defaultImagePath;
    if (imagePath == null || imagePath == cardholderNameAppearance) {
      await writeDefaultSignatureImage(initialImage, fullName: cardholderName);
    } else {
      await normalizeSignatureImage(File(imagePath), initialImage);
    }
    await pdfrxFlutterInitialize();
    document = await PdfDocument.openFile(
      copy.path,
      passwordProvider: () async => null,
    );
    if (!context.mounted) return null;
    final route = DialogRoute<PdfAppearance>(
      context: context,
      builder: (_) => _AppearanceEditor(
        directory: directory,
        document: document!,
        service: service,
        initialInfo: info,
        cardholderTextOnly:
            imagePath == null || imagePath == cardholderNameAppearance,
        initialAppearance: initialAppearance,
        cardholderName: cardholderName,
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    if (result == null) return null;
    retained = true;
    return PreparedPdfSignature(directory, copy.path, result);
  } finally {
    await document?.dispose();
    if (!retained && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _AppearanceEditor extends StatefulWidget {
  const _AppearanceEditor({
    required this.directory,
    required this.document,
    required this.service,
    required this.initialInfo,
    required this.cardholderTextOnly,
    this.cardholderName,
    this.initialAppearance,
  });
  final Directory directory;
  final PdfDocument document;
  final CieService service;
  final JsonResult initialInfo;
  final bool cardholderTextOnly;
  final String? cardholderName;
  final PdfAppearance? initialAppearance;
  @override
  State<_AppearanceEditor> createState() => _AppearanceEditorState();
}

class _AppearanceEditorState extends State<_AppearanceEditor> {
  late bool cardholderTextOnly = widget.cardholderTextOnly;
  int page = 0, rotation = 0, imageRevision = 0;
  double left = .1, top = .75, width = .35;
  ui.Image? image;
  bool working = true;
  bool fitTextOnLoad = false, positionOnLoad = true;
  String? error;
  File get imageFile => File('${widget.directory.path}/originale.png');
  PdfPage get pdfPage => widget.document.pages[page];
  double get aspect => pdfPage.width / pdfPage.height;
  double get height => image == null
      ? .06
      : math.min(.5, width * aspect * image!.height / image!.width);
  @override
  void initState() {
    super.initState();
    final initial = widget.initialAppearance;
    if (initial != null && initial.page < widget.document.pages.length) {
      positionOnLoad = false;
      page = initial.page;
      left = initial.left;
      top = initial.top;
      width = initial.width;
      rotation = widget.document.pages[page].rotation.index * 90;
    } else {
      rotation = widget.initialInfo['rotation'] as int;
    }
    fitTextOnLoad = initial == null && cardholderTextOnly;
    _loadImage();
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final next = await decodeSignatureImage(imageFile);
      if (!mounted) {
        next.dispose();
        return;
      }
      setState(() {
        image?.dispose();
        image = next;
        if (fitTextOnLoad) {
          width = (width * next.width / 880).clamp(.12, .65);
          fitTextOnLoad = false;
        }
        if (positionOnLoad) {
          final origin = defaultSignaturePosition(
            Size(pdfPage.width, pdfPage.height),
            Size(width, height),
          );
          left = origin.dx;
          top = origin.dy;
          positionOnLoad = false;
        }
        working = false;
        imageRevision++;
        _clamp();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          working = false;
          error = 'Immagine non leggibile. Scegliere un PNG o JPEG.';
        });
      }
    }
  }

  void _clamp() {
    left = left.clamp(0, 1 - width);
    top = top.clamp(0, 1 - height);
  }

  Future<void> _page(int next) async {
    setState(() {
      working = true;
      error = null;
    });
    final info = await widget.service.pdfInfo(
      '${widget.directory.path}/documento.pdf',
      next,
    );
    if (!mounted) return;
    setState(() {
      working = false;
      if (info['ok'] == true &&
          info['pageCount'] == widget.document.pages.length) {
        page = next;
        rotation = info['rotation'] as int;
        _clamp();
      } else {
        error = 'Impossibile preparare questa pagina.';
      }
    });
  }

  Future<void> _chooseImage() async {
    final selected = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Immagine PNG o JPEG',
          extensions: ['png', 'jpg', 'jpeg'],
        ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      final decoded = await decodeSignatureImage(File(selected.path));
      try {
        await writeSignaturePng(decoded, imageFile);
        cardholderTextOnly = false;
      } finally {
        decoded.dispose();
      }
      await FileImage(imageFile).evict();
      await _loadImage();
    } catch (_) {
      if (mounted) {
        setState(() {
          working = false;
          error = 'Immagine non valida o troppo grande. Scegliere un PNG o JPEG fino a 16 megapixel e 10 MiB.';
        });
      }
    }
  }

  Future<void> _restoreName() async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await writeDefaultSignatureImage(
        imageFile,
        fullName: widget.cardholderName,
      );
      cardholderTextOnly = true;
      width = .35;
      fitTextOnLoad = true;
      await FileImage(imageFile).evict();
      await _loadImage();
    } catch (_) {
      if (mounted) {
        setState(() {
          working = false;
          error = 'Impossibile creare la firma grafica.';
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (working || image == null) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      final prepared = File('${widget.directory.path}/firma.png');
      final info = await widget.service.pdfInfo(
        '${widget.directory.path}/documento.pdf',
        page,
      );
      if (info['ok'] != true ||
          info['pageCount'] != widget.document.pages.length ||
          ((info['width'] as num?)?.toDouble() ?? 0) <= 0 ||
          ((info['height'] as num?)?.toDouble() ?? 0) <= 0 ||
          ((info['width'] as num).toDouble() - pdfPage.width).abs() > .5 ||
          ((info['height'] as num).toDouble() - pdfPage.height).abs() > .5 ||
          rotation != pdfPage.rotation.index * 90) {
        throw const FormatException(
          'Rotazione della pagina non coerente con l’anteprima.',
        );
      }
      await writeSignaturePng(image!, prepared);
      if (!mounted) return;
      Navigator.pop(
        context,
        PdfAppearance(
          imagePath: cardholderTextOnly
              ? cardholderNameAppearance
              : prepared.path,
          page: page,
          left: left,
          top: top,
          width: width,
          height: height,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          working = false;
          error = 'Impossibile preparare il segno grafico.';
        });
      }
    }
  }

  void _move(double x, double y) => setState(() {
    left += x;
    top += y;
    _clamp();
  });
  @override
  Widget build(BuildContext context) => SignatureAppearanceDialog(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, "Firma PDF con segno grafico"),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          widget.cardholderName?.isNotEmpty == true
              ? tr(
                  context,
                  "Scegli la pagina e trascina il riquadro. L’anteprima usa il Nome e Cognome verificati durante l’abbinamento; la firma li rilegge dalla CIE effettivamente usata dopo l'inserimento del PIN. Anche un’immagine personalizzata è accompagnata dal Nome e Cognome. Data e ora mostrate sono indicative: il documento riporterà quelle del momento della firma, con il fuso orario locale.",
                )
              : tr(
                  context,
                  "Scegli la pagina e trascina il riquadro. Il Nome e Cognome effettivi saranno letti dal certificato della CIE al momento della firma, dopo il PIN. Il testo mostrato ora indica solo la posizione; anche un’immagine personalizzata sarà accompagnata dal Nome e Cognome della CIE. Data e ora finali saranno inserite al momento della firma, con il fuso orario locale.",
                ),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            IconButton(
              tooltip: tr(context, "Pagina precedente"),
              onPressed: working || page == 0 ? null : () => _page(page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              tr(context, "Pagina {p0} di {p1}", [
                page + 1,
                widget.document.pages.length,
              ]),
            ),
            IconButton(
              tooltip: tr(context, "Pagina successiva"),
              onPressed: working || page + 1 == widget.document.pages.length
                  ? null
                  : () => _page(page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
            OutlinedButton.icon(
              onPressed: working ? null : _chooseImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(tr(context, "Personalizza immagine")),
            ),
            TextButton(
              onPressed: working || cardholderTextOnly ? null : _restoreName,
              child: Text(tr(context, "Ripristina firma testuale predefinita")),
            ),
          ],
        ),
        if (working) const LinearProgressIndicator(),
        AppNotification(message: error, error: true, enabled: !working, onDismissed: () { if (mounted) setState(() => error = null); }),
        LayoutBuilder(
          builder: (context, constraints) {
            final pageHeight = math.max(
              380.0,
              _SignaturePreviewViewport.heightOf(context) -
                  MediaQuery.textScalerOf(context).scale(240),
            );
            final w = math.min(constraints.maxWidth, pageHeight * aspect),
                h = w / aspect;
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: GestureDetector(
                  onTapDown: working
                      ? null
                      : (d) => setState(() {
                          left = d.localPosition.dx / w - width / 2;
                          top = d.localPosition.dy / h - height / 2;
                          _clamp();
                        }),
                  onPanUpdate: working
                      ? null
                      : (d) => _move(d.delta.dx / w, d.delta.dy / h),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PdfPageView(
                          document: widget.document,
                          pageNumber: page + 1,
                          maximumDpi: 144,
                          decoration: const BoxDecoration(color: Colors.white),
                        ),
                      ),
                      Positioned(
                        left: left * w,
                        top: top * h,
                        width: width * w,
                        height: height * h,
                        child: Container(
                          foregroundDecoration: const _DashedSignatureBorder(),
                          color: const Color(0x18FFFFFF),
                          child: image == null
                              ? const SizedBox()
                              : Column(
                                  children: [
                                    Expanded(
                                      child: Image.file(
                                        imageFile,
                                        key: ValueKey(imageRevision),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    if (!cardholderTextOnly)
                                      SizedBox(
                                        height:
                                            math.min(
                                              48.0,
                                              height * pdfPage.height * .65,
                                            ) /
                                            pdfPage.height *
                                            h,
                                        child: FittedBox(
                                          child: Text.rich(
                                            signatureTextSpan(
                                              fullName: widget.cardholderName,
                                              signingDate: DateTime.now(),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(tr(context, "Dimensione")),
            Expanded(
              child: Slider(
                value: width,
                min: .12,
                max: .65,
                onChanged: working
                    ? null
                    : (n) => setState(() {
                        width = n;
                        _clamp();
                      }),
              ),
            ),
            IconButton(
              tooltip: tr(context, "Sposta a sinistra"),
              onPressed: working ? null : () => _move(-.01, 0),
              icon: const RotatedBox(
                quarterTurns: 2,
                child: Icon(Icons.play_arrow, size: 20),
              ),
            ),
            IconButton(
              tooltip: tr(context, "Sposta a destra"),
              onPressed: working ? null : () => _move(.01, 0),
              icon: const RotatedBox(
                quarterTurns: 0,
                child: Icon(Icons.play_arrow, size: 20),
              ),
            ),
            IconButton(
              tooltip: tr(context, "Sposta in alto"),
              onPressed: working ? null : () => _move(0, -.01),
              icon: const RotatedBox(
                quarterTurns: 3,
                child: Icon(Icons.play_arrow, size: 20),
              ),
            ),
            IconButton(
              tooltip: tr(context, "Sposta in basso"),
              onPressed: working ? null : () => _move(0, .01),
              icon: const RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.play_arrow, size: 20),
              ),
            ),
          ],
        ),
      ],
    ),
    actions: Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        TextButton(
          onPressed: working ? null : () => Navigator.pop(context),
          child: Text(tr(context, "Annulla")),
        ),
        FilledButton(
          onPressed: working || image == null ? null : _confirm,
          child: Text(tr(context, "Conferma anteprima")),
        ),
      ],
    ),
  );
}

/// Keeps the preview actions visible while its document and controls scroll.
class SignatureAppearanceDialog extends StatelessWidget {
  const SignatureAppearanceDialog({
    super.key,
    required this.content,
    required this.actions,
  });

  final Widget content;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _SignaturePreviewViewport(
                  height: constraints.maxHeight,
                  child: SingleChildScrollView(child: content),
                ),
              ),
            ),
            const Divider(height: 24),
            actions,
          ],
        ),
      ),
    ),
  );
}

class _SignaturePreviewViewport extends InheritedWidget {
  const _SignaturePreviewViewport({required this.height, required super.child});

  final double height;

  static double heightOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SignaturePreviewViewport>()
      ?.height ?? MediaQuery.sizeOf(context).height;

  @override
  bool updateShouldNotify(_SignaturePreviewViewport oldWidget) =>
      height != oldWidget.height;
}

class _DashedSignatureBorder extends Decoration {
  const _DashedSignatureBorder();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedSignaturePainter();
}

class _DashedSignaturePainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = (offset & size).deflate(.75);
    final path = Path()..addRect(rect);
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (double start = 0; start < metric.length; start += 9) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 5, metric.length)),
          paint,
        );
      }
    }
  }
}
