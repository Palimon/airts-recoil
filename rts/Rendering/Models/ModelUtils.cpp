#include "ModelUtils.h"

#include <cassert>
#include <string>
#include <numeric>
#include <algorithm>
#include <array>
#include <cstring>
#include <unordered_map>

#include "3DModelLog.h"
#include "3DModelDefs.hpp"
#include "3DModel.hpp"
#include "3DModelPiece.hpp"
#include "System/Misc/TracyDefs.h"
#include "Lua/LuaParser.h"

using namespace Skinning;

uint16_t Skinning::GetBoneID(const SVertexData& vert, size_t wi)
{
	return vert.boneIDsLow[wi] | (vert.boneIDsHigh[wi] << 8);
};

namespace {
	// Slot 0 must hold the bone of the piece the vertex is stored in (vertex positions are in
	// that piece's bind space and the GL4 vertex shaders treat slot 0 as the vertex's own space).
	// Moves boneID to slot 0 (weight 0 if the vertex has no such influence) and keeps the
	// vertex's other influences in slots 1-3 in their existing (descending) weight order, so the
	// heaviest real influences sit where every shader reads them. If the vertex had four
	// influences and none was boneID, the lightest one is dropped and the rest renormalized to 255.
	void MakeBoneFirst(SVertexData& vert, uint16_t boneID)
	{
		if (GetBoneID(vert, 0) == boneID)
			return;

		std::array<std::pair<uint16_t, uint8_t>, SVertexData::MAX_BONES_PER_VERTEX> out;
		out.fill({ static_cast<uint16_t>(INV_PIECE_NUM), 0 });
		out[0] = { boneID, 0 };

		size_t n = 1;
		uint32_t dropped = 0;
		for (size_t wi = 0; wi < out.size(); ++wi) {
			const auto bID = GetBoneID(vert, wi);
			const auto bW = vert.boneWeights[wi];

			if (bID == boneID) {
				out[0].second = bW;
				continue;
			}
			if (bID == INV_PIECE_NUM)
				continue;

			if (n < out.size())
				out[n++] = { bID, bW };
			else
				dropped += bW;
		}

		if (dropped > 0) {
			uint32_t kept = 0;
			for (const auto& [bID, bW] : out)
				kept += bW;

			if (kept > 0) {
				int32_t sum = 0;
				size_t maxIdx = 0;
				for (size_t wi = 0; wi < out.size(); ++wi) {
					out[wi].second = static_cast<uint8_t>(std::min<uint32_t>(255, (out[wi].second * 255u + kept / 2) / kept));
					sum += out[wi].second;
					if (out[wi].second > out[maxIdx].second)
						maxIdx = wi;
				}
				// absorb the rounding error in the heaviest influence
				out[maxIdx].second = static_cast<uint8_t>(std::clamp<int32_t>(out[maxIdx].second + (255 - sum), 0, 255));
			}
		}

		for (size_t wi = 0; wi < out.size(); ++wi) {
			vert.boneIDsLow [wi] = static_cast<uint8_t>((out[wi].first     ) & 0xFF);
			vert.boneIDsHigh[wi] = static_cast<uint8_t>((out[wi].first >> 8) & 0xFF);
			vert.boneWeights[wi] = out[wi].second;
		}
	}

	// exact-match key for vertex de-duplication in ReparentMeshesTrianglesToBones
	struct VertKey {
		std::array<uint32_t, 3 + 3 + 2 * 2> f; // pos, normal, uv0, uv1 bit patterns
		std::array<uint8_t, 12> b;             // bone ids low/high and weights

		explicit VertKey(const SVertexData& v) {
			const float src[] = {
				v.pos.x, v.pos.y, v.pos.z,
				v.normal.x, v.normal.y, v.normal.z,
				v.texCoords[0].x, v.texCoords[0].y,
				v.texCoords[1].x, v.texCoords[1].y,
			};
			static_assert(sizeof(src) == sizeof(f));
			std::memcpy(f.data(), src, sizeof(src));

			for (size_t i = 0; i < 4; ++i) {
				b[i + 0] = v.boneIDsLow[i];
				b[i + 4] = v.boneIDsHigh[i];
				b[i + 8] = v.boneWeights[i];
			}
		}
		bool operator == (const VertKey& o) const { return f == o.f && b == o.b; }
	};

