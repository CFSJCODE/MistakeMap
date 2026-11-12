-- Reconstrução pública da versão já aplicada em 2026-09-28.
-- A original contém uma lista privada de e-mails para promover administradores.
-- Aqui novos perfis recebem 'user'; perfis existentes são preservados.
-- Esta diferença é intencional: consulte ../../README.md.
-- NÃO reaplicar no projeto existente nem marcar essa versão como reverted.

-- 1. Adiciona coluna role à tabela profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'user'
  CHECK (role IN ('admin', 'user'));

-- 2. Função para criar perfil automático ao cadastrar novo usuário
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, education_level, role)
  VALUES (new.id, 'ensino_medio', 'user')
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

-- 3. Trigger que dispara após cada novo usuário em auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 4. Atualiza role para admins que já existam no banco
-- Bootstrap pessoal omitido da cópia pública. Provisione administradores
-- separadamente, por um canal privilegiado e após verificar a identidade.

-- 5. Admins podem ver todos os perfis
DROP POLICY IF EXISTS "admins_view_all_profiles" ON public.profiles;
CREATE POLICY "admins_view_all_profiles"
  ON public.profiles FOR SELECT
  USING (
    id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- 6. Remove policy antiga que bloqueava admins de ver outros perfis
DROP POLICY IF EXISTS "profiles_owner_all" ON public.profiles;

-- 7. Usuário pode gerenciar próprio perfil (exceto role)
CREATE POLICY "user_manage_own_profile"
  ON public.profiles FOR ALL
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    AND role = (SELECT role FROM public.profiles WHERE id = auth.uid())
  );

-- 8. Admin pode atualizar role de qualquer usuário
CREATE POLICY "admin_update_any_profile"
  ON public.profiles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );
