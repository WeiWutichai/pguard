// Small display helpers shared by the guards list + detail modal.

/** Show only the last 4 of an account number in the list (the admin can open the detail modal for
 *  the full value the contract returns). PDPA-friendly at-a-glance display. */
export function maskAccount(account: string | null | undefined): string | null {
  if (!account) return null;
  const tail = account.slice(-4);
  return account.length <= 4 ? account : `••••${tail}`;
}

/** Avatar initials — first char of the first two words of the account-holder name (the only
 *  person-name field GuardProfile carries); falls back to the user-id prefix. */
export function initialsOf(name: string | null | undefined, userId: string): string {
  const trimmed = name?.trim();
  if (trimmed) {
    return trimmed
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part.charAt(0))
      .join("");
  }
  return userId.slice(0, 2).toUpperCase();
}
