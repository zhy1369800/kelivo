import Foundation
import WeatherKit
import CoreLocation
import Flutter

final class WeatherKitHandler: NSObject {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getWeather" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let args = call.arguments as? [String: Any] ?? [:]
    guard let lat = args["latitude"] as? Double,
          let lng = args["longitude"] as? Double else {
      result(FlutterError(
        code: "invalid_args",
        message: "Parameters 'latitude' and 'longitude' are required.",
        details: nil
      ))
      return
    }

    if #available(iOS 16.0, *) {
      getWeather(latitude: lat, longitude: lng, result: result)
    } else {
      fetchFallbackWeather(latitude: lat, longitude: lng, result: result)
    }
  }

  @available(iOS 16.0, *)
  private func getWeather(latitude lat: Double, longitude lng: Double, result: @escaping FlutterResult) {
    let location = CLLocation(latitude: lat, longitude: lng)
    let service = WeatherService.shared

    Task {
      do {
        let weather = try await service.weather(for: location)
        var response = [String: Any]()

        // 1. Current Weather
        let current = weather.currentWeather
        response["provider"] = "Apple WeatherKit"
        response["current"] = [
          "condition": current.condition.description,
          "temperature_c": (current.temperature.converted(to: .celsius).value * 10).rounded() / 10,
          "apparent_temperature_c": (current.apparentTemperature.converted(to: .celsius).value * 10).rounded() / 10,
          "humidity": (current.humidity * 100).rounded() / 100,
          "wind_speed_kmh": (current.wind.speed.converted(to: .kilometersPerHour).value * 10).rounded() / 10,
          "wind_direction": current.wind.compassDirection.description,
          "pressure_hpa": (current.pressure.converted(to: .hectopascals).value * 10).rounded() / 10,
          "pressure_trend": current.pressureTrend.description,
          "uv_index": current.uvIndex.value,
          "visibility_km": (current.visibility.converted(to: .kilometers).value * 10).rounded() / 10,
          "dew_point_c": (current.dewPoint.converted(to: .celsius).value * 10).rounded() / 10,
          "cloud_cover": (current.cloudCover * 100).rounded() / 100,
          "is_daylight": current.isDaylight,
          "location": ["latitude": lat, "longitude": lng]
        ] as [String: Any]

        // 2. Hourly Forecast (up to 48 hours)
        let hourlyForecasts = weather.hourlyForecast.forecast
        var hourly = [[String: Any]]()
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH:mm"
        hourFormatter.timeZone = TimeZone.current
        let isoFormatter = ISO8601DateFormatter()

        for forecast in hourlyForecasts.prefix(48) {
          hourly.append([
            "hour": hourFormatter.string(from: forecast.date),
            "date": isoFormatter.string(from: forecast.date),
            "condition": forecast.condition.description,
            "temp_c": (forecast.temperature.converted(to: .celsius).value * 10).rounded() / 10,
            "apparent_temp_c": (forecast.apparentTemperature.converted(to: .celsius).value * 10).rounded() / 10,
            "humidity": (forecast.humidity * 100).rounded() / 100,
            "precip_chance": (forecast.precipitationChance * 100).rounded() / 100,
            "wind_speed_kmh": (forecast.wind.speed.converted(to: .kilometersPerHour).value * 10).rounded() / 10,
            "uv_index": forecast.uvIndex.value,
            "cloud_cover": (forecast.cloudCover * 100).rounded() / 100,
            "is_daylight": forecast.isDaylight
          ])
        }
        response["hourly"] = hourly

        // 3. Daily Forecast (up to 10 days)
        let dailyForecasts = weather.dailyForecast.forecast
        var daily = [[String: Any]]()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current

        for forecast in dailyForecasts.prefix(10) {
          var entry: [String: Any] = [
            "date": dayFormatter.string(from: forecast.date),
            "condition": forecast.condition.description,
            "high_c": (forecast.highTemperature.converted(to: .celsius).value * 10).rounded() / 10,
            "low_c": (forecast.lowTemperature.converted(to: .celsius).value * 10).rounded() / 10,
            "precip_chance": (forecast.precipitationChance * 100).rounded() / 100,
            "wind_speed_kmh": (forecast.wind.speed.converted(to: .kilometersPerHour).value * 10).rounded() / 10,
            "uv_index": forecast.uvIndex.value
          ]
          if let sunrise = forecast.sun.sunrise {
            entry["sunrise"] = timeFormatter.string(from: sunrise)
          }
          if let sunset = forecast.sun.sunset {
            entry["sunset"] = timeFormatter.string(from: sunset)
          }
          daily.append(entry)
        }
        response["daily"] = daily

        // 4. Weather Alerts
        var alertList = [[String: Any]]()
        if let alerts = weather.weatherAlerts {
          for alert in alerts {
            alertList.append([
              "summary": alert.summary,
              "severity": alert.severity.description,
              "source": alert.source,
              "region": alert.region ?? ""
            ])
          }
        }
        response["alerts"] = alertList

        DispatchQueue.main.async {
          result(response)
        }
      } catch {
        // Fallback to Open-Meteo REST API when WeatherKit throws entitlement/JWT error
        self.fetchFallbackWeather(latitude: lat, longitude: lng, result: result)
      }
    }
  }

  // MARK: - Open-Meteo Free Fallback Weather

  private func fetchFallbackWeather(latitude lat: Double, longitude lng: Double, result: @escaping FlutterResult) {
    let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,surface_pressure,wind_speed_10m&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max&timezone=auto"

    guard let url = URL(string: urlString) else {
      result(FlutterError(code: "weather_fetch_failed", message: "Invalid fallback URL.", details: nil))
      return
    }

    let task = URLSession.shared.dataTask(with: url) { data, _, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "weather_fetch_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let data = data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        DispatchQueue.main.async {
          result(FlutterError(code: "weather_fetch_failed", message: "Failed to parse Open-Meteo weather response.", details: nil))
        }
        return
      }

      let parsed = self.formatOpenMeteoResponse(json: json, lat: lat, lng: lng)
      DispatchQueue.main.async {
        result(parsed)
      }
    }
    task.resume()
  }

  private func formatOpenMeteoResponse(json: [String: Any], lat: Double, lng: Double) -> [String: Any] {
    var response = [String: Any]()
    response["provider"] = "Open-Meteo (Free Fallback)"

    if let current = json["current"] as? [String: Any] {
      let code = (current["weather_code"] as? NSNumber)?.intValue ?? 0
      let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue ?? 0.0
      let apparent = (current["apparent_temperature"] as? NSNumber)?.doubleValue ?? temp
      let humidity = (current["relative_humidity_2m"] as? NSNumber)?.doubleValue ?? 0.0
      let windSpeed = (current["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0.0
      let pressure = (current["surface_pressure"] as? NSNumber)?.doubleValue ?? 1013.2
      let isDay = ((current["is_day"] as? NSNumber)?.intValue ?? 1) == 1

      response["current"] = [
        "condition": wmoCodeToCondition(code),
        "temperature_c": temp,
        "apparent_temperature_c": apparent,
        "humidity": humidity,
        "wind_speed_kmh": windSpeed,
        "pressure_hpa": pressure,
        "is_daylight": isDay,
        "location": ["latitude": lat, "longitude": lng]
      ] as [String: Any]
    }

    if let hourly = json["hourly"] as? [String: Any],
       let times = hourly["time"] as? [String],
       let temps = hourly["temperature_2m"] as? [Double],
       let humidities = hourly["relative_humidity_2m"] as? [Double],
       let codes = hourly["weather_code"] as? [Int] {
      var hourlyList = [[String: Any]]()
      let limit = min(times.count, 48)
      for i in 0..<limit {
        hourlyList.append([
          "date": times[i],
          "condition": wmoCodeToCondition(codes[i]),
          "temp_c": temps[i],
          "humidity": humidities[i]
        ])
      }
      response["hourly"] = hourlyList
    }

    if let daily = json["daily"] as? [String: Any],
       let times = daily["time"] as? [String],
       let maxTemps = daily["temperature_2m_max"] as? [Double],
       let minTemps = daily["temperature_2m_min"] as? [Double],
       let codes = daily["weather_code"] as? [Int] {
      var dailyList = [[String: Any]]()
      let limit = min(times.count, 10)
      for i in 0..<limit {
        dailyList.append([
          "date": times[i],
          "condition": wmoCodeToCondition(codes[i]),
          "high_c": maxTemps[i],
          "low_c": minTemps[i]
        ])
      }
      response["daily"] = dailyList
    }

    response["alerts"] = [[String: Any]]()
    return response
  }

  private func wmoCodeToCondition(_ code: Int) -> String {
    switch code {
    case 0: return "Clear"
    case 1, 2, 3: return "Partly Cloudy"
    case 45, 48: return "Foggy"
    case 51, 53, 55: return "Drizzle"
    case 61, 63, 65: return "Rain"
    case 71, 73, 75: return "Snow"
    case 80, 81, 82: return "Showers"
    case 95, 96, 99: return "Thunderstorm"
    default: return "Partly Cloudy"
    }
  }
}
