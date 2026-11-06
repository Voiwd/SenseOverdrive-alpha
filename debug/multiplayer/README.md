# Testar multiplayer local / LAN

## No mesmo PC (mais fácil)

1. Na Godot, abra `res://debug/multiplayer/multiplayer_debug.tscn` pelo painel **FileSystem**.
2. Aperte **F6** (executar a cena atual). **F5** continua abrindo o jogo normal.
3. Clique em **Testar 2 janelas**. A primeira cria a sala e a segunda abre e conecta automaticamente.
4. Confira **Jogadores: 2/4** nas duas janelas. Cada janela controla seu próprio personagem.
5. Clique na arena para capturar o mouse. Use **WASD/setas**, **Shift** e o **mouse**.
6. Aperte **Esc** para liberar o mouse e **Alt+Tab** para trocar de janela.

**Repor posição** devolve o personagem local ao ponto inicial. Também há retorno automático se ele cair da plataforma. Os pilares coloridos ajudam a conferir direção e deslocamento.

A janela aberta automaticamente é um processo independente. Feche essa janela ao terminar; parar a execução no editor pode encerrar apenas a primeira. Ao fechar ou desconectar o host, o cliente volta ao menu.

## Núcleo de missão

**F5** também permite experimentar o núcleo sozinho na Sala. Ele pulsa ao lado do personagem. **E** pega ou larga. Caminhe com ele e aperte **E** de novo para deixá-lo à sua frente.

Com **F6** na arena multiplayer, o núcleo começa ao alcance dos dois primeiros jogadores. Tentem pegá-lo juntos e depois passá-lo de um para o outro. Aproxime-se de onde o portador o largou. **V** consulta a disponibilidade de disparo manual. Carregar ocupa as mãos. A arma e a morte são sistemas futuros.

No host, **G** força a soltura e **R** repõe o núcleo no centro. Desconectar o portador também libera o núcleo. Para conferir entrada tardia, pegue o núcleo no host antes de conectar o cliente.

No Inspector remoto do nó `Component`, ajuste `pickup_range` no host para mudar o alcance aceito, `drop_distance` para mudar a distância de soltura e `carry_offset` para testar a posição visual local. Aplique os valores desejados na cena para usá-los em todas as instâncias.

## Duas instâncias pelo editor

Como alternativa ao botão, configure **Debug > Customize Run Instances…** para executar **2 instâncias** (o nome pode aparecer traduzido). Execute esta cena com **F6**. Em uma janela, clique **Criar sala**; na outra, mantenha `127.0.0.1` e clique **Entrar**. Use a mesma porta nas duas.

Depois desse teste, volte a configuração para **1 instância** para não duplicar a execução das outras cenas. Se a execução embutida dificultar alternar entre jogadores, desative **Embed Game on Play** no menu de execução e use janelas separadas.

## Dois PCs na mesma rede

Abra a mesma versão do projeto e esta cena nos dois PCs. No primeiro, use **Criar sala**. No segundo, preencha o **IP do host**, exibido no painel da primeira janela, e clique **Entrar**. O padrão é a porta **UDP 7000**, ajustável antes de conectar.

O painel pode mostrar mais de um IP por causa de VPNs e adaptadores virtuais. Use o IP do adaptador conectado à mesma rede do outro PC, normalmente começando com `192.168.` ou `10.`. Se funcionar no mesmo PC mas falhar na rede, confira a permissão da Godot no firewall para redes privadas e o isolamento de clientes do Wi-Fi.

## O que conferir rapidamente

- **Imagem local:** F8 alterna o filtro apenas na janela ativa. Ajuste os parâmetros no Inspector remoto em `MultiplayerDebug/WorldPostProcess`. A interface fica na camada 10, acima do filtro. Teste visual isolado, controles e medições: [guia visual](../visual/README.md).

- **Movimento e direção:** ande e gire a câmera em uma janela; veja o outro personagem se mover e virar na outra.
- **Entrada tardia:** mova o host antes de conectar outro jogador; o cliente deve receber sua posição atual.
- **Saída e reconexão:** desconecte um cliente; seu personagem deve desaparecer. Clique **Entrar** novamente para voltar.
- **Queda do host:** desconecte ou feche o host; o cliente deve limpar os personagens e liberar o menu.
- **Falha de conexão:** tente entrar sem host; após 8 segundos o menu libera uma nova tentativa.
- **Até quatro jogadores:** abra mais instâncias desta cena e use **Entrar**. Só uma instância deve criar a sala na mesma porta.

## Organização e limites desta base

- `multiplayer_debug.tscn` / `.gd`: arena isolada, interface, conexão ENet, timeout e gerenciamento da sessão.
- `multiplayer_player.tscn` / `.gd`: reaproveitam o personagem existente com controle e câmera apenas no dono de cada jogador.
- O host usa **MultiplayerSpawner** para criar e remover os jogadores. A autoridade é definida na função de spawn, antes de entrar na árvore.
- **MultiplayerSynchronizer** transmite posição, velocidade e direção horizontal da câmera a 30 Hz. A inclinação e a marcha são calculadas localmente a partir desses valores.
- Cada dono simula seu próprio movimento. Esta é uma base para testar cooperação local; ainda não tem validação de movimento pelo servidor, predição, interpolação de rede, migração de host ou conexão pela internet/Steam.
- Os jogadores colidem com o chão e atravessam uns aos outros para evitar disputas entre simulações nesta etapa.

Os parâmetros `default_port` e `connection_timeout` ficam no Inspector da raiz do debug. A porta também pode ser ajustada pelo painel antes de criar/entrar na sala.

Para executar por terminal, os argumentos opcionais são `--mp-host`, `--mp-join=127.0.0.1` e `--mp-port=7000`, depois do separador `--` da Godot. Exemplo:

```text
Godot.exe --path "CAMINHO_DO_PROJETO" res://debug/multiplayer/multiplayer_debug.tscn -- --mp-host --mp-port=7000
Godot.exe --path "CAMINHO_DO_PROJETO" res://debug/multiplayer/multiplayer_debug.tscn -- --mp-join=127.0.0.1 --mp-port=7000
```

Referências da Godot: [replicação de cenas](https://godotengine.org/article/multiplayer-in-godot-4-0-scene-replication/) e [MultiplayerSpawner](https://docs.godotengine.org/en/stable/classes/class_multiplayerspawner.html).
