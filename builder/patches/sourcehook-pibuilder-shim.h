/* css34: modern ProtoInfo/PassInfo/CProtoInfoBuilder for bintools on SH v4 headers.
 * SourceHook v4 (core-legacy) uses a compact ProtoInfo layout for hook runtime;
 * bintools 1.11 expects the newer PassInfo-based API. Define SOURCEMOD_BINTOOLS_PROTO_SHIM
 * before including sourcehook.h so the legacy ProtoInfo struct is omitted here.
 */
#ifndef __SOURCEHOOK_PIBUILDER_H__
#define __SOURCEHOOK_PIBUILDER_H__

#define SOURCEMOD_BINTOOLS_PROTO_SHIM 1
#include "sourcehook.h"
#undef SOURCEMOD_BINTOOLS_PROTO_SHIM

#include "sh_vector.h"
#include <string.h>

namespace SourceHook
{
	struct PassInfo
	{
		enum PassType
		{
			PassType_Unknown = 0,
			PassType_Basic,
			PassType_Float,
			PassType_Object,
		};

		enum PassFlags
		{
			PassFlag_ByVal    = (1<<0),
			PassFlag_ByRef    = (1<<1),
			PassFlag_ODtor    = (1<<2),
			PassFlag_OCtor    = (1<<3),
			PassFlag_AssignOp = (1<<4),
			PassFlag_CCtor    = (1<<5),
			PassFlag_RetMem   = (1<<6),
			PassFlag_RetReg   = (1<<7)
		};

		size_t size;
		int type;
		unsigned int flags;

		struct V2Info
		{
			void *pNormalCtor;
			void *pCopyCtor;
			void *pDtor;
			void *pAssignOperator;
		};
	};

	struct ProtoInfo
	{
		enum CallConvention
		{
			CallConv_Unknown,
			CallConv_ThisCall,
			CallConv_Cdecl,
			CallConv_StdCall,

			CallConv_HasVarArgs = (1<<16),
			CallConv_HasVafmt = CallConv_HasVarArgs | (1<<17)
		};

		int numOfParams;
		PassInfo retPassInfo;
		const PassInfo *paramsPassInfo;
		int convention;
		PassInfo::V2Info retPassInfo2;
		const PassInfo::V2Info *paramsPassInfo2;
	};

	class CProtoInfoBuilder
	{
		ProtoInfo m_PI;
		CVector<PassInfo> m_Params;
		CVector<PassInfo::V2Info> m_Params2;
	public:
		CProtoInfoBuilder(int cc)
		{
			memset(reinterpret_cast<void*>(&m_PI), 0, sizeof(ProtoInfo));
			m_PI.convention = cc;

			PassInfo dummy;
			PassInfo::V2Info dummy2;
			memset(reinterpret_cast<void*>(&dummy), 0, sizeof(PassInfo));
			memset(reinterpret_cast<void*>(&dummy2), 0, sizeof(PassInfo::V2Info));

			dummy.size = 1;

			m_Params.push_back(dummy);
			m_Params2.push_back(dummy2);
		}

		void SetReturnType(size_t size, PassInfo::PassType type, int flags,
			void *pNormalCtor, void *pCopyCtor, void *pDtor, void *pAssignOperator)
		{
			if (pNormalCtor)
				flags |= PassInfo::PassFlag_OCtor;
			if (pCopyCtor)
				flags |= PassInfo::PassFlag_CCtor;
			if (pDtor)
				flags |= PassInfo::PassFlag_ODtor;
			if (pAssignOperator)
				flags |= PassInfo::PassFlag_AssignOp;

			m_PI.retPassInfo.size = size;
			m_PI.retPassInfo.type = type;
			m_PI.retPassInfo.flags = flags;
			m_PI.retPassInfo2.pNormalCtor = pNormalCtor;
			m_PI.retPassInfo2.pCopyCtor = pCopyCtor;
			m_PI.retPassInfo2.pDtor = pDtor;
			m_PI.retPassInfo2.pAssignOperator = pAssignOperator;
		}

		void AddParam(size_t size, PassInfo::PassType type, int flags,
			void *pNormalCtor, void *pCopyCtor, void *pDtor, void *pAssignOperator)
		{
			PassInfo pi;
			PassInfo::V2Info pi2;

			if (pNormalCtor)
				flags |= PassInfo::PassFlag_OCtor;
			if (pCopyCtor)
				flags |= PassInfo::PassFlag_CCtor;
			if (pDtor)
				flags |= PassInfo::PassFlag_ODtor;
			if (pAssignOperator)
				flags |= PassInfo::PassFlag_AssignOp;

			pi.size = size;
			pi.type = type;
			pi.flags = flags;
			pi2.pNormalCtor = pNormalCtor;
			pi2.pCopyCtor = pCopyCtor;
			pi2.pDtor = pDtor;
			pi2.pAssignOperator = pAssignOperator;

			m_Params.push_back(pi);
			m_Params2.push_back(pi2);
			++m_PI.numOfParams;
		}

		operator ProtoInfo*()
		{
			m_PI.paramsPassInfo = &(m_Params[0]);
			m_PI.paramsPassInfo2 = &(m_Params2[0]);
			return &m_PI;
		}
	};
}

#endif
