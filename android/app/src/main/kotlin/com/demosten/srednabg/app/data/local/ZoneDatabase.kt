// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / app

package com.demosten.srednabg.app.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [ZoneEntity::class, ZoneTraversalEntity::class],
    version = 4,
    exportSchema = false,
)
abstract class ZoneDatabase : RoomDatabase() {
    abstract fun zoneDao(): ZoneDao
    abstract fun zoneTraversalDao(): ZoneTraversalDao

    companion object {
        /**
         * v1 → v2: adds the History feature's `zone_traversals` table. Purely
         * additive — it does NOT touch the `zones` table, so the re-syncable
         * zone cache is preserved across the upgrade instead of being wiped by
         * the destructive fallback. The CREATE TABLE must match the schema Room
         * derives from [ZoneTraversalEntity] exactly (column order, types,
         * nullability, PK), or Room's open-time validation throws.
         */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `zone_traversals` (" +
                        "`id` TEXT NOT NULL, " +
                        "`zoneId` TEXT NOT NULL, " +
                        "`road` TEXT NOT NULL, " +
                        "`roadLatin` TEXT, " +
                        "`direction` TEXT NOT NULL, " +
                        "`speedLimitKmh` INTEGER NOT NULL, " +
                        "`vehicleType` TEXT NOT NULL, " +
                        "`entryTimeMs` INTEGER NOT NULL, " +
                        "`exitTimeMs` INTEGER NOT NULL, " +
                        "`avgSpeedKmh` REAL, " +
                        "`sustainedMinKmh` REAL NOT NULL, " +
                        "`sustainedMaxKmh` REAL NOT NULL, " +
                        "`isOverLimit` INTEGER NOT NULL, " +
                        "`distanceM` INTEGER NOT NULL, " +
                        "`samplesJson` TEXT NOT NULL, " +
                        "PRIMARY KEY(`id`))"
                )
            }
        }

        /**
         * v2 → v3: adds the geometry snapshot to `zone_traversals` (description,
         * start/end coordinates, simplified centerline) so "Show on map" no
         * longer depends on the live catalog. All six columns are nullable with
         * no default, which is exactly what Room derives for the nullable
         * entity fields — existing rows keep NULL and stay unshowable.
         */
        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `zone_traversals` ADD COLUMN `description` TEXT")
                db.execSQL("ALTER TABLE `zone_traversals` ADD COLUMN `startLat` REAL")
                db.execSQL("ALTER TABLE `zone_traversals` ADD COLUMN `startLng` REAL")
                db.execSQL("ALTER TABLE `zone_traversals` ADD COLUMN `endLat` REAL")
                db.execSQL("ALTER TABLE `zone_traversals` ADD COLUMN `endLng` REAL")
                db.execSQL("ALTER TABLE `zone_traversals` ADD COLUMN `centerlineJson` TEXT")
            }
        }

        /**
         * v3 → v4 (SrednaUK): speed limits switch from km/h to whole mph with no
         * schema change. Empty the zone cache so `ZoneRepository.ensureLoaded`
         * reseeds it from the bundle (converted on load), and convert limits
         * already recorded in History. Without this, an earlier SrednaUK build's
         * cached "140" would be read as 140 mph.
         */
        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("DELETE FROM `zones`")
                db.execSQL(
                    "UPDATE `zone_traversals` SET `speedLimitKmh` = " +
                        "CAST(ROUND(`speedLimitKmh` / 1.609344) AS INTEGER)",
                )
            }
        }
    }
}
