// =====================================================================
// TEAM F.E. — Integração Supabase da Área Administrativa (Prof. Edu)
// Importe o `supabase` já configurado (ver supabaseClient.js do guia anterior)
// import { supabase } from './supabaseClient'
// =====================================================================


// =====================================================================
// 1. AGENDA & CONTROLE DE VAGAS
// =====================================================================

// Lista as turmas com quantas vagas já foram ocupadas numa data específica
async function listarTurmasComVagas(data) {
  const { data: turmas, error } = await supabase
    .from('turmas')
    .select('*')
    .order('dia_semana')
    .order('hora_inicio')

  if (error) throw error

  // busca, pra cada turma, quantas confirmações existem nessa data
  const comVagas = await Promise.all(
    turmas.map(async (turma) => {
      const { count } = await supabase
        .from('agendamentos')
        .select('*', { count: 'exact', head: true })
        .eq('turma_id', turma.id)
        .eq('data', data)
        .eq('status', 'confirmada')

      return { ...turma, vagas_ocupadas: count ?? 0 }
    })
  )

  return comVagas
}

// Lista os alunos agendados numa turma + data (linha "Aluno / Plano / Status" da tela)
async function listarAlunosDaTurma(turmaId, data) {
  const { data: lista, error } = await supabase
    .from('agendamentos')
    .select(`
      id,
      status,
      profiles ( nome ),
      usuario_id
    `)
    .eq('turma_id', turmaId)
    .eq('data', data)

  if (error) throw error

  // busca o plano de cada aluno separadamente (join simples)
  const comPlano = await Promise.all(
    lista.map(async (item) => {
      const { data: assinatura } = await supabase
        .from('assinaturas')
        .select('planos(nome)')
        .eq('usuario_id', item.usuario_id)
        .eq('ativo', true)
        .single()

      return { ...item, plano: assinatura?.planos?.nome ?? '—' }
    })
  )

  return comPlano
}

// Botão "✓" da tabela — admin confirma manualmente um agendamento pendente
async function confirmarAgendamento(agendamentoId) {
  return await supabase
    .from('agendamentos')
    .update({ status: 'confirmada' })
    .eq('id', agendamentoId)
}

// Botão "✕" da tabela — admin cancela e notifica o aluno
async function cancelarAgendamentoAdmin(agendamentoId) {
  const { data: agendamento } = await supabase
    .from('agendamentos')
    .update({ status: 'cancelada' })
    .eq('id', agendamentoId)
    .select('usuario_id')
    .single()

  if (agendamento) {
    await supabase.from('notificacoes').insert({
      usuario_id: agendamento.usuario_id,
      tipo: 'cancelamento',
      mensagem: 'Sua aula foi cancelada pelo professor.'
    })
  }
}

// Botão "+ Editar horário" — cria uma nova turma na grade
async function criarTurma({ dia_semana, hora_inicio, hora_fim, nivel, capacidade_max }) {
  return await supabase.from('turmas').insert({
    dia_semana, hora_inicio, hora_fim, nivel, capacidade_max
  })
}

// Editar uma turma existente (ex: mudar horário ou capacidade)
async function editarTurma(turmaId, campos) {
  const { data: antiga } = await supabase.from('turmas').select('*').eq('id', turmaId).single()

  const { error } = await supabase.from('turmas').update(campos).eq('id', turmaId)
  if (error) throw error

  // se o horário mudou, avisa quem já tinha aula agendada nessa turma
  if (campos.hora_inicio && campos.hora_inicio !== antiga.hora_inicio) {
    await notificarMudancaDeHorario(turmaId)
  }
}

async function excluirTurma(turmaId) {
  return await supabase.from('turmas').delete().eq('id', turmaId)
}


// =====================================================================
// 2. ALUNOS
// =====================================================================

// Lista todos os alunos com nível e plano atual (tela "Todos os alunos")
async function listarAlunos() {
  const { data: alunos, error } = await supabase
    .from('profiles')
    .select('id, nome, nivel')
    .eq('tipo', 'aluno')
    .order('nome')

  if (error) throw error

  const comPlano = await Promise.all(
    alunos.map(async (aluno) => {
      const { data: assinatura } = await supabase
        .from('assinaturas')
        .select('ativo, planos(nome)')
        .eq('usuario_id', aluno.id)
        .eq('ativo', true)
        .single()

      return { ...aluno, plano: assinatura?.planos?.nome ?? 'Sem plano' }
    })
  )

  return comPlano
}

// Editar dados de um aluno (nome, nível)
async function editarAluno(alunoId, campos) {
  return await supabase.from('profiles').update(campos).eq('id', alunoId)
}

