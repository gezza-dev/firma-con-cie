// SPDX-License-Identifier: BSD-3-Clause
#import "../CIE ID/HelpNavigation.h"
#include <cstdio>
#include <cstdlib>

static void require(BOOL result, const char *message) {
    if (!result) { fprintf(stderr, "%s\n", message); exit(1); }
}

int main() {
    @autoreleasepool {
        NSURL *guide = [NSURL fileURLWithPath:@"/Applications/CIE ID.app/Contents/Resources/Guida.html"];
        NSURL *web = [NSURL URLWithString:@"https://www.cartaidentita.interno.gov.it/info-utili/software-cie-2/"];
        require(CIEHelpPolicy(guide, WKNavigationTypeOther, YES, guide) == CIEHelpNavigationAllow,
            "The bundled guide must load without Internet");
        require(CIEHelpPolicy([NSURL URLWithString:@"#firma" relativeToURL:guide].absoluteURL,
            WKNavigationTypeLinkActivated, YES, guide) == CIEHelpNavigationAllow,
            "Table-of-contents anchors must remain inside the guide");
        require(CIEHelpPolicy(web, WKNavigationTypeLinkActivated, YES, guide) == CIEHelpNavigationOpenExternally,
            "A normal web link must open in the default browser");
        require(CIEHelpPolicy(web, WKNavigationTypeLinkActivated, NO, guide) == CIEHelpNavigationOpenExternally,
            "A target=_blank link must also open in the default browser");
        require(CIEHelpPolicy(web, WKNavigationTypeOther, NO, guide) == CIEHelpNavigationCancel,
            "Scripted popups must not launch external apps");
        require(CIEHelpPolicy([NSURL URLWithString:@"https://idserver.servizicie.interno.gov.it/idp/aiuto.jsp"],
            WKNavigationTypeOther, YES, guide) == CIEHelpNavigationAllow,
            "The existing remote help page must still load inside the app");
        require(CIEHelpPolicy([NSURL URLWithString:@"mailto:example@example.org"],
            WKNavigationTypeLinkActivated, YES, guide) == CIEHelpNavigationOpenExternally,
            "An explicit email link must reach the default mail app");
        for (NSString *address in @[@"file:///etc/passwd", @"file:///Applications/CIE%20ID.app/Contents/Resources/other.html",
                @"javascript:alert(1)", @"data:text/html,example", @"custom-app:example"]) {
            require(CIEHelpPolicy([NSURL URLWithString:address], WKNavigationTypeLinkActivated, YES, guide)
                == CIEHelpNavigationCancel, "Unrelated local files and unsupported schemes must not be opened");
        }
        require(CIEHelpPolicy(nil, WKNavigationTypeOther, YES, guide) == CIEHelpNavigationCancel,
            "Missing navigation URLs must be rejected");
        require(CIEHelpPolicy([NSURL URLWithString:@"about:blank"], WKNavigationTypeOther, YES, guide)
            == CIEHelpNavigationAllow, "The missing-guide fallback must be renderable");
        puts("Help navigation checks passed");
    }
}
