#define ENABLE_USER_AUTH
#define ENABLE_DATABASE
#define DEBUG 1

#include "secrets.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <FirebaseClient.h>
#include <ModbusMaster.h>
#include <time.h>

/* ================= Firebase ================= */
UserAuth user_auth(FIREBASE_API_KEY, FIREBASE_EMAIL, FIREBASE_PASSWORD);
FirebaseApp app;
WiFiClientSecure ssl;
AsyncClientClass asyncClient(ssl);
RealtimeDatabase Database;

/* ================= RS485 ================= */
#define MAX485_DE 5
#define MAX485_RE 4
#define RS485_RX 16
#define RS485_TX 17
#define MODBUS_BAUD 9600
#define SLAVE_ID 1

ModbusMaster node;

/* ================= Timers ================= */
const unsigned long POLL_INTERVAL = 2000;
const unsigned long LIVE_INTERVAL = 2000;
const unsigned long ENERGY_INTERVAL  = 180000; // 3 min
const unsigned long HISTORY_INTERVAL = 180000; // 3 min
const unsigned long SYSTEM_INTERVAL  = 60000;  // 1 min (uptime)
unsigned long lastLiveValuePush = 0;
const unsigned long LIVE_VALUE_MIN_GAP = 6000; // 6 sec per value

/* ================= State ================= */
unsigned long lastPoll = 0, lastLivePush = 0, lastEnergyPush = 0;
unsigned long lastHistoryPush = 0, lastSystemPush = 0;
unsigned long lastValidData = 0;

/* ================= Data ================= */
float pv1_voltage = 0, pv1_current = 0;
float grid_voltage = 0, grid_frequency = 0, grid_current = 0;
float ac_power = 0;
float today_energy_kwh = 0;
float total_energy_kwh = 0;
float total_work_hours = 0;

float monthly_baseline = -1;
float yearly_baseline = -1;

bool inverterOnline = false;
bool lastInverterOnline = false;
bool wifiConnected = false;
bool firebaseReady = false;

uint8_t modbusFailCount = 0;
uint8_t lastModbusError = 0; // 0 = OK


/* ================= Last sent values ================= */
float last_pv_voltage = -1, last_pv_current = -1, last_ac_power = -1;
float last_grid_voltage = -1, last_grid_current = -1;
float last_grid_frequency = -1, last_work_hours = -1;
String status_text = "Unknown", last_status_text = "";

/* ================= Time ================= */
String dateStr, monthStr, yearStr, hourStr;
String lastMonth = "", lastYear = "";

/* ================= Helpers ================= */
bool timeValid()
{
  struct tm t;
  return getLocalTime(&t);
}

void updateTimeStrings()
{
  struct tm t;
  if (!getLocalTime(&t))
    return;

  char buf[16];
  strftime(buf, sizeof(buf), "%Y-%m-%d", &t);
  dateStr = buf;
  strftime(buf, sizeof(buf), "%Y-%m", &t);
  monthStr = buf;
  strftime(buf, sizeof(buf), "%Y", &t);
  yearStr = buf;
  strftime(buf, sizeof(buf), "%H:%M", &t);
  hourStr = buf;
}

void logEvent(const String &msg)
{
  static unsigned long lastLog = 0;
  if (millis() - lastLog < 3000)
    return; // max 1 log / 3 sec
  lastLog = millis();

#if DEBUG
  Serial.println(msg);
#endif

  if (!app.ready() || !timeValid())
    return;

  updateTimeStrings();

  Database.set<String>(asyncClient, "/system/last_event", msg);
  Database.set<String>(
      asyncClient,
      "/system/last_event_time",
      dateStr + " " + hourStr);
}

/* ================= RS485 ================= */
void preTransmission()
{
  digitalWrite(MAX485_DE, HIGH);
  digitalWrite(MAX485_RE, HIGH);
}
void postTransmission()
{
  digitalWrite(MAX485_DE, LOW);
  digitalWrite(MAX485_RE, LOW);
}

/* ================= Modbus ================= */
void resetModbus()
{
  Serial2.end();
  delay(200);
  Serial2.begin(MODBUS_BAUD, SERIAL_8N1, RS485_RX, RS485_TX);
  node.begin(SLAVE_ID, Serial2);
  node.preTransmission(preTransmission);
  node.postTransmission(postTransmission);
  modbusFailCount = 0;
  logEvent("Modbus reset");
}

bool readRegs(uint16_t start, uint16_t count)
{
  uint8_t res = node.readInputRegisters(start, count);

  if (res != node.ku8MBSuccess)
  {
    modbusFailCount++;
    lastModbusError = res;   // <-- store actual error code
    return false;
  }

  modbusFailCount = 0;
  lastModbusError = 0;       // <-- clear on success
  return true;
}



void pollGrowatt()
{
  // Status + PV
  if (!readRegs(0, 10))
    return;

  uint16_t sc = node.getResponseBuffer(0);
  status_text = (sc == 0) ? "Waiting" : (sc == 1) ? "Normal"
                                    : (sc == 2)   ? "Fault"
                                                  : "Unknown";

  pv1_voltage = node.getResponseBuffer(3) * 0.1;
  pv1_current = node.getResponseBuffer(4) * 0.1;

  // Power + Grid
  if (!readRegs(35, 10))
    return;

  ac_power = (((uint32_t)node.getResponseBuffer(0) << 16) |
              node.getResponseBuffer(1)) *
             0.1;
  grid_frequency = node.getResponseBuffer(2) * 0.01;
  grid_voltage = node.getResponseBuffer(3) * 0.1;
  grid_current = node.getResponseBuffer(4) * 0.1;

  // Energy
  if (!readRegs(53, 6))
    return;

  today_energy_kwh = (((uint32_t)node.getResponseBuffer(0) << 16) |
                      node.getResponseBuffer(1)) *
                     0.1;
  total_energy_kwh = (((uint32_t)node.getResponseBuffer(2) << 16) |
                      node.getResponseBuffer(3)) *
                     0.1;
  total_work_hours = ((((uint32_t)node.getResponseBuffer(4) << 16) |
                       node.getResponseBuffer(5)) *
                      0.5) /
                     3600.0;

  lastValidData = millis();
  inverterOnline = true;
}

/* ================= Firebase ================= */
void pushLive()
{
  if (!app.ready()) return;

  unsigned long now = millis();
  if (now - lastLiveValuePush < LIVE_VALUE_MIN_GAP) return;
  lastLiveValuePush = now;

  auto pushF = [&](const char *p, float &last, float val, float th)
  {
    if (abs(val - last) > th)
    {
      Database.set<float>(asyncClient, p, val);
      last = val;
    }
  };

  pushF("/live/pv_voltage", last_pv_voltage, pv1_voltage, 0.2);
  pushF("/live/pv_current", last_pv_current, pv1_current, 0.2);
  pushF("/live/ac_power", last_ac_power, ac_power, 10);
  pushF("/live/grid_voltage", last_grid_voltage, grid_voltage, 1.0);
  pushF("/live/grid_current", last_grid_current, grid_current, 0.2);
  pushF("/live/grid_frequency", last_grid_frequency, grid_frequency, 0.02);
  pushF("/live/work_hours", last_work_hours, total_work_hours, 0.02);

  if (status_text != last_status_text)
  {
    Database.set<String>(asyncClient, "/live/status_text", status_text);
    last_status_text = status_text;
  }
}

void pushEnergy()
{
  if (!app.ready() || !timeValid())
    return;

  updateTimeStrings();

  Database.set<float>(asyncClient,
                      "/energy/daily/" + dateStr + "/kwh", today_energy_kwh);

  if (monthStr != lastMonth)
  {
    lastMonth = monthStr;
    monthly_baseline = total_energy_kwh;
    Database.set<float>(asyncClient,
                        "/energy/baseline/monthly/" + monthStr, monthly_baseline);
  }

  if (yearStr != lastYear)
  {
    lastYear = yearStr;
    yearly_baseline = total_energy_kwh;
    Database.set<float>(asyncClient,
                        "/energy/baseline/yearly/" + yearStr, yearly_baseline);
  }

  Database.set<float>(asyncClient,
                      "/energy/monthly/" + monthStr + "/kwh",
                      total_energy_kwh - monthly_baseline);

  Database.set<float>(asyncClient,
                      "/energy/yearly/" + yearStr + "/kwh",
                      total_energy_kwh - yearly_baseline);
}

void pushHistory()
{
  if (!app.ready() || !timeValid())
    return;

  updateTimeStrings();
  Database.set<float>(asyncClient,
                      "/history/" + dateStr + "/" + hourStr, ac_power);
}

void pushSystem()
{
  if (!app.ready())
    return;

  Database.set<bool>(asyncClient, "/system/wifi_connected", wifiConnected);
  Database.set<bool>(asyncClient, "/system/firebase_ready", firebaseReady);
  Database.set<bool>(asyncClient, "/system/inverter_online", inverterOnline);
  Database.set<uint8_t>(asyncClient, "/system/modbus_error_code", lastModbusError);
  Database.set<uint32_t>(asyncClient, "/system/uptime_seconds", millis() / 1000);
}

/* ================= Setup ================= */
void setup()
{
  Serial.begin(115200);

  pinMode(MAX485_DE, OUTPUT);
  pinMode(MAX485_RE, OUTPUT);
  digitalWrite(MAX485_DE, LOW);
  digitalWrite(MAX485_RE, LOW);

  Serial2.begin(MODBUS_BAUD, SERIAL_8N1, RS485_RX, RS485_TX);
  node.begin(SLAVE_ID, Serial2);
  node.preTransmission(preTransmission);
  node.postTransmission(postTransmission);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED)
    delay(500);
  wifiConnected = true;

  configTime(19800, 0, "pool.ntp.org");

  ssl.setInsecure();
  initializeApp(asyncClient, app, getAuth(user_auth));
  app.getApp<RealtimeDatabase>(Database);
  Database.url(FIREBASE_DB_URL);
}

/* ================= Loop ================= */
void loop()
{
  app.loop();

  firebaseReady = app.ready();

  if (WiFi.status() != WL_CONNECTED)
    wifiConnected = false;
  else
    wifiConnected = true;

  if (millis() - lastPoll >= POLL_INTERVAL)
  {
    lastPoll = millis();

    inverterOnline = false;
    pollGrowatt();

    if (!lastInverterOnline && inverterOnline)
      resetModbus();

    lastInverterOnline = inverterOnline;
  }

  if (millis() - lastLivePush >= LIVE_INTERVAL)
  {
    lastLivePush = millis();
    pushLive();
  }

  if (millis() - lastEnergyPush >= ENERGY_INTERVAL)
  {
    lastEnergyPush = millis();
    pushEnergy();
  }

  if (millis() - lastHistoryPush >= HISTORY_INTERVAL)
  {
    lastHistoryPush = millis();
    pushHistory();
  }

  if (millis() - lastSystemPush >= SYSTEM_INTERVAL)
  {
    lastSystemPush = millis();
    pushSystem();
  }
}
