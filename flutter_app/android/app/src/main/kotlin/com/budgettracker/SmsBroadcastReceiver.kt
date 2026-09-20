package com.budgettracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * SmsBroadcastReceiver
 *
 * Receives the system-wide SMS_RECEIVED broadcast.
 * Strict Client-Side Pre-Filtering:
 * 1. Checks sender ID against an allowlist of Saudi banks.
 * 2. Uses Regex / keyword matching on the message body to drop any message
 *    containing OTP or verification keywords ("OTP", "code", "رمز", "تحقق")
 *    before forwarding to SmsListenerService or caching.
 */
class SmsBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsBroadcastReceiver"

        // Lowercase sender IDs to whitelist
        private val ALLOWED_SENDERS = setOf(
            "snb", "alrajhi", "al rajhi", "rajhibank",
            "alinma", "riyad", "anb", "sab", "bsf",
            "albilad", "aljazira", "gib", "9200",
        )

        // OTP / verification keywords and regex
        private val OTP_KEYWORDS = listOf("otp", "code", "رمز", "تحقق")
        private val OTP_REGEX = Regex("""(?i)\b(otp|code)\b|رمز|تحقق""")

        fun isAllowedSender(sender: String): Boolean {
            val senderLower = sender.lowercase().trim()
            return ALLOWED_SENDERS.any { senderLower.contains(it) }
        }

        fun isOtpOrVerificationMessage(body: String): Boolean {
            val bodyLower = body.lowercase()
            return OTP_KEYWORDS.any { bodyLower.contains(it) } || OTP_REGEX.containsMatchIn(body)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        for (sms in messages) {
            val sender = sms.originatingAddress ?: continue
            val body   = sms.messageBody       ?: continue
            val ts     = sms.timestampMillis

            // 1. Strict allowlist sender check
            if (!isAllowedSender(sender)) {
                Log.d(TAG, "Ignored SMS from non-bank sender: $sender")
                continue
            }

            // 2. Strict OTP / verification keyword pre-filter check
            if (isOtpOrVerificationMessage(body)) {
                Log.i(TAG, "Dropped OTP / verification SMS from '$sender' before transmitting.")
                continue
            }

            Log.i(TAG, "Bank transaction SMS verified from '$sender' (len=${body.length}). Forwarding…")
            SmsListenerService.forwardSmsToFlutter(context, body, sender, ts)
        }
    }
}
