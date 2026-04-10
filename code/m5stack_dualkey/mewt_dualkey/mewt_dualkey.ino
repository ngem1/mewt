/*
 * Mewt — M5 Stack Chain DualKey
 *
 * Hardware (see M5 docs): NeoPixel data GPIO21, LED power GPIO40, keys GPIO0 & GPIO17.
 * Serial @ 9600 baud (USB CDC): host sends one integer per line for LED state; 101 = startup blink.
 * Key behavior matches stock Mewt Pro Micro sketch: on release after a press, prints 0 or 1 + newline.
 * Either key toggles the same mute state.
 *
 * Board: M5ChainDualKey (M5Stack board package >= 3.2.4)
 * Library: Adafruit NeoPixel >= 1.15.2
 */

#include <Adafruit_NeoPixel.h>

#define LED_PWR_PIN 40
#define LED_SIG_PIN 21
#define NUM_LEDS 2
#define KEY1_PIN 0
#define KEY2_PIN 17

Adafruit_NeoPixel pixels(NUM_LEDS, LED_SIG_PIN, NEO_GRB + NEO_KHZ800);

String inByte;
int ledDisplay = 0;
unsigned long lastLedDisplayUpdate = 0;

int toggleState = 1;

static void applyLedCode(int code) {
  switch (code) {
    case 0:
      // Muted: left off, right green (swap pixel indices if your unit is wired the other way)
      pixels.setPixelColor(0, pixels.Color(0, 0, 0));
      pixels.setPixelColor(1, pixels.Color(0, 255, 0));
      break;
    case 1:
      // Unmuted, quiet: left red, right off
      pixels.setPixelColor(0, pixels.Color(255, 0, 0));
      pixels.setPixelColor(1, pixels.Color(0, 0, 0));
      break;
    case 2:
      // Unmuted, talking: both red
      pixels.setPixelColor(0, pixels.Color(255, 0, 0));
      pixels.setPixelColor(1, pixels.Color(255, 0, 0));
      break;
    case 101:
      for (int b = 0; b < 2; b++) {
        pixels.setPixelColor(0, pixels.Color(0, 255, 0));
        pixels.setPixelColor(1, pixels.Color(0, 255, 0));
        pixels.show();
        delay(200);
        pixels.clear();
        pixels.show();
        delay(150);
      }
      return;
    default:
      pixels.clear();
      break;
  }
  pixels.show();
}

void setup() {
  pinMode(LED_PWR_PIN, OUTPUT);
  digitalWrite(LED_PWR_PIN, HIGH);

  pixels.begin();
  pixels.clear();
  pixels.show();

  pinMode(KEY1_PIN, INPUT_PULLUP);
  pinMode(KEY2_PIN, INPUT_PULLUP);

  Serial.begin(9600);
  Serial.setTimeout(50);
}

void loop() {
  if (Serial.available() > 0) {
    inByte = Serial.readStringUntil('\n');
    inByte.trim();
    if (inByte.length() > 0) {
      ledDisplay = inByte.toInt();
      applyLedCode(ledDisplay);
      lastLedDisplayUpdate = millis();
    }
  }

  if (lastLedDisplayUpdate > 0 && (millis() - lastLedDisplayUpdate > 1000)) {
    pixels.clear();
    pixels.show();
    lastLedDisplayUpdate = 0;
  }

  static bool down = false;
  bool anyLow =
      (digitalRead(KEY1_PIN) == LOW) || (digitalRead(KEY2_PIN) == LOW);

  if (anyLow && !down) {
    down = true;
  }
  if (!anyLow && down) {
    down = false;
    toggleState = (toggleState == 0) ? 1 : 0;
    Serial.println(toggleState);
  }

  delay(1);
}
