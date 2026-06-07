/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

package com.immortal.launcher

import android.content.Context
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.roundToInt
import org.json.JSONObject

/**
 * Keyless weather for the header and the photo frame.
 *
 * Robustness matters here: the free IP-geolocation services rate-limit hard
 * (ipapi.co returns HTTP 429 once its quota is hit), which previously blanked the
 * weather everywhere. So we:
 *   1. resolve the device's location ONCE and cache it (a fixed Portal doesn't
 *      move), so geolocation is hit at most once rather than on every refresh;
 *   2. try multiple geolocators (ipwho.is first — far more generous — then
 *      ipapi.co); and
 *   3. read the temperature from Open-Meteo, which is keyless and reliable.
 */
object Weather {

  private const val PREFS = "immortal_weather"

  /** Returns e.g. "☀️ 72°", or "" if it can't be fetched (caller can retry). */
  fun fetch(context: Context): String =
      runCatching {
            val (lat, lon) = location(context) ?: return ""
            // °F or °C per the user's setting (default: follow the device locale).
            val unit = if (ImmortalSettings.useFahrenheit(context)) "fahrenheit" else "celsius"
            val w =
                JSONObject(
                    httpGet(
                        "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
                            "&current=temperature_2m,weather_code&temperature_unit=$unit"))
            val cur = w.getJSONObject("current")
            "${emoji(cur.getInt("weather_code"))} ${cur.getDouble("temperature_2m").roundToInt()}°"
          }
          .getOrDefault("")

  /** Cached lat/lon, or a fresh geolocation (cached on success). */
  private fun location(context: Context): Pair<Double, Double>? {
    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    prefs.getString("lat", null)?.toDoubleOrNull()?.let { la ->
      prefs.getString("lon", null)?.toDoubleOrNull()?.let { lo -> return la to lo }
    }
    for (url in listOf("https://ipwho.is/", "https://ipapi.co/json/")) {
      val coords =
          runCatching {
                val j = JSONObject(httpGet(url))
                val la = j.optDouble("latitude", Double.NaN)
                val lo = j.optDouble("longitude", Double.NaN)
                if (!la.isNaN() && !lo.isNaN() && (la != 0.0 || lo != 0.0)) la to lo else null
              }
              .getOrNull()
      if (coords != null) {
        prefs
            .edit()
            .putString("lat", coords.first.toString())
            .putString("lon", coords.second.toString())
            .apply()
        return coords
      }
    }
    return null
  }

  private fun httpGet(spec: String): String {
    val c = URL(spec).openConnection() as HttpURLConnection
    c.connectTimeout = 8000
    c.readTimeout = 8000
    c.instanceFollowRedirects = true
    c.setRequestProperty("User-Agent", "Immortal/1.0")
    return c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
  }

  fun emoji(code: Int): String =
      when (code) {
        0 -> "☀️"
        1, 2 -> "🌤️"
        3 -> "☁️"
        in 45..48 -> "🌫️"
        in 51..67 -> "🌦️"
        in 71..77 -> "🌨️"
        in 80..82 -> "🌧️"
        in 95..99 -> "⛈️"
        else -> "🌡️"
      }
}
