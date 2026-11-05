# DevAssistance 0.2

Ferramentas contextuais para ajustar e observar experimentos durante a execução. A primeira integração é o teste visual existente; a interface usa Dear ImGui e os menus só existem enquanto seus alvos estão na árvore.

## Testar agora

1. Abra `res://debug/visual/visual_debug.tscn` e pressione **F6**. Também pode usar **Project → Tools → DevAssistance: executar cena atual**.
2. No cabeçalho, o ícone da **paleta** abre/fecha o menu Visual; o **frasco** abre/fecha Experimento. Passe o mouse para ler os nomes.
3. Arraste a barra de título para mover um menu. O traço recolhe seu conteúdo; o ícone no cabeçalho fecha o menu. O ícone no cabeçalho permite reabri-lo. É possível abrir os dois juntos.
4. Em **Ajustes**, altere sliders ou clique no campo numérico para digitar. **Sistemas** reúne as chaves booleanas. Os limites também são aplicados à entrada numérica e aos presets. Passe o mouse para ler a descrição; O ícone de restauração recupera o valor inicial daquele parâmetro.
5. Clique no nome do parâmetro para fixá-lo, ou no alfinete do painel para fixar todos. Botão direito no nome restaura o valor inicial. Use a fixação para acompanhar um valor fora do menu. As observações continuam visíveis quando as ferramentas são ocultadas e não capturam cliques.
6. Use **Ctrl+Alt+D** para ocultar/reabrir as ferramentas e dê duplo clique no cabeçalho para recuperar o posicionamento. O layout e as seleções de observação duram somente nesta execução.

Os menus usam rolagem e são limitados às dimensões da janela, independentemente da escala do viewport 3D. O guia considera janelas de pelo menos **640×360**.

## Presets, ações e câmera

Na aba **Ações**, cada menu oferece suas ações. O rodapé contém o seletor de presets e **Salvar preset**. Informe um nome e use **Salvar / substituir preset**. Os botões **Aplicar** recuperam os valores salvos em `user://devassistance/presets.cfg`, separados pelo identificador do contexto. Salvar o mesmo nome substitui aquele preset. Os arquivos do projeto não são alterados.

Presets guardam parâmetros registrados; não salvam o estado completo do mundo, o layout ou o posicionamento do personagem. **Reiniciar experimento**, no menu Experimento, restaura os parâmetros iniciais, a posição do personagem, comparações e câmera. O gráfico **Frame time**, na aba Ações, mostra o tempo do frame em ms amostrado a cada 0,1 s, com até 120 amostras; ela não substitui o profiler da Godot.

As comparações **F1–F4** e **Home** continuam disponíveis. **Controlar personagem** fecha as ferramentas e captura o mouse. Abrir com Ctrl+Alt+D libera o mouse e bloqueia apenas os comandos locais; gravidade, física e atualizações visuais continuam. Fechar retoma seu controle. Esc continua liberando o mouse conforme o controlador existente. Home volta à câmera de órbita.

**Medir e capturar A/B** preserva a medição anterior: oculta ferramentas e observações, mede as configurações e restaura o estado ao concluir. Resultados em `user://sen5/`.

## Integrar outro experimento

Adicione um `DevAssistance` como filho da cena e registre os alvos depois de estarem prontos:

```gdscript
var tools := DevAssistance.new()
add_child(tools)
tools.register_context("rig.example", "Rig", null, rig_node, [
    {
        "property": "blend", "label": "Influência do IK",
        "description": "0 desliga o IK; 1 aplica sua influência completa.",
        "min": 0.0, "max": 1.0,
    },
], [
    {"label": "Reiniciar", "description": "Restaura as condições do teste.",
     "callback": reset_experiment},
])
```

Esse exemplo pressupõe que `rig_node` já tem a propriedade `blend` e que o experimento fornece `reset_experiment`. A ferramenta aceita propriedades **bool, int e float**. O terceiro argumento é uma `Texture2D` opcional; sem ícone, usa um botão de texto. IDs estáveis identificam os presets entre execuções. Ações são chamadas de forma diferida, permitindo reiniciar ou trocar uma cena com segurança.

O registro captura os valores iniciais e acompanha os valores atuais a cada frame, inclusive alterações feitas pelo Inspector remoto. A saída do alvo da árvore remove o menu e suas observações. Nenhuma descoberta automática de sistemas do jogo é feita.

Para jogos que leem entradas por polling (`Input.is_action_pressed`), conecte `visibility_changed(open)` para bloquear somente as entradas do controlador enquanto as ferramentas estão abertas, mantendo física e animações ativas; o teste visual demonstra essa integração. Fechar apenas uma janela de menu não retoma o gameplay: Ctrl+Alt+D controla a visibilidade do ambiente inteiro.

A apresentação mantém Dear ImGui, com fontes Nunito e IBM Plex Mono, grade de ícones, indicação do contexto aberto, painéis translúcidos e arraste com interpolação independente do FPS. O blur usa uma cópia da tela abaixo do ImGui, conforme a [documentação de screen-reading shaders da Godot](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html). Os primeiros 16 painéis visíveis recebem blur; os demais continuam funcionais com transparência. A camada 127 fica reservada ao fundo e a configuração ImGui deve manter a camada 128. O fundo também é ocultado durante medições A/B.

