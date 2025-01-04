#ifndef CREDENTIALS_H
#define CREDENTIALS_H

// WiFi Credentials
const char* ssid = "WiEarth";         // Replace with your WiFi SSID
const char* password = "3TS9fFtZNf"; // Replace with your WiFi Password

// Server Configuration
const char* serverURL = "https://door-lock-notifier-c934666628c1.herokuapp.com";     
const uint16_t serverPort = 27608;            // Replace with your server port
const char* scanEndpoint = "/scan";          // Endpoint for scanning cards

#endif // CREDENTIALS_H
