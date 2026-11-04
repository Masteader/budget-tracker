"""Invariants 1 to 7 in spec Section 3.3 (task B3)."""

import hashlib
import sqlite3
from datetime import timedelta

import pytest
from state_support import (
    OWNER,
    TWO_PLATFORMS,
    Bench,
    Clock,
    live_config,
    make_video,
    shipped_config,
    tap,
)

from core.state import (
    ActionRefused,
    OwnerTapRequired,
    PostOutcome,
    PostStatus,
    ReelState,
    RefusalReason,
    StateStore,
    TapAction,
    TapOutcome,
    VerifiedOwnerTap,
    post_idempotency_key,
)

S = ReelState


@pytest.fixture
def bench(tmp_path):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        yield Bench(store, live_config(tmp_path), make_video(tmp_path), clock)


def assert_refused(result, reason):
    assert result.outcome == TapOutcome.REFUSED
    assert result.reason == reason


def approvals_of(bench, reel, action=TapAction.APPROVE):
    return [row for row in bench.store.approvals_for(reel.reel_id) if row.action == action]


# --- 1. The only path to approved -------------------------------------------------------


def test_an_owner_tap_approves_and_is_recorded_with_its_binding(bench):
    reel = bench.awaiting()

    result = bench.store.apply_tap(tap(reel, TapAction.APPROVE, callback="cb-1"), bench.config)

    assert result.outcome == TapOutcome.APPLIED
    assert bench.refresh(reel).state == S.APPROVED
    row = bench.store.approvals_for(reel.reel_id)[0]
    assert (row.revision, row.mp4_sha256, row.telegram_user_id, row.callback_query_id) == (
        reel.revision,
        reel.mp4_sha256,
        OWNER,
        "cb-1",
    )


def test_plain_transition_cannot_approve(bench):
    reel = bench.awaiting()
    with pytest.raises(OwnerTapRequired):
        bench.store.transition(reel.reel_id, S.AWAITING_APPROVAL, S.APPROVED)
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


def test_the_database_refuses_approved_without_an_approval_row(bench):
    reel = bench.awaiting()
    with pytest.raises(sqlite3.IntegrityError, match="owner tap"):
        bench.store._db.execute(
            "UPDATE reels SET state = 'approved' WHERE reel_id = ?", (reel.reel_id,)
        )


def test_the_database_refuses_approved_on_a_row_for_another_revision_or_file(bench):
    reel = bench.awaiting()
    db = bench.store._db
    insert = (
        "INSERT INTO approvals (reel_id, revision, mp4_sha256, telegram_user_id, action, "
        "callback_query_id, at) VALUES (?, ?, ?, 1, ?, ?, 'x')"
    )
    db.execute(insert, (reel.reel_id, reel.revision + 1, reel.mp4_sha256, "approve", "a"))
    db.execute(insert, (reel.reel_id, reel.revision, "other-hash", "approve", "b"))
    db.execute(insert, (reel.reel_id, reel.revision, reel.mp4_sha256, "reject", "c"))
    with pytest.raises(sqlite3.IntegrityError, match="owner tap"):
        db.execute("UPDATE reels SET state = 'approved' WHERE reel_id = ?", (reel.reel_id,))


@pytest.mark.parametrize(
    "imitation",
    [
        lambda reel: {"reel_id": reel.reel_id, "revision": reel.revision, "action": "approve"},
        lambda reel: type(
            "Tap",
            (),
            {
                "reel_id": reel.reel_id,
                "revision": reel.revision,
                "action": TapAction.APPROVE,
                "telegram_user_id": OWNER,
                "callback_query_id": "cb",
                "platform": None,
            },
        )(),
    ],
    ids=["dict", "look-alike object"],
)
def test_only_a_real_tap_object_is_accepted(bench, imitation):
    reel = bench.awaiting()
    with pytest.raises(TypeError):
        bench.store.apply_tap(imitation(reel), bench.config)
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


def test_a_subclass_of_the_tap_is_not_accepted(bench):
    class Forged(VerifiedOwnerTap):
        pass

    reel = bench.awaiting()
    forged = Forged(reel.reel_id, reel.revision, TapAction.APPROVE, OWNER, "cb")
    with pytest.raises(TypeError):
        bench.store.apply_tap(forged, bench.config)


