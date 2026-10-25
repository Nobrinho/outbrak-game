# Lançamento: o que falta e como fazer

Checklist das semanas 11–12 (docs/DEFINICOES.md §7). Os passos marcados como **você** são
no Studio ou no Creator Hub, que só o dono da experiência acessa.

## 1. Publicar a build de teste (você)

1. No Studio, confira que o Rojo está conectado e que **não** existe `Workspace.Map` no modo
   de edição. O mapa é criado pelo `FarmMap` a cada partida; uma cópia salva duplica tudo.
2. **File → Publish to Roblox** (experiência 10772783638).
3. Creator Hub → a experiência → **Configure → Settings**: deixe **Private** durante o teste
   e adicione os testadores em **Collaborators** (ou um grupo com permissão de jogar).
4. O número da build aparece no canto inferior direito (`Config.BUILD`); peça aos
   testadores para citá-lo.

## 1b. Acampamento (hub) e place da Fazenda (você, uma vez)

O place de entrada não pode ser trocado, então ele vira o **Acampamento** e o jogo vai para
um place novo:

1. Creator Hub → a experiência → **Places → Create Place** (ou, no Studio, **Asset Manager →
   Places → Add New Place**). Nome: **Fazenda**.
2. Abra o place atual no Studio (o jogo, com `ReplicatedStorage.Assets`) e use **File →
   Publish As** escolhendo o place **Fazenda**. As malhas vão junto.
3. Configurações do place Fazenda: **Server Size = 4**.
4. Copie o placeId da Fazenda para `Config.MAPS` (linha `Farm`, `placeId`). Republique a
   Fazenda (`rojo serve` + Publish).
5. Abra o place de entrada (77549309919854), rode `rojo serve hub.project.json --port 34873`,
   conecte o Rojo nessa porta, **apague** o que sobrou do jogo antigo no Workspace se houver,
   e publique. Server Size do acampamento: 30–50.
6. Teste publicado: entrar → acampamento; pisar no heliponto da Fazenda com amigos → contagem
   → todos na mesma partida privada → no fim, de volta ao acampamento. O nível tem de ser o
   mesmo nos dois places.

Mapas futuros: um place novo por mapa e uma linha em `Config.MAPS` (os pads "EM BREVE" usam
`placeId = -1`).

## 2. Teste com 2–4 jogadores (você e os testadores)

Anotar por partida: build, aparelho, onda alcançada, FPS na onda mais cheia (Ctrl+F6 no
celular), o que travou ou incomodou. Pontos que só um teste real confirma:

- câmera de espectador seguindo o colega vivo;
- escala de dificuldade com 2–4 jogadores (+35% de zumbis por jogador extra);
- progresso salvo entre sessões (DataStore só funciona nos servidores publicados);
- 60 FPS em celular intermediário; abaixo de 40 FPS o jogo corta partículas, luzes do
  cano e metade dos zumbis animados por conta própria (`Effects.quality`).

## 3. Monetização (você cria, eu ligo)

Nada à venda dá vantagem (§6). O código já trata as duas ofertas; elas aparecem como
"EM BREVE" enquanto os IDs forem 0.

1. Creator Hub → a experiência → **Monetization → Passes → Create a Pass**
   - Nome: **Pacote do Sobrevivente**
   - Descrição: "Armas douradas e um rastro ciano e dourado. Só visual."
   - Preço sugerido: 149 Robux. Ative **Item for Sale**.
2. **Monetization → Developer Products → Create**
   - Nome: **Boost 2x XP (1 hora)**
   - Descrição: "Dobra o XP de conta por 1 hora. Acumula se comprar de novo."
   - Preço sugerido: 49 Robux.
3. Copie os dois IDs para `src/shared/Config.luau`, em `MONETIZATION`:
   `survivorPackId` e `xpBoostProductId`. Publique de novo.
4. Teste no servidor publicado (compras no Studio são simuladas): o pacote deve dourar a
   arma e mostrar o rastro; o boost deve mostrar "2x XP — 60 min" no HUD.

## 4. Página da experiência (você envia)

- Ícone 512×512: `assets/export/store_icon.png`
- Thumbnail 1920×1080: `assets/export/store_thumbnail.png`
  (gerados por `python3 tools/art.py thumbnails`, só com as malhas do próprio jogo)
- Creator Hub → **Configure → Places/Experience → Icon / Thumbnails**.
- Descrição sugerida:

  > Sobreviva a 10 ondas de zumbis com até 4 amigos na Fazenda Santa Luzia. Compre armas,
  > conserte barricadas, instale torretas e corra para o helicóptero na onda final — com o
  > Brute no seu encalço. Jogável no celular com dois polegares.

- Gênero: Shooter / Survival. Classificação de maturidade: preencher o questionário
  (violência estilizada, sem sangue realista).

## 5. Antes de tornar pública (você)

- `Config.DEBUG`: tudo `false` (já está).
- `Config.BUILD`: tirar o sufixo `-teste`.
- Experiência em **Public**.
