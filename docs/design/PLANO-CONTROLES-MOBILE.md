# Plano de controles mobile — mapa Fazenda

Data: 27/10/2026. Estado: proposta de desenvolvimento; não altera o jogo.

## Objetivo e decisão de design

Entregar controles para um shooter cooperativo de sobrevivência em terceira pessoa que permitam caminhar, acompanhar um zumbi com a câmera e disparar usando dois polegares. O jogador deve conseguir executar as ações principais sem reposicionar a mão, acionar outro botão por engano ou perder a visão das ameaças.

Responsividade terá três critérios independentes: adaptação geométrica às telas, alcance confortável dos controles e resposta correta aos gestos simultâneos. Uma captura sem sobreposições comprova apenas parte do primeiro critério.

Escopo principal: combate na Fazenda. O acampamento reutilizará infraestrutura de área segura, preferências e entrada, sem exibir botões de combate. PC e controle físico terão testes de regressão. Preservar estilo visual aprovado, regras de combate, pulo e movimento nativos inicialmente.

## 1. Diagnóstico da implementação atual

Revisão baseada nos fontes locais e no relatório do teste anterior. O defeito relatado agora ainda não foi reproduzido no aparelho do usuário; os itens abaixo distinguem fatos de riscos.

| Evidência no código | Consequência / risco | Prioridade |
| --- | --- | --- |
| `Layout.luau` calcula escala por `clamp(alturaSegura / 380, 0.85, 1.15)` | Largura disponível e proporção não determinam a composição do conjunto; falta um perfil compacto próprio | P0 |
| `MobileHUD.luau` posiciona grupo de 240×116 vezes a escala, com offsets e compensação de primeira linha | Correções locais não garantem que todos os botões caibam quando outras reservas mudam | P0 |
| Botões secundários têm diâmetro `52 * escala`, chegando a 44,2 unidades | Tamanho físico e facilidade de toque não foram comprovados; não confundir unidades Roblox com pt/dp | P0 |
| Faca e interação acompanham a posição calculada da munição | Uma decisão sobre informação visual desloca comandos; pode afastá-los do polegar | P1 |
| Disparo é um TextLabel pass-through, detectado por TouchStarted global | É necessário verificar prioridade sobre outras interfaces e coexistência com a câmera nativa; conflito ainda é hipótese | P0 |
| Layout observa coordenadas do analógico dinâmico | Pode recalcular o HUD durante movimento do dedo; verificar se a vida muda de posição e estabilizar reservas | P1 |
| Dependência dos nomes JumpButton/ThumbstickStart/StickImage | Isolar descoberta e prever fallback caso a hierarquia nativa mude | P1 |
| Verificador atual confere interseções de alguns widgets e insets | Não verifica limites completos, tamanho físico, hitboxes, textos, arrasto nem multitouch | P0 |
| Evidência anterior cobre uma configuração mobile da Fazenda | Não comprova adaptação a outros celulares, tablets ou uso físico prolongado | P0 |

Preservar o que já existe de útil: CoreUISafeInsets, seleção por PreferredInput, mira alternável, bloqueio de combate em modal e cancelamento ao perder foco. Revalidar esses comportamentos após a reorganização.

## 2. Princípios e fontes

Controles frequentes devem ficar ao alcance dos polegares; movimento à esquerda e câmera à direita; menus secundários podem ficar no topo. A Apple recomenda estados de pressão visíveis e alvos frequentes com pelo menos 44×44 pt. Usaremos essas orientações como referência ergonômica, sem converter pt diretamente para offsets Roblox. [Apple — Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls).