@pytest.mark.parametrize(
    "fields",
    [
        {"revision": 0},
        {"revision": True},
        {"revision": "1"},
        {"telegram_user_id": 0},
        {"telegram_user_id": -5},
        {"telegram_user_id": "777"},
        {"callback_query_id": ""},
        {"action": "approve"},
        {"platform": "instagram"},  # Approve has no platform
        {"action": TapAction.POSTED},  # Posted needs one
        {"action": TapAction.RETRY, "platform": "myspace"},
    ],
)
def test_a_malformed_tap_cannot_be_built(fields):
    values = {
        "reel_id": "r1",
        "revision": 1,
        "action": TapAction.APPROVE,
        "telegram_user_id": OWNER,
        "callback_query_id": "cb",
        "platform": None,
    }
    with pytest.raises((TypeError, ValueError)):
        VerifiedOwnerTap(**(values | fields))


def test_a_tap_cannot_be_altered_after_it_is_built(bench):
    reel = bench.awaiting()
    built = tap(reel, TapAction.REJECT)
    with pytest.raises(AttributeError):
        built.action = TapAction.APPROVE


# --- 2. Bound to reel, revision and file hash -------------------------------------------


def test_a_changed_file_blocks_the_approval(bench):
    reel = bench.awaiting()
    bench.video.write_bytes(b"swapped before the tap")

    result = bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config)

    assert_refused(result, RefusalReason.HASH_CHANGED)
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL
    assert approvals_of(bench, reel) == []


def test_a_missing_file_blocks_the_approval(bench):
    reel = bench.awaiting()
    bench.video.unlink()

    result = bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config)

    assert_refused(result, RefusalReason.HASH_CHANGED)


def test_a_file_changed_after_approval_goes_back_to_awaiting_before_any_send(bench):
    reel = bench.publishing()
    bench.video.write_bytes(b"swapped after approval")

    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)

    assert refused.value.reason == RefusalReason.HASH_CHANGED
    fresh = bench.refresh(reel)
    assert fresh.state == S.AWAITING_APPROVAL
    assert fresh.scheduled_for is None
    assert {post.status for post in bench.store.posts_for(reel.reel_id)} == {PostStatus.PENDING}


def test_a_file_changed_while_scheduled_goes_back_before_publishing(bench):
    reel = bench.scheduled()
    bench.video.write_bytes(b"swapped while waiting")

    with pytest.raises(ActionRefused) as refused:
        bench.store.start_publishing(reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config)

    assert refused.value.reason == RefusalReason.HASH_CHANGED
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL
    assert bench.store.posts_for(reel.reel_id) == []


def test_an_old_approval_does_not_carry_over_after_a_send_back(bench):
    reel = bench.publishing()
    original = bench.video.read_bytes()
    bench.video.write_bytes(b"swapped")
    with pytest.raises(ActionRefused):
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.video.write_bytes(original)  # the file comes back, and the owner still has to tap

    with pytest.raises(ActionRefused):
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert (
        bench.store.start_publishing(reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config)
        is False
    )
    assert bench.store.schedule_reel(reel.reel_id, reel.revision, bench.clock()) is False
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL

    result = bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config)
    assert result.applied
    assert bench.refresh(reel).state == S.APPROVED


def test_nothing_can_rewrite_the_bound_file_after_approval(bench):
    reel = bench.approved()
    with pytest.raises(sqlite3.IntegrityError):
        bench.store._db.execute(
            "UPDATE reels SET mp4_sha256 = 'other' WHERE reel_id = ?", (reel.reel_id,)
        )
    with pytest.raises(sqlite3.IntegrityError):
        bench.store._db.execute(
            "UPDATE reels SET mp4_path = 'other.mp4' WHERE reel_id = ?", (reel.reel_id,)
        )


def test_the_stored_hash_comes_from_the_file_itself(bench):
    reel = bench.rendered()
    assert reel.mp4_sha256 == hashlib.sha256(bench.video.read_bytes()).hexdigest()


def test_rendering_a_missing_file_is_refused(bench, tmp_path):
    reel = bench.voiced()
    with pytest.raises(ActionRefused) as refused:
        bench.store.record_rendered(
            reel.reel_id, reel.revision, tmp_path / "gone.mp4", "hash", bench.config
        )
    assert refused.value.reason == RefusalReason.HASH_CHANGED
    assert bench.refresh(reel).state == S.VOICED


