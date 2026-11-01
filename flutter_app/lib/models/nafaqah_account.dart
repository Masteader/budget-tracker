/// Helper function to enforce Islamic compliance for wife expenses:
/// Wife personal allowance and wife reimbursable expenses must NEVER be linked
/// to a household account, ensuring the database triggers never debit household
/// funds for money paid by the wife (Rule 02 §3.2, §3.3).
library;

String? accountForNafaqahClass(String? nafaqahClass, String? accountId) =>
    (nafaqahClass == 'wife_personal' || nafaqahClass == 'wife_reimbursable')
        ? null
        : accountId;

