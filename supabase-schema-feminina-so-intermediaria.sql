-- Rode DEPOIS de supabase-schema-feminina-por-niveis.sql
-- Mantém só a turma de sexta Intermediária como feminina; Iniciante e
-- Avançada de sexta voltam a ser turmas gerais (mistas).
update public.turmas
  set publico = 'geral'
  where dia_semana = 'sexta' and publico = 'feminina' and nivel in ('iniciante', 'avancada');