O Android recomenda alvos de pelo menos 48×48 dp e separação de 8 dp; a área clicável pode ser maior que o ícone. Essa recomendação orienta a validação física, não fornece uma equivalência automática para Roblox. [Android — Touch target size](https://support.google.com/accessibility/android/answer/7101858?hl=en-GB).

Manter interfaces interativas em CoreUISafeInsets para respeitar controles superiores e recortes do aparelho; isso não substitui reservar espaço para movimento, pulo e dedos. [Roblox — On-screen UI containers](https://create.roblox.com/docs/ui/on-screen-containers).

Usar PreferredInput para o modo de entrada vigente e preservar bindings nativos quando adequados. TouchEnabled indica capacidade e não deve sozinho decidir qual HUD aparece. [Roblox — Input](https://create.roblox.com/docs/input).

Todas as posições, medidas e metas de desempenho propostas nas seções seguintes são hipóteses específicas deste projeto, a calibrar nos testes, e não padrões oficiais dos fabricantes.

## 3. Composição recomendada

| Região | Conteúdo e comportamento |
| --- | --- |
| Faixa reservada do Roblox | Nenhum botão, contador ou painel nosso sobre os controles do aplicativo |
| Topo da área segura | Objetivo/onda compacto ao centro; menu discreto à direita; informação longa recolhida durante combate |
| Inferior esquerda | Analógico nativo; vida imediatamente acima de uma reserva estável de movimento; créditos deixam a área principal do combate |
| Centro | Mira e feedback breve de acerto/dano; sem cartões persistentes sobre inimigos |
| Direita livre | Superfície ampla para arrastar câmera, incluindo região do disparo com política explícita de compartilhamento |
| Alcance do polegar direito | Disparo maior, próximo da posição natural de repouso; recarga e mira nos vizinhos mais próximos |
| Reserva inferior direita | Pulo nativo preservado; disparo não invade seu alvo de toque |
| Arco secundário direito | Habilidade, granada e faca em posições estáveis, com granada afastada do tiro e da recarga |
| Próximo da arma | Munição compacta e legível; não usar o painel de munição para ancorar a geometria dos botões |
| Interação contextual | Slot reservado perto das ações, visível quando aplicável; não deslocar os demais controles ao aparecer |

Não determinar todas as coordenadas agora a partir de uma captura. Primeiro medir área segura, reservas nativas, alvos mínimos e alcance; então escolher e validar a composição. Todos os comandos existentes de combate permanecem acessíveis, sem esconder granada ou habilidade em menu durante uma onda.

## 4. Contrato de cada controle

| Ação | Gesto proposto | Feedback e regra de término |
| --- | --- | --- |
| Movimento | Analógico nativo | Soltar encerra movimento; nenhuma UI nossa captura a região reservada |
| Câmera | Arrastar região direita livre | Movimento contínuo; abrir modal interrompe a captura |
| Tiro | Pressionar e segurar; arrastar o mesmo dedo acompanha alvo | Pressão visível imediata; soltar aquele dedo encerra o tiro mesmo fora do botão |
| Mira | Toque alterna ligado/desligado por padrão | Estado explícito; opção segurar só como preferência; morte/modal limpa o estado |
| Recarga | Um toque | Uma solicitação por gesto; estado de recarga e resultado refletidos na munição |
| Granada | Um toque, preservando mecânica atual | Contagem e indisponibilidade claras; não transformar em lançamento ao soltar sem projeto específico |
| Habilidade | Um toque | Mostrar cooldown e confirmação da ativação; servidor continua autorizando |
| Faca | Um toque, preservando cadência existente | Resposta visual de ataque; posição independente do contador de munição |
| Interagir | Toque ou segurar conforme HoldDuration do prompt | Progresso e cancelamento; sumir alvo/modal cancela a ação pendente |
| Pulo | Controle nativo | Sem botão duplicado e sem sobreposição |

O gesto iniciado no tiro continua pertencendo ao tiro/câmera quando o dedo sai do círculo; não deve acionar granada ao cruzá-la. Um arrasto de câmera iniciado fora do tiro não começa a disparar ao cruzar seu alvo.

Não exigir três dedos para o ciclo caminhar + acompanhar alvo + atirar. Pular e atirar simultaneamente em modo manual pode exigir outro dedo; o projeto não deve prometer todas as ações simultâneas com apenas dois. Preservar o disparo automático opcional já existente, explicar seu estado e testar manual e automático separadamente. Não alterar força de assistência de mira ou regras de dano junto com o ajuste de HUD.

## 5. Tamanho e adaptação

Separar três geometrias: ícone, superfície visual e alvo de toque. O ícone pode ser menor, mas alvos ampliados não podem se sobrepor nem roubar arrastos da câmera. Contorno circular não basta: a área efetiva precisa ser medida e testada.

Pontos iniciais para prototipação em unidades de UI do Roblox, sujeitos a calibração física:

| Elemento | Faixa inicial |
| --- | --- |
| Alvo do tiro | 76–96 por lado |
| Alvos de mira e recarga | 56–68 por lado |
| Alvos secundários | 52–64 por lado |
| Separação entre alvos customizados | 10–16 |
| Margem adicional dentro da área segura | 12–20 |

Essas faixas não equivalem a pt/dp nem são limites físicos universais. Se um perfil não couber, reduzir painéis e textos secundários e recompor a distribuição antes de diminuir os controles abaixo do mínimo validado naquele aparelho.

Três perfis de composição, escolhidos pela área utilizável e pelas restrições satisfeitas, não pelo nome do dispositivo:

1. **Celular compacto:** objetivo de uma linha, vida compacta, contador de munição reduzido, controles principais preservados e secundários reorganizados. Não mover ações ao receber dano ou aparecer um prompt.
2. **Celular amplo/alongado:** mesmos agrupamentos e ordem dos controles; espaço extra libera a cena e área de câmera, sem esticar as distâncias entre ações.
3. **Tablet:** grupos próximos às bordas de pegada, com escala máxima e alcance configurável. Não distribuir ações pelo centro nem aumentar tudo proporcionalmente à largura.

Calcular largura e altura mínimas exigidas por cada perfil a partir dos alvos, espaçamento e reservas. Escolher o primeiro perfil que satisfaça as restrições; se nenhum satisfizer, registrar falha e revisar o suporte àquela área, sem ocultar uma ação crítica silenciosamente.

Manter paisagem nas duas orientações. Durante mudança de orientação, cancelar gestos ativos antes de reposicionar. Ajustar a novos insets sem contar a margem duas vezes. O HUD não deve seguir o movimento do analógico dinâmico; usar envelope estável de interação. No modo PC, mudanças de tamanho da janela também devem preservar legibilidade.

## 6. Entrada e câmera

Criar uma camada pequena de roteamento touch integrada ao InputController existente. Cada InputObject mantém dono até terminar: controle nativo, câmera, tiro com câmera, outra ação ou modal. Uma ação só pode liberar o toque que a iniciou; quando mais de uma fonte puder mantê-la, usar conjunto de fontes ativas, evitando que uma liberação cancele outra fonte válida.

Prioridade: interface do sistema → modal do jogo → alvo exclusivo de ação → gesto compartilhado tiro/câmera → câmera livre. Não implementar simplesmente ignorando todo gameProcessedEvent: o compartilhamento intencional do tiro precisa de contrato explícito, enquanto controles exclusivos devem consumir o gesto.

Antes de substituir a câmera nativa, instrumentar o pass-through atual. Verificar se ela recebe o arrasto uma única vez e se reconhece corretamente o dedo junto ao analógico. Conservar a solução nativa se passar nos testes; adaptar a integração apenas se houver conflito reproduzido. Não somar uma rotação manual à rotação nativa do mesmo gesto.

Liberar ações ao terminar/cancelar toque, perder foco, abrir modal, morrer, renascer, trocar dispositivo e mudar orientação. Não remapear um dedo já pressionado para um novo botão durante uma mudança de layout.

Mostrar pressão local até o próximo frame renderizado, sem esperar ida e volta ao servidor. Dano, munição e efeitos de habilidade continuam sujeitos à autoridade do servidor. Registrar separadamente demora de entrada, frame e confirmação de rede para não diagnosticar latência de rede como tamanho errado de botão.

## 7. Estados, acessibilidade e preferências

Usar estados distinguíveis: normal, pressionado, ativo, indisponível e cooldown. Combinar ícone/contorno/número com cor; não depender só de vermelho versus verde. Evitar pulsos permanentes. Verificar contraste sobre terra, fogo, vegetação, noite e enxame.

Manter ações indisponíveis em posições estáveis e indicar o motivo relevante. Interação só aparece com alvo válido, sem empurrar tiro/recarga. Loja e seleção de classe bloqueiam ações atrás do painel; isso não pausa a partida multiplayer nem congela inimigos.

Primeira versão: ajustes limitados de tamanho, transparência, sensibilidade normal e ao mirar, mira alternar/segurar e disparo automático. Manter opção restaurar padrão. Não mudar a preferência do jogador silenciosamente ao reconectar teclado ou controle.

Etapa posterior: editor de posição com validação de limites/colisões, perfis separados de celular e tablet e persistência versionada. Um preset canhoto completo exige estudar também movimento/câmera nativos; não basta espelhar somente os botões de combate. Adiar editor livre e presets avançados até o padrão funcionar bem.

## 8. Implementação em etapas

| Etapa | Trabalho | Arquivos principais | Entrega para revisão |
| --- | --- | --- | --- |
| 1 — Reproduzir | Registrar viewport, área segura, orientação, entrada, geometria nativa e sequência que falha | verify-hud e relatório QA | Capturas e passos da falha; separar corte/sobreposição de toque perdido |
| 2 — Especificar | Definir regiões reservadas, alvos, três perfis e política de gestos | Novo spec de layout e este documento | Prévia em celular compacto, amplo e tablet, com hitboxes visíveis no modo diagnóstico |
| 3 — Corrigir geometria | Medição compartilhada, reservas estáveis, perfis por restrições, separar munição de botões | Layout, MobileHUD, CombatHUD, MatchHUD | Nenhuma violação geométrica na matriz definida |
| 4 — Corrigir entrada | Identidade por dedo, prioridade, cancelamentos e tiro+arrasto | InputController, MobileHUD, CameraController | Sequências multitouch reproduzíveis sem ação presa |
| 5 — Refinar feedback | Estados, legibilidade, preferências básicas | MobileHUD, MenuController, CombatHUD | Sessão jogável com configuração padrão e ampliada |
| 6 — Validar | Testes em Studio e aparelhos; regressão Hub/PC | Ferramentas QA e relatório | Evidências por perfil, limitações registradas e critérios satisfeitos |

Separar cálculo de layout em função testável que receba métricas e produza retângulos, sem efeitos sobre a árvore de UI. Compartilhar uma medição por viewport, em vez de cada tela percorrer toda TouchGui. Coalescer eventos de resize e desconectar observadores de controles destruídos. Evitar recalcular geometria em RenderStepped.

Os testes automatizados devem verificar invariantes reais — limites, hitboxes, reservas, tamanho mínimo e estabilidade — em vez de apenas repetir as fórmulas da implementação. Não reescrever sistemas de arma/servidor para resolver apresentação; preservar validações de remotes e cadência existentes.

## 9. Matriz de validação

A documentação do Device Simulator permite comparar resolução, proporção e tamanho físico calibrado. Usar essas opções quando disponíveis, registrar versão do Studio e modo de escala; completar a avaliação com aparelhos reais, pois uma janela ampliada no monitor não mede alcance dos polegares. [Roblox — Device Simulator](https://create.roblox.com/docs/studio/device-simulator).

| Família | Variações a cobrir |
| --- | --- |
| Celular pequeno 16:9 | Menor área suportada; orientações paisagem esquerda/direita |
| Celular alongado 19,5:9 / 20:9 | Recorte lateral, margens do sistema, Android e iOS |
| Tablet 4:3 | Alcance lateral e escala máxima |
| Tablet 16:10 | Distribuição das ações e região livre de câmera |
| Caso anterior | Reproduzir viewport 685×338 e área segura 685×280; registrar que são medidas daquele teste |
| Híbridos | Touch → teclado/mouse → touch e controle físico conectado |
| PC | Janela pequena e 16:9; botões touch ausentes e atalhos preservados |

No Studio: varrer dimensões intermediárias e próximas de cada transição de perfil, não apenas presets. Conferir todas as fases: preparação, onda, chefe, extração, morte/espectador, respawn e modais. No acampamento: fila, progressão e menu, sem combate.

Em dispositivos reais: pelo menos um Android e um iPhone; incluir um aparelho de tela pequena. Se indisponíveis, registrar esses testes como pendentes. Avaliar a ~30 e ~60 FPS quando o hardware permitir, e com latência simulada separadamente, sem confundir desempenho do aparelho com layout.

Roteiro funcional:

1. Caminhar em círculo e acompanhar alvo por 30 segundos.
2. Repetir disparando manualmente com o polegar direito; soltar dedos em ordens diferentes.
3. Arrastar o dedo do tiro para fora do alvo e sobre outros botões, sem ativá-los.
4. Iniciar arrasto fora do tiro e cruzá-lo: não disparar.
5. Alternar mira, recarregar, usar faca/granada/habilidade e conferir uma ativação por gesto.
6. Interagir segurando; afastar-se/perder alvo e conferir cancelamento.
7. Abrir/fechar menu, minimizar/retomar aplicativo, morrer/renascer e virar aparelho durante ações mantidas.
8. Repetir com disparo automático, controles ampliados e entrada híbrida.
9. Jogar uma onda completa para avaliar ameaças ocultas, alcance, cansaço e erros involuntários.

## 10. Critérios de aceite

- Zero alvos customizados fora da área segura em toda a matriz suportada.
- Zero interseções entre alvos exclusivos; a única sobreposição funcional permitida é tiro/câmera, documentada e testada.
- Nenhum alvo invade reservas de movimento/pulo ou controles superiores do Roblox.
- Cada ação continua disponível e seu estado permanece legível no perfil compacto.
- Nenhum botão se move durante uma sequência comum de combate por aparecer prompt, dano ou cooldown.
- Ciclo caminhar + acompanhar alvo + disparar manualmente funciona com dois polegares.
- Nenhum tiro, mira ou interação fica preso após as sequências de interrupção.
- Feedback de pressão local até o próximo frame renderizado no dispositivo de teste; resposta do servidor medida separadamente.
- Pulo e câmera nativos funcionam junto aos controles novos; sem rotação duplicada.
- Teste exploratório com pelo menos cinco jogadores: observar erros e desconforto. Meta inicial proposta de 95% de acerto em toques intencionais em tarefa controlada; isso é um indicador de iteração, não garantia estatística para toda a base.
- Relatório contém tamanho real da área segura, aparelho/perfil, modo de escala, FPS observado, capturas, falhas e pendências. Screenshots sozinhas não encerram a validação.

Prioridade de entrega: geometria e reservas + gestos simultâneos → feedback e legibilidade → preferências básicas → personalização avançada. Publicação só deve ocorrer após a revisão dos resultados; este documento não publica nem implementa alterações.
