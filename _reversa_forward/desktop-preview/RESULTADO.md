# Restauração da prévia local

Data: 30/09/2026.

Objetivo: restaurar o acesso ao MistakeMap em http://localhost:8765/ após ERR_CONNECTION_REFUSED.

Diagnóstico confirmado: não havia listener na porta 8765 nem processo Flutter/Dart do servidor web ativo. A causa do encerramento anterior não foi confirmada.

Resultado: servidor Flutter reiniciado no pacote appmistakemap, sem atualização de dependências, restrito a 127.0.0.1:8765. Verificação HTTP retornou 200; a tela Início carregou no Edge com a sessão existente. Nenhuma credencial foi inserida e nenhum arquivo do aplicativo foi alterado.

Limitação: duas tentativas de iniciar um processo independente e oculto foram bloqueadas pela revisão automática, com a mensagem genérica blocked by policy, sem justificativa específica. A restauração usou uma sessão de terminal normal. Não se afirma execução independente desse terminal.

Artefatos: INICIAR-PREVIA.cmd permite ao usuário iniciar a mesma prévia em uma janela de terminal própria, que deve permanecer aberta. Captura visual em ../ui-motion/preview-restaurada.jpg. O script usa exclusivamente o Flutter instalado, o pacote existente e o acesso local; não instala serviços nem cria agendamento.

Validação: disponibilidade da porta e resposta HTTP conferidas depois de iniciar; Home conferida no navegador. O script foi conferido por leitura; não foi executado para evitar uma segunda instância na mesma porta. Não foram repetidos testes de código porque nenhum código foi alterado.

O hook global de sincronização do resumo não foi verificado.
