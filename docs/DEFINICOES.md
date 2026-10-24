# Roblox Swarm: Outbreak: Documento de Definições (pré-produção)

## Contexto
O GDD original é muito amplo para uma pessoa só. Este documento fixa as decisões antes de qualquer código: escopo do MVP, direção de arte, regras de gameplay, arquitetura e cronograma. Decisões já tomadas: **low-poly estilizado · solo · MVP em ~3 meses · 4 jogadores · missão com ondas · Rojo + VS Code**.

Entregável ao aprovar: salvar este documento como `/Users/emersonnobre/wwz/docs/DEFINICOES.md` e montar a estrutura do projeto com a skill `roblox-dev:setup` (Rojo, Wally, Selene, StyLua, Luau strict).

---

## 1. Pilares (servem de filtro: o que não atende a nenhum deles fica fora do MVP)
1. **A horda é a estrela**: muitos zumbis na tela e a pirâmide escalando o muro.
2. **Polegar primeiro**: tudo jogável com dois polegares, sem precisar de precisão.
3. **Preparar e depois sobreviver**: a tensão vem da fase de preparação antes da onda.
4. **Partida curta**: 15 minutos, cabe numa pausa.

## 2. Escopo do MVP e o que fica para depois
| Entra no MVP | Fica para depois (atualizações) |
|---|---|
| 1 mapa: "Fazenda Abandonada" | 2º e 3º mapas |
| 2 classes: Gunslinger e Exterminador | Médico, Slasher |
| 4 zumbis: Runner, Bull, Creeper e o chefe Brute | Variantes especiais |
| 8 armas: pistola, SMG, escopeta, rifle, AK-47, faca, taco com pregos, granada | Rifle de precisão, motosserra |
| 2 defesas: barricada reparável e torreta | Cerca elétrica, minas, arame |
| Créditos na partida, loja em caixa | Árvore de talentos completa |
| XP de conta e desbloqueio de armas | Battle Pass, skins, emotes |
| 1 Gamepass de cosmético e 1 Boost 2x | Revive Token (avaliar depois de ver o balanceamento) |

## 3. Direção de arte: low-poly estilizado
- **Tom:** apocalipse sério, mas legível. É "WWZ desenhado", não comédia.
- **Paleta:** ambiente dessaturado (cinza-azulado e ocre) e elementos de jogo saturados.
  - Zumbis: verde-oliva e pele cinza, com olhos **laranja emissivo** para o jogador ler a ameaça de longe.
  - Jogadores: contorno/realce **azul-ciano**.
  - Interativos (loja, munição, reparo): **amarelo**.
  - Perigo (Creeper, explosões): **vermelho**.
- **Geometria:** de 200 a 800 tris por zumbi, sem texturas (só cor de material e SurfaceAppearance mínima). Silhuetas distintas: Runner magro, Bull largo com placas, Creeper inchado e brilhante.
- **Sangue:** partículas estilizadas escuras, sem desmembramento. Mantém a classificação **13+** sem risco.
- **Iluminação:** `ShadowMap` (não usar Future), névoa (Atmosphere) para esconder o LOD distante, entardecer laranja.
- **UI:** fonte condensada e militar (Gotham Black / Bangers), painéis escuros semitransparentes com cantos cortados e ícones de traço grosso.
- **Áudio:** grunhidos de massa em loop (uma única fonte "horda", não um som por zumbi) e stingers no começo de cada onda.

## 3b. Mapa 1: Fazenda Abandonada
- **Clima:** céu vermelho-acinzentado com fumaça no horizonte, cinzas no ar, plantação seca e moinho quebrado. Trovões distantes sem chuva (a chuva custa partículas).
- **Layout:** a casa-sede e o celeiro formam o **forte dos jogadores**, dentro de uma cerca de madeira com portão. O milharal ao redor é a **névoa natural**, porque os zumbis surgem de dentro dele, o que também esconde o LOD. O silo e o muro de pedra do curral são os **ClimbZones** da pirâmide. A extração acontece no campo aberto, onde o helicóptero pousa, e é preciso correr até lá na onda final.
- **Pontos de interesse:** a caixa de loja fica no celeiro, a munição na varanda, a torreta em 3 posições marcadas e há 4 barricadas (2 janelas, porta da casa e portão).
- **Música:** drone grave contínuo na preparação (cordas e sintetizador) que **cresce em camadas** conforme a onda chega (percussão e batida cardíaca). Stinger quando o Brute aparece. Sons diegéticos: cata-vento rangendo, corvos, porteira batendo.

## 4. Gameplay
**Loop da partida (~15 min):**
1. Lobby e escolha de classe (30 s)
2. Preparação 1 (60 s): comprar, posicionar torreta, reparar
3. Onda 1 → Preparação 2 → Onda 2 → Preparação 3 → **Onda final + extração** (sobreviver 90 s até o helicóptero)
4. Tela de resultado: XP e créditos de conta

**Zumbis (valores iniciais para balancear):**
| Tipo | Vida | Velocidade | Dano | Especial |
|---|---|---|---|---|
| Runner (1) | 50 | 22 | 10 (mordida, alcance de 3 studs) | **Atraído por barulho**: tiros e explosões criam um "ponto de ruído" por 3 s que puxa os Runners num raio proporcional ao volume (pistola 40, AK 70, granada 100; armas brancas são silenciosas). Forma pirâmides |
| Brute (2, chefe) | 3000 (escala por jogador) | 12 | Soco 50 + empurrão; pedra 30 (área) | Arremessa pedras a distância (aviso de 1 s com a mão erguida); **ponto fraco nas costas, onde leva 3x de dano**. Aparece na onda final |
| Bull | 600 | 14 / investida 40 | 35 | Investida destrói barricada; fraco nas costas (versão menor do Brute, ensina a mecânica nas ondas 2–3) |
| Creeper | 80 | 16 | 60 (área de 12 studs) | Explode perto; pulsa vermelho; explosão também gera barulho |

