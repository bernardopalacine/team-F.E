import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const { nome, email, nivel, planoId } = await req.json()

  // Cliente admin — só existe aqui, dentro da função, nunca no navegador
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // 1) Confere se quem está chamando é realmente um admin
  const authHeader = req.headers.get('Authorization')!
  const supabaseAuth = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )
  const { data: { user } } = await supabaseAuth.auth.getUser()
  const { data: perfil } = await supabaseAuth
    .from('profiles')
    .select('tipo')
    .eq('id', user?.id)
    .single()

  if (perfil?.tipo !== 'admin') {
    return new Response(JSON.stringify({ error: 'Apenas o admin pode cadastrar alunos' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // 2) Cria o usuário e já manda um e-mail de convite (define senha depois)
  const { data: novoUsuario, error: erroConvite } =
    await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
      data: { nome }
    })

  if (erroConvite) {
    return new Response(JSON.stringify({ error: erroConvite.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }

  // 3) Atualiza nível no perfil (o trigger já criou a linha em profiles)
  await supabaseAdmin
    .from('profiles')
    .update({ nivel })
    .eq('id', novoUsuario.user.id)

  // 4) Vincula o plano escolhido
  if (planoId) {
    await supabaseAdmin
      .from('assinaturas')
      .insert({ usuario_id: novoUsuario.user.id, plano_id: planoId, ativo: true })
  }

  return new Response(JSON.stringify({ sucesso: true, usuario: novoUsuario.user }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
