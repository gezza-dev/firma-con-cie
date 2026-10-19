/*
 * PdfSignatureGenerator.cpp
 * Created by svp on 26/05/12.
 * Copyright 2012 __MyCompanyName__. All rights reserved.
 * Modified for the independent native fork: PoDoFo 1.1 deferred signing.
 */
#include "PdfSignatureGenerator.h"
#include "CiePdfSignatureField.h"
#include "PdfVerifier.h"
#include "Native/SigningTime.h"
#include "../../native/OpenSslRuntime.h"
#include <stdexcept>
#include <vector>
#include <cstring>

using namespace PoDoFo;
namespace {
class ExternalCmsSigner final : public PdfSigner {
public:
    charbuff bytes;
    std::string subFilter;
    void Reset() override { bytes.clear(); }
    void AppendData(const bufferview& value) override { bytes.insert(bytes.end(), value.begin(), value.end()); }
    void ComputeSignature(charbuff& result, bool dryrun) override {
        if (!dryrun) throw std::logic_error("Use deferred signing");
        result.resize(32768);
    }
    void FetchIntermediateResult(charbuff& result) override { result = bytes; }
    void ComputeSignatureDeferred(const bufferview& cms, charbuff& result, bool dryrun) override {
        if (dryrun) { result.resize(32768); return; }
        if (cms.empty() || cms.size() > 32768) throw std::runtime_error("CMS signature exceeds reserved space");
        result.assign(cms.begin(), cms.end());
    }
    std::string GetSignatureSubFilter() const override { return subFilter; }
    std::string GetSignatureType() const override { return subFilter == "ETSI.RFC3161" ? "DocTimeStamp" : "Sig"; }
};
}
struct PdfSignatureGenerator::State {
    PdfMemDocument document;
    charbuff input, output;
    std::shared_ptr<BufferStreamDevice> device;
    std::shared_ptr<ExternalCmsSigner> signer;
    PdfSigningContext signing;
    PdfSigningResults results;
    PdfSignerId id;
    bool loaded = false, started = false, finished = false;
};
PdfSignatureGenerator::PdfSignatureGenerator() : state_(new State) { }
PdfSignatureGenerator::~PdfSignatureGenerator() = default;
int PdfSignatureGenerator::Load(const char* pdf, int length)
{
    if (!pdf || length <= 0 || !cie::initializeOpenSsl()) return -1;
    try {
        state_.reset(new State);
        state_->input.assign(pdf, pdf + length);
        state_->document.LoadFromBuffer(bufferview(state_->input.data(), state_->input.size()));
        state_->loaded = true;
        return PDFVerifier::GetNumberOfSignatures(&state_->document);
    } catch (...) { state_.reset(new State); return -2; }
}
void PdfSignatureGenerator::AddFont(const char*, const char* path)
{
    if (path && *path) state_->document.GetFonts().GetOrCreateFont(path);
}
void PdfSignatureGenerator::InitSignature(int page, const char* reason, const char* reasonLabel,
    const char* name, const char* nameLabel, const char* location, const char* locationLabel,
    const char* field, const char* subFilter)
{
    InitSignature(page, 0, 0, 0, 0, reason, reasonLabel, name, nameLabel, location, locationLabel, field, subFilter);
}
void PdfSignatureGenerator::InitSignature(int page, float left, float bottom, float width, float height,
    const char* reason, const char* reasonLabel, const char* name, const char* nameLabel,
    const char* location, const char* locationLabel, const char* field, const char* subFilter)
{
    InitSignature(page, left, bottom, width, height, reason, reasonLabel, name, nameLabel,
        location, locationLabel, field, subFilter, nullptr, nullptr, nullptr, nullptr);
}
void PdfSignatureGenerator::InitSignature(int page, float left, float bottom, float width, float height,
    const char* reason, const char*, const char* name, const char*, const char* location, const char*,
    const char* field, const char* subFilter, const char* image, const char* description,
    const char* graphometricData, const char*)
{
    if (!state_->loaded || state_->started || page < 0) throw std::logic_error("Invalid PDF signing state");
    if (graphometricData && *graphometricData) throw std::runtime_error("Private graphometric format is unsupported");
    auto& target = state_->document.GetPages().GetPageAt(unsigned(page));
    // GetCropBox swaps dimensions but keeps the raw origin. Transform both
    // corners around MediaBox so offset/rotated CropBoxes use displayed axes.
    auto crop = Rect::FromCorners(target.GetCropBoxRaw());
    double angle;
    if (target.TryGetRotationRadians(angle)) {
        auto transform = GetFrameRotationTransform(Rect::FromCorners(target.GetMediaBoxRaw()), angle);
        auto raw = target.GetCropBoxRaw();
        crop = Rect::FromCorners(raw.GetCorner1() * transform, raw.GetCorner2() * transform);
    }
    Rect rectangle(crop.X + left * crop.Width, crop.Y + crop.Height - bottom * crop.Height, width * crop.Width, height * crop.Height);
    auto& signature = target.CreateField<PdfSignature>(field && *field ? field : "Signature", rectangle);
    // The public setter maps displayed coordinates through page rotation.
    signature.MustGetWidget().SetRect(rectangle);
    const auto instant = std::time(nullptr);
    const auto local = cie::localSigningTime(instant);
    // Appearance and PDF metadata use exactly one instant and the same offset.
    const PdfDate date(std::chrono::seconds(instant), std::chrono::minutes(local.offsetMinutes));
    signature.SetSignatureDate(date);
    const std::string& visibleDate = local.visible;
    if (reason && *reason) signature.SetSignatureReason(PdfString(reason));
    if (name && *name) signature.SetSignerName(PdfString(name));
    if (location && *location) signature.SetSignatureLocation(PdfString(location));
    if (rectangle.Width > 0 && rectangle.Height > 0) cie::setSignatureAppearance(state_->document, signature, rectangle, image, description, visibleDate.c_str());
    state_->signer = std::make_shared<ExternalCmsSigner>();
    state_->signer->subFilter = subFilter && *subFilter ? subFilter : "adbe.pkcs7.detached";
    state_->output = state_->input;
    state_->device = std::make_shared<BufferStreamDevice>(state_->output);
    state_->id = state_->signing.AddSigner(signature, state_->signer);
    // Always append a revision: existing signatures and their signed bytes
    // remain untouched, including the first signing of an existing document.
    state_->signing.StartSigning(state_->document, state_->device, state_->results, PdfSaveOptions::NoMetadataUpdate);
    state_->started = true;
}
void PdfSignatureGenerator::GetBufferForSignature(UUCByteArray& output)
{
    if (!state_->started) throw std::logic_error("PDF signing has not started");
    auto& data = state_->results.Intermediate.at(state_->id);
    output.append(reinterpret_cast<const BYTE*>(data.data()), data.size());
}
void PdfSignatureGenerator::SetSignature(const char* cms, int length)
{
    if (!state_->started || state_->finished || !cms || length <= 0) throw std::logic_error("Invalid CMS signature");
    state_->results.Intermediate[state_->id].assign(cms, cms + length);
    state_->signing.FinishSigning(state_->results);
    state_->finished = true;
}
void PdfSignatureGenerator::GetSignedPdf(UUCByteArray& output)
{
    if (!state_->finished) throw std::logic_error("PDF signing is incomplete");
    output.append(reinterpret_cast<const BYTE*>(state_->output.data()), state_->output.size());
}
const double PdfSignatureGenerator::getWidth(int page)
{
    return state_->loaded ? state_->document.GetPages().GetPageAt(unsigned(page)).GetRect().Width : 0;
}
const double PdfSignatureGenerator::getHeight(int page)
{
    return state_->loaded ? state_->document.GetPages().GetPageAt(unsigned(page)).GetRect().Height : 0;
}