# --- 3. A stale button ------------------------------------------------------------------


@pytest.mark.parametrize(
    "action", [TapAction.APPROVE, TapAction.REGENERATE, TapAction.REJECT, TapAction.REVOICE]
)
def test_a_stale_button_does_nothing_but_say_so(bench, action):
    reel = bench.awaiting()
    stale = tap(reel, action, revision=reel.revision + 1)

    result = bench.store.apply_tap(stale, bench.config)

    assert result.outcome == TapOutcome.STALE
    assert bench.refresh(reel) == reel
    assert bench.store.approvals_for(reel.reel_id) == []


def test_a_tap_on_an_unknown_reel_is_refused(bench):
    forged = VerifiedOwnerTap("no-such-reel", 1, TapAction.APPROVE, OWNER, "cb-x")
    assert_refused(bench.store.apply_tap(forged, bench.config), RefusalReason.UNKNOWN_REEL)


def test_a_refused_tap_leaves_an_audit_event(bench):
    reel = bench.awaiting()
    bench.video.write_bytes(b"swapped")
    bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config)
    refused = [e for e in bench.store.events_for(reel.reel_id) if e.kind == "tap_refused"]
    assert [event.detail for event in refused] == [RefusalReason.HASH_CHANGED]


# --- Double taps ------------------------------------------------------------------------


@pytest.mark.parametrize("action", [TapAction.APPROVE, TapAction.REGENERATE, TapAction.REJECT])
def test_the_same_callback_delivered_twice_applies_once(bench, action):
    reel = bench.awaiting()
    first = tap(reel, action, callback="cb-same")

    assert bench.store.apply_tap(first, bench.config).outcome == TapOutcome.APPLIED
    state_after_first = bench.refresh(reel)
    assert bench.store.apply_tap(first, bench.config).outcome == TapOutcome.DUPLICATE

    assert bench.refresh(reel) == state_after_first
    assert len(bench.store.approvals_for(reel.reel_id)) == 1


def test_a_second_tap_with_a_new_id_also_applies_once(bench):
    # A real double tap on a Telegram button gets two different ids.
    reel = bench.awaiting()
    assert bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config).applied

    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config),
        RefusalReason.NOT_AWAITING,
    )

    assert len(approvals_of(bench, reel)) == 1


@pytest.mark.parametrize(
    "state",
    [S.DRAFT, S.RENDERED, S.APPROVED, S.REJECTED, S.EXPIRED, S.POSTED, S.TEST_DELIVERED],
)
@pytest.mark.parametrize("action", [TapAction.APPROVE, TapAction.REGENERATE, TapAction.REJECT])
def test_owner_buttons_work_only_while_awaiting(bench, state, action):
    reel = bench.walk_to(state)
    result = bench.store.apply_tap(tap(reel, action), bench.config)
    assert_refused(result, RefusalReason.NOT_AWAITING)
    assert bench.refresh(reel) == reel


# --- 4. Regeneration ---------------------------------------------------------------------


def test_regenerating_invalidates_every_older_approval(bench):
    reel = bench.publishing()
    original = bench.video.read_bytes()
    bench.video.write_bytes(b"swapped")
    with pytest.raises(ActionRefused):
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.video.write_bytes(original)
    assert approvals_of(bench, reel), "the old approval row stays in the record"

    regenerate = bench.store.apply_tap(tap(reel, TapAction.REGENERATE), bench.config)
    assert regenerate.applied
    assert bench.store.finish_regeneration(reel.reel_id, reel.revision)
    assert bench.store.record_voiced(reel.reel_id, reel.revision + 1, "S0")
    # The same bytes, so the same hash: only the revision tells the two approvals apart.
    assert bench.store.record_rendered(
        reel.reel_id, reel.revision + 1, bench.video, "content-hash", bench.config
    )
    assert bench.store.offer_for_approval(reel.reel_id, reel.revision + 1, bench.config)

    old_button = tap(reel, TapAction.APPROVE, revision=reel.revision)
    assert bench.store.apply_tap(old_button, bench.config).outcome == TapOutcome.STALE
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL
    with pytest.raises(sqlite3.IntegrityError, match="owner tap"):
        bench.store._db.execute(
            "UPDATE reels SET state = 'approved' WHERE reel_id = ?", (reel.reel_id,)
        )