	struct VertKeyHash {
		size_t operator() (const VertKey& k) const {
			uint64_t h = 1469598103934665603ull; // FNV-1a
			const auto mix = [&h](const uint8_t* p, size_t n) {
				for (size_t i = 0; i < n; ++i) { h ^= p[i]; h *= 1099511628211ull; }
			};
			mix(reinterpret_cast<const uint8_t*>(k.f.data()), sizeof(k.f));
			mix(k.b.data(), sizeof(k.b));
			return static_cast<size_t>(h);
		}
	};
}

void Skinning::ReparentMeshesTrianglesToBones(S3DModel* model, const std::vector<SkinnedMesh>& meshes)
{
	RECOIL_DETAILED_TRACY_ZONE;

	std::vector<std::pair<size_t, size_t>> boneWeights;
	std::vector<std::unordered_map<VertKey, uint32_t, VertKeyHash>> vertLookup(model->pieceObjects.size());
	size_t numBadBones = 0;

	for (const auto& mesh : meshes) {
		const auto& verts = mesh.verts;
		const auto& indcs = mesh.indcs;

		for (size_t trID = 0; trID < indcs.size() / 3; ++trID) {

			boneWeights.clear();
			for (size_t vi = 0; vi < 3; ++vi) {
				const auto& vert = verts[indcs[trID * 3 + vi]];

				for (size_t wi = 0; wi < 4; ++wi) {
					const auto bID = GetBoneID(vert, wi);
					if (bID == INV_PIECE_NUM)
						continue;

					auto it = std::find_if(boneWeights.begin(), boneWeights.end(), [bID](const auto& p) { return p.first == bID; });
					if (it == boneWeights.end()) {
						it = boneWeights.emplace(boneWeights.end(), bID, 0);
					}

					it->second += vert.boneWeights[wi];
				}
			}

			std::sort(boneWeights.begin(), boneWeights.end(), [](const auto& lhs, const auto& rhs) {
				return lhs.second > rhs.second;
			});

			size_t selectedBoneID = INV_PIECE_NUM;
			for (auto& [bID, bw] : boneWeights) {
				bool allVertsHaveBone = true;
				for (size_t vi = 0; vi < 3; ++vi) {
					const auto& vert = verts[indcs[trID * 3 + vi]];
					bool vertHasBone = false;
					for (size_t wi = 0; wi < 4; ++wi) {
						if (GetBoneID(vert, wi) == bID) {
							vertHasBone = true;
							break;
						}
					}
					allVertsHaveBone &= vertHasBone;
				}
				if (allVertsHaveBone) {
					selectedBoneID = bID;
					break;
				}
			}

			// a triangle with no valid influence at all goes to the root piece
			if (selectedBoneID == INV_PIECE_NUM)
				selectedBoneID = boneWeights.empty() ? 0 : boneWeights.begin()->first;

			if (selectedBoneID >= model->pieceObjects.size()) {
				++numBadBones;
				selectedBoneID = 0;
			}

			auto* selectedPiece = model->pieceObjects[selectedBoneID];

			auto& pieceVerts = selectedPiece->GetVerticesVec();
			auto& pieceIndcs = selectedPiece->GetIndicesVec();
			auto& pieceLookup = vertLookup[selectedBoneID];

			// seed the lookup with vertices the piece already had (first use only)
			if (pieceLookup.empty() && !pieceVerts.empty()) {
				for (size_t pvi = 0; pvi < pieceVerts.size(); ++pvi)
					pieceLookup.try_emplace(VertKey(pieceVerts[pvi]), static_cast<uint32_t>(pvi));
			}

			for (size_t vi = 0; vi < 3; ++vi) {
				auto  targVert = verts[indcs[trID * 3 + vi]]; //copy

				// the triangle's bone must come first, even if it doesn't exist in targVert's influences
				MakeBoneFirst(targVert, static_cast<uint16_t>(selectedBoneID));

				// de-duplicate on exact position, normal, UVs and influences (hash lookup, first occurrence wins)
				const auto [it, inserted] = pieceLookup.try_emplace(VertKey(targVert), static_cast<uint32_t>(pieceVerts.size()));
				pieceIndcs.emplace_back(it->second);

				if (inserted)
					pieceVerts.emplace_back(std::move(targVert));
			}
		}
	}

	if (numBadBones > 0)
		LOG_SL(LOG_SECTION_MODEL, L_WARNING, "[ReparentMeshesTrianglesToBones] %u triangles referenced a bone past the piece count, moved to the root piece", static_cast<uint32_t>(numBadBones));

	// transform model space mesh vertices into bone/piece space
	for (auto* piece : model->pieceObjects) {
		if (!piece->HasGeometryData())
			continue;

		if (piece->bposeTransform.IsIdentity())
			continue;

		const auto invTra = piece->bposeTransform.InvertAffineNormalized();

		for (auto& vert : piece->GetVerticesVec()) {
			vert.TransformBy(invTra);
		}
	}
}

