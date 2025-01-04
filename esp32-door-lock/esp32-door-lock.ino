#include <SPI.h>
#include <MFRC522.h>

// Define pins
#define RST_PIN 22
#define SS_PIN 21

MFRC522 rfid(SS_PIN, RST_PIN);
MFRC522::MIFARE_Key key;

void setup() {
  Serial.begin(115200);
  SPI.begin();
  rfid.PCD_Init();
  Serial.println("Place your card near the reader...");

  // Initialize the default key (FFFFFFFFFFFF)
  for (byte i = 0; i < 6; i++) {
    key.keyByte[i] = 0xFF;
  }
}

void loop() {
  // Check if a card is present
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    return;
  }

  Serial.println("Card detected!");

  // Authenticate block 4
  byte block = 4; // Block to read from
  MFRC522::StatusCode status = rfid.PCD_Authenticate(
      MFRC522::PICC_CMD_MF_AUTH_KEY_A, block, &key, &(rfid.uid));
  if (status != MFRC522::STATUS_OK) {
    Serial.print("Authentication failed: ");
    Serial.println(rfid.GetStatusCodeName(status));
    return;
  }

  // Read data
  byte buffer[18]; // Buffer to store data
  byte size = sizeof(buffer);
  status = rfid.MIFARE_Read(block, buffer, &size);

  if (status == MFRC522::STATUS_OK) {
    Serial.print("Data read from block ");
    Serial.print(block);
    Serial.print(": ");
    for (byte i = 0; i < 16; i++) {
      if (buffer[i] >= 32 && buffer[i] <= 126) { // Printable ASCII range
        Serial.write(buffer[i]); // Print as ASCII characters
      } else {
        break;
      }
    }
    Serial.println();
  } else {
    Serial.print("Read failed: ");
    Serial.println(rfid.GetStatusCodeName(status));
  }

  // Halt communication
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}
