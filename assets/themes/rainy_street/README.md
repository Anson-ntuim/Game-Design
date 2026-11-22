# Rainy Street background provenance

- Purpose: stage 04 animated parallax background and matching platform/UI treatment.
- Created: 2026-11-17 with OpenAI built-in image generation.
- Art-direction reference: user-provided `第四關場景構想.png`.
- Generated family: opaque storm sky plus transparent distant city, storefront street, and wet promenade layers.
- Sky animation edit: the original `sky.png` is retained as a rollback source; `sky_base.png` removes baked clouds and `clouds.png` preserves them on transparency so the cloud layer can loop continuously to the right.
- Style locks: hand-painted rainy neon night, deep navy and cool violet structure, restrained cyan/magenta accents, warm windows and lamps, no readable text or logos.
- Runtime motion: quality-scaled diagonal rain, subtle puddle ripples, and a low-frequency double lightning flash are drawn procedurally so their strength remains adjustable.
- Cloud motion: `clouds_far.png` contains only thin distant wisps and moves right at 1.8 pixels per second; `clouds_near.png` contains the larger upper/side banks and moves at 3.8 pixels per second. Both remove the lowest 22% cloud band.
- Loop repair: the complete far/near cloud layers alternate normal and mirrored copies. Matching outer edges meet outside the viewport and form one continuous rightward cloud stream without transparent seams.
- Derived layer: `street_neon.png` deterministically isolates only the cyan/magenta music and heart signs from `street_mid.png`; it is overlaid at the same parallax scale for beat-reactive brightness without moving or flashing the buildings.
- Gameplay locks: decorative artwork does not alter level layout, collision, or player movement.
- Restrictions: project use; no third-party stock assets were intentionally included.