def test_the_old_revision_cannot_publish_during_regeneration(bench):
    reel = bench.awaiting()
    assert bench.store.apply_tap(tap(reel, TapAction.REGENERATE), bench.config).applied
    with pytest.raises(ActionRefused):
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert bench.store.schedule_reel(reel.reel_id, reel.revision, bench.clock()) is False


def test_regeneration_stops_at_the_limit(tmp_path):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        config = live_config(tmp_path)
        bench = Bench(store, config, make_video(tmp_path), clock)
        limit = config.approval.max_regenerations
        reel = bench.awaiting()
        for _ in range(limit):
            assert store.apply_tap(tap(reel, TapAction.REGENERATE), config).applied
            assert store.finish_regeneration(reel.reel_id, reel.revision)
            reel = bench.refresh(reel)
            assert store.record_voiced(reel.reel_id, reel.revision, "S0")
            assert store.record_rendered(reel.reel_id, reel.revision, bench.video, "h", config)
            assert store.offer_for_approval(reel.reel_id, reel.revision, config)
            reel = bench.refresh(reel)

        result = store.apply_tap(tap(reel, TapAction.REGENERATE), config)

        assert_refused(result, RefusalReason.LIMIT_REACHED)
        assert bench.refresh(reel).state == S.AWAITING_APPROVAL
        assert bench.refresh(reel).regenerations == limit


def test_a_regeneration_is_marked_as_a_new_script(bench):
    reel = bench.awaiting()
    assert bench.store.apply_tap(tap(reel, TapAction.REGENERATE), bench.config).applied
    assert bench.refresh(reel).regenerate_kind == "script"
    assert bench.refresh(reel).regenerations == 1


# --- 5. Terminal states are covered by test_state_machine. Taps on them are refused above.
# --- 6. F0 audio ------------------------------------------------------------------------


def test_f0_audio_cannot_be_approved(bench):
    reel = bench.awaiting(voice_tier="F0")
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config),
        RefusalReason.F0_AUDIO,
    )
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL
    assert approvals_of(bench, reel) == []


def test_f0_audio_may_be_approved_only_if_the_owner_allows_it(tmp_path):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        config = live_config(tmp_path, allow_public_on_f0=True)
        bench = Bench(store, config, make_video(tmp_path), clock)
        reel = bench.awaiting(voice_tier="F0")
        assert store.apply_tap(tap(reel, TapAction.APPROVE), config).applied


def test_f0_audio_is_refused_again_at_publishing_if_the_setting_is_turned_back(tmp_path):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        allowing = live_config(tmp_path, allow_public_on_f0=True)
        bench = Bench(store, allowing, make_video(tmp_path), clock)
        reel = bench.awaiting(voice_tier="F0")
        assert store.apply_tap(tap(reel, TapAction.APPROVE), allowing).applied
        assert store.schedule_reel(reel.reel_id, reel.revision, clock())

        with pytest.raises(ActionRefused) as refused:
            store.start_publishing(
                reel.reel_id, reel.revision, TWO_PLATFORMS, live_config(tmp_path)
            )

        assert refused.value.reason == RefusalReason.F0_AUDIO


def test_a_reel_with_no_recorded_audio_tier_cannot_be_voiced(bench):
    reel = bench.new_reel()
    with pytest.raises(ValueError, match="voice tier"):
        bench.store.record_voiced(reel.reel_id, reel.revision, "S1")


def test_re_voice_makes_a_new_revision_marked_as_voice_only(bench):
    reel = bench.awaiting(voice_tier="F0")

    assert bench.store.apply_tap(tap(reel, TapAction.REVOICE), bench.config).applied

    assert bench.refresh(reel).state == S.REGENERATING
    assert bench.refresh(reel).regenerate_kind == "voice"
    assert bench.store.finish_regeneration(reel.reel_id, reel.revision)
    fresh = bench.refresh(reel)
    assert (fresh.state, fresh.revision, fresh.voice_tier) == (S.DRAFT, reel.revision + 1, None)


