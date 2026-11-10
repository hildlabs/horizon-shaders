# Daybreak: a shader pack for Horizon

**Daybreak** is a shader pack for [Horizon](https://github.com/horizon-rust/horizon), the Rust
reimplementation of Minecraft: Java Edition. It's written in WGSL against Horizon's own shader
API (0.1). It runs inside Horizon's renderer and doesn't replace it, so Horizon's culling,
batching, LOD and meshing stay in charge, and the pack adds as little GPU time as possible.

![Sunset over the sea with Daybreak: sun glare, sun rays and reflections on the waves](docs/screenshots/sunset.jpg)

<p>
  <img src="docs/screenshots/day.jpg" width="49%" alt="A lake by day: reflections, sun rays and the sun's glint on the water">
  <img src="docs/screenshots/night.jpg" width="49%" alt="The same lake at night: moonlight on the water under a dim blue sky">
</p>

On an RTX 4070 SUPER at 1920 × 1080 these scenes cost Daybreak 0.2 1.2–1.4 ms of GPU time per
frame, shadow pass included (F3: [day](docs/screenshots/f3-day.jpg), [night](docs/screenshots/f3-night.jpg),
[sunset](docs/screenshots/f3-sunset.jpg)). Since 0.3 Daybreak also counts the CPU time it costs
Horizon (see [What 0.3 changes](#what-03-changes)).

| Effect | How | Cost |
| --- | --- | --- |
| Sun and moon shadows | 1536² distorted shadow map over 64 blocks, normal-offset lookup, slope-scaled bias, 1/4/9-tap grid PCF (smooth edges, no noise) | the shadow pass plus up to 9 compare taps per pixel |
| Day and night light | own sun, sky and block light, wrapped diffuse, with vanilla's face shade taken back out | inside terrain's own draw: no extra pass |
| Coloured block light | soul fire blue, redstone red, copper green, froglights… (`[[lights]]`, only light of another colour than the warm default) | one 3D texture read |
| Mob shadows | mobs, chests and particles take the sun's shadow and the sky's tint in the composite, by a terrain mask (`set_surface`) and the same shadow map | 4 compare taps, only on non-terrain pixels |
| Light from held torches | Horizon's dynamic lights, in the item's colour, per pixel | Horizon's own: none from the pack |
| Waving leaves and plants | vertex stage, continuous across two-block plants | a few `sin`s per vertex |
| Water | rolling waves, Fresnel reflection (screen-space, or the full water mirror), refraction, depth absorption, sun glint | 12 + 4 steps per pixel of water; the mirror is a half-resolution pass |
| Sky | deeper zenith, warm sunset band, sun glow; vanilla's horizon kept, so fog never seams | per sky pixel |
| Sun rays | screen-space radial march over the sky mask, **quarter resolution**, 16 dithered steps | ~1/16 of the pixels |
| Sun glare | bloom, halo, anamorphic streak and lens ghosts, dimmed by how much of the sun shows (9 taps) | in the same quarter-resolution pass |
| Haze | aerial perspective from depth: distant land fades to the sky, warm toward the sun | part of the composite |
| Bloom | Karis-averaged bright pass and a 13-tap two-ring blur, both **quarter resolution** | ~1/16 of the pixels |
| Grade | eye adaptation from the light at the camera, shoulder, S-curve, saturation, vignette, dither | one full-screen pass |

Every option is a WGSL `override` constant, so a switched-off effect is a branch on a constant:
the GPU never runs it, and nothing is recompiled with text substitution.

## Quality

The most expensive part is the shadow pass, which draws the terrain in its square again each
frame. Its size is up to the player: **Shadows** off means no shadow map and no pass at all,
**Shadow detail** is the map's size and **Shadow distance** the square it covers (Lighting page of
the Shader Options). Changing them rebuilds the map; nothing else is reloaded. The defaults are
High; for slower or faster computers:

| Level | Shadows | Shadow detail | Shadow distance | Shadow edges | Reflections | Full mirror | Sun rays |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Low | off | – | – | – | off | off | 0 |
| Medium | on | 1024 | 48 | Sharp | on | off | 0.35 |
| **High** (default) | on | 1536 | 64 | Soft | on | off | 0.5 |
| Ultra | on | 4096 | 160 | Very soft | on | on | 0.6 |

Settings you changed yourself are kept when Daybreak updates (**Reset all options** on the Shader
Options page brings back the defaults), except the shadow map's size and distance: in 0.3 they are
new options with new values, so everyone starts on High.

Until 0.1.1 these were four separate packs (Daybreak Low, Medium and Ultra came in a zip),
because a pack's shadow map was fixed by its manifest. Horizon's shader API now lets options
size it ([horizon#8557](https://github.com/horizon-rust/horizon/pull/8557)), so one pack does
all four. Old `daybreak_low`, `daybreak_medium` and `daybreak_ultra` packs can be deleted from
`shaderpacks/`.

## What 0.3 changes

Measured in a scripted flight through a town, a parade of mobs, fireworks, a redstone factory and
a storm (7800X3D, RTX 4070 SUPER, 1080p), Daybreak 0.2 halved the frame rate, and the 1 % lows
fell to a third. Most of it was not the GPU but the CPU, in three places, which 0.3 takes out:

- **Coloured light only where it is coloured.** Horizon spreads the `[[lights]]` sources into a
  grid on the CPU each time the camera moves on 16 blocks or a listed block changes. 0.2 listed
  torches, lanterns, fire, glowstone, lava and redstone lamps, so a wall of switching lamps or a
  lava lake rebuilt it frame after frame: the stutters. Their warm colour is now block light's
  own tint, and `[[lights]]` lists only what is another colour (soul fire, redstone torches,
  sea lanterns, amethyst, copper, froglights, end rods). Redstone lamps were red in 0.2; they
  are warm yellow, like their texture.
- **Screen-space reflections instead of the mirror.** The water mirror draws the terrain a second
  time, and while it does Horizon can't cull the world on the GPU. Water now reflects what the
  screen shows, and the sky where it ends: no extra pass. The mirror is still there as
  **Full mirror** on the Water page.
- **A smaller shadow square, a finer map.** 64 blocks instead of 96 is less than half the
  sections for the shadow pass to cull and draw; 1536 texels over it are sharper near you than
  0.2's 2048 over 96. Beyond it, the sky light still says where the sun reaches.

## Try it

1. Install the Horizon launcher and a Nightly from 2026-11-05 or newer (Daybreak 0.2 needs
   Horizon's `[shadow]` options; 0.1.1 runs on Nightlies from 2026-11-03).
2. Install Daybreak from the launcher's mod browser (Shader packs), or put
   `daybreak-<version>.hshader` from a [release](https://github.com/hildlabs/horizon-shaders/releases)
   into `shaderpacks/` beside your `options.txt`.
   For working on the shaders, link the source pack instead (it hot-reloads every save):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\link-pack.ps1
   ```
3. In the game: **Options > Horizon Settings > Shader Packs > Daybreak (Horizon)**, then
   **Shader Options…** for the settings and the quality (Lighting page).
4. For light from torches in your hand and dropped on the ground, turn on Horizon's
   **Dynamic lights** in the game's Horizon settings (it is off by default).
5. Press **F3** to see each pass's GPU time.

## Develop

```sh
cargo install --git https://github.com/horizon-rust/horizon --rev ee06d18c391102428fa5dded4f3d9d091ea361f0 horizon-shader-api --locked
horizon-shader check pack/daybreak    # what the game, the launcher and the registry check
horizon-shader pack pack/daybreak     # writes daybreak-<version>.hshader
```

| File | Stage |
| --- | --- |
| `common.wgsl` | shared: material ids, the light's colour, noise, the tone shoulder, the water wave |
| `vertex.wgsl` | wind on leaves and plants, waves on water |
| `material.wgsl`, `lighting.wgsl`, `water.wgsl` | how terrain and water are lit |
| `sky.wgsl` | the sky's colour |
| `post/*.wgsl` | bloom prefilter → bloom blur → sun rays → composite |

The API reference is Horizon's
[`docs/api/shaders-reference.md`](https://github.com/horizon-rust/horizon/blob/main/docs/api/shaders-reference.md).

## Credits

Original code, MIT licensed. The techniques come from published work: interleaved gradient noise
and the Karis average (Jimenez, *Next Generation Post Processing in Call of Duty: Advanced Warfare*,
2014), Schlick's Fresnel approximation (1994), Vogel-spiral disc sampling. No code from other
shader packs and no Minecraft assets are included.
