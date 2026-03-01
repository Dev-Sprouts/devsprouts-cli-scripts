# devsprouts-cli-scripts

Public installer scripts for `@dev-sprouts/devsprouts-cli`.

## One-step install

```bash
curl -fsSL https://raw.githubusercontent.com/Dev-Sprouts/devsprouts-cli-scripts/main/scripts/install.sh | bash
```

## What it does

1. Configures npm to use GitHub Packages with your `gh auth token`
2. Installs `@dev-sprouts/devsprouts-cli` globally
3. Configures shell autocomplete
4. Runs `devsprouts config init`
5. Runs `devsprouts doctor`

## Requirements

- `gh` authenticated (`gh auth login`)
- `npm`
- `curl`

