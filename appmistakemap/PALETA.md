# Paleta azul do MistakeMap

A mesma paleta é compartilhada pelos layouts mobile e web em
`lib/theme/blue_palette.dart`. A identidade mantém Fluent UI, Liquid Glass,
tipografia e raios existentes. As referências GTA V são de cor, sem reproduzir
a interface do jogo.

| Referência | Índice | Aproximação Web RGB | Aplicação |
|---|---:|---|---|
| Midnight Blue | 141 | `#0A0C17` | Texto principal e início dos degradês escuros |
| Ultra Blue | 70 | `#0B9CF1` | Faixas e brilhos decorativos |
| Racing Blue | 73 | `#2354A1` | Títulos, botões, seleção e fim dos degradês escuros |
| Diamond Blue | 67 | `#D6E7F1` | Base clara do fundo e superfícies |

Fonte RGB: [RAGE Multiplayer — Vehicle Colors](https://wiki.rage.mp/wiki/Vehicle_Colors).
Os nomes de exibição do jogo e os nomes internos das tabelas diferem; os índices
identificam as referências solicitadas. A pintura metálica depende de material
e iluminação: os HEX são aproximações para interface, não uma reprodução física.

## Fundos e legibilidade

Diamond Blue foi adotado por oferecer fundo claro de baixa saturação. O fundo
passa por azul gelo `#F2F8FC` e névoa `#C6E4F8`; painéis usam Diamond e gelo.
Textos secundários usam `#456079`, sem transparência que reduza sua leitura.

Contraste sRGB sobre Diamond: Midnight **15,36:1**, Racing **5,80:1** e texto
secundário **5,17:1**. Branco sobre Racing tem **7,36:1**. O degradê escuro
Midnight → Racing admite texto branco em toda a extensão.

Ultra Blue sobre Diamond tem apenas **2,35:1**, e branco sobre Ultra **2,98:1**.
Por isso Ultra fica em ornamentos sem significado exclusivo, nunca como texto
pequeno ou como único contorno funcional. Cores de erro, alerta e sucesso
continuam semânticas, acompanhadas de rótulos e ícones.

## Proporções

Conteúdo até 1120px, textos longos até 720px, formulários até 640px, login até
440px, cartões de resumo até 300px e botão Sobre até 480px. A navegação tem
limite de 720px. Em telas estreitas os elementos quebram em linhas e podem
rolar, respeitando fonte ampliada e teclado.
