# HUD aplicado — acampamento e fazenda

Implementação dos modelos aprovados em 27/10/2026, preservando o kit visual existente.

## Alterações

- `UI/Layout.luau`: área segura `CoreUISafeInsets`, escala limitada e observação das medidas do pulo/analógico nativos. Mira e efeitos mantêm camada própria alinhada à câmera.
- Fazenda: vida/créditos abaixo à esquerda; munição na base; no touch, faca ao lado da arma, tiro separado do pulo e grupo compacto de mira, recarga, granada e habilidade. Sem esconder ou duplicar o pulo Roblox.
- Acampamento: título/orientação contextuais, cartão de grupo só na fila, nível/XP no rodapé do PC ou acima do analógico no mobile.
- Menu compartilhado nos dois projetos: progressão/cosméticos e controles. Disparo automático é uma preferência touch e não dispara ao usar teclado/mouse.
- Classe: seleção local, botão de confirmação e PRONTO separado. A escolha é enviada ao servidor apenas ao confirmar. O servidor continua validando as permissões de fase.
- Uma janela principal por vez; tiro e câmera bloqueados durante menus. Prompts segurados e toques são liberados ao perder foco, morrer, mudar de entrada ou abrir uma janela.
- Botões secundários usam texto claro sobre o asset escuro.

## Verificação executada

- `selene src`: zero erros, avisos e erros de parsing.
- StyLua nos arquivos alterados e `git diff --check`.
- Builds Rojo dos dois projetos: `hud-fazenda.rbxlx` e `hud-acampamento.rbxlx`, nesta pasta.
- Fazenda sincronizada na instância Studio `fazenda` (place 99300600626141).
- Início de Play com bootstrap do cliente e servidor sem erro dos scripts de HUD.
- Emulador Samsung Galaxy S25 Ultra em paisagem: viewport 685×338, área segura 685×280.
- Confirmação de classe pelo botão real: janela fechou e `ClassConfirmed` ficou true. A partida avançou pela regra de tempo existente; o HUD de preparação apareceu.
- Checagem por retângulos das interfaces visíveis: zero sobreposições entre menu, vida, munição, banner, faca, cinco botões de combate e pulo nativo. Pulo nativo permaneceu visível.
- Captura real: `hud-fazenda-mobile.png`.
- Backup dos scripts anteriores da instância: `hud-studio-before.json`.

## Limites

O acampamento foi integrado e compilado; não foi executado no seu place nesta sessão, pois só a fazenda estava aberta. Não houve publicação na Roblox. A captura corresponde ao teste mobile da fazenda; ergonomia física e multiplayer ainda precisam de playtest em aparelho.

O Studio emite os avisos existentes de DataStore indisponível no modo offline e de um asset de áudio incompatível; não são erros da interface.

Para repetir a verificação geométrica, executar `tools/studio/verify-hud.luau` no datamodel Client durante Play, com o HUD visível. O verificador não modifica o jogo.
