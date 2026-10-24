# Fazenda low poly — ferramentas e referência

Referência principal: [fazenda-referencia-principal.png](fazenda-referencia-principal.png),
imagem anexada e escolhida pelo usuário em 24/10/2026.
Direção visual e composição: [DIRECAO-FAZENDA.md](DIRECAO-FAZENDA.md).

Contexto do fluxo de ferramentas: https://chatgpt.com/share/6adcfdfe-6798-83e9-be65-4a574006e244

O usuário aceita Blender, com modelagem automatizada por scripts, sem trabalho manual.
A nova imagem define uma noite azulada com lua cheia e iluminação laranja nas
construções. Ela substitui o pôr do sol como referência de luz desta cena.
Casa à esquerda, moinho entre a casa e o celeiro, celeiro vermelho à direita,
silo na extrema direita e caminhonete no primeiro plano direito. Estrada de
lama e poças conduz ao celeiro. As demais imagens desta pasta são auxiliares.

## Ferramentas

- Roblox Studio: montagem, terreno, colisões, iluminação e teste jogável.
- MCP oficial do Studio: conexão direta para inspeção, scripts Luau e capturas.
- Blender 4.5 LTS Apple Silicon: modelos procedurais via Python em segundo plano.
- Rojo 7.4.4: sincronização do código; não faz upload de meshes.
- StyLua 0.20.0 e Selene 0.27.1: formatação e análise de Luau.

O Blender local fica em `.local/Blender.app`, ignorado no Git. É possível
usar outra instalação definindo `BLENDER_BIN` como o caminho do executável.
Não é necessário instalar um servidor MCP de terceiros para o Blender:
`bpy` executa os scripts diretamente.

## Comandos

```sh
python3 tools/art.py doctor
python3 tools/art.py smoke
rojo serve default.project.json --address 127.0.0.1
```

O teste `smoke` gera um barril de teste com cores sólidas e faces planas:
`assets/source/pipeline_barrel.blend`, `assets/export/pipeline_barrel.fbx`,
`assets/export/pipeline_barrel.glb` e um manifesto com triângulos e dimensões.
O FBX é o arquivo destinado ao importador 3D do Studio; o GLB facilita inspeção
em outras ferramentas. A geração é local e não publica nenhum asset.

Validação em 24/10/2026: Blender 4.5.9 LTS executado com sucesso, barril com
5 meshes e 220 triângulos exportado nos três formatos. O sandbox do Codex
causa falha na inicialização do Metal neste Mac; executar o comando de geração
com a permissão de execução fora do sandbox quando solicitado.
Studio `RobloxSwarmOutbreak.rbxlx` encontrado pelo MCP em modo Edit.
Servidor Rojo iniciado em `127.0.0.1:34872`; a conexão do plugin Rojo no Studio
não foi verificada nesta configuração.

## Prévia de geometria validada no Studio

Em 24/10/2026, a automação da janela nativa do Studio não respondeu em duas
tentativas. O FBX não foi importado pelo importador. Para testar o motor sem
depender da interface, o script Blender passou a exportar também
`pipeline_barrel.geometry.json` e `pipeline_barrel.preview.luau`.

O script de prévia usa `EditableMesh` com os vértices e triângulos do Blender,
converte Z vertical para Y vertical e mantém normais planas e cores sRGB.
Foi executado no modo Edit por MCP no projeto `RobloxSwarmOutbreak.rbxlx`.
Resultado: 5 MeshParts, dimensões 2,26 × 3,20 × 2,26 studs e pivô na base.
O modelo temporário chama-se `Workspace.ArtPipelinePreview`, está em
(300, 10, 0), é ancorado e não participa das colisões, toques ou raycasts.
A captura está em `assets/export/pipeline_barrel.studio.jpg`.

Essa prévia valida geometria e conversão de coordenadas; não comprova escala,
materiais ou persistência pelo importador FBX. Não houve publicação de assets
nem salvamento do place nesta etapa. O script é reproduzível e deve ser
executado no modo Edit somente quando não houver uma prévia com o mesmo nome.

## Import piloto concluído

O usuário importou o FBX pelo Studio em 24/10/2026 e inseriu
`Workspace.pipeline_barrel`, com cinco MeshParts e IDs de mesh publicados.
A inspeção encontrou dimensões 226 × 320 × 226 studs (100× maiores),
cor cinza uniforme, material Plastic e peças desancoradas. Orientação e
pivô na base foram preservados.

O script `tools/blender/normalize_barrel.luau` corrigiu a escala por 0,01,
reaplicou a paleta do Blender e SmoothPlastic e ancorou as peças. A amostra
fica sem colisões, toques ou raycasts, ao lado da prévia em (304, 10, 0).
A validação confirmou 2,26 × 3,20 × 2,26 studs e pivô na base.
Há waypoints de undo antes e depois da normalização.

Próximos imports deste FBX precisam da normalização: não assumir que as
cores sólidas chegam pelo FBX nem que a unidade do importador coincide com
studs. O script usa a altura medida para calcular a razão e pode ser
reexecutado. O exportador FBX permanece igual ao arquivo testado.
Para outros assets, usar dimensões e paleta dos respectivos manifestos.
A captura de comparação é `assets/export/pipeline_barrel.imported.studio.jpg`.
O place não foi salvo automaticamente após a correção.

## Convenções para os próximos modelos

- 1 unidade Blender representa 1 stud pretendido; confirmar a escala no primeiro
  import. Blender usa Z vertical, Roblox usa Y; FBX exporta Y para cima.
- Pivô no chão, origem central, transformações de escala aplicadas e nomes estáveis.
- Faces planas, materiais simples e paleta consistente com as referências.
- Mesh visual separado de colisões simples. Manter tags e pontos usados pelo gameplay.
- Assets, scripts e revisões devem ser reproduzíveis; fontes e exports são gerados.
- Fazer um import piloto antes da produção em lote: escala, cores, orientação e pivô.

## Validação de fidelidade

1. Preservar a imagem original como referência, sem substituí-la por uma nova geração.
2. Definir câmera de comparação e proporção de imagem fixas.
3. Ajustar primeiro enquadramento, posições e silhuetas da casa, celeiro, moinho e silo.
4. Refinar deterioração, vegetação, terreno, cores, luz e sombras.
5. Comparar capturas no Studio com a referência; depois validar navegação e desempenho.

FBX/GLB não entram automaticamente no Roblox pelo Rojo. O import piloto do
barril foi validado; novos assets ainda passam pelo importador do Studio.
A configuração das ferramentas não comprova ainda a fidelidade do mapa.
