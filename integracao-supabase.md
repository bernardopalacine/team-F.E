# Team F.E. — Guia de integração com Supabase

## 1. Criar o projeto

1. Acesse [supabase.com](https://supabase.com) e crie um projeto novo.
2. Vá em **SQL Editor** → cole o conteúdo de `supabase-schema.sql` → **Run**.
3. Em **Authentication → Providers**, deixe **Email** ativado (login com e-mail/senha).
4. Em **Project Settings → API**, copie a **URL** e a **anon key** — você vai usar no front-end.

## 2. Conectar o front-end

Instale o cliente:

```bash
npm install @supabase/supabase-js
```

Crie um arquivo `supabaseClient.js`:

```javascript
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://SEU-PROJETO.supabase.co'
const supabaseKey = 'SUA-ANON-KEY'

export const supabase = createClient(supabaseUrl, supabaseKey)
```

## 3. Cadastro e login (tela de Login)

```javascript
// Criar conta
async function criarConta(email, senha, nome) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password: senha,
    options: { data: { nome } } // preenche o nome do perfil automaticamente
  })
  return { data, error }
}

// Login
async function entrar(email, senha) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password: senha
  })
  return { data, error }
}

// Esqueci minha senha
async function recuperarSenha(email) {
  return await supabase.auth.resetPasswordForEmail(email)
}
```

## 4. Buscar a agenda da semana (tela Agenda)

```javascript
async function buscarTurmas() {
  const { data, error } = await supabase
    .from('turmas')
    .select('*')
    .order('dia_semana')
    .order('hora_inicio')
  return data
}

// Vagas ocupadas de uma turma numa data específica
async function vagasOcupadas(turmaId, data) {
  const { count } = await supabase
    .from('agendamentos')
    .select('*', { count: 'exact', head: true })
    .eq('turma_id', turmaId)
    .eq('data', data)
    .eq('status', 'confirmada')
  return count
}
```

## 5. Agendar e cancelar aula (botão "Agendar" dos cards)

Toda a regra de negócio (vaga + limite do plano) já está dentro da função SQL `agendar_aula`, então o front-end só precisa chamar:

```javascript
async function agendarAula(turmaId, data) {
  const { data: agendamento, error } = await supabase
    .rpc('agendar_aula', { p_turma_id: turmaId, p_data: data })

  if (error) {
    // error.message vai trazer: "Turma lotada", "Limite semanal atingido" etc.
    alert(error.message)
    return
  }
  return agendamento
}

async function cancelarAula(agendamentoId) {
  return await supabase.rpc('cancelar_aula', { p_agendamento_id: agendamentoId })
}
```

## 6. Dashboard do aluno

```javascript
async function minhasProximasAulas() {
  const { data } = await supabase
    .from('agendamentos')
    .select('*, turmas(*)')
    .eq('status', 'confirmada')
    .gte('data', new Date().toISOString().slice(0, 10))
    .order('data')
  return data
}

async function meuPlanoAtual() {
  const { data } = await supabase
    .from('assinaturas')
    .select('*, planos(*)')
    .eq('ativo', true)
    .single()
  return data
}
```

## 7. Notificações

```javascript
async function minhasNotificacoes() {
  const { data } = await supabase
    .from('notificacoes')
    .select('*')
    .order('criado_em', { ascending: false })
  return data
}

async function marcarComoLida(notificacaoId) {
  return await supabase
    .from('notificacoes')
    .update({ lida: true })
    .eq('id', notificacaoId)
}
```

## 8. Área do professor/admin

O `profiles.tipo` precisa ser `'admin'` para o Prof. Edu — dá pra ajustar direto no **Table Editor** do Supabase depois que ele criar a conta.

```javascript
// Alunos agendados numa turma/data (tela "Agenda & Vagas")
async function alunosDaTurma(turmaId, data) {
  const { data: lista } = await supabase
    .from('agendamentos')
    .select('*, profiles(nome), status')
    .eq('turma_id', turmaId)
    .eq('data', data)
  return lista
}

// Cadastrar aluno manualmente (via convite por e-mail, feito no painel do Supabase
// ou por uma Edge Function usando a service_role key — nunca exponha essa key no front-end)

// Marcar presença
async function marcarPresenca(agendamentoId, presente) {
  return await supabase
    .from('presencas')
    .upsert({ agendamento_id: agendamentoId, presente, marcado_em: new Date() })
}

// Enviar notificação em massa para uma turma
async function enviarNotificacaoParaTurma(turmaId, data, tipo, mensagem) {
  const alunos = await alunosDaTurma(turmaId, data)
  const linhas = alunos.map(a => ({ usuario_id: a.usuario_id, tipo, mensagem }))
  return await supabase.from('notificacoes').insert(linhas)
}
```

## 9. Lembretes automáticos (opcional)

Para o lembrete "sua aula é amanhã" e para marcar aulas antigas como `concluida` automaticamente, use um **Supabase Edge Function agendada (cron)**:

1. Crie uma função em **Edge Functions** que roda uma vez por dia.
2. Ela seleciona os agendamentos de amanhã e insere uma notificação do tipo `lembrete` para cada aluno.
3. Ela também atualiza para `status = 'concluida'` os agendamentos cuja data já passou e que ainda estavam `confirmada`.
4. Agende a execução em **Database → Cron Jobs** (extensão `pg_cron`), por exemplo todo dia às 08:00.

## Ordem sugerida para conectar tudo no design

1. Rodar o schema → testar login/cadastro.
2. Ligar a tela de Agenda ao `buscarTurmas()` + `agendarAula()`.
3. Ligar o Dashboard ao `minhasProximasAulas()` e `meuPlanoAtual()`.
4. Ligar Notificações.
5. Por último, a área Admin (mais tabelas envolvidas).