def test_re_voice_does_not_use_up_the_script_regenerations(bench):
    reel = bench.awaiting(voice_tier="F0")
    assert bench.store.apply_tap(tap(reel, TapAction.REVOICE), bench.config).applied
    assert bench.refresh(reel).regenerations == 0


def test_re_voice_is_refused_on_paid_audio(bench):
    reel = bench.awaiting(voice_tier="S0")
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.REVOICE), bench.config),
        RefusalReason.NOT_F0,
    )


# --- 7. Test reels and the brand gate ---------------------------------------------------


def test_a_test_reel_is_never_approved_even_with_a_complete_brand(bench):
    reel = bench.rendered(is_test=True)
    with pytest.raises(ActionRefused) as refused:
        bench.store.offer_for_approval(reel.reel_id, reel.revision, bench.config)
    assert refused.value.reason == RefusalReason.TEST_REEL
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config),
        RefusalReason.NOT_AWAITING,
    )
    assert bench.refresh(reel).state == S.RENDERED


def test_the_database_keeps_a_test_reel_away_from_approval(bench):
    reel = bench.rendered(is_test=True)
    with pytest.raises(sqlite3.IntegrityError):
        bench.store._db.execute(
            "UPDATE reels SET state = 'awaiting_approval' WHERE reel_id = ?", (reel.reel_id,)
        )
    with pytest.raises(sqlite3.IntegrityError):
        bench.store._db.execute("UPDATE reels SET is_test = 0 WHERE reel_id = ?", (reel.reel_id,))


def test_a_real_reel_cannot_be_delivered_as_a_test(bench):
    reel = bench.rendered()
    with pytest.raises(ActionRefused) as refused:
        bench.store.mark_test_delivered(reel.reel_id, reel.revision)
    assert refused.value.reason == RefusalReason.NOT_TEST_REEL
    assert bench.refresh(reel).state == S.RENDERED


def test_a_test_reel_still_renders_in_the_shipped_test_mode(bench):
    reel = bench.voiced(is_test=True)
    assert bench.store.record_rendered(
        reel.reel_id, reel.revision, bench.video, "h", shipped_config()
    )
    assert bench.refresh(reel).state == S.RENDERED


def test_a_real_reel_cannot_render_while_the_gate_fails(bench):
    reel = bench.voiced()
    with pytest.raises(ActionRefused) as refused:
        bench.store.record_rendered(reel.reel_id, reel.revision, bench.video, "h", shipped_config())
    assert refused.value.reason == RefusalReason.BRAND_GATE
    assert bench.refresh(reel).state == S.VOICED


def test_a_real_reel_cannot_be_offered_while_the_gate_fails(bench):
    reel = bench.rendered()
    with pytest.raises(ActionRefused) as refused:
        bench.store.offer_for_approval(reel.reel_id, reel.revision, shipped_config())
    assert refused.value.reason == RefusalReason.BRAND_GATE
    assert bench.refresh(reel).state == S.RENDERED


def test_the_callback_handler_re_checks_the_gate_at_the_tap(bench):
    reel = bench.awaiting()
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.APPROVE), shipped_config()),
        RefusalReason.BRAND_GATE,
    )
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


def test_requeue_re_checks_the_gate(bench):
    reel = bench.walk_to(S.EXPIRED)
    with pytest.raises(ActionRefused) as refused:
        bench.store.requeue(reel.reel_id, shipped_config())
    assert refused.value.reason == RefusalReason.BRAND_GATE
    assert bench.refresh(reel).state == S.EXPIRED


def test_the_publisher_re_checks_the_gate_when_publishing_starts(bench):
    reel = bench.scheduled()
    with pytest.raises(ActionRefused) as refused:
        bench.store.start_publishing(reel.reel_id, reel.revision, TWO_PLATFORMS, shipped_config())
    assert refused.value.reason == RefusalReason.BRAND_GATE
    assert bench.refresh(reel).state == S.SCHEDULED


def test_the_publisher_re_checks_the_gate_before_each_send(bench):
    reel = bench.publishing()
    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], shipped_config())
    assert refused.value.reason == RefusalReason.BRAND_GATE
    assert {post.status for post in bench.store.posts_for(reel.reel_id)} == {PostStatus.PENDING}


# --- Publishing pre-checks ----------------------------------------------------------------


