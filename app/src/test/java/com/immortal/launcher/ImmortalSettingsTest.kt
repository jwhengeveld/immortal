/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

package com.immortal.launcher

import java.util.Locale
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImmortalSettingsTest {

  @Test
  fun `fahrenheit territories default to F`() {
    assertTrue(ImmortalSettings.localeUsesFahrenheit(Locale.US))
    assertTrue(ImmortalSettings.localeUsesFahrenheit(Locale("en", "LR")))
    assertTrue(ImmortalSettings.localeUsesFahrenheit(Locale("my", "MM")))
    assertTrue(ImmortalSettings.localeUsesFahrenheit(Locale("en", "BS")))
  }

  @Test
  fun `everywhere else defaults to C`() {
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale.UK))
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale.CANADA))
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale.GERMANY))
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale.JAPAN))
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale("es", "MX")))
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale("en", "AU")))
  }

  @Test
  fun `no-country locale defaults to C`() {
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale("en")))
    assertFalse(ImmortalSettings.localeUsesFahrenheit(Locale.ROOT))
  }
}
