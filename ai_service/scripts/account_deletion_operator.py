"""
Schedules, or cancels, the ordinary 30-day account deletion for someone who cannot sign in.

    python scripts/account_deletion_operator.py --email ADDRESS --inquiry-id REF --verified-by HANDLE
    python scripts/account_deletion_operator.py ... --choice HOUSEHOLD_ID:delete --execute
    python scripts/account_deletion_operator.py ... --choice HOUSEHOLD_ID:transfer:USER_ID --execute
    python scripts/account_deletion_operator.py ... --cancel --execute

A dry run unless --execute is given. Verify the person first, as
docs/runbooks/account-deletion-purge.md says. Run by hand with the service key; the API process
never imports this and there is no HTTP route to it.

It prints and logs request ids, household ids, the inquiry reference and the operator's handle:
never the address, a user id, a name or a raw error, which can quote any of those.
"""

from __future__ import annotations

import argparse
import logging
import os
import re
import sys
from typing import Any, Dict, List, Optional, Sequence

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv  # noqa: E402

from postgrest_compat import db_error_fields  # noqa: E402
from supabase_client import get_client  # noqa: E402

logger = logging.getLogger("account_deletion_operator")

_UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
_HANDLE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
_REFERENCE_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

# What the database says when it refuses. Anything else is a failed run.
_REFUSALS = {
    "inquiry_invalid",
    "operator_handle_invalid",
    "account_not_found",
    "household_choice_missing",
    "household_choice_invalid",
    "successor_invalid",
    "successor_pending_deletion",
    "deletion_in_progress",
}


def _handle(value: str) -> str:
    if not _HANDLE_RE.match(value):
        raise argparse.ArgumentTypeError("letters, digits, dot, dash and underscore only: a handle, not an address")
    return value


def _reference(value: str) -> str:
    if not _REFERENCE_RE.match(value):
        raise argparse.ArgumentTypeError("the reference or id of the inquiry")
    return value


def _choice(value: str) -> Dict[str, str]:
    parts = value.split(":")
    if not _UUID_RE.match(parts[0]):
        raise argparse.ArgumentTypeError("HOUSEHOLD_ID:delete or HOUSEHOLD_ID:transfer:USER_ID")
    if len(parts) == 2 and parts[1] == "delete":
        return {"household_id": parts[0], "action": "delete"}
    if len(parts) == 3 and parts[1] == "transfer" and _UUID_RE.match(parts[2]):
        return {"household_id": parts[0], "action": "transfer", "successor_user_id": parts[2]}
    raise argparse.ArgumentTypeError("HOUSEHOLD_ID:delete or HOUSEHOLD_ID:transfer:USER_ID")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Schedule or cancel the 30-day deletion for someone who cannot sign in.")
    parser.add_argument("--email", required=True, help="The address on the account, which you verified by reply.")
    parser.add_argument("--inquiry-id", required=True, type=_reference, help="The form request's reference or id.")
    parser.add_argument("--verified-by", required=True, type=_handle, help="Your handle, not an address.")
    parser.add_argument("--choice", action="append", default=[], type=_choice,
                        help="HOUSEHOLD_ID:delete or HOUSEHOLD_ID:transfer:USER_ID, for each household that needs one.")
    parser.add_argument("--locale", choices=["ar", "en", "ur"], help="Language of the emails. Default: the form's.")
    parser.add_argument("--cancel", action="store_true", help="Cancel the open request instead.")
    parser.add_argument("--execute", action="store_true", help="Make the change. Without it, only print what would happen.")
    return parser


def _rpc(client: Any, name: str, params: Dict[str, Any]) -> Any:
    return client.rpc(name, params).execute().data


def _print_preview(preview: Dict[str, Any]) -> None:
    print("Inquiry: valid")
    print("Account: an account has this address")
    print(f"The address typed in the form matches it: {'yes' if preview.get('inquiry_email_matches') else 'no'}")
    print("Verify through the address on the account either way (see the runbook).")
    for household in preview.get("households") or []:
        print(
            f"Household {household['household_id']}: {household['position']}, "
            f"{household['other_members']} other member(s), "
            f"{'needs --choice' if household['needs_choice'] else 'no choice needed'}"
        )
    if not preview.get("households"):
        print("Households: none")


