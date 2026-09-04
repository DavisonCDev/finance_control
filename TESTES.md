# Bateria de Testes — Finance Control

## Preparação

1. Inicie o backend:
   ```bash
   cd api
   node server.js
   ```
2. Inicie o app Flutter:
   ```bash
   cd app
   flutter run -d windows
   ```

---

## 1. Cadastro e login

- [ ] Abrir o app mostra a tela de splash por 2 segundos
- [ ] Criar uma conta com nome, e-mail e senha
- [ ] Fazer login com a conta criada
- [ ] Fechar e abrir o app mantém o usuário logado (splash → tela inicial)
- [ ] Clicar em sair faz logout e volta para a tela de login

---

## 2. Contas

- [ ] Acessar a aba Contas
- [ ] Criar uma conta corrente com saldo inicial de R$ 5.000,00
- [ ] Criar uma conta de dinheiro com saldo de R$ 500,00
- [ ] Verificar se o saldo total na tela inicial está correto

---

## 3. Categorias e transações

- [ ] Acessar a aba Transações
- [ ] Criar uma despesa de Alimentação no valor de R$ 150,00
- [ ] Verificar se o saldo da conta diminuiu em R$ 150,00
- [ ] Criar uma receita de Salário no valor de R$ 5.000,00
- [ ] Verificar se o saldo da conta aumentou em R$ 5.000,00
- [ ] Verificar se as transações aparecem corretamente com acentuação (Alimentação, Saúde, Educação)

---

## 4. Cartões de crédito

- [ ] Acessar a aba Cartões
- [ ] Cadastrar um cartão de crédito (nome, bandeira, limite, dia de fechamento e vencimento)
- [ ] Verificar se o cartão aparece na lista

---

## 5. Metas financeiras

- [ ] Acessar a aba Metas
- [ ] Criar uma meta chamada "Viagem" com valor alvo de R$ 10.000,00
- [ ] Verificar se a barra de progresso inicia em 0%
- [ ] Verificar se o percentual é exibido corretamente

---

## 6. Orçamentos

- [ ] Acessar a aba Orçamento
- [ ] Criar um orçamento de R$ 1.000,00 para a categoria Alimentação
- [ ] Cadastrar uma despesa de Alimentação de R$ 300,00
- [ ] Acessar a aba Relatório
- [ ] Verificar se o gráfico de pizza aparece
- [ ] Verificar se a barra de progresso de Alimentação está em 30%

---

## 7. Relatórios

- [ ] Acessar a aba Relatório
- [ ] Verificar se o resumo de receitas e despesas do mês está correto
- [ ] Verificar se o gráfico de pizza aparece quando há orçamentos
- [ ] Verificar se a barra de progresso muda de cor quando o gasto ultrapassa 100%

---

## 8. Navegação e UX

- [ ] A navegação por abas funciona corretamente
- [ ] A tela de splash aparece ao abrir o app
- [ ] O logout remove o acesso e volta para a tela de login
- [ ] As categorias com acentos são exibidas corretamente

---

## Resultado esperado

Marcar cada item com `[x]` conforme for testado. Se algum item falhar, anotar o erro e reportar.
