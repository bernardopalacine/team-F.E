-- =====================================================================
-- TEAM F.E. — Migration: Fila de espera
-- Rode este arquivo no SQL Editor do seu projeto Supabase, DEPOIS de já
-- ter rodado o supabase-schema.sql original.
-- =====================================================================

-- =====================================================================
-- 1. TABELA: fila_espera
-- =====================================================================
create table public.fila_espera (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.profiles(id) on delete cascade,
  turma_id int not null references public.turmas(id),
  data date not null,
  criado_em timestamptz not null default now(),
  unique (usuario_id, turma_id, data)
);

alter table public.fila_espera enable row level security;

create policy "ver propria fila" on public.fila_espera
  for select using (usuario_id = auth.uid() or public.is_admin());
create policy "entrar na propria fila" on public.fila_espera
  for insert with check (usuario_id = auth.uid());
create policy "sair da propria fila" on public.fila_espera
  for delete using (usuario_id = auth.uid() or public.is_admin());

-- =====================================================================
-- 2. FUNÇÃO: entrar na fila de espera de uma turma lotada
-- =====================================================================
create or replace function public.entrar_fila_espera(p_turma_id int, p_data date)
returns public.fila_espera
language plpgsql
security definer
as $$
declare
  v_usuario uuid := auth.uid();
  v_turma public.turmas;
  v_ocupadas int;
  v_novo public.fila_espera;
begin
  if v_usuario is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_turma from public.turmas where id = p_turma_id;
  if not found then
    raise exception 'Turma não encontrada';
  end if;

  select count(*) into v_ocupadas
  from public.agendamentos
  where turma_id = p_turma_id and data = p_data and status = 'confirmada';

  if v_ocupadas < v_turma.capacidade_max then
    raise exception 'Ainda há vagas nesta turma, agende direto pela agenda';
  end if;

  if exists (
    select 1 from public.agendamentos
    where usuario_id = v_usuario and turma_id = p_turma_id and data = p_data and status = 'confirmada'
  ) then
    raise exception 'Você já está agendado nesta aula';
  end if;

  insert into public.fila_espera (usuario_id, turma_id, data)
  values (v_usuario, p_turma_id, p_data)
  on conflict (usuario_id, turma_id, data) do nothing
  returning * into v_novo;

  if v_novo.id is null then
    raise exception 'Você já está na fila de espera desta aula';
  end if;

  return v_novo;
end;
$$;

-- =====================================================================
-- 3. cancelar_aula agora promove automaticamente o primeiro da fila
-- =====================================================================
create or replace function public.cancelar_aula(p_agendamento_id uuid)
returns public.agendamentos
language plpgsql
security definer
as $$
declare
  v_usuario uuid := auth.uid();
  v_agendamento public.agendamentos;
  v_proximo_fila public.fila_espera;
  v_turma public.turmas;
begin
  select * into v_agendamento from public.agendamentos where id = p_agendamento_id;

  if not found or v_agendamento.usuario_id <> v_usuario then
    raise exception 'Agendamento não encontrado';
  end if;

  update public.agendamentos set status = 'cancelada'
  where id = p_agendamento_id
  returning * into v_agendamento;

  insert into public.notificacoes (usuario_id, tipo, mensagem)
  values (v_usuario, 'cancelamento', 'Sua aula foi cancelada.');

  -- promove o primeiro da fila de espera, se houver
  select * into v_proximo_fila
  from public.fila_espera
  where turma_id = v_agendamento.turma_id and data = v_agendamento.data
  order by criado_em asc
  limit 1;

  if found then
    select * into v_turma from public.turmas where id = v_agendamento.turma_id;

    insert into public.agendamentos (usuario_id, turma_id, data, status)
    values (v_proximo_fila.usuario_id, v_proximo_fila.turma_id, v_proximo_fila.data, 'confirmada');

    delete from public.fila_espera where id = v_proximo_fila.id;

    insert into public.notificacoes (usuario_id, tipo, mensagem)
    values (v_proximo_fila.usuario_id, 'aula_confirmada',
      'Uma vaga abriu na turma ' || v_turma.nivel || ' em ' || to_char(v_agendamento.data,'DD/MM') || ' e você foi confirmado automaticamente.');
  end if;

  return v_agendamento;
end;
$$;

-- =====================================================================
-- Fim da migration.
-- =====================================================================