def _cancel(client: Any, args: argparse.Namespace, preview: Dict[str, Any]) -> int:
    deletion = preview.get("deletion") or {}
    if deletion.get("status") in (None, "none"):
        print("Nothing to cancel: this account has no open deletion.")
        return 0
    if not deletion.get("can_cancel"):
        print(f"Cannot cancel: the deletion is {deletion.get('status')}, and its data may already be gone.")
        return 2
    if not args.execute:
        print(f"DRY RUN: would cancel the deletion set for {deletion.get('scheduled_for')}. Add --execute to do it.")
        return 0
    result = _rpc(client, "cancel_account_deletion_by_operator", {
        "p_user_id": preview["user_id"],
        "p_inquiry_reference": args.inquiry_id,
        "p_verified_by": args.verified_by,
    }) or {}
    logger.info("Operator cancelled a deletion: inquiry=%s verified_by=%s cancelled=%s",
                args.inquiry_id, args.verified_by, result.get("cancelled"))
    print(f"Cancelled: {result.get('cancelled')}")
    return 0


def _schedule(client: Any, args: argparse.Namespace, preview: Dict[str, Any]) -> int:
    deletion = preview.get("deletion") or {}
    if deletion.get("status") not in (None, "none"):
        print(f"This account already has a deletion: {deletion.get('status')}, set for {deletion.get('scheduled_for')}. "
              "Nothing to do.")
        return 0

    chosen = {choice["household_id"].lower() for choice in args.choice}
    missing: List[str] = [
        h["household_id"] for h in preview.get("households") or []
        if h.get("needs_choice") and h["household_id"].lower() not in chosen
    ]
    if missing:
        print("Refused: this person administers a household with other members, and the choice is theirs. "
              "Ask them, then pass --choice for each:")
        for household_id in missing:
            print(f"  --choice {household_id}:delete  or  --choice {household_id}:transfer:USER_ID")
        return 2

    if not args.execute:
        print("DRY RUN: would schedule the deletion for 30 days from now.")
        for choice in args.choice:
            print(f"  Household {choice['household_id']}: {choice['action']}")
        print("Add --execute to do it.")
        return 0

    result = _rpc(client, "schedule_account_deletion_by_operator", {
        "p_user_id": preview["user_id"],
        "p_inquiry_reference": args.inquiry_id,
        "p_verified_by": args.verified_by,
        "p_household_choices": args.choice,
        "p_locale": args.locale,
    }) or {}
    logger.info("Operator scheduled a deletion: request=%s inquiry=%s verified_by=%s already_requested=%s",
                result.get("request_id"), args.inquiry_id, args.verified_by, result.get("already_requested"))
    print(f"Scheduled: request {result.get('request_id')}, for {result.get('scheduled_for')}.")
    return 0


def main(argv: Optional[Sequence[str]] = None, client: Any = None) -> int:
    args = _parser().parse_args(argv)
    if client is None:
        load_dotenv()
        logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
        # httpx logs every URL at INFO.
        logging.getLogger("httpx").setLevel(logging.WARNING)
        logging.getLogger("httpcore").setLevel(logging.WARNING)
        try:
            client = get_client()
        except Exception as exc:  # noqa: BLE001 - logged by type only
            print(f"Could not create the Supabase client ({type(exc).__name__}).")
            return 1

    try:
        preview = _rpc(client, "get_account_deletion_operator_preview",
                       {"p_email": args.email, "p_inquiry_reference": args.inquiry_id}) or {}
        if not preview.get("inquiry_valid"):
            print("Refused: no account deletion request has that reference.")
            return 2
        if not preview.get("account_found"):
            print("No account matches this address. Nothing was changed.")
            return 2
        _print_preview(preview)
        return _cancel(client, args, preview) if args.cancel else _schedule(client, args, preview)
    except Exception as exc:  # noqa: BLE001 - raw errors can quote personal data
        hint = db_error_fields(exc)["hint"]
        if hint in _REFUSALS:
            print(f"Refused by the database: {hint}. Nothing was changed.")
            logger.info("Operator action refused: inquiry=%s verified_by=%s code=%s", args.inquiry_id, args.verified_by, hint)
            return 2
        print(f"Failed ({type(exc).__name__}). Nothing is known to have changed: check the status before retrying.")
        logger.error("Operator action failed: inquiry=%s verified_by=%s type=%s",
                     args.inquiry_id, args.verified_by, type(exc).__name__)
        return 1


if __name__ == "__main__":
    sys.exit(main())
