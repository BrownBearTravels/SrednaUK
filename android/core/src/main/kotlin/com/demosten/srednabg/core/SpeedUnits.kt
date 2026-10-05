// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 SrednaBG Contributors
//
// SrednaBG — android / core

package com.demosten.srednabg.core

import kotlin.math.roundToInt

/**
 * SrednaUK unit convention: zone **limits** are whole mph (as UK signs and data
 * sources publish them), while every **measured** speed — GPS fixes, running
 * averages, max-for-remainder — stays in km/h. The engine converts a limit
 * with [mphToKmh] at the point of comparison, never by rounding to an integer
 * km/h, so "over the limit" agrees exactly with what the mph display shows.
 */
const val KMH_PER_MPH = 1.609344

fun Int.mphToKmh(): Double = this * KMH_PER_MPH

fun Double.kmhToMph(): Double = this / KMH_PER_MPH

/** Nearest whole mph — for converting km/h source data into mph limits. */
fun Int.kmhToMphLimit(): Int = (this / KMH_PER_MPH).roundToInt()
