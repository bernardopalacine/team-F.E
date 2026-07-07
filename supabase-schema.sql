-- =====================================================================
-- TEAM F.E. — Schema Supabase (Postgres)
-- Rode este arquivo inteiro no SQL Editor do seu projeto Supabase.
-- =====================================================================

-- Extensão usada para gerar UUIDs
create extension if not exists "pgcrypto";

-- =====================================================================
-- 1. PERFIS (estende a tabela auth.users, que o Supabase já cria)
-- =====================================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  telefone text,
  tipo text not null default 'aluno' check (tipo in ('aluno','admin')),
  nivel text check (nivel in ('iniciante','intermediaria','avancada','feminina')),
  criado_em timestamptz not null default now()
);

-- Cria o perfil automaticamente quando alguém se cadastra
create function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nome)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', 'Aluno'));
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =====================================================================
-- 2. PLANOS
-- =====================================================================
create table public.planos (
  id serial primary key,
  nome text not null unique,
  aulas_por_semana int not null,
  descricao text
);

insert into public.planos (nome, aulas_por_semana, descricao) values
  ('Bronze', 1, '1 aula por semana'),
  ('Prata', 2, '2 aulas por semana'),
  ('Ouro', 3, '3 aulas por semana'),
  ('Premium', 4, '4 aulas por semana'),
  ('Passe Livre', 5, '5 aulas por semana');

-- =====================================================================
-- 3. ASSINATURAS (o plano contratado por cada aluno)
-- =====================================================================
create table public.assinaturas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.profiles(id) on delete cascade,
  plano_id int not null references public.planos(id),
  ativo boolean not null default true,
  data_inicio date not null default current_date,
  criado_em timestamptz not null default now()
);

-- Garante que cada aluno tenha só uma assinatura ativa por vez
create unique index one_active_subscription_per_user
  on public.assinaturas (usuario_id)
  where ativo;

-- =====================================================================
-- 4. TURMAS (a grade fixa semanal)
-- =====================================================================
create table public.turmas (
  id serial primary key,
  dia_semana text not null check (dia_semana in ('segunda','terca','quarta','quinta','sexta')),
  hora_inicio time not null,
  hora_fim time not null,
  nivel text not null check (nivel in ('iniciante','intermediaria','avancada','feminina')),
  professor text not null default 'Edu',
  capacidade_max int not null default 8
);

-- Grade padrão: segunda a quinta (Iniciante/Intermediária/Avançada) + sexta (Feminina)
insert into public.turmas (dia_semana, hora_inicio, hora_fim, nivel, capacidade_max)
select dia, '14:30'::time, '15:30'::time, 'iniciante', 10
from unnest(array['segunda','terca','quarta','quinta']) as dia
union all
select dia, '15:30'::time, '16:30'::time, 'intermediaria', 8
from unnest(array['segunda','terca','quarta','quinta']) as dia
union all
select dia, '16:30'::time, '17:30'::time, 'avancada', 8
from unnest(array['segunda','terca','quarta','quinta']) as dia
union all
select 'sexta', '15:30'::time, '16:30'::time, 'feminina', 8;

-- =====================================================================
-- 5. AGENDAMENTOS
-- =====================================================================
create table public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.profiles(id) on delete cascade,
  turma_id int not null references public.turmas(id),
  data date not null,
  status text not null default 'confirmada' check (status in ('confirmada','concluida','cancelada')),
  criado_em timestamptz not null default now(),
  unique (usuario_id, turma_id, data) -- evita agendar a mesma aula duas vezes
);

-- =====================================================================
-- 6. NOTIFICAÇÕES
-- =====================================================================
create table public.notificacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.profiles(id) on delete cascade,
  tipo text not null check (tipo in (
    'aula_confirmada','lembrete','alteracao_horario',
    'cancelamento','limite_plano','nova_turma'
  )),
  mensagem text not null,
  lida boolean not null default false,
  criado_em timestamptz not null default now()
);

-- =====================================================================
-- 7. PRESENÇA
-- =====================================================================
create table public.presencas (
  agendamento_id uuid primary key references public.agendamentos(id) on delete cascade,
  presente boolean not null default false,
  marcado_em timestamptz
);

-- =====================================================================
-- 8. FUNÇÃO PRINCIPAL: agendar uma aula com todas as regras de negócio
--    (vaga disponível + limite semanal do plano)
-- =====================================================================
create or replace function public.agendar_aula(p_turma_id int, p_data date)
returns public.agendamentos
language plpgsql
security definer
as $$
declare
  v_usuario uuid := auth.uid();
  v_turma public.turmas;
  v_ocupadas int;
  v_limite_semana int;
  v_usadas_semana int;
  v_novo public.agendamentos;
