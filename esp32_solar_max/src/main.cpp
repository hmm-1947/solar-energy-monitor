#define ENABLE_USER_AUTH
#define ENABLE_DATABASE

#include "secrets.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <FirebaseClient.h>
#include <ModbusMaster.h>
#include <time.h>

UserAuth user_auth(API_KEY, USER_EMAIL, USER_PASSWORD);
FirebaseApp app;
WiFiClientSecure ssl;
AsyncClientClass asyncClient(ssl);
RealtimeDatabase Database;

/* RS485 */
#define MAX485_DE 5
#define MAX485_RE 4
#define RS485_RX 16
#define RS485_TX 17
#define MODBUS_BAUD 9600
#define SLAVE_ID 1

ModbusMaster node;

/* Data */
float pv1_voltage = 0, pv1_current = 0;
float grid_voltage = 0, grid_frequency = 0, grid_current = 0;
float ac_power = 0;
float today_energy_kwh = 0;
float total_energy_kwh = 0;
float total_work_hours = 0;
float monthly_baseline = -1;
float yearly_baseline = -1;
float last_pv_voltage = -1;
float last_pv_current = -1;
float last_ac_power = -1;
float last_grid_voltage = -1;
float last_grid_current = -1;
float last_grid_frequency = -1;
float last_work_hours = -1;
unsigned long lastHistoryPush = 0;
const unsigned long HISTORY_INTERVAL = 300000; // 5 minutes
String status_text = "Unknown";
String last_status_text = "";
String lastMonth = "";
String lastYear = "";
unsigned long lastPoll = 0;
unsigned long lastLivePush = 0;
unsigned long lastEnergyPush = 0;
const unsigned long POLL_INTERVAL = 2000;
const unsigned long LIVE_INTERVAL = 2000;
const unsigned long ENERGY_INTERVAL = 300000;

/* Time */
String dateStr, monthStr, yearStr;

void updateDateStrings()
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
}
String hourStr;

void updateHourString()
{
  struct tm t;
  if (!getLocalTime(&t)) return;

  char buf[8];
  strftime(buf, sizeof(buf), "%H:%M", &t);
  hourStr = buf;
}
void pushPowerHistory()
{
  if (!app.ready()) return;

  updateDateStrings();
  updateHourString();

  String path;
  path = "/history/";
  path += dateStr;
  path += "/";
  path += hourStr;

  Database.set<float>(asyncClient, path, ac_power);
}


/* RS485 control */
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

/* Modbus */
void pollGrowatt()
{
  if (node.readInputRegisters(0, 108) != node.ku8MBSuccess)
    return;

  pv1_voltage = node.getResponseBuffer(3) * 0.1;
  pv1_current = node.getResponseBuffer(4) * 0.1;
  uint32_t pac = ((uint32_t)node.getResponseBuffer(35) << 16) | node.getResponseBuffer(36);
  ac_power = pac * 0.1;
  grid_frequency = node.getResponseBuffer(37) * 0.01;
  grid_voltage   = node.getResponseBuffer(38) * 0.1;
  grid_current   = node.getResponseBuffer(39) * 0.1;
  uint32_t et = ((uint32_t)node.getResponseBuffer(53) << 16) | node.getResponseBuffer(54);
  today_energy_kwh = et * 0.1;
  uint32_t ett = ((uint32_t)node.getResponseBuffer(55) << 16) | node.getResponseBuffer(56);
  total_energy_kwh = ett * 0.1;
  uint32_t wt = ((uint32_t)node.getResponseBuffer(57) << 16) | node.getResponseBuffer(58);
  total_work_hours = (wt * 0.5) / 3600.0;
  uint16_t status_code = node.getResponseBuffer(0);
  status_text = (status_code == 1) ? "Normal" : (status_code == 0) ? "Waiting" : "Fault";
}

/* Firebase live */
void pushLive()
{
  if (!app.ready())
  {
    return;
  }
  if (abs(pv1_voltage - last_pv_voltage) > 0.1)
  {
    Database.set<float>(asyncClient, "/live/pv_voltage", pv1_voltage);
    last_pv_voltage = pv1_voltage;
  }
  if (abs(pv1_current - last_pv_current) > 0.1)
  {
    Database.set<float>(asyncClient, "/live/pv_current", pv1_current);
    last_pv_current = pv1_current;
  }
  if (abs(ac_power - last_ac_power) > 5)
  {
    Database.set<float>(asyncClient, "/live/ac_power", ac_power);
    last_ac_power = ac_power;
  }
  if (abs(grid_voltage - last_grid_voltage) > 0.5)
  {
    Database.set<float>(asyncClient, "/live/grid_voltage", grid_voltage);
    last_grid_voltage = grid_voltage;
  }
  if (abs(grid_current - last_grid_current) > 0.1)
  {
    Database.set<float>(asyncClient, "/live/grid_current", grid_current);
    last_grid_current = grid_current;
  }
  if (abs(grid_frequency - last_grid_frequency) > 0.01)
  {
    Database.set<float>(asyncClient, "/live/grid_frequency", grid_frequency);
    last_grid_frequency = grid_frequency;
  }
  if (abs(total_work_hours - last_work_hours) > 0.01)
  {
    Database.set<float>(asyncClient, "/live/work_hours", total_work_hours);
    last_work_hours = total_work_hours;
  }
  if (status_text != last_status_text)
  {
    Database.set<String>(asyncClient, "/live/status_text", status_text);
    last_status_text = status_text;
  }
}

/* Firebase energy */
void pushEnergy()
{
  if (!app.ready())
    return;

  updateDateStrings();
  String path;
  path = "/energy/daily/";
  path += dateStr;
  path += "/kwh";
  Database.set<float>(asyncClient, path, today_energy_kwh);
  if (monthStr != lastMonth)
  {
    lastMonth = monthStr;
    monthly_baseline = total_energy_kwh;

    path = "/energy/baseline/monthly/";
    path += monthStr;
    Database.set<float>(asyncClient, path, monthly_baseline);
  }
  path = "/energy/monthly/";
  path += monthStr;
  path += "/kwh";
  Database.set<float>(asyncClient, path, total_energy_kwh - monthly_baseline);

  if (yearStr != lastYear)
  {
    lastYear = yearStr;
    yearly_baseline = total_energy_kwh;

    path = "/energy/baseline/yearly/";
    path += yearStr;
    Database.set<float>(asyncClient, path, yearly_baseline);
  }
  path = "/energy/yearly/";
  path += yearStr;
  path += "/kwh";
  Database.set<float>(asyncClient, path, total_energy_kwh - yearly_baseline);
}

/* Setup */
void setup()
{
  Serial.begin(115200);
  delay(1000);
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

  configTime(19800, 0, "pool.ntp.org");
  ssl.setInsecure();
  initializeApp(asyncClient, app, getAuth(user_auth));
  app.getApp<RealtimeDatabase>(Database);
  Database.url(DATABASE_URL);
}

/* Loop */
void loop()
{
  app.loop();
  static bool readyPrinted = false;
  if (!readyPrinted && app.ready())
    readyPrinted = true;
  if (millis() - lastPoll >= POLL_INTERVAL)
  {
    lastPoll = millis();
    pollGrowatt();
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
    pushPowerHistory();
  }
  delay(50);
}
