# Roblox Swarm: Outbreak

Co-op horde shooter (mobile first). Definições do jogo: [docs/DEFINICOES.md](docs/DEFINICOES.md).

## Desenvolvimento

1. Instale o toolchain: `rokit install`
2. Sincronize: `rojo serve`
3. No Roblox Studio, conecte pelo plugin do Rojo.

## Estrutura

- `src/shared` → ReplicatedStorage/Shared — tipos, config, utilitários
- `src/server` → ServerScriptService/Server — sistemas autoritativos
- `src/client` → StarterPlayerScripts/Client — render, input, UI

## Checks

- `stylua src` · `selene src`
