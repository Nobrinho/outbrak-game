# Outbreak UI — design system v0.1

Primeira versão para revisão visual, 25/10/2026. Jogo: Roblox Swarm: Outbreak.
Kit de produção: [assets de UI, armas, hub e divulgação](ASSETS.md).
Base: tema existente, [plano de HUD](../PLANO-HUD.md) e
[direção da fazenda](../art/DIRECAO-FAZENDA.md). A referência noturna mais recente
prevalece sobre o entardecer descrito no documento de pré-produção.

![Prancha de componentes](design-system.png)

## Identidade

Sobrevivência tática, low poly e legível em movimento. A horda e a fazenda
noturna são protagonistas. A interface parece equipamento de campo: placas
grafite, pequenos marcadores amarelos, bordas discretas e números condensados.
Texturas gastas pertencem ao cenário; textos e barras permanecem limpos.

Assinatura: painel de raio 4 com marcador amarelo no canto superior esquerdo.
O `Theme.panel` atual simula esse detalhe com um quadrado rotacionado e recortado;
não é um recorte real da silhueta do painel. Não repetir o marcador em cada
linha de uma lista. Amarelo é pontual, sem molduras luminosas ou brilho contínuo.

## Cores semânticas

| Token Luau | Hex | Uso |
|---|---|---|
| panel | #101014 | Fundo de HUD e janelas |
| surface | #24242A | Linhas, trilhos e ações secundárias |
| text | #ECE8DE | Informação principal |
| muted | #A09C94 | Informação secundária, sem reduzir opacidade adicional |
| accent | #FFCC00 | Interação, compra e créditos da partida |
| player | #00C8E6 | Vida normal, jogador e habilidade pronta |
| danger | #DC2828 | Perigo, vida crítica, dano e bloqueio urgente |
| fire | #FF8C14 | Fogo e confirmação de acerto na cabeça |
| disabled | #5A5A60 | Fundo de ação indisponível |

Texto escuro `panel` sobre amarelo, ciano ou laranja. Texto principal sobre
grafite. Vermelho serve para barra, ícone e faixa; avisos usam texto claro em
fundo grafite com rótulo explícito. Não usar vermelho como texto pequeno sobre
grafite. Uma ação indisponível mantém texto claro e informa o motivo.

Referências de contraste em fundos opacos: text/panel ≈15,5:1,
muted/panel ≈6,9:1, panel/accent ≈12,6:1, text/disabled ≈5,6:1.
São pares de tokens, não garantia sobre o cenário: o HUD usa 30% de
transparência e deve ser conferido sobre janelas, lua, fogo e névoa. Aumentar
a opacidade do painel quando necessário. Estado nunca depende só de cor.

## Tipografia

| Papel | Fonte Roblox | Tamanho de referência |
|---|---|---|
| Legenda secundária | Oswald Medium | 14 |
| Rótulo / tecla | Oswald Medium | 18 |
| Descrição e mensagem | Oswald Medium | 20 |
| Título de janela | Oswald Bold | 28 |
| Vida, munição, tempo | Oswald Bold | 36 |
| Anúncio breve | Bangers | 48 |

Medidas em unidades de UI Roblox; não equivalem a pontos físicos. Bangers
fica restrita a anúncios e títulos breves. Descrições usam frase normal;
rótulos curtos podem usar caixa alta. Não comprimir textos longos para caber.
Novos componentes usam `TextSize` e quebra de linha; quando `TextScaled` for
necessário, combinar `UITextSizeConstraint` com limites explícitos.
Os tamanhos acima são a escala proposta; controladores legados ainda usam
escala livre. Textos principais devem continuar legíveis no menor aparelho.

## Medidas, superfície e camadas

- Espaçamento: 4, 8, 12, 16, 24, 32. Padding padrão 16; compacto 8–12.
- Raio: 4. Borda: 1. Marcador de canto: quadrado de 16 a 45°.
- Transparência Roblox: HUD 0,30; modal 0,10; borda 0,85.
- Alvo touch mínimo 48×48; secundário 60×60; tiro 88×88; intervalo 12.
- Ordem proposta por `ScreenGui.DisplayOrder`: HUD 10, contexto 20,
  anúncio 30, modal 40, toast 50. `ZIndex` resolve a ordem dentro da tela.
  Mira continua em ScreenGui próprio, alinhado ao raio da câmera.
- Margem inicial 16 após insets. Reservar também topbar, chat, lista de
  jogadores, analógico e pulo Roblox; margem sozinha não resolve colisões.

## Biblioteca de componentes