def test_pausing_holds_publishing_at_both_steps(bench):
    scheduled = bench.scheduled()
    publishing = bench.publishing()
    bench.store.set_paused(True)
    assert bench.store.is_paused() is True

    with pytest.raises(ActionRefused) as refused:
        bench.store.start_publishing(
            scheduled.reel_id, scheduled.revision, TWO_PLATFORMS, bench.config
        )
    assert refused.value.reason == RefusalReason.PAUSED
    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(publishing.reel_id, TWO_PLATFORMS[0], bench.config)
    assert refused.value.reason == RefusalReason.PAUSED

    bench.store.set_paused(False)
    assert bench.store.begin_post(publishing.reel_id, TWO_PLATFORMS[0], bench.config)


@pytest.mark.parametrize(
    "state",
    [S.DRAFT, S.RENDERED, S.AWAITING_APPROVAL, S.APPROVED, S.SCHEDULED, S.REJECTED, S.POSTED],
)
def test_a_post_can_begin_only_while_publishing(bench, state):
    reel = bench.walk_to(state)
    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert refused.value.reason == RefusalReason.NOT_PUBLISHING


def test_a_claim_carries_what_the_adapter_needs(bench):
    reel = bench.publishing()
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert claim.mp4_path == bench.video
    assert claim.mp4_sha256 == reel.mp4_sha256
    assert claim.idempotency_key == post_idempotency_key(reel.reel_id, TWO_PLATFORMS[0])
    assert claim.attempt == 1


def test_the_idempotency_key_is_the_spec_formula():
    expected = hashlib.sha256(b"r1instagram").hexdigest()
    assert post_idempotency_key("r1", "instagram") == expected


def test_a_second_begin_on_the_same_platform_is_refused(bench):
    reel = bench.publishing()
    bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert refused.value.reason == RefusalReason.NOT_PENDING


def test_a_platform_that_was_not_targeted_cannot_be_posted(bench):
    reel = bench.publishing(TWO_PLATFORMS[:1])
    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[1], bench.config)
    assert refused.value.reason == RefusalReason.NOT_PENDING


@pytest.mark.parametrize("platforms", [(), ("myspace",), ("instagram", "instagram")])
def test_bad_target_lists_are_refused(bench, platforms):
    reel = bench.scheduled()
    with pytest.raises(ValueError, match="platforms"):
        bench.store.start_publishing(reel.reel_id, reel.revision, platforms, bench.config)
    assert bench.refresh(reel).state == S.SCHEDULED


def test_each_send_counts_an_attempt_and_records_the_remote_id(bench):
    reel = bench.publishing(TWO_PLATFORMS[:1])
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)

    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="abc") is True

    post = bench.store.posts_for(reel.reel_id)[0]
    assert (post.status, post.remote_id, post.attempts) == (PostStatus.POSTED, "abc", 1)
    assert post.posted_at == bench.clock()
    assert bench.refresh(reel).state == S.POSTED


@pytest.mark.parametrize("remote_id", [None, "", "   "])
def test_success_with_no_remote_id_counts_as_an_unclear_answer(bench, remote_id):
    reel = bench.publishing()
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)

    bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id=remote_id)

    post = bench.store.posts_for(reel.reel_id)[0]
    assert post.status == PostStatus.UNKNOWN_OUTCOME
    assert bench.refresh(reel).state == S.NEEDS_ATTENTION


def test_a_definite_rejection_is_failed_and_an_unclear_answer_is_unknown(bench):
    reel = bench.publishing()
    first = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(first, PostOutcome.FAILED)
    assert bench.store.posts_for(reel.reel_id)[0].status == PostStatus.FAILED
    assert bench.refresh(reel).state == S.NEEDS_ATTENTION

    other = bench.publishing()
    second = bench.store.begin_post(other.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(second, PostOutcome.UNKNOWN)
    assert bench.store.posts_for(other.reel_id)[0].status == PostStatus.UNKNOWN_OUTCOME
    assert bench.refresh(other).state == S.NEEDS_ATTENTION


def test_a_late_result_for_an_old_attempt_changes_nothing(bench):
    reel = bench.publishing()
    first = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(first, PostOutcome.FAILED)
    tapped = tap(reel, TapAction.RETRY, platform=TWO_PLATFORMS[0])
    assert bench.store.apply_tap(tapped, bench.config).applied
    second = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)

    assert bench.store.record_post_result(first, PostOutcome.POSTED, remote_id="old") is False

    post = bench.store.posts_for(reel.reel_id)[0]
    assert (post.status, post.attempts) == (PostStatus.IN_FLIGHT, second.attempt)