begin
  if v_usuario is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_turma from public.turmas where id = p_turma_id;
  if not found then
    raise exception 'Turma não encontrada';
  end if;

  -- 1) checa vaga na turma, na data escolhida
  select count(*) into v_ocupadas
  from public.agendamentos
  where turma_id = p_turma_id and data = p_data and status = 'confirmada';

  if v_ocupadas >= v_turma.capacidade_max then
    raise exception 'Turma lotada para esta data';
  end if;

  -- 2) checa limite semanal do plano do aluno
  select p.aulas_por_semana into v_limite_semana
  from public.assinaturas a
  join public.planos p on p.id = a.plano_id
  where a.usuario_id = v_usuario and a.ativo
  limit 1;

  if v_limite_semana is null then
    raise exception 'Aluno sem plano ativo';
  end if;

  select count(*) into v_usadas_semana
  from public.agendamentos
  where usuario_id = v_usuario
    and status = 'confirmada'
    and date_trunc('week', data) = date_trunc('week', p_data);

  if v_usadas_semana >= v_limite_semana then
    raise exception 'Limite semanal do plano atingido';
  end if;

  -- 3) tudo certo: agenda
  insert into public.agendamentos (usuario_id, turma_id, data)
  values (v_usuario, p_turma_id, p_data)
  returning * into v_novo;

  insert into public.notificacoes (usuario_id, tipo, mensagem)
  values (v_usuario, 'aula_confirmada',
    'Sua aula de ' || v_turma.nivel || ' em ' || to_char(p_data,'DD/MM') || ' foi confirmada.');

  -- 4) avisa se está próximo do limite do plano
  if v_usadas_semana + 1 >= v_limite_semana then
    insert into public.notificacoes (usuario_id, tipo, mensagem)
    values (v_usuario, 'limite_plano', 'Você atingiu o limite semanal do seu plano.');
  end if;

  return v_novo;
end;
$$;

-- =====================================================================
-- 9. FUNÇÃO: cancelar uma aula
-- =====================================================================
create or replace function public.cancelar_aula(p_agendamento_id uuid)
returns public.agendamentos
language plpgsql
security definer
as $$
declare
  v_usuario uuid := auth.uid();
  v_agendamento public.agendamentos;
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

  return v_agendamento;
end;
$$;

-- =====================================================================
-- 10. ROW LEVEL SECURITY (cada aluno só vê/edita os próprios dados)
-- =====================================================================
alter table public.profiles enable row level security;
alter table public.assinaturas enable row level security;
alter table public.agendamentos enable row level security;
alter table public.notificacoes enable row level security;
alter table public.presencas enable row level security;
alter table public.turmas enable row level security;
alter table public.planos enable row level security;

-- Função utilitária: o usuário logado é admin?
create or replace function public.is_admin()
returns boolean language sql stable as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and tipo = 'admin'
  );
$$;

-- Turmas e planos: todo mundo autenticado pode ler
create policy "turmas visiveis para autenticados" on public.turmas
  for select using (auth.role() = 'authenticated');
create policy "planos visiveis para autenticados" on public.planos
  for select using (auth.role() = 'authenticated');
create policy "admin gerencia turmas" on public.turmas
  for all using (public.is_admin());

-- Perfis: cada um vê/edita o próprio; admin vê todos
create policy "ver proprio perfil" on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy "editar proprio perfil" on public.profiles
  for update using (id = auth.uid());

-- Assinaturas: aluno vê a própria; admin vê e edita todas
create policy "ver propria assinatura" on public.assinaturas
  for select using (usuario_id = auth.uid() or public.is_admin());
create policy "admin edita assinaturas" on public.assinaturas
  for all using (public.is_admin());

-- Agendamentos: aluno vê/cria os próprios; admin vê todos
create policy "ver proprios agendamentos" on public.agendamentos
  for select using (usuario_id = auth.uid() or public.is_admin());
create policy "admin gerencia agendamentos" on public.agendamentos
  for all using (public.is_admin());

-- Notificações: cada aluno só vê as suas
create policy "ver proprias notificacoes" on public.notificacoes
  for select using (usuario_id = auth.uid() or public.is_admin());
create policy "marcar propria notificacao como lida" on public.notificacoes
  for update using (usuario_id = auth.uid());
create policy "admin envia notificacoes" on public.notificacoes
  for insert with check (public.is_admin());

-- Presenças: só admin marca; aluno pode ver a própria
create policy "admin controla presenca" on public.presencas
  for all using (public.is_admin());
create policy "aluno ve propria presenca" on public.presencas
  for select using (
    exists (
      select 1 from public.agendamentos ag
      where ag.id = agendamento_id and ag.usuario_id = auth.uid()
    )
  );

-- =====================================================================
-- Fim do schema.
-- =====================================================================