void Skinning::ReparentCompleteMeshesToBones(S3DModel* model, const std::vector<SkinnedMesh>& meshes) {
	RECOIL_DETAILED_TRACY_ZONE;

	std::vector<std::pair<size_t, size_t>> boneWeights;

	for (const auto& mesh : meshes) {
		const auto& verts = mesh.verts;
		const auto& indcs = mesh.indcs;

		// accumulate per-piece weights (the vector used to be cleared and then indexed, which is undefined behaviour)
		boneWeights.assign(model->pieceObjects.size(), { 0, 0 });
		for (size_t pi = 0; pi < boneWeights.size(); ++pi)
			boneWeights[pi].first = pi;

		for (const auto& vert : verts) {
			for (size_t wi = 0; wi < 4; ++wi) {
				const auto bID = GetBoneID(vert, wi);
				if (bID == INV_PIECE_NUM || bID >= boneWeights.size())
					continue;

				boneWeights[bID].second += vert.boneWeights[wi];
			}
		}
		std::stable_sort(boneWeights.begin(), boneWeights.end(), [](const auto& lhs, const auto& rhs) {
			return lhs.second > rhs.second;
		});

		// all-zero weights fall back to the root piece (index 0 after the stable sort)
		const auto maxWeightedBoneID = boneWeights.begin()->first;

		auto* maxWeightedPiece = model->pieceObjects[maxWeightedBoneID];

		auto& pieceVerts = maxWeightedPiece->GetVerticesVec();
		auto& pieceIndcs = maxWeightedPiece->GetIndicesVec();
		const auto indexOffset = static_cast<uint32_t>(pieceVerts.size());

		for (auto targVert : verts) { // deliberate copy
			// Unlike ReparentMeshesTrianglesToBones() do not check for already existing vertices
			// Just copy mesh as is. Modelers and assimp should have done necessary dedup for us.

			// the mesh's bone must come first, even if it doesn't exist in targVert's influences
			MakeBoneFirst(targVert, static_cast<uint16_t>(maxWeightedBoneID));

			pieceVerts.emplace_back(std::move(targVert));
		}

		for (const auto indx : indcs) {
			pieceIndcs.emplace_back(indexOffset + indx);
		}
	}

	// transform model space mesh vertices into bone/piece space
	for (auto* piece : model->pieceObjects) {
		if (!piece->HasGeometryData())
			continue;

		if (piece->bposeTransform.IsIdentity())
			continue;

		const auto invTra = piece->bposeTransform.InvertAffineNormalized();

		for (auto& vert : piece->GetVerticesVec()) {
			vert.TransformBy(invTra);
		}
	}
}

