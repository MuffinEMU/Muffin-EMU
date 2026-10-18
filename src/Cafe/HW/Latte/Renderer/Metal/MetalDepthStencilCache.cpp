#include "Cafe/HW/Latte/Renderer/Metal/MetalDepthStencilCache.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "HW/Latte/ISA/RegDefines.h"
#include "HW/Latte/Renderer/Metal/LatteToMtl.h"
#include "Metal/MTLDepthStencil.hpp"

MetalDepthStencilCache::~MetalDepthStencilCache()
{
    for (auto& pair : m_depthStencilCache)
    {
        pair.second->release();
    }
    m_depthStencilCache.clear();
}

MTL::DepthStencilState* MetalDepthStencilCache::GetDepthStencilState(const LatteContextRegister& lcr, bool hasDepthAttachment, bool hasStencilAttachment)
{
    uint64 stateHash = CalculateDepthStencilHash(lcr, hasDepthAttachment, hasStencilAttachment);
    auto& depthStencilState = m_depthStencilCache[stateHash];
    if (depthStencilState)
        return depthStencilState;

	// Depth stencil state
	bool depthEnable = hasDepthAttachment && lcr.DB_DEPTH_CONTROL.get_Z_ENABLE();
	auto depthFunc = lcr.DB_DEPTH_CONTROL.get_Z_FUNC();
	bool depthWriteEnable = hasDepthAttachment && lcr.DB_DEPTH_CONTROL.get_Z_WRITE_ENABLE();

	NS_STACK_SCOPED MTL::DepthStencilDescriptor* desc = MTL::DepthStencilDescriptor::alloc()->init();
	if (depthEnable)
	{
	    desc->setDepthWriteEnabled(depthWriteEnable);
	    desc->setDepthCompareFunction(GetMtlCompareFunc(depthFunc));
	}

	// Stencil state. A pass whose depth texture has no stencil (D32_FLOAT, D16_UNORM) binds no stencil attachment, and
	// a stencil test on such a pass is undefined on Metal: the tile has no stencil to test against, so fragments can be
	// dropped at random. The guest often leaves the stencil test on from an earlier pass (a shadow-map pass after the
	// main scene), so it is switched off here, which is what Vulkan does when the pass has no stencil attachment.
	bool stencilEnable = hasStencilAttachment && lcr.DB_DEPTH_CONTROL.get_STENCIL_ENABLE();
	if (stencilEnable)
	{
	    // get stencil control parameters
    	bool backStencilEnable = lcr.DB_DEPTH_CONTROL.get_BACK_STENCIL_ENABLE();
    	auto frontStencilFunc = lcr.DB_DEPTH_CONTROL.get_STENCIL_FUNC_F();
    	auto frontStencilZPass = lcr.DB_DEPTH_CONTROL.get_STENCIL_ZPASS_F();
    	auto frontStencilZFail = lcr.DB_DEPTH_CONTROL.get_STENCIL_ZFAIL_F();
    	auto frontStencilFail = lcr.DB_DEPTH_CONTROL.get_STENCIL_FAIL_F();
    	auto backStencilFunc = lcr.DB_DEPTH_CONTROL.get_STENCIL_FUNC_B();
    	auto backStencilZPass = lcr.DB_DEPTH_CONTROL.get_STENCIL_ZPASS_B();
    	auto backStencilZFail = lcr.DB_DEPTH_CONTROL.get_STENCIL_ZFAIL_B();
    	auto backStencilFail = lcr.DB_DEPTH_CONTROL.get_STENCIL_FAIL_B();
    	// get stencil control parameters
    	uint32 stencilCompareMaskFront = lcr.DB_STENCILREFMASK.get_STENCILMASK_F();
    	uint32 stencilWriteMaskFront = lcr.DB_STENCILREFMASK.get_STENCILWRITEMASK_F();
    	uint32 stencilCompareMaskBack = lcr.DB_STENCILREFMASK_BF.get_STENCILMASK_B();
    	uint32 stencilWriteMaskBack = lcr.DB_STENCILREFMASK_BF.get_STENCILWRITEMASK_B();

    	NS_STACK_SCOPED MTL::StencilDescriptor* frontStencil = MTL::StencilDescriptor::alloc()->init();
    	frontStencil->setReadMask(stencilCompareMaskFront);
    	frontStencil->setWriteMask(stencilWriteMaskFront);
    	frontStencil->setStencilCompareFunction(GetMtlCompareFunc(frontStencilFunc));
    	frontStencil->setDepthFailureOperation(GetMtlStencilOp(frontStencilZFail));
    	frontStencil->setStencilFailureOperation(GetMtlStencilOp(frontStencilFail));
    	frontStencil->setDepthStencilPassOperation(GetMtlStencilOp(frontStencilZPass));
    	desc->setFrontFaceStencil(frontStencil);

    	NS_STACK_SCOPED MTL::StencilDescriptor* backStencil = MTL::StencilDescriptor::alloc()->init();
    	if (backStencilEnable)
    	{
           	backStencil->setReadMask(stencilCompareMaskBack);
           	backStencil->setWriteMask(stencilWriteMaskBack);
           	backStencil->setStencilCompareFunction(GetMtlCompareFunc(backStencilFunc));
           	backStencil->setDepthFailureOperation(GetMtlStencilOp(backStencilZFail));
           	backStencil->setStencilFailureOperation(GetMtlStencilOp(backStencilFail));
           	backStencil->setDepthStencilPassOperation(GetMtlStencilOp(backStencilZPass));
    	}
    	else
    	{
           	backStencil->setReadMask(stencilCompareMaskFront);
           	backStencil->setWriteMask(stencilWriteMaskFront);
           	backStencil->setStencilCompareFunction(GetMtlCompareFunc(frontStencilFunc));
           	backStencil->setDepthFailureOperation(GetMtlStencilOp(frontStencilZFail));
           	backStencil->setStencilFailureOperation(GetMtlStencilOp(frontStencilFail));
           	backStencil->setDepthStencilPassOperation(GetMtlStencilOp(frontStencilZPass));
    	}
    	desc->setBackFaceStencil(backStencil);
	}

	depthStencilState = m_mtlr->GetDevice()->newDepthStencilState(desc);

	return depthStencilState;
}

