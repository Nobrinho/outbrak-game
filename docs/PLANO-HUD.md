# Planejamento de HUD — Hub e Fazenda

Status: proposta para revisão visual, sem mudanças no gameplay ou nos scripts de interface.
Base: interfaces atuais em src/hub/Controllers e src/client/Controllers, tema em src/client/UI/Theme.luau e regras atuais em src/shared/Config.luau.

## Objetivo e direção

O hub deve responder: onde embarcar, com quem vou e qual é meu progresso.
A fazenda deve responder: o que preciso fazer agora, quanto posso aguentar e quais ações tenho disponíveis.

Manter a identidade existente: painéis grafite translúcidos, textos claros, Oswald para leitura e números, Bangers apenas em anúncios breves. Amarelo para interação/economia; ciano para jogador/habilidade disponível; vermelho para perigo; laranja para fogo. Estado sempre tem texto ou símbolo além de cor.

Centro e região abaixo da mira ficam livres durante deslocamento e combate, exceto mira, confirmação de acerto, progresso curto de recarga e interação contextual. Evitar molduras grandes, títulos permanentes e instruções longas sobre o cenário.

## 1. Hub no PC

| Região | Conteúdo | Quando aparece |
|---|---|---|
| Superior esquerda, abaixo dos controles Roblox | Nível e barra curta de XP | Sempre |
| Superior direita, fora da lista de jogadores | Menu compacto: progressão, loja cosmética e opções | Sempre; uma única entrada pode reunir as telas |
| Superior central | Orientação curta: “Vá ao heliponto da Fazenda” | Primeira entrada; desaparece após compreensão/embarque |
| Inferior central | Fazenda, ocupação 2/4, contagem e “Saia do heliponto para cancelar” | Somente dentro da fila |
| Próximo ao ponto de interesse | Nome e condição do heliponto | No mundo; evitar repetir no HUD fora da fila |

Não criar seleção de classe no hub nesta etapa: o projeto já oferece essa seleção na fazenda. Uma transferência futura precisa de decisão própria sobre persistência e fluxo.

Não mostrar vida, munição, mira ou botões de combate no acampamento. O próprio heliponto continua sendo a ação de embarque; não adicionar um botão “Jogar” que concorra com esse fluxo.

## 2. Hub no mobile

Mesma organização do PC, em paisagem, com nível/XP resumidos e uma única entrada de menu no alto à direita.

- Inferior esquerda: analógico de movimento do Roblox.
- Inferior direita: espaço reservado ao controle de pulo, caso esteja habilitado.
- Centro/direita do cenário: área livre para arrastar a câmera.
- Fila: cartão curto entre as áreas dos polegares, acima da margem inferior; em telas estreitas, duas linhas sem reduzir demais o texto.
- Menus: uma tela por vez, com fechar visível e conteúdo rolável se necessário.
- Falha de teleporte: mensagem clara, fim da tela de carregamento e retorno ao estado de fila informado pelo servidor.

## 3. Fazenda no PC

| Região | Conteúdo | Prioridade |
|---|---|---|
| Superior esquerda | Vida e créditos da partida em um único bloco | Alta |
| Superior central | Fase, onda atual/total e informação da fase | Alta |
| Superior direita | Arma, munição atual/reserva; abaixo, habilidade e granadas | Alta |
| Centro | Mira, hitmarker e barra curta durante recarga | Alta |
| Próximo ao alvo interativo | Nome da ação, tecla E e progresso de segurar | Contextual |
| Sob a informação da fase | Vida do Brute | Somente enquanto o chefe estiver ativo |
| Menu secundário | Classe, progressão, opções e loja cosmética conforme permitido pela fase | Baixa |

Manter os comandos atuais: mouse esquerdo atira; direito mira; R recarrega; Q usa habilidade; G lança granada; V usa corpo a corpo; E interage. Exibir atalhos junto à ação correspondente e tutorial curto na primeira partida, sem uma lista permanente de teclas.

Não adicionar minimapa no primeiro passe. Usar marcação de objetivo para a extração, com indicação de direção quando sair da tela; esse marcador é uma melhoria proposta, não um recurso confirmado na interface atual.

## 4. Fazenda no mobile

Informações superiores iguais às do PC, com menos texto: vida/créditos à esquerda, fase/onda ao centro e arma/munição à direita. Menus e progressão recolhidos durante combate.

Distribuição dos polegares:

- Esquerdo: analógico de movimento, sem painéis sobrepostos.
- Direito: área de arrasto para câmera e botão principal ATIRAR próximo da borda, acima da região de apoio do polegar.
- Próximos ao tiro: MIRA com alternância e RECARREGAR, como ações frequentes.
- Acima do grupo: HABILIDADE com recarga e GRANADA com quantidade.
- Corpo a corpo e pulo: reservar posições distintas e acessíveis; validar junto aos controles Roblox existentes antes de fixar o desenho.
- INTERAGIR: botão contextual separado, à esquerda do grupo de ações e fora do centro da mira. Só aparece com alvo válido; mostra “Comprar”, “Munição” ou “Reparar” e progresso de segurar.

Disparo automático continua como preferência inicial de touch conforme o sistema existente; manter tiro manual acessível. Quantidade de granadas e recarga da habilidade ficam nos próprios botões para evitar duplicação.

Ponto de partida para protótipo: ações secundárias de 56–64 unidades de UI, tiro de 80–96 e separação de 8–12. Ajustar após teste em aparelho; não escalar o conjunto inteiro proporcionalmente à largura. Ícone com rótulo curto no primeiro passe, sem abreviações ambíguas.

## 5. Estados da fazenda

| Estado | Informação dominante | Interfaces adicionais |
|---|---|---|
| Lobby | Pronto, jogadores e contagem | Seleção de classe e progressão |
| Preparação | Tempo restante; reparar e reabastecer | Classe disponível, créditos e interação com loja |
| Onda | Onda atual/total e zumbis restantes | Combate; ocultar ofertas e progressão |
| Final | Sobrevivência e tempo até helicóptero | Combate e barra do chefe quando aplicável |
| Extração | “Chegue ao helicóptero” e tempo restante | Marcador do destino proposto |
| Eliminado | Condição atual e regra de retorno real | Retirar ações que não funcionam; não sugerir reviver sem suporte |
| Entrada tardia | Partida em andamento e informação de entrada | Voltar ao hub quando permitido |
| Resultado | Resultado, XP ganho e tempo até próxima partida | Voltar ao hub e progressão |

O total de ondas vem da configuração/estado da partida. Atualmente são 10; o documento inicial de pré-produção descreve 3. Não fixar o número na arte.

## 6. Comportamentos compartilhados

- Reservar espaço para barra superior, chat, lista de jogadores, recortes da tela, analógico e pulo do Roblox. Não assumir que margem física segura resolve todas essas colisões.
- Em dispositivos híbridos, apresentar controles conforme a entrada em uso, evitando mostrar touch e atalhos de teclado simultaneamente sem necessidade.
- Abrir menu libera o cursor e impede tiro/rotação de câmera causados pela interação com a interface. Fechar restaura o controle; o mundo multiplayer continua rodando.
- Uma janela principal aberta por vez. No início de onda, fechar telas de compra/classe que perderam validade e devolver controle ao jogador.
- Avisos breves não se empilham no centro. Prioridade: perigo/objetivo, falha de ação, recompensa.
- Baixa munição: número e símbolo/aviso curto; vida baixa: barra e efeito discreto nas bordas. Não usar flashes intensos contínuos.
- Barra de chefe não deve empurrar o bloco de objetivo sobre a mira.
- Compra, reparo e habilidades mostram estados disponível, indisponível e em andamento, com o motivo quando útil.

## 7. Organização proposta para implementação

Preservar os controladores existentes, centralizando as decisões de espaço, modalidade e visibilidade para que cada um não escolha posições isoladamente.

