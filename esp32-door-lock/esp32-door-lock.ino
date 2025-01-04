#include <SPI.h>
#include <MFRC522.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include "credentials.h" // Include credentials header

// Define RFID pins
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

  // Connect to WiFi
  WiFi.begin(ssid, password);
  Serial.println("Connecting to WiFi...");
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");
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

  // Read data from the block
  byte buffer[18];
  byte size = sizeof(buffer);
  status = rfid.MIFARE_Read(block, buffer, &size);
  if (status != MFRC522::STATUS_OK) {
    Serial.print("Read failed: ");
    Serial.println(rfid.GetStatusCodeName(status));
    return;
  }

  // Extract readable data
  char data[17]; // Data buffer (16 characters + null terminator)
  strncpy(data, (char*)buffer, 16);
  data[16] = '\0'; // Null terminate the string
  Serial.print("Read Data: ");
  Serial.println(data);

  // Send the data to the server
  sendToServer(data);

  // Halt RFID communication
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

void sendToServer(const char* cardData) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected.");
    return;
  }

  HTTPClient http;
  String url = String("https://") + serverURL + scanEndpoint;

  // Prepare JSON payload
  String jsonPayload = "{\"enteredKey\":\"" + String(cardData) + "\"}";

  

  // Start connection and send HTTP POST request
  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  // Set a custom timeout period (e.g., 10 seconds)
  http.setTimeout(10000); // Timeout in milliseconds

  Serial.print("Sending POST request to: ");
  Serial.println(url);

  int httpResponseCode = http.POST(jsonPayload);

  // Check the HTTP response code
  if (httpResponseCode > 0) {
    Serial.print("HTTP Response code: ");
    Serial.println(httpResponseCode);

    // Determine card validity based on the status code
    if (httpResponseCode == 200) {
      Serial.println("Card is VALID!");
    } else if (httpResponseCode == 401) {
      Serial.println("Card is INVALID!");
    } else {
      Serial.println("Unexpected response from server.");
    }
  } else {
    Serial.print("Error on sending POST: ");
    Serial.println(http.errorToString(httpResponseCode));
  }

  // End HTTP connection
  http.end();
}