**Armas (valores iniciais):**
| Arma | Tipo | Dano | Barulho | Custo |
|---|---|---|---|---|
| Pistola | inicial | 20 | médio | grátis |
| SMG | automática | 14 | médio | 400 |
| Escopeta | 8 bagos | 12x8 | alto | 500 |
| Rifle | automática | 24 | alto | 700 |
| **AK-47** | automática pesada | 32, recuo forte | muito alto | 900 |
| **Faca** | corpo a corpo, slot fixo | 35, rápida | silenciosa | grátis |
| **Taco com pregos** | corpo a corpo, golpe em arco (até 3 alvos) | 60 + sangramento | silenciosa | 350 |
| **Granada** | arremesso, máximo de 2 | 150 em área | muito alto (isca!) | 150 cada |

A faca vem em todo loadout. Taco e faca dividem o slot corpo a corpo, e a granada fica num botão próprio. Combinação tática: jogar a granada longe para **atrair os Runners** pelo barulho.

**Pirâmide:** é **falsa e barata**. Zumbis que chegam a um `ClimbZone` (parte marcada no muro) se empilham em "slots" predefinidos e sobem por uma rampa de animação. Não usa física real entre zumbis.

**Classes:**
- **Gunslinger:** +25% de dano com rifle e SMG, +30% de munição. Habilidade: munição incendiária por 10 s.
- **Exterminador:** escopeta inicial. Habilidade: molotov (área de fogo por 6 s).
- Habilidades com recarga de 45 s, num botão grande.

**Controles mobile:** analógico à esquerda; à direita, botões de tiro, mira, recarga, habilidade e um botão de contexto (comprar/reparar/reviver). **Auto-fire ligado por padrão no mobile**, com mira assistida leve (cone de 4°). Interação por "segurar 0,5 s" para evitar toques acidentais.

**Economia na partida:** Runner 5 cr, Creeper 15, Bull 50. A arma custa de 300 a 900 e a torreta 750. A munição na caixa é grátis, com recarga de 30 s por jogador.

## 5. Arquitetura técnica
- **Servidor autoritativo:** o servidor simula os zumbis como **dados** (posição, vida, estado) em tabelas, não como Humanoids.
- **Os clientes renderizam** os zumbis: replicação compacta por `UnreliableRemoteEvent` em lotes de 10 Hz (id, posição quantizada, estado). O cliente interpola e anima.
- **Movimento:** um campo de fluxo (flow field) pré-calculado por mapa até o alvo, com separação simples entre vizinhos (grade espacial). Sem `PathfindingService` por zumbi.
- **LOD no cliente:** perto (<60 studs) usa modelo com AnimationController; médio usa modelo estático com "bob" via CFrame; longe usa impostor ou nada. Pool de modelos com reaproveitamento, sem criar e destruir.
- **Orçamentos:** no máximo **120 zumbis vivos** no servidor e no máximo **40 modelos animados** por cliente, mirando 60 FPS em celular intermediário. Qualidade automática: reduz partículas se o FPS ficar abaixo de 40.
- **Tiro:** raycast no cliente para resposta imediata; o servidor revalida (distância, cadência, linha de visão) e aplica o dano.
- **StreamingEnabled** ligado, com o mapa dividido em setores.
- **Dados:** ProfileStore com session locking, para XP, desbloqueios e moeda de conta.

**Estrutura (Rojo):**
```
src/
  shared/   Types, Config (Zombies, Weapons, Classes), Net (remotes)
  server/   Services: MatchService, HordeService, CombatService, EconomyService, DefenseService, DataService
  client/   Controllers: InputController, CameraController, ZombieRenderer, HUD, ShopUI
```

## 6. Monetização (justa)
- MVP: Gamepass "Pacote do Sobrevivente" (skin e trilha cosmética) e Developer Product "Boost 2x XP por 1 h".
- Proibido: vender dano, vida ou armas exclusivas.

## 7. Cronograma (12 semanas)
| Semanas | Marco |
|---|---|
| 1 | Setup Rojo, protótipo cinza do mapa, controles mobile |
| 2–3 | **Horda técnica**: 120 Runners com flow field, replicação e LOD. **Gate: precisa rodar a 60 FPS num celular real, senão reduzir o escopo** |
| 4 | Tiro, armas e dano validado no servidor |
| 5 | Barricadas e a pirâmide |
| 6 | Sistema de barulho, Bull, Creeper e Brute (chefe), loop de ondas e extração |
| 7 | Classes, habilidades, economia e loja |
| 8 | Arte low-poly: zumbis, armas, mapa |
| 9 | UI/HUD final, áudio, VFX |
| 10 | Dados, progressão e monetização |
| 11 | Playtests com 4 jogadores e balanceamento |
| 12 | Polimento, ícone/thumbnail, lançamento |

## Verificação
- Depois do setup: `rojo serve` sincroniza com o Studio e `selene` e `stylua --check` passam.
- Gate da semana 3: teste em celular real (Studio Device Emulator + aparelho físico) com 120 zumbis, medido pelo MicroProfiler.
- Cada sistema novo passa pelo agente `roblox-dev:roblox-reviewer` (segurança dos remotes e performance).