uint64 MetalDepthStencilCache::CalculateDepthStencilHash(const LatteContextRegister& lcr, bool hasDepthAttachment, bool hasStencilAttachment)
{
    if (!hasDepthAttachment)
        return 0;

    uint32* ctxRegister = lcr.GetRawView();

    // The state is fully described by DB_DEPTH_CONTROL plus the compare and write masks of each face, which is
    // exactly 64 bits, so they are packed side by side instead of hashed. The old rotate-and-add hash let the
    // stencil write mask spill into the depth control bits, so two different states could share one key and a
    // draw got the other one's depth test or stencil setup. The stencil reference is left out: it is set per
    // draw with setStencilReferenceValues and is not part of the state object.
    uint32 depthControl = ctxRegister[Latte::REGADDR::DB_DEPTH_CONTROL];
    uint64 frontMasks = 0;
    uint64 backMasks = 0;
    // Bit 0 is STENCIL_ENABLE and bit 7 BACK_STENCIL_ENABLE; a stencil test without a stencil attachment is not
    // applied (see GetDepthStencilState), so its key is the one of the same state with the test off
    const bool stencilTestEnable = (depthControl & 1) && hasStencilAttachment;
    if (stencilTestEnable)
    {
        frontMasks = (ctxRegister[mmDB_STENCILREFMASK] >> 8) & 0xFFFF; // STENCILMASK_F, STENCILWRITEMASK_F
        if (depthControl & (1 << 7)) // back stencil enable
            backMasks = (ctxRegister[mmDB_STENCILREFMASK_BF] >> 8) & 0xFFFF; // STENCILMASK_B, STENCILWRITEMASK_B
    }
    else
    {
        // zero out the stencil related bits: the two enables and the ops and functions (8-31)
        depthControl &= 0xFF & ~((1u << 0) | (1u << 7));
    }

    return (uint64)depthControl | (frontMasks << 32) | (backMasks << 48);
}
