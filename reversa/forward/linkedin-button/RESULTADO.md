# Botão LinkedIn na tela Sobre

Data: 2026-10-01.

Implementado um componente Flutter no cartão de Cláudio Francisco, inspirado no HTML/Tailwind fornecido: ícone vetorial branco, corpo azul, ponta em diamante, expansão de 700 ms e nome revelado gradualmente. A área reservada mantém os elementos vizinhos estáveis. O foco pelo teclado também expande o botão; Enter, Espaço, clique e toque acionam o perfil. Layouts compactos/Android/iOS exibem o nome imediatamente. A preferência por movimento reduzido é respeitada.

O perfil usa a URL pública fornecida, sem o parâmetro pessoal isSelfProfile. A abertura mantém o aplicativo e usa uma nova aba na web ou destino externo nas demais plataformas. Falhas reportadas pelo lançador mostram um aviso no aplicativo. O plugin url_launcher já está instalado e registrado por Supabase; nenhuma dependência/configuração foi alterada.

## Arquivos da alteração

- appmistakemap/lib/about/linkedin_profile_button.dart
- appmistakemap/lib/about/external_profile.dart
- appmistakemap/lib/main.dart
- appmistakemap/test/linkedin_profile_button_test.dart
- appmistakemap/test/external_profile_test.dart

## Validação

- Flutter analyze --no-pub: sem problemas.
- Testes do componente: 6 aprovados (hover intermediário/reversão, clique, teclado/foco, semântica, movimento reduzido, 320 px com texto 2x).
- Testes do destino externo: 2 aprovados (URL do perfil, abertura externa/nova aba e resultado de falha).
- Testes existentes da tela Sobre em 320 px/texto 2x e 1440 px/texto 1.5x: 2 aprovados; duas prévias existentes ignoradas pelo filtro.
- Prévia recompilada em http://localhost:8765/.
- No Edge, o clique abriu uma nova aba com o título do perfil e a URL correta. A aba auxiliar foi fechada após o teste e a prévia foi mantida aberta.
- Capturas de antes, recolhido e expandido nesta pasta.

## Limite de validação

A abertura externa em Android/iOS não foi testada em dispositivo nesta etapa. Não houve publicação remota.
