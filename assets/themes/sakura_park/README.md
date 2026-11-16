# Sakura Park background provenance

- Purpose: stage 02 animated parallax background and matching platform-art pilot.
- Created: 2026-11-12 with OpenAI built-in image generation.
- Art direction reference: user-provided `櫻花樂園像素素材圖鑑.png`.
- Style reference: the project's existing Heartbeat City hand-painted background layers.
- Additional generated element: isolated Ferris wheel, created with OpenAI built-in image generation to match the park layer; prompt requested a transparent, front-facing pink-lavender wheel with no ground, text, or logo.
- Additional generated layers: a cloudless sunset base plus transparent far/near cloud families, edited/generated with OpenAI built-in image generation from the original sky as the locked style and palette reference.
- Deterministic processing: `tools/build_sakura_background.py` cleans low-alpha residue and disconnected cloud speckles, derives `park_near_bottom.png`, removes the baked wheel from the far layer, and normalizes generated assets.
- Runtime motion: two depth layers of procedural petals, two right-drifting cloud depths, and a slowly rotating wheel; platform collision and level geometry remain unchanged.
- Restrictions: project use; no text, logos, signatures, or third-party stock assets were intentionally included.
