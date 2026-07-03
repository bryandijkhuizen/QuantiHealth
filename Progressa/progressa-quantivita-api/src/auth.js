export async function authenticatedUser(supabaseAdmin, token) {
  if (!token) return null;

  try {
    const { data, error } = await supabaseAdmin.auth.getUser(token);
    if (error || !data?.user?.id) return null;
    return data.user;
  } catch {
    return null;
  }
}