1. Definir medidas, margens, tamanhos de texto e variantes compacta/ampla no sistema de UI compartilhado.
2. Fazer quatro wireframes: hub PC, hub mobile, fazenda PC e fazenda mobile; representar também fila, chefe e loja aberta.
3. Ajustar primeiro a composição do mobile da fazenda, que tem mais restrições; depois derivar a versão PC.
4. Aplicar composição do hub reutilizando o mesmo tema.
5. Integrar transições por fase, prompts e menus; verificar regressões de entrada e teleporte.

Novos elementos propostos que exigem implementação: entrada unificada de menu, composição responsiva compartilhada e marcador de extração. Não assumir seleção de classe no hub, inventário novo, minimapa, revive ou indicador de aliados como sistemas já disponíveis.

## 8. Critérios de validação

Testar telas de referência 667×375, 844×390, tablet 1024×768, PC 1366×768 e 1920×1080, incluindo proporções diferentes, recortes e UI Roblox. Usar emulador para composição e celular físico para alcance dos dedos.

- Vida, munição e fase legíveis sem abrir menus.
- Nenhuma sobreposição entre HUD, controles touch e interfaces Roblox nas telas de referência.
- Movimento, câmera e ação frequente utilizáveis com dois polegares; ações ocasionais podem exigir reposicionamento breve.
- Interface persistente no PC ocupa como meta até aproximadamente 20% da tela; mobile validado principalmente pelo espaço de visão e alcance dos dedos.
- Testar: fila 1/4 e 4/4, sair da fila, teleporte/falha, loja, recarga, habilidade indisponível, início de onda com menu aberto, chefe, extração, eliminação e resultado.
- Nomes e mensagens longos não invadem controles; menus rolam e mantêm fechar acessível.
- Ao fechar menus, trocar de entrada ou retornar de segundo plano, nenhuma ação fica presa.

Este documento define a proposta de layout. Ainda não representa HUD implementado nem validação visual em execução.

## Revisão do protótipo — 27/10/2026

Referência: captura mobile fornecida pelo usuário. Conflitos visíveis: controles do Roblox sobre vida/créditos; modal de classe concorrendo com botões de combate, Pronto e retorno; coluna Classe/Nível/VIP consumindo visão lateral.

Proposta revisada, ainda sem aplicação nos scripts:

- Reservar a faixa superior para a UI do Roblox e recortes do aparelho. A faixa ilustrada no protótipo é esquemática; a aplicação deve usar os insets reais do runtime, sem presumir altura fixa universal. `CoreUISafeInsets` é a referência para HUD interativo, enquanto mira/efeitos continuam alinhados à câmera em camada própria.
- Vida/créditos no inferior esquerdo no PC e acima da área do analógico no mobile. Progressão/VIP ficam no menu durante a partida.
- Arma/munição no inferior direito no PC. No mobile, arma/munição e ação de faca ficam em acesso rápido na base, fora do pulo nativo.
- Preservar analógico e pulo nativos, sem criar pulo duplicado. Tiro grande na direita acima do pulo; mira alternável e recarga ao lado; granada e habilidade em posições secundárias. Não acrescentar corrida/agachamento sem mecânica correspondente.
- Escolha de classe oculta HUD e ações de combate. Selecionar → confirmar classe → Pronto. Retorno ao hub pertence ao rodapé da janela; nenhum botão flutua sobre os cartões.
- Protótipo interativo com menus, seleção/confirmar/Pronto, tiro/recarga ilustrativos e opção de disparo automático. Nenhum desses cliques dispara rede ou compra real.
- Alternar controles pelo tipo de entrada preferido, incluindo troca para mouse/teclado em aparelho touch.

Fontes oficiais consultadas:
- https://create.roblox.com/docs/ui/on-screen-containers
- https://create.roblox.com/docs/input

Limites: revisão baseada na captura enviada e no protótipo HTML. Alcance físico, sensibilidade, multitouch e convivência com a UI real do Roblox ainda dependem de teste em Studio/aparelho. Não se trata de auditoria do jogo em execução.
