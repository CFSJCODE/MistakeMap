-- Reconstrução pública da versão já aplicada em 2026-09-29, recuperada de
-- supabase_migrations.schema_migrations. As instruções abaixo são as mesmas
-- registradas no projeto; só este cabeçalho foi acrescentado.
-- NÃO reaplicar no projeto existente nem marcar essa versão como reverted.

-- Migration: Fix infinite recursion in profiles RLS policies
-- Uses SECURITY DEFINER is_admin function to prevent recursive policy evaluations

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
  );
$$;

DROP POLICY IF EXISTS admins_view_all_profiles ON public.profiles;

CREATE POLICY admins_view_all_profiles ON public.profiles
FOR SELECT USING (
  id = auth.uid() OR public.is_admin()
);

DROP POLICY IF EXISTS admin_update_any_profile ON public.profiles;

CREATE POLICY admin_update_any_profile ON public.profiles
FOR UPDATE USING (
  public.is_admin()
);