def test_a_result_cannot_be_recorded_twice(bench):
    reel = bench.publishing()
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="abc") is True
    assert bench.store.record_post_result(claim, PostOutcome.FAILED) is False
    assert bench.store.posts_for(reel.reel_id)[0].status == PostStatus.POSTED


def test_all_platforms_posted_or_skipped_finishes_the_reel(bench):
    reel = bench.publishing()
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="abc")
    assert bench.refresh(reel).state == S.PUBLISHING

    assert bench.store.skip_platform(reel.reel_id, TWO_PLATFORMS[1]) is True

    assert bench.refresh(reel).state == S.POSTED


def test_skip_only_takes_a_pending_row(bench):
    reel = bench.publishing()
    bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert bench.store.skip_platform(reel.reel_id, TWO_PLATFORMS[0]) is False


def test_each_post_status_change_writes_an_event(bench):
    reel = bench.publishing(TWO_PLATFORMS[:1])
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="abc")
    changes = [
        (event.from_state, event.to_state, event.platform)
        for event in bench.store.events_for(reel.reel_id)
        if event.kind == "post"
    ]
    assert changes == [
        (None, "pending", TWO_PLATFORMS[0]),
        ("pending", "in_flight", TWO_PLATFORMS[0]),
        ("in_flight", "posted", TWO_PLATFORMS[0]),
    ]


# --- The owner resolves platforms in telegram_only and after an unclear answer ---------------


def test_the_owner_marks_a_hand_upload_posted(bench):
    reel = bench.publishing(TWO_PLATFORMS[:1])

    result = bench.store.apply_tap(
        tap(reel, TapAction.POSTED, platform=TWO_PLATFORMS[0]), bench.config
    )

    assert result.applied
    post = bench.store.posts_for(reel.reel_id)[0]
    assert post.status == PostStatus.POSTED
    assert post.posted_at == bench.clock()
    assert bench.refresh(reel).state == S.POSTED


def test_posted_tapped_twice_counts_once(bench):
    reel = bench.publishing()
    first = tap(reel, TapAction.POSTED, platform=TWO_PLATFORMS[0])
    assert bench.store.apply_tap(first, bench.config).applied

    assert bench.store.apply_tap(first, bench.config).outcome == TapOutcome.DUPLICATE
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.POSTED, platform=TWO_PLATFORMS[0]), bench.config),
        RefusalReason.NOT_PENDING,
    )


@pytest.mark.parametrize("action", [TapAction.POSTED, TapAction.RETRY])
def test_the_owner_cannot_resolve_a_row_that_is_still_in_flight(bench, action):
    reel = bench.publishing()
    bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    result = bench.store.apply_tap(tap(reel, action, platform=TWO_PLATFORMS[0]), bench.config)
    assert_refused(result, RefusalReason.NOT_PENDING)
    assert bench.store.posts_for(reel.reel_id)[0].status == PostStatus.IN_FLIGHT


@pytest.mark.parametrize("outcome", [PostOutcome.FAILED, PostOutcome.UNKNOWN])
def test_already_posted_resolves_a_row_and_work_on_the_rest_carries_on(bench, outcome):
    reel = bench.needs_attention(outcome)

    result = bench.store.apply_tap(
        tap(reel, TapAction.POSTED, platform=TWO_PLATFORMS[0]), bench.config
    )

    assert result.applied
    assert bench.refresh(reel).state == S.PUBLISHING
    assert bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[1], bench.config)


@pytest.mark.parametrize("outcome", [PostOutcome.FAILED, PostOutcome.UNKNOWN])
def test_retry_sends_the_row_back_to_pending_only_on_the_owners_tap(bench, outcome):
    reel = bench.needs_attention(outcome)
    assert bench.store.posts_for(reel.reel_id)[0].status != PostStatus.PENDING

    result = bench.store.apply_tap(
        tap(reel, TapAction.RETRY, platform=TWO_PLATFORMS[0]), bench.config
    )

    assert result.applied
    assert bench.refresh(reel).state == S.PUBLISHING
    assert bench.store.posts_for(reel.reel_id)[0].status == PostStatus.PENDING
    assert bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config).attempt == 2


