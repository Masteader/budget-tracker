package com.budgettracker

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * SmsQueue
 *
 * SQLite-backed offline queue for SMS messages that couldn't be forwarded
 * to the FastAPI webhook (e.g., no internet). The Flutter app drains this
 * queue on each foreground resume via the MethodChannel.
 */
object SmsQueue {

    private const val DB_NAME    = "sms_queue.db"
    private const val DB_VERSION = 1
    private const val TABLE      = "pending_sms"

    private class DbHelper(ctx: Context) : SQLiteOpenHelper(ctx, DB_NAME, null, DB_VERSION) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $TABLE (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    body      TEXT    NOT NULL,
                    sender    TEXT    NOT NULL,
                    timestamp INTEGER NOT NULL,
                    enqueued_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
                )
                """.trimIndent(),
            )
        }

        override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {
            db.execSQL("DROP TABLE IF EXISTS $TABLE")
            onCreate(db)
        }
    }

    /** Add an SMS to the pending queue. */
    fun enqueue(context: Context, body: String, sender: String, timestamp: Long) {
        val db = DbHelper(context).writableDatabase
        val values = ContentValues().apply {
            put("body", body)
            put("sender", sender)
            put("timestamp", timestamp)
        }
        db.insert(TABLE, null, values)
        db.close()
    }

    /**
     * Return all pending SMS messages and clear the queue atomically.
     * Each item is a Map matching the MethodChannel argument format.
     */
    fun drainAll(context: Context): List<Map<String, Any>> {
        val db = DbHelper(context).writableDatabase
        val results = mutableListOf<Map<String, Any>>()

        val cursor = db.query(TABLE, null, null, null, null, null, "id ASC")
        val ids    = mutableListOf<Long>()

        cursor.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(c.getColumnIndexOrThrow("id"))
                ids.add(id)
                results.add(
                    mapOf(
                        "body"      to c.getString(c.getColumnIndexOrThrow("body")),
                        "sender"    to c.getString(c.getColumnIndexOrThrow("sender")),
                        "timestamp" to c.getLong(c.getColumnIndexOrThrow("timestamp")),
                    ),
                )
            }
        }

        // Delete successfully read rows
        if (ids.isNotEmpty()) {
            val placeholders = ids.joinToString(",") { "?" }
            db.delete(TABLE, "id IN ($placeholders)", ids.map { it.toString() }.toTypedArray())
        }

        db.close()
        return results
    }
}
