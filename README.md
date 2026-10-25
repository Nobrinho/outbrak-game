# Roblox Swarm: Outbreak

Co-op horde shooter (mobile first). Definições do jogo: [docs/DEFINICOES.md](docs/DEFINICOES.md).

## Desenvolvimento

A experiência tem dois places, cada um com seu projeto do Rojo:

| Place | Projeto | Servir |
|---|---|---|
| Acampamento (hub, place de entrada) | `hub.project.json` | `rojo serve hub.project.json --port 34873` |
| Fazenda (mapa) | `default.project.json` | `rojo serve` |

1. Instale o toolchain: `rokit install`
2. Sirva o projeto do place que vai abrir no Studio (tabela acima); com os dois abertos, use
   as duas portas, uma janela do Studio para cada.
3. No Roblox Studio, conecte pelo plugin do Rojo (na porta certa).

## Estrutura

- `src/shared` → ReplicatedStorage/Shared — tipos, config (inclui `PLACES` e `MAPS`), utilitários
- `src/server` → ServerScriptService/Server — sistemas autoritativos do mapa
- `src/client` → StarterPlayerScripts/Client — render, input, UI do mapa
- `src/hub` → o acampamento: `HubMap` (mapa), `PortalService` (helipontos → servidores
  reservados), `PortalHUD`, e os bootstraps. Reaproveita `DataService`, `ProgressionService`,
  `MonetizationService`, `ProgressionHUD` e `Theme` dos mapas.

## Checks

- `stylua src` · `selene src`

## Modelos 3D da fazenda

Pipeline Blender → FBX → Roblox Studio: [docs/art/PIPELINE.md](docs/art/PIPELINE.md).

- Verificar ferramentas: `python3 tools/art.py doctor`
- Gerar modelo de teste: `python3 tools/art.py smoke`