def test_retry_on_a_posted_row_is_refused(bench):
    reel = bench.publishing()
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="abc")
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.RETRY, platform=TWO_PLATFORMS[0]), bench.config),
        RefusalReason.NOT_PENDING,
    )
    assert bench.store.posts_for(reel.reel_id)[0].status == PostStatus.POSTED


@pytest.mark.parametrize("state", [S.AWAITING_APPROVAL, S.APPROVED, S.SCHEDULED, S.POSTED])
def test_posted_and_retry_need_a_reel_that_is_publishing(bench, state):
    reel = bench.walk_to(state)
    for action in (TapAction.POSTED, TapAction.RETRY):
        result = bench.store.apply_tap(tap(reel, action, platform=TWO_PLATFORMS[0]), bench.config)
        assert_refused(result, RefusalReason.NOT_PUBLISHING)
    assert bench.refresh(reel) == reel


def test_posts_survive_a_send_back_and_are_not_sent_again(bench):
    reel = bench.publishing()
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="abc")
    original = bench.video.read_bytes()
    bench.video.write_bytes(b"swapped")
    with pytest.raises(ActionRefused):
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[1], bench.config)
    bench.video.write_bytes(original)

    assert bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config).applied
    assert bench.store.schedule_reel(reel.reel_id, reel.revision, bench.clock())
    assert bench.store.start_publishing(reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config)

    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    assert refused.value.reason == RefusalReason.NOT_PENDING
    assert bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[1], bench.config)


def test_a_new_revision_of_a_posted_platform_is_still_not_posted_again(bench):
    # The row is per reel and platform across revisions: a regenerated reel stays posted there.
    reel = bench.publishing()
    claim = bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)
    bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="abc")
    original = bench.video.read_bytes()
    bench.video.write_bytes(b"swapped")
    with pytest.raises(ActionRefused):
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[1], bench.config)
    bench.video.write_bytes(original)
    assert bench.store.apply_tap(tap(reel, TapAction.REGENERATE), bench.config).applied
    assert bench.store.finish_regeneration(reel.reel_id, reel.revision)
    revision = reel.revision + 1
    assert bench.store.record_voiced(reel.reel_id, revision, "S0")
    bench.video.write_bytes(b"revision two")
    assert bench.store.record_rendered(reel.reel_id, revision, bench.video, "h2", bench.config)
    assert bench.store.offer_for_approval(reel.reel_id, revision, bench.config)
    fresh = bench.refresh(reel)
    assert bench.store.apply_tap(tap(fresh, TapAction.APPROVE), bench.config).applied
    assert bench.store.schedule_reel(reel.reel_id, revision, bench.clock() + timedelta(1))
    assert bench.store.start_publishing(reel.reel_id, revision, TWO_PLATFORMS, bench.config)

    with pytest.raises(ActionRefused) as refused:
        bench.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], bench.config)

    assert refused.value.reason == RefusalReason.NOT_PENDING
    assert len(bench.store.posts_for(reel.reel_id)) == len(TWO_PLATFORMS)


# --- Notes and metrics for the bot ------------------------------------------------------------


def test_a_metric_is_stored_against_a_real_reel_and_platform(bench):
    reel = bench.new_reel()
    bench.store.record_metric(reel.reel_id, "instagram", views=10, saves=2, shares=1)
    assert bench.store.metrics_for(reel.reel_id)[0].views == 10
    with pytest.raises(sqlite3.IntegrityError):
        bench.store.record_metric("no-such-reel", "instagram", views=1, saves=1, shares=1)
    with pytest.raises(sqlite3.IntegrityError):
        bench.store.record_metric(reel.reel_id, "myspace", views=1, saves=1, shares=1)
    with pytest.raises(sqlite3.IntegrityError):
        bench.store.record_metric(reel.reel_id, "instagram", views=-1, saves=1, shares=1)


def test_a_note_goes_in_the_audit_log(bench):
    reel = bench.walk_to(S.REJECTED)
    bench.store.add_note(reel.reel_id, "too salesy")
    assert bench.store.events_for(reel.reel_id)[-1].detail == "too salesy"