void ModelUtils::CalculateModelDimensions(S3DModel* model, S3DModelPiece* piece)
{
	// TODO fix
	const CMatrix44f scaleRotMat = piece->ComposeTransform(ZeroVector, ZeroVector, piece->scale).ToMatrix();

	// cannot set this until parent relations are known, so either here or in BuildPieceHierarchy()
	piece->goffset = scaleRotMat.Mul(piece->offset) + ((piece->parent != nullptr) ? piece->parent->goffset : ZeroVector);

	// update model min/max extents
	model->mins = float3::min(piece->goffset + piece->mins, model->mins);
	model->maxs = float3::max(piece->goffset + piece->maxs, model->maxs);

	piece->SetCollisionVolume(CollisionVolume('b', 'z', piece->maxs - piece->mins, (piece->maxs + piece->mins) * 0.5f));

	// Repeat with children
	for (S3DModelPiece* childPiece : piece->children) {
		CalculateModelDimensions(model, childPiece);
	}
}

void ModelUtils::CalculateModelProperties(S3DModel* model, const LuaTable& modelTable)
{
	RECOIL_DETAILED_TRACY_ZONE;

	model->UpdatePiecesMinMaxExtents();
	CalculateModelDimensions(model, model->GetRootPiece());

	model->mins = modelTable.GetFloat3("mins", model->mins);
	model->maxs = modelTable.GetFloat3("maxs", model->maxs);

	model->radius = modelTable.GetFloat("radius", model->CalcDrawRadius());
	model->height = modelTable.GetFloat("height", model->CalcDrawHeight());

	model->relMidPos = modelTable.GetFloat3("midpos", model->CalcDrawMidPos());
}

void ModelUtils::GetModelParams(const LuaTable& modelTable, ModelParams& modelParams)
{
	RECOIL_DETAILED_TRACY_ZONE;

	auto CondGetLuaValue = [&modelTable]<typename T>(std::optional<T>& value, const std::string& key) {
		if (!modelTable.KeyExists(key))
			return;

		value = modelTable.Get(key, T{});
	};

	CondGetLuaValue(modelParams.texs[0], "tex1");
	CondGetLuaValue(modelParams.texs[1], "tex2");

	CondGetLuaValue(modelParams.mins, "mins");
	CondGetLuaValue(modelParams.maxs, "maxs");

	CondGetLuaValue(modelParams.relMidPos, "midpos");

	CondGetLuaValue(modelParams.radius, "radius");
	CondGetLuaValue(modelParams.height, "height");

	CondGetLuaValue(modelParams.flipTextures, "fliptextures");
	CondGetLuaValue(modelParams.invertTeamColor, "invertteamcolor");
	CondGetLuaValue(modelParams.s3oCompat, "s3ocompat");
}

void ModelUtils::ApplyModelProperties(S3DModel* model, const ModelParams& modelParams)
{
	RECOIL_DETAILED_TRACY_ZONE;

	model->UpdatePiecesMinMaxExtents();
	CalculateModelDimensions(model, model->GetRootPiece());

	// Note the content from Lua table will overwrite whatever has already been defined in modelParams

	model->mins = modelParams.mins.value_or(model->mins);
	model->maxs = modelParams.maxs.value_or(model->maxs);

	// must come after mins / maxs assignment
	model->relMidPos = modelParams.relMidPos.value_or(model->CalcDrawMidPos());

	model->radius = modelParams.radius.value_or(model->CalcDrawRadius());
	model->height = modelParams.height.value_or(model->CalcDrawHeight());
}

void ModelUtils::CalculateNormals(std::vector<SVertexData>& verts, const std::vector<uint32_t>& indcs)
{
	if (indcs.size() < 3)
		return;

	// set the triangle-level S- and T-tangents
	for (size_t i = 0, n = indcs.size(); i < n; i += 3) {

		const auto& v0idx = indcs[i + 0];
		const auto& v1idx = indcs[i + 1];
		const auto& v2idx = indcs[i + 2];

		if (v1idx == INVALID_INDEX || v2idx == INVALID_INDEX) {
			// not a valid triangle, skip
			i += 3; continue;
		}

		auto& v0 = verts[v0idx];
		auto& v1 = verts[v1idx];
		auto& v2 = verts[v2idx];

		const auto& p0 = v0.pos;
		const auto& p1 = v1.pos;
		const auto& p2 = v2.pos;

		const auto p10 = p1 - p0;
		const auto p20 = p2 - p0;

		const auto N = p10.cross(p20);

		v0.normal += N;
		v1.normal += N;
		v2.normal += N;
	}

	// set the smoothed per-vertex tangents
	for (size_t i = 0, n = verts.size(); i < n; i++) {
		float3& N = verts[i].normal;

		N.AssertNaNs();

		const float sql = N.SqLength();
		if likely(N.CheckNaNs() && sql > float3::nrm_eps())
			N *= math::isqrt(sql);
		else
			N = float3{ 0.0f, 1.0f, 0.0f };
	}
}

