# Questões pendentes — Edge Functions e serviço de IA

1. **Fontes de prática:** o backend pode reutilizar apenas exercícios do dono ou haverá catálogo compartilhado? Como autorizar acesso e registrar proveniência?
2. **Ausência de fonte:** a geração deve falhar sem exercício elegível ou oferecer outro modo explicitamente separado?
3. **Revisão humana:** quais transições são permitidas (`pending`→`confirmed/rejected`) e como registrar edição, autor, timestamp e motivo?
4. **Prioridade:** o fator `importance` deve participar da fórmula e qual normalização deve ser aplicada?
5. **Segredo do cron:** confirmar que o segredo em produção está em armazenamento seguro/Vault e pode ser rotacionado sem indisponibilidade.

Não expor gabaritos nem confiar em IDs de fonte enviados pelo cliente sem validar propriedade. 🔴