// ⚠️ Cadastrar um aluno novo (criar login) exige a service_role key, que NUNCA
// deve rodar no front-end. Isso precisa ser uma Edge Function no servidor.
// Veja o arquivo `edge-function-convidar-aluno.md` com o código pronto.
async function cadastrarAluno({ nome, email, nivel, planoId }) {
  const { data, error } = await supabase.functions.invoke('convidar-aluno', {
    body: { nome, email, nivel, planoId }
  })
  if (error) throw error
  return data
}


// =====================================================================
// 3. PLANOS (assinaturas dos alunos)
// =====================================================================

// Lista todos os alunos com plano atual e quantas aulas já usaram na semana
async function listarAssinaturas() {
  const { data: assinaturas, error } = await supabase
    .from('assinaturas')
    .select('usuario_id, profiles(nome), planos(nome, aulas_por_semana)')
    .eq('ativo', true)

  if (error) throw error

  const inicioSemana = new Date()
  inicioSemana.setDate(inicioSemana.getDate() - inicioSemana.getDay() + 1) // segunda-feira
  const dataInicio = inicioSemana.toISOString().slice(0, 10)

  const comUso = await Promise.all(
    assinaturas.map(async (a) => {
      const { count } = await supabase
        .from('agendamentos')
        .select('*', { count: 'exact', head: true })
        .eq('usuario_id', a.usuario_id)
        .eq('status', 'confirmada')
        .gte('data', dataInicio)

      return { ...a, usadas_na_semana: count ?? 0 }
    })
  )

  return comUso
}

// Botão "Alterar" — troca o plano ativo de um aluno
async function alterarPlanoDoAluno(usuarioId, novoPlanoId) {
  // desativa a assinatura atual
  await supabase
    .from('assinaturas')
    .update({ ativo: false })
    .eq('usuario_id', usuarioId)
    .eq('ativo', true)

  // cria a nova assinatura ativa
  const { error } = await supabase
    .from('assinaturas')
    .insert({ usuario_id: usuarioId, plano_id: novoPlanoId, ativo: true })

  if (error) throw error

  await supabase.from('notificacoes').insert({
    usuario_id: usuarioId,
    tipo: 'nova_turma', // reaproveitando o tipo mais próximo do enum atual
    mensagem: 'Seu plano foi atualizado pelo professor.'
  })
}


// =====================================================================
// 4. NOTIFICAÇÕES (tela "Enviar notificações")
// =====================================================================

// Envia a mesma mensagem para todos os alunos agendados numa turma/data
async function enviarNotificacaoParaTurma(turmaId, data, tipo, mensagem) {
  const alunos = await listarAlunosDaTurma(turmaId, data)
  if (alunos.length === 0) return

  const linhas = alunos.map((a) => ({
    usuario_id: a.usuario_id,
    tipo,
    mensagem
  }))

  return await supabase.from('notificacoes').insert(linhas)
}

// Envia para todos os alunos de um nível (ex: toda a Turma Avançada, em qualquer dia)
async function enviarNotificacaoParaNivel(nivel, tipo, mensagem) {
  const { data: turmasDoNivel } = await supabase
    .from('turmas')
    .select('id')
    .eq('nivel', nivel)

  const { data: agendamentos } = await supabase
    .from('agendamentos')
    .select('usuario_id')
    .in('turma_id', turmasDoNivel.map((t) => t.id))
    .eq('status', 'confirmada')

  const usuariosUnicos = [...new Set(agendamentos.map((a) => a.usuario_id))]
  const linhas = usuariosUnicos.map((usuario_id) => ({ usuario_id, tipo, mensagem }))

  return await supabase.from('notificacoes').insert(linhas)
}

// Usado internamente quando um horário de turma é editado
async function notificarMudancaDeHorario(turmaId) {
  const { data: agendamentosFuturos } = await supabase
    .from('agendamentos')
    .select('usuario_id')
    .eq('turma_id', turmaId)
    .eq('status', 'confirmada')
    .gte('data', new Date().toISOString().slice(0, 10))

  const linhas = agendamentosFuturos.map((a) => ({
    usuario_id: a.usuario_id,
    tipo: 'alteracao_horario',
    mensagem: 'O horário da sua turma foi alterado. Confira a nova agenda.'
  }))

  if (linhas.length > 0) {
    await supabase.from('notificacoes').insert(linhas)
  }
}


// =====================================================================
// 5. LISTA DE PRESENÇA
// =====================================================================

// Carrega a lista de presença de uma turma/data (junta agendamento + presença)
async function listarPresenca(turmaId, data) {
  const { data: lista, error } = await supabase
    .from('agendamentos')
    .select('id, profiles(nome), presencas(presente)')
    .eq('turma_id', turmaId)
    .eq('data', data)
    .eq('status', 'confirmada')

  if (error) throw error
  return lista
}

// Botão "Salvar presença" — marca presente/ausente por agendamento
async function salvarPresenca(agendamentoId, presente) {
  return await supabase
    .from('presencas')
    .upsert({
      agendamento_id: agendamentoId,
      presente,
      marcado_em: new Date().toISOString()
    })
}