void ModelUtils::CalculateTangents(std::vector<SVertexData>& verts, const std::vector<uint32_t>& indcs)
{
	if (indcs.size() < 3)
		return;

	// set the triangle-level S- and T-tangents
	for (size_t i = 0, n = indcs.size(); i < n; i += 3) {

		const auto& v0idx = indcs[i + 0];
		const auto& v1idx = indcs[i + 1];
		const auto& v2idx = indcs[i + 2];

		if (v1idx == INVALID_INDEX || v2idx == INVALID_INDEX) {
			// not a valid triangle, skip
			continue;
		}

		auto& v0 = verts[v0idx];
		auto& v1 = verts[v1idx];
		auto& v2 = verts[v2idx];

		const auto& p0 = v0.pos;
		const auto& p1 = v1.pos;
		const auto& p2 = v2.pos;

		const auto& tc0 = v0.texCoords[0];
		const auto& tc1 = v1.texCoords[0];
		const auto& tc2 = v2.texCoords[0];

		const auto p10 = p1 - p0;
		const auto p20 = p2 - p0;

		const auto tc10 = tc1 - tc0;
		const auto tc20 = tc2 - tc0;

		// if d is 0, texcoors are degenerate
		const float d = (tc10.x * tc20.y - tc20.x * tc10.y);
		if (math::fabsf(d) < 1e-9)
			continue; // garbage, skip it

		const float r = 1.0f / d;
		// note: not necessarily orthogonal to each other
		// or to vertex normal, only to the triangle plane
		const auto sdir = ( p10 * tc20.y - p20 * tc10.y) * r;
		const auto tdir = (-p10 * tc20.x + p20 * tc10.x) * r;

		v0.sTangent += sdir;
		v1.sTangent += sdir;
		v2.sTangent += sdir;

		v0.tTangent += tdir;
		v1.tTangent += tdir;
		v2.tTangent += tdir;
	}

	// set the smoothed per-vertex tangents
	for (size_t i = 0, n = verts.size(); i < n; i++) {
		float3& N = verts[i].normal;
		float3& T = verts[i].sTangent;
		float3& B = verts[i].tTangent; // bi

		N.AssertNaNs(); N.SafeANormalize();
		T.AssertNaNs();
		B.AssertNaNs();

		// Gram-Schmidt: orthogonalize T against N
		T = (T - N * N.dot(T));
		T.SafeANormalize();

		const float handednessSign = Sign(B.dot(N.cross(T)));

		// Can probably also do Gram-Schmidt: orthogonalize B against N and T
		//B = (B - N * N.dot(B) - T * T.dot(B));
		B = N.cross(T) * handednessSign;
		B.SafeANormalize();
	}
}

void ModelLog::LogModelProperties(const S3DModel& model)
{
	// Verbose logging of model properties
	LOG_SL(LOG_SECTION_MODEL, L_DEBUG, "model->name: %s", model.name.c_str());
	LOG_SL(LOG_SECTION_MODEL, L_DEBUG, "model->numobjects: %d", model.numPieces);
	LOG_SL(LOG_SECTION_MODEL, L_DEBUG, "model->radius: %f", model.radius);
	LOG_SL(LOG_SECTION_MODEL, L_DEBUG, "model->height: %f", model.height);
	LOG_SL(LOG_SECTION_MODEL, L_DEBUG, "model->mins: (%f,%f,%f)", model.mins[0], model.mins[1], model.mins[2]);
	LOG_SL(LOG_SECTION_MODEL, L_DEBUG, "model->maxs: (%f,%f,%f)", model.maxs[0], model.maxs[1], model.maxs[2]);
	LOG_SL(LOG_SECTION_MODEL, L_INFO, "Model %s Imported.", model.name.c_str());
}