Para ajustar durante a execução: abra a árvore **Remote**, selecione `VisualDebug/DevAssistance` e altere no Inspector:

- `drag_response`: resposta por segundo, 0–40. Maior acompanha o cursor mais rápido; 0 remove a suavização.
- `background_blur`: 0–5 níveis de mipmap. Maior desfoca mais; 0 mantém a cena nítida sob os painéis.
- `panel_opacity`: 0,3–1. Maior aumenta o contraste e oculta mais o fundo.

**F4** liga a órbita da câmera com os menus abertos e permite conferir imediatamente que a cena continua ativa. No modo personagem, o bloqueio usa `input_enabled` em vez de desativar o processamento do nó.

Os exports `toggle_shortcut` e `start_open` configuram o atalho e a abertura inicial. O atalho pode ser alterado no Inspector remoto. As fontes da interface ficam no recurso `res://addons/imgui-godot/data/DevAssistanceConfig.tres` para a próxima execução.

## Dependências e distribuição

- **imgui-godot 6.3.2 / Dear ImGui 1.91.6**, pacote completo oficial: [release fixada](https://github.com/pkdawson/imgui-godot/releases/tag/v6.3.2). Suporte a GDScript por GDExtension, sem exigir C#. A licença e os binários ficam em `addons/imgui-godot/`. Há uma configuração própria de escala 1,0 e layout sem persistência.
- Fonte **Nunito Regular**, copiada do recurso já distribuído no projeto; licença SIL OFL em `fonts/OFL.txt`.
- Ícones da biblioteca **@icons 1.5.0** instalada pelo usuário: duas cópias SVG e a licença MIT estão em `icons/`. A execução não depende do plugin de seleção de ícones do editor.

A instalação está habilitada em `project.godot`. Para atualizar a dependência, substitua pelo pacote oficial, preserve `DevAssistanceConfig.tres` e repita a validação. O teste foi feito em **Windows x86_64, Godot 4.7.1, Forward+ / D3D12**; os demais binários do pacote estão preservados, mas não foram testados.

O handler não processa nem abre ferramentas em builds release. O exporter do imgui-godot usa `imgui/release=false` por padrão e exclui sua execução; mantenha essa opção desativada nos presets de exportação. A validação desta versão não inclui um executável exportado, pois o ambiente não tem os templates de exportação instalados.

## Validação e limites desta versão

```text
Godot --headless --path . --script res://debug/visual/verify_dev_assistance.gd
Godot --path . --script res://debug/visual/verify_dev_assistance.gd -- --da-capture
Godot --path . --script res://debug/visual/verify_post_process.gd
```

O primeiro comando verifica registro e remoção de alvos, limites, reset, persistência de presets, Ctrl+Alt+D e controle do personagem. Em modo gráfico também verifica arraste por eventos, acomodação após soltar, blur dentro/fora dos painéis e ocultação na medição. O segundo também gera capturas em 1280×720, 800×600 e 640×360 em `user://devassistance/`. O terceiro executa as regressões gráficas existentes do pós-processamento. Testes de presets usam um arquivo separado dos presets do usuário.

Câmera livre, seleção espacial, gizmos, visualizações físicas, módulos de rede e edição de objetos são próximos recortes possíveis. Nesta versão, a câmera e as ações pertencem ao experimento visual e usam os controles já existentes.

## Referência Figma — SEN-19

Interface baseada no frame **Context Handler · Overlay (3:2)** do [DevAssistance Design](https://www.figma.com/design/CJE6FhvUOe39HZmyuHdzjq/DevAssistance-Design?node-id=3-2). Painéis de 356 px, raio de 14 px, destaque lilás, Nunito Regular/Bold e IBM Plex Mono. Os SVGs originais exportados estão em `icons/figma/`, preservados nas dimensões originais. As fontes adicionais vêm de google/fonts, sob SIL OFL (licenças em `fonts/`). A apresentação permanece em Dear ImGui; primitivas visuais ficam em `figma_skin.gd`.

Para comparar diretamente o desenho, abra **`res://debug/visual/dev_assistance_design_preview.tscn` com F6**. Os oito cartões e os valores de LocalPlayer são demonstrações de interface; os sistemas correspondentes não foram implementados. Seus presets usam `user://devassistance/design_preview.cfg`. A integração real continua em `visual_debug.tscn`, com Visual e Experimento.

O cabeçalho adapta o número de linhas aos contextos registrados. Em janelas baixas o painel começa à direita, com rolagem interna. Cabeçalho e painéis têm arraste suavizado. Tab/Enter permitem navegar e confirmar o diálogo de presets.

Verificação gráfica adicional: `Godot --path . --script res://debug/visual/verify_dev_assistance_design.gd`. Exercita os controles por eventos reais de mouse/teclado e grava `user://devassistance/figma_preview.png`.
