# Edge Function: `convidar-aluno`

Essa função roda no **servidor** do Supabase (não no navegador), porque criar um
usuário novo exige a `service_role key` — uma chave com poder total que **nunca**
pode ser exposta no front-end.

## 1. Criar a função

No terminal, dentro do seu projeto (com a [Supabase CLI](https://supabase.com/docs/guides/cli) instalada):

```bash
supabase functions new convidar-aluno
```

Isso cria `supabase/functions/convidar-aluno/index.ts`. Substitua o conteúdo por:

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
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
      status: 403
    })
  }

  // 2) Cria o usuário e já manda um e-mail de convite (define senha depois)
  const { data: novoUsuario, error: erroConvite } =
    await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
      data: { nome }
    })

  if (erroConvite) {
    return new Response(JSON.stringify({ error: erroConvite.message }), { status: 400 })
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
    status: 200
  })
})
```

## 2. Publicar a função

```bash
supabase functions deploy convidar-aluno
```

## 3. Chamar do front-end (já está pronto em `admin-supabase.js`)

```javascript
const { data, error } = await supabase.functions.invoke('convidar-aluno', {
  body: { nome, email, nivel, planoId }
})
```

O aluno recebe um e-mail do Supabase pra criar a senha e já entra no sistema com
nível e plano configurados.
