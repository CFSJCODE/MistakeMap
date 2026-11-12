# Questões pendentes — banco PostgreSQL

1. **Schema remoto:** qual projeto Supabase/branch é o ambiente canônico para reconciliar e quais migrations já foram aplicadas?
2. **Revisão humana:** o estudante pode confirmar, editar ou rejeitar evento? A correção deve criar novo evento ou atualizar versão?
3. **Auditoria:** quais campos são obrigatórios para revisão (motivo, evidência, timestamp, autor, classificação anterior)?
4. **Rastreabilidade de prática:** `source_attempt_ids` deve se tornar tabela relacional com FK? Como tratar exercício-fonte excluído ou inacessível?
5. **Bootstrap e deploy:** existe procedimento seguro para criar usuário/admin inicial sem credencial privilegiada no histórico?

As respostas podem alterar grants, RLS, triggers e dados; migrations aplicadas devem permanecer imutáveis. 🔴
