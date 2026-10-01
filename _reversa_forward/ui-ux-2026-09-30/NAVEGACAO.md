# Navegação — 30/09/2026

Implementada em `appmistakemap/lib/layout/navigation_shell.dart`, integrada em `main.dart`.

- Desktop: menu lateral de 224 pixels; destinos com ícone, rótulo, estado selecionado, hover e controles Fluent com foco por teclado. Sobre acessível no menu.
- Celular: quatro destinos principais e menu Mais para Sobre e Administração (apenas administradores). Rótulos curtos e tooltips com o destino completo. A barra ocupa seu próprio espaço e se recolhe quando o teclado aparece.
- Conteúdo preservado ao trocar de seção pelo IndexedStack; clicar novamente na seção atual não dispara nova consulta.
- O comando Ver no Mapa agora seleciona o mapa, corrigindo o destino anterior para exercícios.
- Voltar dentro do shell retorna ao início; Sobre continua como página com retorno. Altura da barra superior acompanha fonte ampliada.
- Painéis e cabeçalhos conservam as superfícies estáveis da implementação anterior; não há filtro de borda sobre o conteúdo.

Validação: quatro testes específicos do novo shell passaram; dois testes de navegação integrada para aluno/admin passaram; análise estática sem problemas. Suíte final: 93 aprovados, quatro ignorados de geração de prévias, quatro falhas remanescentes de recursos não implementados (lista/detalhe no desktop e dobradiça; métricas administrativas em duas larguras). Não foram removidas essas expectativas.

Prévias móveis e desktop atualizadas em `appmistakemap/test/previews/navegacao-{390,1280}-synthetic.png`, com dados sintéticos. Ambas inspecionadas. Teste de geração de prévias passou.

Versão atual compilada pelo Flutter em servidor exclusivamente local `http://localhost:8765/`; aberta no Edge e confirmada a navegação desktop e o carregamento da lista. O servidor anterior em 64634 foi preservado. Não houve publicação, alterações de dados ou autenticação automatizada.

Arquivos alterados: lib/main.dart, novo lib/layout/navigation_shell.dart, novo test/navigation_shell_test.dart, test/responsive_test.dart e prévias opcionais. Servidor local permanece ativo para visualização.
