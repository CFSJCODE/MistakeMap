# Questões pendentes — CI/CD e distribuição

1. **Entrega acadêmica:** basta navegação funcional em Flutter durante a demonstração ou é necessário entregar APK/instalador?
2. **Android:** se necessário, o artefato será APK para teste, AAB para loja ou ambos? Quem gerencia a chave de assinatura?
3. **Windows:** qual formato/canal é esperado (MSIX, ZIP portátil, instalador ou execução local)?
4. **Distribuição:** onde artefatos serão armazenados e por quanto tempo? A publicação será pública, privada ou apenas demonstrada em aula?
5. **Worker arquivado:** o job Rust deve permanecer como gate, ser marcado como manutenção histórica ou ser removido do CI?

Não implementar assinatura ou publicação sem decisão de formato e administração segura das chaves. 🔴
