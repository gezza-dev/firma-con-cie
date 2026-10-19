// SPDX-License-Identifier: BSD-3-Clause
#include "CiePdfSignatureField.h"
#include <algorithm>
#include <stdexcept>
#include <filesystem>
#include <fstream>
#include <vector>
namespace cie {
void setSignatureAppearance(PoDoFo::PdfDocument& document, PoDoFo::PdfSignature& signature,
    const PoDoFo::Rect& rectangle, const char* imagePath, const char* description, const char* date)
{
    using namespace PoDoFo;
    auto appearance = document.CreateXObjectForm(Rect(0, 0, rectangle.Width, rectangle.Height));
    PdfPainter painter;
    painter.SetCanvas(*appearance);
    const bool hasImage=imagePath && *imagePath;
    const bool hasText=description && *description;
    double borderWidth=rectangle.Width;
    const double textHeight=hasText ? (hasImage ? std::min(48.0,rectangle.Height*.65) : rectangle.Height) : 0;
    if (hasImage) {
        auto image = document.CreateImage();
        std::ifstream file(std::filesystem::u8path(imagePath),std::ios::binary|std::ios::ate);
        auto size=file.tellg();if(!file || size<=0 || size>10*1024*1024) throw std::runtime_error("Invalid signature image size");
        std::vector<char> encoded(static_cast<size_t>(size));file.seekg(0);
        if(!file.read(encoded.data(),size)) throw std::runtime_error("Unreadable signature image");
        image->LoadFromBuffer(bufferview(encoded.data(),encoded.size()));
        if (!image->GetWidth() || !image->GetHeight()) throw std::runtime_error("Invalid signature image");
        double scale = std::min(rectangle.Width / image->GetWidth(), (rectangle.Height-textHeight) / image->GetHeight());
        painter.DrawImage(*image, (rectangle.Width - image->GetWidth() * scale) / 2,
            textHeight+(rectangle.Height-textHeight-image->GetHeight()*scale)/2, scale, scale);
    }
    if (hasText) {
        auto& font = document.GetFonts().GetStandard14Font(PdfStandard14FontType::Helvetica);
        const double padding=std::min(2.0,std::min(rectangle.Width,textHeight)*.1);
        constexpr const char* signerCaption="Firmato digitalmente da/Signed by:";
        constexpr const char* dateCaption="In Data/On Date:";
        double fontSize=std::min(24.0,(textHeight-2*padding)/4.25);
        const double baseSize=fontSize;
        painter.TextState.SetFont(font,fontSize);
        double nameWidth=0,dateWidth=0,signerWidth=0,dateCaptionWidth=0;
        if(!font.TryGetStringLength(description,painter.TextState,nameWidth) || nameWidth<=0 || !date ||
           !font.TryGetStringLength(date,painter.TextState,dateWidth) ||
           !font.TryGetStringLength(signerCaption,painter.TextState,signerWidth) ||
           !font.TryGetStringLength(dateCaption,painter.TextState,dateCaptionWidth))
            throw std::runtime_error("Cardholder label cannot be represented by the PDF font");
        const double maxWidth=std::max({nameWidth,.85*dateWidth,.6*signerWidth,.6*dateCaptionWidth});
        fontSize*=std::min(1.0,(rectangle.Width-2*padding)/maxWidth);
        if(!hasImage)borderWidth=std::min(rectangle.Width,maxWidth*fontSize/baseSize+2*padding);
        if(fontSize<=0)throw std::runtime_error("Invalid cardholder label rectangle");
        const double bottom=padding+(textHeight-2*padding-4.25*fontSize)/2;
        painter.GraphicsState.SetNonStrokingColor(PdfColor(100.0/255,181.0/255,246.0/255));
        painter.TextState.SetFont(font,.6*fontSize);
        painter.DrawText(signerCaption,padding,bottom+3.45*fontSize);
        painter.DrawText(dateCaption,padding,bottom+1.1*fontSize);
        painter.GraphicsState.SetNonStrokingColor(PdfColor(0.0));
        painter.TextState.SetFont(font,fontSize);
        painter.DrawText(description,padding,bottom+2.1*fontSize);
        painter.TextState.SetFont(font,.85*fontSize);
        painter.DrawText(date,padding,bottom);

    }
    const double inset=std::min(.5,std::min(rectangle.Width,rectangle.Height)/4);
    painter.GraphicsState.SetLineWidth(inset);
    painter.GraphicsState.SetStrokingColor(PdfColor(.35));
    painter.SetStrokeStyle(PdfStrokeStyle::Dash);
    painter.DrawRectangle(inset,inset,borderWidth-2*inset,rectangle.Height-2*inset);
    painter.FinishDrawing();
    signature.MustGetWidget().SetAppearanceStream(*appearance);
}
}
