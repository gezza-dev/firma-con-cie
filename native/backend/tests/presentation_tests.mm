#import "../CIE ID/AppPresentation.h"
#include <cstdio>
#include <cstdlib>

static void require(BOOL result, const char *message) {
    if (!result) { fprintf(stderr, "%s\n", message); exit(1); }
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTextField *label = [NSTextField labelWithString:@"Si è verificato un errore durante la firma"];
        label.font = [NSFont systemFontOfSize:19];
        CIEWrapLabel(label, 276);
        NSSize size = [label.cell cellSizeForBounds:NSMakeRect(0, 0, 276, CGFLOAT_MAX)];
        require(size.height > 23 && size.height < 100, "Signing failure must wrap to multiple lines within the status panel");
        require(size.width <= 276, "Signing failure must fit horizontally");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 815, 570)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        NSArray<NSString *> *messages = @[
            @"Il PIN digitato è errato. Rimangono 2 tentativi",
            @"La CIE risulta essere già stata associata precedentemente, per cui l'operazione di firma è stata annullata. Ripetere il procedimento, selezionando la CIE dal selettore presente in 'Firma Elettronica'.",
            [@"Messaggio diagnostico con dettagli e percorso del documento.\n" stringByPaddingToLength:12000 withString:@"Dettagli dell'errore di firma. " startingAtIndex:0]
        ];
        for (NSString *message in messages) {
            NSAlert *alert = CIEMessageAlert(@"Errore durante la firma", message, window);
            NSScrollView *scroll = (NSScrollView *)alert.accessoryView;
            NSTextView *text = (NSTextView *)scroll.documentView;
            require([text.string isEqualToString:message], "Alert must preserve the entire diagnostic");
            require(NSWidth(scroll.frame) < NSWidth(window.frame) && NSHeight(scroll.frame) <= 300,
                "Alert body must fit the main window");
            require(NSHeight(text.frame) <= NSHeight(scroll.frame) || scroll.hasVerticalScroller,
                "Long diagnostics must remain accessible by scrolling");
            require(text.layoutManager.firstUnlaidCharacterIndex >= message.length,
                "All diagnostic text must be laid out");
        }
        puts("Presentation layout checks passed");
    }
    return 0;
}
