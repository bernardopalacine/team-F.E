-- =====================================================================
-- TEAM F.E. — Migration: Turma Feminina por nível (Iniciante/Intermediária/Avançada)
-- Rode este arquivo no SQL Editor do seu projeto Supabase, DEPOIS de já
-- ter rodado o supabase-schema.sql original (e, se aplicável,
-- supabase-schema-fila-espera.sql).
--
-- Antes só existia 1 turma feminina genérica (sexta, 15:30–16:30).
-- Agora a sexta passa a ter 3 turmas femininas, uma por nível, no mesmo
-- padrão de horário de segunda a quinta.
-- =====================================================================

-- 1. Nova coluna: identifica se a turma é a versão feminina do nível
alter table public.turmas
  add column if not exists publico text not null default 'geral' check (publico in ('geral', 'feminina'));

-- 2. Converte a turma feminina genérica existente (sexta, 15:30–16:30)
--    na versão feminina do nível Intermediária (mesmo horário)
update public.turmas
  set nivel = 'intermediaria', publico = 'feminina'
  where dia_semana = 'sexta' and nivel = 'feminina';

-- 3. Adiciona as turmas femininas de sexta que ainda não existem
insert into public.turmas (dia_semana, hora_inicio, hora_fim, nivel, capacidade_max, publico)
select 'sexta', '14:30'::time, '15:30'::time, 'iniciante', 8, 'feminina'
where not exists (
  select 1 from public.turmas
  where dia_semana = 'sexta' and nivel = 'iniciante' and publico = 'feminina'
);

insert into public.turmas (dia_semana, hora_inicio, hora_fim, nivel, capacidade_max, publico)
select 'sexta', '15:30'::time, '16:30'::time, 'intermediaria', 8, 'feminina'
where not exists (
  select 1 from public.turmas
  where dia_semana = 'sexta' and nivel = 'intermediaria' and publico = 'feminina'
);

insert into public.turmas (dia_semana, hora_inicio, hora_fim, nivel, capacidade_max, publico)
select 'sexta', '16:30'::time, '17:30'::time, 'avancada', 8, 'feminina'
where not exists (
  select 1 from public.turmas
  where dia_semana = 'sexta' and nivel = 'avancada' and publico = 'feminina'
);

-- =====================================================================
-- Fim da migration.
-- =====================================================================
