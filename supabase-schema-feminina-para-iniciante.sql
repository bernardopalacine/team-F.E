-- Rode DEPOIS das migrations anteriores.
-- A turma feminina exclusiva de sexta (15:30–16:30) passa de Intermediária para Iniciante.
update public.turmas
  set nivel = 'iniciante'
  where dia_semana = 'sexta' and publico = 'feminina';
