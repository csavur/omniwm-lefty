# Lefty for OmniWM

A style for [OmniWM](https://github.com/OmniNull/OmniWM) 0.8 or later.

| Style | Summary |
| --- | --- |
| [Lefty](styles/lefty) | A quiet bar with pill-shaped workspaces, a blue accent and a slow glow. |

## Install

In OmniWM, open **Settings > Styles & Widgets > Get Styles > Add from GitHub…**, paste this repository's main-page URL, choose **Load**, install the style and choose **Use Style**. A style runs code in OmniWM, so only install styles you trust.

## Development

```sh
uv run --no-project --python 3.12 python scripts/check_palette.py styles/lefty
swift scripts/render_shader.swift styles/lefty /tmp
```

The first checks the manifest and palette contrast. The second compiles and renders the shader and checks text contrast over it. Raise `version` in `style.toml` with every published change, or OmniWM will not offer an update.

## Licence

GPL-2.0-only. See [LICENSE](LICENSE).