| Componente | Anatomia e estados |
|---|---|
| Painel | Superfície grafite, borda discreta e marcador; sem título obrigatório |
| Ação principal | Amarelo + texto escuro; normal, foco, pressionado e indisponível |
| Ação secundária | Superfície + texto claro; foco visível e alvo touch completo |
| Compra | Nome, preço e ação; disponível, saldo insuficiente, nível exigido, aguardando resposta |
| Vida | Rótulo, barra e valor; normal ciano, crítico vermelho com “VIDA BAIXA” |
| Munição | Carregador dominante, reserva secundária, arma; pouca munição e recarga têm texto |
| Habilidade | Nome, tecla ou botão, recarga numérica; pronta, ativa e recarregando |
| Fase | Nome, onda/total dinâmico e tempo ou objetivo curto |
| Interação | Ação real, alvo e tecla E ou botão touch; progresso ao segurar |
| Fila | Destino, ocupação/capacidade e contagem; sair do heliponto cancela |
| Aviso | Mensagem curta e categoria; no máximo um aviso dominante por vez |
| Modal | Título, fechar, conteúdo rolável e ação; apenas uma janela principal aberta |
| Resultado | Resultado, XP ganho e retorno ao hub quando disponível |

Foco: contorno claro de 2 unidades, sem mudar geometria. Pressionado: escurecer
levemente a superfície. Aguardando resposta: impedir envio repetido e mostrar
“AGUARDE”. Indisponível: fundo disabled, rótulo do motivo e bloqueio da ação
na interface; o servidor continua validando tudo. Estas são especificações de
componentes, não novos sistemas de gameplay já implementados.

Ícones: silhueta simples, traço visual consistente de 2–3 unidades na base 24,
sem emoji como asset final. Ações novas recebem rótulo curto junto do ícone.
O [kit de assets](ASSETS.md) agora fornece ícones individuais em SVG/PNG e
fundos de botão; importar e validar no Studio antes de integrar.

## Composição por contexto

**Fazenda:** vida/créditos no alto à esquerda; fase no alto ao centro;
arma/munição no alto à direita. Habilidade e granadas aparecem junto do
respectivo controle touch ou abaixo da munição no teclado. Centro e região
abaixo da mira livres, exceto feedback de combate e interação contextual.
Chefe só aparece quando ativo. Progressão, ofertas e descrições ficam em menus.

**Acampamento:** nível/XP à esquerda e entrada compacta de menu à direita.
Dentro da fila, cartão de embarque na região inferior entre áreas dos polegares.
Sem vida, munição ou mira. Embarque continua sendo pelo heliponto.

**Mobile em paisagem:** derivar a composição a partir de 667×375 e 844×390.
Não encolher toda a UI pela largura. Manter alvos touch, abreviar rótulos
secundários e recolher informação opcional. Reservar analógico e pulo nativos;
menus limitados à área segura com rolagem e fechar sempre acessível.

**PC e tablet:** verificar 1024×768, 1366×768 e 1920×1080. No PC, meta de
HUD persistente em até aproximadamente 20% da tela. Dispositivos híbridos
trocam os rótulos conforme entrada em uso. Controle por gamepad ainda requer
um passe próprio de navegação e foco.

O [plano de HUD](../PLANO-HUD.md) detalha fila, lobby, preparação, onda,
final, extração, eliminação, entrada tardia e resultado. Não introduzir minimapa,
revive ou seleção de classe no hub por meio do design system.

## Movimento e mensagens

Feedback de ação: 120 ms. Abertura/fechamento: 200 ms. Aviso breve: 3 s.
Estes tempos são tokens propostos, não mudanças dos timers de gameplay.
Prioridade: perigo/objetivo → falha de ação → recompensa. Não empilhar
animações sobre a mira. Não usar flashes contínuos; movimento reduzido remove
transições decorativas, mantendo números, rótulos e feedback necessário.

Mensagens dizem o que fazer: “RECARREGANDO”, “SEGURE PARA REPARAR”,
“CRÉDITOS INSUFICIENTES”, “CHEGUE AO HELICÓPTERO”. Valores, ondas, preços,
capacidade e cooldown vêm de Config/estado do servidor; os valores na prancha
são exemplos visuais. Não exibir promessa de recurso inexistente.

## Integração e validação

Fonte dos tokens: `src/client/UI/Tokens.luau`. `Theme` expõe `TOKENS`,
`COLOR` e `FONT`, mantendo a API existente de `text`, `panel` e `button`.
Cor, fonte e geometria desses helpers agora vêm dos tokens, com os mesmos
valores anteriores. Espaçamentos, tamanhos, camadas e estados são contratos
para a migração dos controladores; ainda não foram aplicados a todas as telas.
Há cores e medidas locais nos HUDs que devem ser migradas num próximo passe.

Exemplo para um componente novo:

```lua
local Theme = require(script.Parent.Parent.UI.Theme)
local T = Theme.TOKENS
Theme.panel(frame, T.transparency.modal)
Theme.text(frame, "heavy", {
    Text = "SUPRIMENTOS",
    TextScaled = false,
    TextSize = T.textSize.title,
})
```

Prancha é uma especificação vetorial, não captura do Roblox. A prévia PNG usa
fontes condensadas locais equivalentes; a aparência exata de Oswald/Bangers
deve ser validada no Studio. Próximo passe: migrar componentes e conferir em
execução contraste, sobreposições, textos longos, foco, alcance dos dedos e
abertura de menu durante início de onda. Não declarar validação em aparelho
físico ou Studio a partir desta prancha.
